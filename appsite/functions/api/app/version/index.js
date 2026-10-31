/**
 * GET    /api/app/version       —— 匿名，读 latest，60s 缓存
 * POST   /api/app/version       —— x-release-token 鉴权，发布版本
 * DELETE /api/app/version?build= —— x-release-token 鉴权，撤回指定 build
 *
 * 业务逻辑全部在 ../../_lib/release-store.js，此文件只负责 HTTP。
 */

'use strict';

const store = require('../../_lib/release-store.js');

const UNAUTHORIZED_BODY = JSON.stringify({
  ok: false,
  error: { code: 'unauthorized', message: '发布口令不正确。' }
});

async function checkAuth(env, request) {
  // fail-closed：未配置 RELEASE_TOKEN → 503
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
  if (extraHeaders) {
    for (const k in extraHeaders) headers[k] = extraHeaders[k];
  }
  return new Response(typeof body === 'string' ? body : JSON.stringify(body), {
    status: status,
    headers: headers
  });
}

export async function onRequestGet(context) {
  const { env, request } = context;
  const KV = env.EARNINGS_KV;
  if (!KV) {
    return jsonResponse(500, store.err('kv_unavailable', 'KV 绑定不可用。'));
  }
  try {
    const latest = await store.readLatest(KV);
    const body = store.ok({
      apiVersion: 1,
      serverTime: store.nowISO(),
      latest: latest ? sanitizeLatest(latest) : null
    });
    return jsonResponse(200, body, {
      'Cache-Control': 'public, max-age=60, s-maxage=60'
    });
  } catch (e) {
    return jsonResponse(500, store.err('kv_unavailable', '读取 KV 失败。'));
  }
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

  let body;
  try {
    body = await request.json();
  } catch (e) {
    return jsonResponse(400, store.err('bad_request', '请求体不是合法 JSON。'), { 'Cache-Control': 'no-store' });
  }

  const result = await store.publishRelease(KV, body);
  const status = result.ok ? 200 : (result.error && result.error.code === 'build_regression' ? 400
    : result.error && (result.error.code === 'ipa_key_missing' || result.error.code === 'bad_request') ? 400 : 400);
  // 把 ipaKey 也保留在 latest 里（管理页用），但不暴露给 GET 端。App 端只需要 ipaPath。
  if (result.ok && result.latest) {
    result.latest = sanitizeLatest(result.latest);
  }
  return jsonResponse(status, result, { 'Cache-Control': 'no-store' });
}

export async function onRequestDelete(context) {
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

  const url = new URL(request.url);
  const build = url.searchParams.get('build');
  if (!build) {
    return jsonResponse(400, store.err('bad_request', '缺少 build 参数。'), { 'Cache-Control': 'no-store' });
  }

  const result = await store.withdrawBuild(KV, build);
  const status = result.ok ? 200 : (result.error && result.error.code === 'not_found' ? 404 : 400);
  return jsonResponse(status, result, { 'Cache-Control': 'no-store' });
}

/**
 * GET / 对外的 latest 不暴露 ipaKey（KV 内部键名），只暴露 ipaPath。
 * POST 返回的 latest 也按同样规则处理。
 */
function sanitizeLatest(latest) {
  if (!latest) return null;
  // 保留 App 侧需要的字段
  return {
    build: Number(latest.build),
    version: latest.version || '',
    notes: latest.notes || '',
    size: Number(latest.size) || 0,
    sha256: latest.sha256 || '',
    publishedAt: latest.publishedAt || '',
    ipaPath: latest.ipaPath || ''
  };
}
