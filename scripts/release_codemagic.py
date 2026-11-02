#!/usr/bin/env python3
"""一条命令发版（Codemagic 通道）：触发构建 → 等 → 下包 → 校验 → 上传云控 → 发布 latest。

取代 `release_pipeline.py` 的 GitHub Actions 分支（用户 2026-11-02 明确要求
「不要再用 GitHub 构建」—— Actions 的 macOS runner 按 10 倍扣配额，一次全量编译
就把免费额度吃掉一半；Codemagic 免费层是 500 分钟 M2/月，不计倍率）。

用法：
    export CODEMAGIC_API_TOKEN=...        # codemagic.io → Teams → API access
    export RELEASE_TOKEN=...              # Cloudflare Pages 环境变量里的发布口令
    python3 scripts/release_codemagic.py --notes notes-3.18.0.txt
    python3 scripts/release_codemagic.py --notes notes-3.18.0.txt --dry-run   # 只构建，不上传

前置：版本号已 bump 并推到 main（`bash scripts/bump.sh` + `python3 scripts/push.py`）。
本脚本**不**负责提交代码 —— 发版与提交是两件事，混在一起会让「包里是什么」
取决于工作区碰巧有什么。

为什么 token 只从环境变量读：写进仓库等于把发布权限交给所有能看到仓库的人
（这是私有仓库也一样 —— 历史里的密钥清不掉）。Codemagic 的 token 尤其危险，
它能把一个月的构建额度全部烧光。
"""
import argparse
import hashlib
import json
import os
import plistlib
import re
import sys
import time
import urllib.error
import urllib.request
import zipfile

# Codemagic 应用 id（ff-ios-app）。换仓库要在 codemagic.io 里重新 Add application
APP_ID = os.environ.get('CODEMAGIC_APP_ID', '6ae54a17b7721bafa016625e')
WORKFLOW_ID = os.environ.get('CODEMAGIC_WORKFLOW', 'ios-unsigned')
BRANCH = os.environ.get('RELEASE_BRANCH', 'main')
BASE = 'https://app.skyzyf335.top'
UA = 'ff-release/2.0'

CM = os.environ.get('CODEMAGIC_API_TOKEN', '').strip()
RT = os.environ.get('RELEASE_TOKEN', '').strip()


def cm_api(path, method='GET', body=None, timeout=180):
    """Codemagic REST。注意它只认 `x-auth-token`，不认 Bearer。"""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request('https://api.codemagic.io' + path, data=data, method=method)
    req.add_header('x-auth-token', CM)
    if data is not None:
        req.add_header('Content-Type', 'application/json')
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read()
        return json.loads(raw.decode()) if raw.strip().startswith(b'{') else {}


def site_api(path, data=None, headers=None, method='POST', timeout=180):
    req = urllib.request.Request(BASE + path, data=data, method=method)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    req.add_header('User-Agent', UA)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            body = r.read().decode('utf-8', 'replace')
            return r.status, (json.loads(body) if body.strip().startswith('{') else body)
    except urllib.error.HTTPError as e:
        body = e.read().decode('utf-8', 'replace')
        try:
            return e.code, json.loads(body)
        except Exception:
            return e.code, body[:400]


def local_version():
    """从 project.yml 读版本号 —— 与包里的 Info.plist 对账用，防止「发了版但用户收不到」。"""
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    text = open(os.path.join(root, 'project.yml'), encoding='utf-8').read()
    marketing = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', text)
    build = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', text)
    if not marketing or not build:
        sys.exit('project.yml 里读不到版本号')
    return marketing.group(1), int(build.group(1))


def trigger():
    res = cm_api('/builds', 'POST', {'appId': APP_ID, 'workflowId': WORKFLOW_ID, 'branch': BRANCH})
    bid = res.get('buildId')
    if not bid:
        sys.exit('触发失败：%s' % json.dumps(res, ensure_ascii=False)[:300])
    return bid


