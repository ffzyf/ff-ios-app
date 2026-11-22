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

def _secret(name):
    """环境变量优先，其次 `~/.secrets/release.env`。

    两个口令每次发版都要，反复 export 是纯粹的摩擦；密钥文件权限 600、不在
    仓库里，和 `~/.secrets/tencent.env` 是同一套做法。环境变量仍然优先，
    CI 里不需要那个文件。
    """
    value = os.environ.get(name, '').strip()
    if value:
        return value
    path = os.path.expanduser('~/.secrets/release.env')
    try:
        for line in open(path, encoding='utf-8'):
            line = line.strip()
            if line.startswith(name + '='):
                return line.split('=', 1)[1].strip()
    except OSError:
        pass
    return ''


CM = _secret('CODEMAGIC_API_TOKEN')
RT = _secret('RELEASE_TOKEN')

# 腾讯云 COS（CDN 回源）。2026-11-17 起下载接口会 302 到 cdn.skyzyf335.top，
# 所以发版要顺手把包同步到桶里，否则新版本只能走 KV 直出（慢 3–4 倍）。
COS_BUCKET = os.environ.get('TENCENT_COS_BUCKET', 'ff-assets-1315861330').strip()
COS_REGION = os.environ.get('TENCENT_COS_REGION', 'ap-hongkong').strip()
# 桶里按类型分目录（2026-11-17 用户要求）：安装包绝不和网站的图片平铺在根目录。
# 以后接第二个站，图片各占 `<站点>/images/`，安装包共用 `ipa/`。
COS_IPA_PREFIX = os.environ.get('TENCENT_COS_IPA_PREFIX', 'ipa/').strip()
# 与 release-store.js 的 MAX_KEEP_FILES 必须一致（那边管 KV，这边管 COS）。
KEEP_IPA_VERSIONS = int(os.environ.get('KEEP_IPA_VERSIONS', '3'))


def tencent_env():
    """腾讯云密钥：优先环境变量，其次 ~/.secrets/tencent.env（本机习惯，不进仓库）。"""
    sid = os.environ.get('TENCENT_SECRET_ID', '').strip()
    skey = os.environ.get('TENCENT_SECRET_KEY', '').strip()
    if sid and skey:
        return sid, skey

    path = os.path.expanduser('~/.secrets/tencent.env')
    if not os.path.exists(path):
        return '', ''
    with open(path, encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if line.startswith('TENCENT_SECRET_ID='):
                sid = line.split('=', 1)[1]
            elif line.startswith('TENCENT_SECRET_KEY='):
                skey = line.split('=', 1)[1]
    return sid, skey


def quota_guard_blocks_cos():
    """COS 存储额度是否已经用到该停的程度。

    读的是 `ops/tencent_quota.py` 写的快照，不在这里现查腾讯云 —— 发版脚本
    已经在等一次 5 分钟的构建，不能再挂一次 30 秒的账单接口，更不能因为
    接口抖动就判成「不许传」。

    规则：
      - 没跑过巡检（文件不存在）→ 放行，并在上传时提示去跑一次；
      - 快照超过 24 小时 → 放行（陈旧数据不该卡住发版）；
      - 明确 `canUploadToCos: false` → 拦住。
    """
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                        '..', '..', 'ops', 'quota-state.json')
    path = os.path.normpath(path)
    if not os.path.exists(path):
        return False
    try:
        with open(path, encoding='utf-8') as fh:
            state = json.load(fh)
    except Exception:
        return False
    if state.get('canUploadToCos') is not False:
        return False
    checked = state.get('checkedAt') or ''
    try:
        from datetime import datetime, timezone, timedelta
        stamp = datetime.fromisoformat(checked)
        if stamp.tzinfo is None:
            stamp = stamp.replace(tzinfo=timezone(timedelta(hours=8)))
        age = datetime.now(timezone(timedelta(hours=8))) - stamp
        if age.total_seconds() > 86400:
            return False
    except Exception:
        return False
    return True


def upload_to_cos(path, key_name):
    """把 ipa 同步到 `ipa/` 目录，供 CDN 回源；顺手删掉超出保留数的旧包。

    失败只警告不中断：KV 里已经有包，下载接口探测到 CDN 404 会自动回退 KV
    直出（慢一点但能装）。发版失败比下载慢更糟，所以这里不 raise。
    """
    if quota_guard_blocks_cos():
        print('提示：COS 存储额度已到停用线（见 ops/quota-state.json），'
              '本次跳过同步，下载走 KV 直出')
        return
    sid, skey = tencent_env()
    if not sid or not skey:
        print('提示：没找到腾讯云密钥，跳过 COS 同步（下载会走 KV，慢 3–4 倍）')
        return
    try:
        from qcloud_cos import CosConfig, CosS3Client
    except ImportError:
        print('提示：没装 cos-python-sdk-v5，跳过 COS 同步')
        return

    try:
        client = CosS3Client(
            CosConfig(Region=COS_REGION, SecretId=sid, SecretKey=skey,
                      Scheme='https', Timeout=300)
        )
        cos_key = COS_IPA_PREFIX + key_name
        with open(path, 'rb') as fh:
            client.put_object(
                Bucket=COS_BUCKET, Body=fh, Key=cos_key,
                ContentType='application/octet-stream',
                # 文件名带版本号，内容不会再变；CDN 那条 30 天规则也认这个头
                CacheControl='public, max-age=31536000, immutable',
                EnableMD5=False,
            )
        print('COS 同步 -> %s/%s' % (COS_BUCKET, cos_key))
    except Exception as error:
        print('警告：COS 同步失败（%s），本次下载会回退 KV 直出' % str(error)[:200])
        return

    prune_cos_ipa(client, key_name)


