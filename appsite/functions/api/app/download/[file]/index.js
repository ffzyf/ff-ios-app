/**
 * GET /api/app/download/:file
 * 匿名直链，返回 ipa 二进制。
 * 200 application/octet-stream + Content-Disposition attachment
 * 404 not_found
 */

'use strict';

const store = require('../../../_lib/release-store.js');

export async function onRequestGet(context) {
  const { env, params } = context;
  const KV = env.EARNINGS_KV;
  if (!KV) {
    return new Response(JSON.stringify({ ok: false, error: { code: 'kv_unavailable', message: 'KV 绑定不可用。' } }), {
      status: 500,
      headers: { 'Content-Type': 'application/json; charset=utf-8' }
    });
  }

  const file = params.file;
  if (!file || typeof file !== 'string') {
    return notFound();
  }
  // 路径遍历防护：不允许路径分隔符与控制字符
  if (/[\/\\\x00-\x1f]/.test(file)) {
    return notFound();
  }

  const buf = await store.readFile(KV, file);
  if (!buf) return notFound();

  // 安全的文件名：只保留可打印 ASCII
  const safeName = file.replace(/[^0-9A-Za-z._-]/g, '_');

  return new Response(buf, {
    status: 200,
    headers: {
      'Content-Type': 'application/octet-stream',
      'Content-Disposition': 'attachment; filename="' + safeName + '"',
      'Content-Length': String(buf.byteLength),
      'Cache-Control': 'public, max-age=86400, s-maxage=86400'
    }
  });
}

function notFound() {
  return new Response(JSON.stringify({ ok: false, error: { code: 'not_found', message: '文件不存在。' } }), {
    status: 404,
    headers: { 'Content-Type': 'application/json; charset=utf-8' }
  });
}
