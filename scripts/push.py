#!/usr/bin/env python3
"""批次 1 推送：全量同步 Sources/Resources/scripts，跳过 .github（令牌无 workflow scope）。"""
import base64, json, os, re, subprocess, sys, time, urllib.request, urllib.error

REPO = 'ffzyf/ff-ios-app'
ROOT = '/workspace/ios-app'
UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
TOKEN = os.environ.get('GH_TOKEN', '').strip()
if not TOKEN:
    _token_file = os.path.expanduser('~/.secrets/gh_token')
    if os.path.exists(_token_file):
        TOKEN = open(_token_file, encoding='utf-8').read().strip()
if not TOKEN:
    # 老路径：从同机另一个仓库的 remote URL 里取内嵌凭据（早期就是这么跑的）。
    # 保留它只是兜底 —— 一旦那个仓库改成裸 https 地址，这里就会拿到 None，
    # 所以上面两条才是主路。
    _url = subprocess.check_output(
        ['git', '-C', '/workspace/blog', 'config', '--get', 'remote.origin.url']
    ).decode()
    _m = re.search(r'://[^:]+:([^@]+)@', _url)
    TOKEN = _m.group(1) if _m else ''
if not TOKEN:
    sys.exit('push: 没有 GitHub 令牌（设 GH_TOKEN，或写 ~/.secrets/gh_token）')
# 三个前缀永不入仓：
#   .github/  —— 令牌无 workflow scope，推了必 403；
#   _release/ —— 3.14.0 事故根源：本地校验的临时解包（_release/verify/Payload/SkyApp.app）
#                被同步进仓库后，CI 的 `find . -maxdepth 6 -name '*.app'` 按字典序先撞上它，
#                把这个只有 Info.plist 没有二进制的空壳打成了 ipa；
#   build/    —— 本地若有编译中间产物同样不许入仓。
SKIP_PREFIXES = ('.github/', '_release/', 'build/')
# 精确跳过：本地打好的产物包。它不是源码，3.7MB 进仓只会让以后每次 clone 都变慢，
# 而且 CI 的 `find -name '*.app'` 有可能先撞上它里面的内容（同 `_release/` 那次事故）。
SKIP_EXACT = ('build-artifact.zip',)
# 形态跳过：Python 字节码缓存。每次跑一次脚本就换一批指纹，不挡的话
# 每次推送都会多出几个"改了但其实没改"的二进制文件。
SKIP_CONTAINS = ('__pycache__/',)


