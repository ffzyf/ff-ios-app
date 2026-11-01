#!/usr/bin/env python3
"""上传 ipa 到云控并发布为 latest。

用法：
    python3 upload_release.py --ipa <path> --version 3.11.0 --build 19 --notes <file> --token <RELEASE_TOKEN>

流程对齐 RELEASE.md：
    1. POST /api/app/version/upload  （raw body + x-file-name）→ 拿到 KV key
    2. POST /api/app/version         （JSON: build/version/notes/ipaKey）→ 设为 latest
"""
import argparse
import hashlib
import json
import mimetypes
import os
import sys
import urllib.error
import urllib.request

BASE = 'https://app.skyzyf335.top'


def call(path, data=None, headers=None, method='POST', timeout=120):
    req = urllib.request.Request(BASE + path, data=data, method=method)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    req.add_header('User-Agent', 'ff-release-bot/1.0')
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


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--ipa', required=True)
    ap.add_argument('--version', required=True)
    ap.add_argument('--build', required=True, type=int)
    ap.add_argument('--notes', required=True, help='更新说明文件路径')
    ap.add_argument('--token', required=True)
    args = ap.parse_args()

    if not os.path.isfile(args.ipa):
        sys.exit('ipa 不存在: %s' % args.ipa)
    raw = open(args.ipa, 'rb').read()
    size = len(raw)
    digest = hashlib.sha256(raw).hexdigest()
    key_name = '%s-%d.ipa' % (args.version, args.build)
    print('本地: %s  %.2f MB  sha256=%s' % (key_name, size / 1048576.0, digest[:16]))

    # 1. 上传字节
    st, r = call('/api/app/version/upload', data=raw, headers={
        'x-release-token': args.token,
        'x-file-name': key_name,
        'Content-Type': 'application/octet-stream',
    }, timeout=300)
    print('upload -> %s %s' % (st, json.dumps(r, ensure_ascii=False)[:200] if isinstance(r, dict) else r))
    if st != 200 or not isinstance(r, dict) or not r.get('ok'):
        sys.exit('上传失败，终止')
    remote_sha = r.get('sha256')
    if remote_sha and remote_sha != digest:
        sys.exit('sha256 不一致：本地 %s / 远端 %s' % (digest, remote_sha))
    kv_key = r.get('key') or key_name

    # 2. 发布为 latest
    notes = open(args.notes, encoding='utf-8').read().strip()
    payload = json.dumps({
        'build': args.build,
        'version': args.version,
        'notes': notes,
        'ipaKey': kv_key,
        'channel': 'ios',
    }, ensure_ascii=False).encode('utf-8')
    st, r2 = call('/api/app/version', data=payload, headers={
        'x-release-token': args.token,
        'Content-Type': 'application/json',
    }, timeout=60)
    print('publish -> %s %s' % (st, json.dumps(r2, ensure_ascii=False)[:300] if isinstance(r2, dict) else r2))
    if st != 200 or not isinstance(r2, dict) or not r2.get('ok'):
        sys.exit('发布失败')

    # 3. 回读校验
    st, latest = call('/api/app/version', method='GET', timeout=30)
    if isinstance(latest, dict):
        lt = latest.get('latest') or {}
        print('线上 latest: build=%s version=%s ipa=%s' % (lt.get('build'), lt.get('version'), lt.get('ipaKey') or lt.get('key')))
    print('DONE')


if __name__ == '__main__':
    main()