def prune_cos_ipa(client, keep_name):
    """只留最近 KEEP_IPA_VERSIONS 个安装包，其余连 CDN 缓存一起删掉。

    KV 那边（release-store.js 的 pruneFiles）只管 KV 里的字节；COS 没有谁会
    自动清，不删就是「每发一版多 5MB，十年后桶里堆两百个包」。这里按
    LastModified 倒序保留前 N 个，`keep_name` 强制保住（刚传的可能因为
    时钟抖动排在后面）。

    删除后必须 PurgeUrlsCache：CDN 上还留着 30 天的副本，不刷新等于没删。
    """
    try:
        resp = client.list_objects(Bucket=COS_BUCKET, Prefix=COS_IPA_PREFIX, MaxKeys=1000)
        items = resp.get('Contents') or []
    except Exception as error:
        print('警告：列 COS 安装包失败（%s），本次跳过清理' % str(error)[:160])
        return

    def mtime(obj):
        raw = obj.get('LastModified') or ''
        # COS 返回 '2026-11-17T13:43:51.000Z'，字典序即时间序
        return raw

    ordered = sorted(items, key=mtime, reverse=True)
    keep = [keep_name]
    for obj in ordered:
        name = (obj.get('Key') or '').split('/')[-1]
        if name and name not in keep and len(keep) < KEEP_IPA_VERSIONS:
            keep.append(name)

    doomed = []
    for obj in ordered:
        key = obj.get('Key') or ''
        name = key.split('/')[-1]
        if name and name not in keep:
            doomed.append(key)
    if not doomed:
        print('COS 安装包：%d 个，在保留数 %d 之内，无需清理' % (len(items), KEEP_IPA_VERSIONS))
        return

    removed = []
    for key in doomed:
        try:
            client.delete_object(Bucket=COS_BUCKET, Key=key)
            removed.append(key)
        except Exception as error:
            print('警告：删除 %s 失败（%s）' % (key, str(error)[:120]))
    if removed:
        print('COS 清理：删掉 %d 个旧包（%s）' % (len(removed), ', '.join(removed)))
        purge_cdn([key for key in removed])


def purge_cdn(keys):
    """把删掉的安装包从腾讯云 CDN 缓存里刷掉。

    CDN 对 `*.ipa` 配了 30 天缓存，只删源站不刷 CDN，用户还能继续下到
    已经删掉的包 —— 等于清理没生效。失败只警告（缓存 30 天后自然过期）。
    """
    base = os.environ.get('IPA_CDN_BASE', 'https://cdn.skyzyf335.top').rstrip('/')
    urls = [base + '/' + key for key in keys]
    sid, skey = tencent_env()
    if not sid or not skey:
        return
    try:
        from tencentcloud.common import credential
        from tencentcloud.cdn.v20180606 import cdn_client, models
        from tencentcloud.common.profile.client_profile import ClientProfile
        from tencentcloud.common.profile.http_profile import HttpProfile

        cred = credential.Credential(sid, skey)
        hp = HttpProfile(); hp.endpoint = 'cdn.tencentcloudapi.com'
        cp = ClientProfile(); cp.httpProfile = hp
        client = cdn_client.CdnClient(cred, '', cp)

        req = models.PurgeUrlsCacheRequest()
        # 腾讯云一次最多 500 条 URL，这里永远是 1~2 条
        req.from_json_string(json.dumps({'Urls': urls}))
        client.PurgeUrlsCache(req)
        print('CDN 刷新：%s' % ', '.join(urls))
    except Exception as error:
        print('警告：CDN 刷新失败（%s），旧包最多再存活 30 天' % str(error)[:160])


def cm_api(path, method='GET', body=None, timeout=180):
    """Codemagic REST。注意它只认 `x-auth-token`，不认 Bearer。

    重试是必须的：这个沙箱到 codemagic 的 TLS 连接时不时被中途掐断
    （`SSLZeroReturnError: TLS/SSL connection has been closed`），一次就放弃
    会让「触发构建」白白失败，而这一步失败时还没有任何构建被创建，
    重试不会产生重复的构建。
    """
    data = json.dumps(body).encode() if body is not None else None
    last = None
    for attempt in range(3):
        req = urllib.request.Request('https://api.codemagic.io' + path, data=data, method=method)
        req.add_header('x-auth-token', CM)
        if data is not None:
            req.add_header('Content-Type', 'application/json')
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                raw = r.read()
                return json.loads(raw.decode()) if raw.strip().startswith(b'{') else {}
        except (urllib.error.URLError, ConnectionError, TimeoutError) as error:
            last = error
            print('  Codemagic 连接失败（%s），第 %d 次重试' % (str(error)[:80], attempt + 1))
            time.sleep(4 + attempt * 4)
    raise last


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
    """用包里的 Info.plist 再核一次版本 —— 脚本以为发 29、包里其实是 28 是真实发生过的。
    """
    with zipfile.ZipFile(dest) as z:
        all_names = z.namelist()
        names = [n for n in all_names if n.endswith('.app/Info.plist')]
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
    upload_to_cos(dest, key_name)

    notes = open(args.notes, encoding='utf-8').read()
    # 说明写太长没人读：App 的更新 sheet 只有一屏，超过 ~200 字就要滚动。
    # 这里不拒绝（拒绝会让发版卡住），只在超限时把字数打出来提醒收短。
    notes_len = len(notes.strip())
    if notes_len > 400:
        print('警告：更新说明 %d 字，超过 400 字上限，服务端会回 notesTooLong；建议压到 200 字内' % notes_len)
    elif notes_len > 200:
        print('提示：更新说明 %d 字，略长；建议压到 200 字内' % notes_len)
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