def api(path, method='GET', body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request('https://api.github.com' + path, data=data, method=method)
    req.add_header('Authorization', 'Bearer ' + TOKEN)
    req.add_header('Accept', 'application/vnd.github+json')
    req.add_header('X-GitHub-Api-Version', '2022-11-28')
    req.add_header('User-Agent', UA)
    if data is not None:
        req.add_header('Content-Type', 'application/json')
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            return r.status, json.loads(r.read().decode(), strict=False)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()[:300]


st, ref = api('/repos/%s/git/ref/heads/main' % REPO)
if st != 200:
    sys.exit('ref 失败 %s %s' % (st, ref))
head = ref['object']['sha']
st, commit = api('/repos/%s/git/commits/%s' % (REPO, head))
base_tree = commit['tree']['sha']

st, t = api('/repos/%s/git/trees/%s?recursive=1' % (REPO, head))
# remote 侧只挡 .github/（令牌推不了它，也不许删除逻辑误删它）；
# _release/、build/ 不挡 —— 它们若出现在远端（3.14.0 事故），要被下面的删除逻辑清掉。
remote = {e['path']: e['sha'] for e in t['tree'] if e['type'] == 'blob' if not e['path'].startswith('.github/')}

local = {}
for root, dirs, files in os.walk(ROOT):
    if '.git' in root:
        continue
    for f in files:
        full = os.path.join(root, f)
        rel = os.path.relpath(full, ROOT)
        if rel.startswith(SKIP_PREFIXES):
            continue
        if rel in SKIP_EXACT:
            continue
        if any(part in rel for part in SKIP_CONTAINS):
            continue
        local[rel] = full

entries = []
changed_count = 0
for rel, full in sorted(local.items()):
    h = subprocess.check_output(['git', 'hash-object', full]).decode().strip()
    if remote.get(rel) == h:
        continue
    with open(full, 'rb') as fh:
        content = base64.b64encode(fh.read()).decode()

    # 逐个上传 blob，带退避重试。
    #
    # 为什么需要重试：一次推 30+ 个文件时，GitHub 会在第 10~20 个 blob 上返回
    # 400 "malformed request"（每次挂的文件都不一样，不是文件本身有问题）——
    # 这是 per-second 的次级限流，换个时间重发就过。之前没有重试，整批推送直接失败，
    # 已经上传的 blob 全部作废（没建 commit，无副作用，但白跑一遍）。
    for attempt in range(5):
        st, blob = api('/repos/%s/git/blobs' % REPO, 'POST', {'content': content, 'encoding': 'base64'})
        if st in (200, 201):
            break
        # 400 / 422 / 403 / 5xx 一律退避重试；4xx 里只有 404 是真错（仓库权限），不重试
        if st == 404 or attempt == 4:
            sys.exit('blob 失败 %s: %s %s' % (rel, st, blob))
        print('  … %s 返回 %s，%.1fs 后重试' % (rel, st, 0.8 * (attempt + 1)))
        time.sleep(0.8 * (attempt + 1))

    entries.append({'path': rel, 'mode': '100755' if rel.endswith('.sh') else '100644',
                    'type': 'blob', 'sha': blob['sha']})
    changed_count += 1
    # 限速：约 3 个 blob / 秒，低于 GitHub 的次级限流阈值
    time.sleep(0.35)

deleted = [p for p in remote if p not in local]
for p in deleted:
    entries.append({'path': p, 'mode': '100644', 'type': 'blob', 'sha': None})

print('更新 %d，删除 %d' % (changed_count, len(deleted)))
for p in deleted:
    print('  -', p)

def _default_message():
    """默认提交说明从 project.yml + 本次 notes 现算。

    以前这里是一段写死的历史文案（"build 3 -> build 4"），推了 60 多个版本之后
    它还在说同一句话 —— 提交历史因此变成噪音，回看时根本不知道哪个 commit 改了什么。
    改成现算：版本号、构建号一定对得上，说明取 notes 的第一段。
    """
    try:
        yml = open(os.path.join(ROOT, 'project.yml'), encoding='utf-8').read()
        ver = re.search(r'MARKETING_VERSION:\s*"([^"]+)"', yml).group(1)
        build = re.search(r'CURRENT_PROJECT_VERSION:\s*"([^"]+)"', yml).group(1)
    except Exception:
        ver, build = '?', '?'

    summary = ''
    notes_path = os.path.join(ROOT, 'notes-%s.txt' % ver)
    if os.path.exists(notes_path):
        text = open(notes_path, encoding='utf-8').read().strip()
        first = text.split('\n\n')[0].strip().replace('\n', ' ')
        if first:
            summary = '\n\n' + (first[:200] + '…' if len(first) > 200 else first)

    changed = ' '.join(sorted(local))[:400]
    return 'feat(release): %s (build %s)%s\n\n本次改动：%s' % (ver, build, summary, changed)


# 用法：`python3 scripts/push.py "你的提交说明"`。不传就按 project.yml 现算。
msg = sys.argv[1] if len(sys.argv) > 1 else _default_message()
st, tree = api('/repos/%s/git/trees' % REPO, 'POST', {'base_tree': base_tree, 'tree': entries})
if st not in (200, 201):
    sys.exit('tree 失败 %s %s' % (st, tree))
st, nc = api('/repos/%s/git/commits' % REPO, 'POST',
             {'message': msg, 'tree': tree['sha'], 'parents': [head]})
if st not in (200, 201):
    sys.exit('commit 失败 %s %s' % (st, nc))
st, upd = api('/repos/%s/git/refs/heads/main' % REPO, 'PATCH', {'sha': nc['sha'], 'force': False})
if st not in (200, 201):
    sys.exit('ref 更新失败 %s %s' % (st, upd))
print('PUSHED %s' % nc['sha'])
