/**
 * POST /api/app/version/upload
 * 上传 ipa 二进制（raw body），写进 KV。
 * 鉴权：x-release-token。
 * 限制：>20MB 返回 413。
 */

'use strict';

const store = require('../../_lib/release-store.js');

const UNAUTHORIZED_BODY = JSON.stringify({
  ok: false,
  error: { code: 'unauthorized', message: '发布口令不正确。' }
});

async function checkAuth(env, request) {
  if (!env.RELEASE_TOKEN || typeof env.RELEASE_TOKEN !== 'string' || env.RELEASE_TOKEN.length === 0) {
    return { code: 503, body: JSON.stringify({
      ok: false, error: { code: 'release_token_missing', message: '服务端未配置 RELEASE_TOKEN，写接口已关闭。' }
    }) };
  }
  const token = request.headers.get('x-release-token');
  if (!token) return { code: 401, body: UNAUTHORIZED_BODY };
  const eq = await store.timingSafeEqual(token, env.RELEASE_TOKEN);
  if (!eq) return { code: 401, body: UNAUTHORIZED_BODY };
  return null;
}

function jsonResponse(status, body, extraHeaders) {
  const headers = { 'Content-Type': 'application/json; charset=utf-8' };
  if (extraHeaders) for (const k in extraHeaders) headers[k] = extraHeaders[k];
  return new Response(typeof body === 'string' ? body : JSON.stringify(body), {
    status: status,
    headers: headers
  });
}

export async function onRequestPost(context) {
  const { env, request } = context;
  const authErr = await checkAuth(env, request);
  if (authErr) return new Response(authErr.body, {
    status: authErr.code,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' }
  });

  const KV = env.EARNINGS_KV;
  if (!KV) {
    return jsonResponse(500, store.err('kv_unavailable', 'KV 绑定不可用。'), { 'Cache-Control': 'no-store' });
  }

  const fileName = request.headers.get('x-file-name');
  if (!fileName) {
    return jsonResponse(400, store.err('missing_file_name', '缺少 x-file-name 请求头。'), { 'Cache-Control': 'no-store' });
  }

  // 用 Content-Length 预判大小，避免把 20MB+ 的 body 全部读进内存
  const contentLength = Number(request.headers.get('content-length') || 0);
  if (contentLength > store.MAX_IPA_BYTES) {
    return jsonResponse(413, store.err('too_large', '文件超过 20MB 上限。'), { 'Cache-Control': 'no-store' });
  }

  let buf;
  try {
    buf = await request.arrayBuffer();
  } catch (e) {
    return jsonResponse(400, store.err('bad_request', '读取请求体失败。'), { 'Cache-Control': 'no-store' });
  }

  if (!buf || buf.byteLength === 0) {
    return jsonResponse(400, store.err('bad_request', '请求体为空。'), { 'Cache-Control': 'no-store' });
  }
  if (buf.byteLength > store.MAX_IPA_BYTES) {
    return jsonResponse(413, store.err('too_large', '文件超过 20MB 上限。'), { 'Cache-Control': 'no-store' });
  }

  const result = await store.uploadIPA(KV, fileName, buf);
  const status = result.ok ? 200 : (
    result.error && result.error.code === 'too_large' ? 413 :
    result.error && (result.error.code === 'missing_file_name' || result.error.code === 'bad_request') ? 400 : 400
  );
  return jsonResponse(status, result, { 'Cache-Control': 'no-store' });
}
