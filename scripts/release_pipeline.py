#!/usr/bin/env python3
"""一条命令发版：GitHub Actions 构建 → 下载产物 → 上传云控 → 发布 latest。

用法：
    export RELEASE_TOKEN=...
    python3 scripts/release_pipeline.py --notes notes.txt
    python3 scripts/release_pipeline.py --notes notes.txt --wait-only   # 只等已有构建
    python3 scripts/release_pipeline.py --notes notes.txt --dry-run     # 只构建，不上传

前置：版本号已经 bump 并推到 main（用 bump.sh + push.py）。本脚本不负责提交代码。

设计取舍：
  · 只认「本次触发之后创建」的 run，避免拿到上一次的旧构建 —— 上一次的 ipa 版本号
    可能与本地的 project.yml 不一致，传上去就会是「发了版但用户收不到」。
  · 下载 artifact 时 GitHub 会 302 到 Azure Blob，且**不允许**把 Authorization 头带过去，
    所以这里手动跟随重定向、第二次请求不带凭据。
  · 上传前用 Info.plist 的实际版本再核一次，杜绝「脚本以为发了 19、包里其实是 18」。
"""
import argparse
import glob
import json
import os
import plistlib
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile

REPO = os.environ.get('RELEASE_REPO', 'ffzyf/ff-ios-app')
WORKFLOW = 'build-ipa.yml'
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASE = 'https://app.skyzyf335.top'
UA = 'ff-release-pipeline/1.0'


def gh_token():
    url = subprocess.check_output(['git', '-C', '/workspace/blog', 'config', '--get',
                                   'remote.origin.url']).decode().strip()
    m = re.search(r'://[^:]+:([^@]+)@', url)
    if not m:
        sys.exit('无法从 /workspace/blog 的 remote 里取到 GitHub token')
    return m.group(1)


TOKEN = None


def api(path, method='GET', body=None, timeout=60):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request('https://api.github.com' + path, data=data, method=method)
    for k, v in {'Authorization': 'Bearer ' + TOKEN, 'Accept': 'application/vnd.github+json',
                 'User-Agent': UA, 'Content-Type': 'application/json'}.items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read()
            return r.status, (json.loads(raw.decode()) if raw else {})
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:400]


def local_version():
    txt = open(os.path.join(ROOT, 'project.yml')).read()
    ver = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', txt).group(1)
    build = int(re.search(r'CURRENT_PROJECT_VERSION:\s*"(\d+)"', txt).group(1))
    return ver, build


def trigger():
    st, r = api('/repos/%s/actions/workflows/%s/dispatches' % (REPO, WORKFLOW), 'POST',
                {'ref': 'main', 'inputs': {'screenshots': 'false'}})
    if st != 204:
        sys.exit('触发构建失败: %s %s' % (st, r))
    print('已触发构建，等待 GitHub 登记 run…')


def find_run(after_ts):
    st, runs = api('/repos/%s/actions/runs?per_page=10' % REPO)
    if st != 200:
        return None
    for w in runs.get('workflow_runs', []):
        if w.get('name') != 'Build Unsigned IPA':
            continue
        created = w.get('created_at', '')
        # 只认触发之后创建的 run
        if created and created >= after_ts:
            return w
    return None


def wait_run(timeout_min=40):
    started = time.time()
    run = None
    while time.time() - started < timeout_min * 60:
        if run is None:
            run = find_run(RUN_AFTER)
            if run:
                print('run #%s 已登记' % run['id'])
        else:
            st, r = api('/repos/%s/actions/runs/%s' % (REPO, run['id']))
            if st == 200:
                run = r
                print('  %s / %s' % (r['status'], r.get('conclusion') or '-'))
                if r['status'] == 'completed':
                    if r['conclusion'] != 'success':
                        dump_failure(run['id'])
                        sys.exit('构建失败: %s' % r['conclusion'])
                    return run
        time.sleep(20)
    sys.exit('等待构建超时（%d 分钟）' % timeout_min)


def dump_failure(run_id):
    st, jobs = api('/repos/%s/actions/runs/%s/jobs' % (REPO, run_id))
    if st != 200:
        return
    for j in jobs.get('jobs', []):
        bad = [s for s in j.get('steps', []) if s.get('conclusion') == 'failure']
        for s in bad:
            print('  ✗ %s / %s' % (j['name'], s['name']))