def wait_build(bid, timeout_min=40):
    """等到终态。每 30 秒一次 —— Codemagic 的免费实例排队可能十几分钟，别刷太快。"""
    deadline = time.time() + timeout_min * 60
    last = ''
    while time.time() < deadline:
        try:
            d = cm_api('/builds/' + bid)
        except Exception as e:          # 网络抖动不算失败，继续等
            print('  轮询失败：%s' % e)
            time.sleep(30)
            continue
        b = d.get('build', d)
        st = b.get('status')
        if st != last:
            print('  状态：%s' % st)
            last = st
        if st in ('finished', 'failed', 'canceled', 'skipped'):
            return b
        time.sleep(30)
    sys.exit('等超时了（%d 分钟），去 codemagic.io 看一眼' % timeout_min)


def download(build, dest):
    arts = build.get('artefacts') or []
    if not arts:
        # 编译步骤全绿但没有产物 = workflow 的 artifacts 段写错，比构建失败更难查
        sys.exit('构建完成但没有产物，检查 codemagic.yaml 的 artifacts 段')
    art = arts[0]
    req = urllib.request.Request(art['url'])
    req.add_header('x-auth-token', CM)
    req.add_header('User-Agent', UA)
    with urllib.request.urlopen(req, timeout=600) as r, open(dest, 'wb') as f:
        while True:
            chunk = r.read(1 << 20)
            if not chunk:
                break
            f.write(chunk)
    return art


def verify(dest, version, build_no):
    """用包里的 Info.plist 再核一次版本 —— 脚本以为发 29、包里其实是 28 是真实发生过的。"""
    with zipfile.ZipFile(dest) as z:
        names = [n for n in z.namelist() if n.endswith('.app/Info.plist')]
        if not names:
            sys.exit('包里没有 Info.plist，这不是一个合法 ipa')
        info = plistlib.loads(z.read(names[0]))
    got_v = str(info.get('CFBundleShortVersionString'))
    got_b = int(info.get('CFBundleVersion'))
    if got_v != version or got_b != build_no:
        sys.exit('版本对不上：local=%s(%s) 包内=%s(%s)' % (version, build_no, got_v, got_b))
    return info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--notes', required=True, help='更新说明文件路径')
    ap.add_argument('--out', default='/tmp', help='ipa 落地目录')
    ap.add_argument('--dry-run', action='store_true', help='只构建下载，不上传云控')
    args = ap.parse_args()

    if not CM:
        sys.exit('没设 CODEMAGIC_API_TOKEN')
    version, build_no = local_version()
    print('本地版本 %s (%d)' % (version, build_no))

    bid = trigger()
    print('构建已触发 %s' % bid)
    build = wait_build(bid)
    if build.get('status') != 'finished':
        sys.exit('构建 %s，去 codemagic.io/builds/%s 看日志' % (build.get('status'), bid))

    dest = os.path.join(args.out, 'SkyApp-%s.ipa' % version)
    art = download(build, dest)
    raw = open(dest, 'rb').read()
    digest = hashlib.sha256(raw).hexdigest()
    print('产物 %s  %.2f MB  sha256=%s' % (dest, len(raw) / 1048576.0, digest[:16]))

    info = verify(dest, version, build_no)
    print('包内版本 %s (%s)  bundle=%s' % (info.get('CFBundleShortVersionString'),
                                          info.get('CFBundleVersion'),
                                          info.get('CFBundleIdentifier')))

    if args.dry_run:
        print('dry-run：不发布')
        return
    if not RT:
        sys.exit('没设 RELEASE_TOKEN，ipa 在 %s，手动传也可以' % dest)

    key_name = '%s-%d.ipa' % (version, build_no)
    st, r = site_api('/api/app/version/upload', data=raw, headers={
        'x-release-token': RT,
        'x-file-name': key_name,
        'Content-Type': 'application/octet-stream',
    })
    if st != 200:
        sys.exit('上传失败 %s %s' % (st, r))
    print('上传 -> %s' % r.get('key'))

    notes = open(args.notes, encoding='utf-8').read()
    st, r = site_api('/api/app/version', data=json.dumps({
        'build': build_no, 'version': version, 'notes': notes, 'ipaKey': key_name,
    }).encode(), headers={'x-release-token': RT, 'Content-Type': 'application/json'})
    if st != 200:
        sys.exit('发布失败 %s %s' % (st, r))
    latest = (r or {}).get('latest') or {}
    print('线上 latest: build=%s version=%s ipa=%s' % (latest.get('build'),
                                                       latest.get('version'),
                                                       latest.get('ipaPath')))
    print('DONE')


if __name__ == '__main__':
    main()