def download_ipa(run_id):
    st, arts = api('/repos/%s/actions/runs/%s/artifacts' % (REPO, run_id))
    if st != 200:
        sys.exit('取 artifact 列表失败: %s' % arts)
    target = None
    for a in arts.get('artifacts', []):
        if a['name'] == 'SkyApp-unsigned-ipa':
            target = a
            break
    if not target:
        sys.exit('没有找到 SkyApp-unsigned-ipa 产物')

    out = os.path.join(ROOT, 'build-artifact.zip')
    url = 'https://api.github.com/repos/%s/actions/artifacts/%s/zip' % (REPO, target['id'])

    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    opener = urllib.request.build_opener(NoRedirect)
    req = urllib.request.Request(url)
    req.add_header('Authorization', 'Bearer ' + TOKEN)
    req.add_header('User-Agent', UA)
    try:
        opener.open(req, timeout=60)
        sys.exit('artifact 下载未发生重定向，接口形态可能变了')
    except urllib.error.HTTPError as e:
        loc = e.headers.get('Location')
        if not loc:
            sys.exit('无重定向地址: %s' % e.code)
        r2 = urllib.request.Request(loc)
        r2.add_header('User-Agent', UA)
        with urllib.request.urlopen(r2, timeout=300) as r, open(out, 'wb') as f:
            shutil.copyfileobj(r, f)

    ipa_dir = os.path.join(ROOT, '_release')
    os.makedirs(ipa_dir, exist_ok=True)
    with zipfile.ZipFile(out) as z:
        names = [n for n in z.namelist() if n.endswith('.ipa')]
        if not names:
            sys.exit('artifact 里没有 .ipa')
        z.extract(names[0], ipa_dir)
        ipa = os.path.join(ipa_dir, names[0])
    print('产物: %s (%.2f MB)' % (ipa, os.path.getsize(ipa) / 1048576.0))
    return ipa


def verify_ipa(ipa, expect_ver, expect_build):
    tmp = os.path.join(ROOT, '_release', 'verify')
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp, exist_ok=True)
    with zipfile.ZipFile(ipa) as z:
        pl = [n for n in z.namelist() if n.endswith('.app/Info.plist')]
        if not pl:
            sys.exit('ipa 里找不到 Info.plist')
        z.extract(pl[0], tmp)
    d = plistlib.load(open(os.path.join(tmp, pl[0]), 'rb'))
    ver = d.get('CFBundleShortVersionString')
    build = d.get('CFBundleVersion')
    print('包内版本: %s (%s)' % (ver, build))
    if ver != expect_ver or str(build) != str(expect_build):
        sys.exit('版本不一致：包内 %s(%s) / project.yml %s(%s)' % (ver, build, expect_ver, expect_build))
    return ver, int(build)


def main():
    global TOKEN, RUN_AFTER
    ap = argparse.ArgumentParser()
    ap.add_argument('--notes', required=True, help='更新说明 txt 路径')
    ap.add_argument('--wait-only', action='store_true', help='不触发，只等最近一次构建')
    ap.add_argument('--dry-run', action='store_true', help='只构建+下载校验，不上传云控')
    args = ap.parse_args()

    TOKEN = gh_token()
    ver, build = local_version()
    print('本地版本: %s (%s)' % (ver, build))

    RUN_AFTER = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(time.time() - 60))
    if not args.wait_only:
        trigger()
    run = wait_run()
    ipa = download_ipa(run['id'])
    verify_ipa(ipa, ver, build)

    if args.dry_run:
        print('dry-run：跳过上传。产物 %s' % ipa)
        return

    token = os.environ.get('RELEASE_TOKEN')
    if not token:
        sys.exit('缺少环境变量 RELEASE_TOKEN')
    cmd = [sys.executable, os.path.join(ROOT, 'scripts', 'upload_release.py'),
           '--ipa', ipa, '--version', ver, '--build', str(build),
           '--notes', args.notes, '--token', token]
    subprocess.check_call(cmd)


if __name__ == '__main__':
    main()
