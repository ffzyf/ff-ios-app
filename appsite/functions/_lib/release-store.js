/**
 * release-store.js
 * 云控更新 · KV 读写与业务逻辑封装（纯函数 + KV 封装）。
 *
 * KV 键约定：
 *   release:ios:latest    —— 最新版元数据 JSON（≤2KB，不设 TTL）
 *   release:ios:history   —— 最近 5 版的历史数组（不设 TTL）
 *   release:ios:file:<key>—— ipa 二进制（不设 TTL）
 *
 * 端点只管 HTTP；业务规则都在这里，保持可测试。
 */

'use strict';

const KV_PREFIX = 'release:ios:';
const LATEST_KEY = KV_PREFIX + 'latest';
const HISTORY_KEY = KV_PREFIX + 'history';
const FILE_PREFIX = KV_PREFIX + 'file:';
const HISTORY_LIMIT = 5;
const FILE_KEEP_BUILDS = 3; // ipa 二进制保留最近 3 个 build

const MAX_IPA_BYTES = 20 * 1024 * 1024; // 20 MB

/* ---------- 小工具 ---------- */

function nowISO() {
  return new Date().toISOString();
}

/**
 * 常量时间比较（先 SHA-256，再逐字节 XOR 累加）。
 * 不直接用 ===，避免字节级时序泄露。
 *
 * @param {string} a
 * @param {string} b
 * @returns {Promise<boolean>}
 */
async function timingSafeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const enc = new TextEncoder();
  const [ha, hb] = await Promise.all([
    crypto.subtle.digest('SHA-256', enc.encode(a)),
    crypto.subtle.digest('SHA-256', enc.encode(b))
  ]);
  const ba = new Uint8Array(ha);
  const bb = new Uint8Array(hb);
  if (ba.length !== bb.length) return false;
  let diff = 0;
  for (let i = 0; i < ba.length; i++) diff |= ba[i] ^ bb[i];
  return diff === 0;
}

/**
 * 计算二进制的 SHA-256（hex 字符串）。
 * @param {ArrayBuffer} buf
 * @returns {Promise<string>}
 */
async function sha256Hex(buf) {
  const digest = await crypto.subtle.digest('SHA-256', buf);
  const bytes = new Uint8Array(digest);
  let out = '';
  for (let i = 0; i < bytes.length; i++) {
    out += bytes[i].toString(16).padStart(2, '0');
  }
  return out;
}

/* ---------- 信封统一响应 ---------- */

function ok(extra) {
  return Object.assign({ ok: true }, extra || {});
}

function err(code, message) {
  return { ok: false, error: { code: code, message: message } };
}

/* ---------- 校验 ---------- */

/**
 * 校验发布元数据字段。返回 null 通过，否则返回错误对象。
 */
function validateReleaseMeta(meta) {
  if (!meta || typeof meta !== 'object') return { code: 'bad_request', message: '请求体必须是 JSON 对象。' };
  const build = Number(meta.build);
  if (!isFinite(build) || build <= 0 || Math.floor(build) !== build) {
    return { code: 'bad_request', message: 'build 必须是正整数。' };
  }
  if (typeof meta.version !== 'string') {
    return { code: 'bad_request', message: 'version 必须是字符串。' };
  }
  if (typeof meta.notes !== 'string') {
    return { code: 'bad_request', message: 'notes 必须是字符串。' };
  }
  if (typeof meta.ipaKey !== 'string' || !meta.ipaKey) {
    return { code: 'ipa_key_missing', message: 'ipaKey 不能为空。' };
  }
  // ipaKey 不允许包含路径分隔符与危险字符
  if (/[\/\\\x00-\x1f]/.test(meta.ipaKey)) {
    return { code: 'bad_request', message: 'ipaKey 包含非法字符。' };
  }
  return null;
}

/* ---------- KV 封装 ---------- */

/**
 * 读 latest。未发布过返回 null。KV 不可用返回 null（调用方自行判断 500）。
 */
async function readLatest(KV) {
  try {
    const raw = await KV.get(LATEST_KEY, 'json');
    return raw || null;
  } catch (e) {
    return null;
  }
}

async function writeLatest(KV, meta) {
  await KV.put(LATEST_KEY, JSON.stringify(meta));
}

async function readHistory(KV) {
  try {
    const raw = await KV.get(HISTORY_KEY, 'json');
    if (Array.isArray(raw)) return raw;
    return [];
  } catch (e) {
    return [];
  }
}

async function writeHistory(KV, list) {
  const trimmed = list.slice(0, HISTORY_LIMIT);
  await KV.put(HISTORY_KEY, JSON.stringify(trimmed));
}

async function fileExists(KV, key) {
  try {
    // KV 没有 exists；用 get 加 type=arrayBuffer 会浪费流量，这里用 metadata 头
    const meta = await KV.getWithMetadata(FILE_PREFIX + key);
    return meta && meta.value !== null && meta.value !== undefined;
  } catch (e) {
    return false;
  }
}

async function readFile(KV, key) {
  try {
    const buf = await KV.get(FILE_PREFIX + key, 'arrayBuffer');
    return buf || null;
  } catch (e) {
    return null;
  }
}

async function writeFile(KV, key, buf) {
  await KV.put(FILE_PREFIX + key, buf);
}

async function deleteFile(KV, key) {
  await KV.delete(FILE_PREFIX + key);
}

/* ---------- 业务操作 ---------- */

/**
 * 上传 ipa 文件。
 * @returns {Promise<{ok:boolean, key:string, size:number, sha256:string}|{ok:false, error}>}
 */
async function uploadIPA(KV, fileName, buf) {
  if (!fileName || typeof fileName !== 'string' || !fileName) {
    return err('missing_file_name', '缺少 x-file-name 请求头。');
  }
  if (/[\/\\\x00-\x1f]/.test(fileName)) {
    return err('bad_request', '文件名包含非法字符。');
  }
  if (!buf || buf.byteLength === 0) {
    return err('bad_request', '请求体为空。');
  }
  if (buf.byteLength > MAX_IPA_BYTES) {
    return err('too_large', '文件超过 20MB 上限。');
  }
  const hash = await sha256Hex(buf);
  await writeFile(KV, fileName, buf);
  return ok({ key: fileName, size: buf.byteLength, sha256: hash });
}

/**
 * 发布版本。
 * 失败返回 { ok:false, error }，statusCode 字段可选。
 */
async function publishRelease(KV, meta) {
  const vErr = validateReleaseMeta(meta);
  if (vErr) return err(vErr.code, vErr.message);

  // 校验 ipaKey 在 KV 里存在
  const exists = await fileExists(KV, meta.ipaKey);
  if (!exists) return err('ipa_key_missing', '指定的 ipaKey 在 KV 中不存在，请先上传。');

  const latest = await readLatest(KV);
  const history = await readHistory(KV);

  // build 单调校验：比 latest.build 小 → build_regression
  if (latest && latest.build != null) {
    const curBuild = Number(latest.build);
    const newBuild = Number(meta.build);
    if (newBuild < curBuild) {
      return err('build_regression', 'build ' + newBuild + ' 小于当前 ' + curBuild + '，不允许回退。');
    }
  }

  // 组装 latest 对象（与 GET /api/app/version 返回的结构一致）
  const publishedAt = nowISO();
  const ipaPath = '/api/app/download/' + encodeURIComponent(meta.ipaKey);
  const size = Number(meta.size) || 0;

  const newLatest = {
    build: Number(meta.build),
    version: meta.version,
    notes: meta.notes,
    size: size,
    sha256: meta.sha256 || '',
    publishedAt: publishedAt,
    ipaPath: ipaPath,
    ipaKey: meta.ipaKey
  };

  // 写入 latest
  await writeLatest(KV, newLatest);

  // 更新 history：同 build 替换，不同 build 插到首位并裁剪到 HISTORY_LIMIT
  const histItem = {
    build: newLatest.build,
    version: newLatest.version,
    publishedAt: newLatest.publishedAt,
    ipaKey: newLatest.ipaKey,
    ipaPath: newLatest.ipaPath,
    size: newLatest.size,
    sha256: newLatest.sha256,
    notes: newLatest.notes
  };
  const filtered = history.filter(function (h) { return Number(h.build) !== Number(meta.build); });
  filtered.unshift(histItem);
  const trimmed = filtered.slice(0, HISTORY_LIMIT);
  await writeHistory(KV, trimmed);

  // 清理旧 ipa 二进制：只保留最近 FILE_KEEP_BUILDS 个 build 的
  await cleanupOldFiles(KV, trimmed);

  return ok({ latest: newLatest });
}

/**
 * 撤回指定 build。
 * - 若 build == 当前 latest.build：latest 回退到 history 下一条（没有则 null）
 * - history 中去掉该 build
 * - ipa 二进制也删掉
 */
async function withdrawBuild(KV, build) {
  const b = Number(build);
  if (!isFinite(b) || b <= 0 || Math.floor(b) !== b) {
    return err('bad_request', 'build 必须是正整数。');
  }

  const latest = await readLatest(KV);
  const history = await readHistory(KV);

  const inHistory = history.some(function (h) { return Number(h.build) === b; });
  const isLatest = latest && Number(latest.build) === b;

  if (!isLatest && !inHistory) {
    return err('not_found', 'build ' + b + ' 不存在。');
  }

  // 找到要删的 ipaKey
  let ipaKeyToDelete = null;
  if (isLatest) ipaKeyToDelete = latest.ipaKey;
  else {
    const hit = history.find(function (h) { return Number(h.build) === b; });
    if (hit) ipaKeyToDelete = hit.ipaKey;
  }

  // 从 history 里移除
  const newHistory = history.filter(function (h) { return Number(h.build) !== b; });

  // 计算新的 latest
  let newLatest = null;
  if (isLatest) {
    if (newHistory.length > 0) {
      // 回退到 history 中下一个 build 最大的
      var sorted = newHistory.slice().sort(function (a, c) { return Number(c.build) - Number(a.build); });
      var top = sorted[0];
      newLatest = {
        build: Number(top.build),
        version: top.version || '',
        notes: top.notes || '',
        size: Number(top.size) || 0,
        sha256: top.sha256 || '',
        publishedAt: top.publishedAt || nowISO(),
        ipaPath: top.ipaPath || ('/api/app/download/' + encodeURIComponent(top.ipaKey || '')),
        ipaKey: top.ipaKey || ''
      };
    }
  } else {
    newLatest = latest; // 撤回的不是 latest，latest 不变
  }

  // 写回
  if (newLatest) await writeLatest(KV, newLatest);
  else await KV.delete(LATEST_KEY);
  await writeHistory(KV, newHistory);

  // 删 ipa 二进制（如果存在且不在保留列表里）
  if (ipaKeyToDelete) {
    const stillKept = newHistory.some(function (h) { return h.ipaKey === ipaKeyToDelete; });
    if (!stillKept) {
      try { await deleteFile(KV, ipaKeyToDelete); } catch (e) { /* 删除失败不影响主流程 */ }
    }
  }

  return ok({});
}

/**
 * 清理 ipa 二进制：只保留最近 FILE_KEEP_BUILDS 个 build 的文件。
 */
async function cleanupOldFiles(KV, historyList) {
  if (!historyList || historyList.length === 0) return;
  const sorted = historyList.slice().sort(function (a, b) { return Number(b.build) - Number(a.build); });
  const keep = sorted.slice(0, FILE_KEEP_BUILDS);
  const keepKeys = new Set(keep.map(function (h) { return h.ipaKey; }));
  const toDelete = sorted.slice(FILE_KEEP_BUILDS);
  for (let i = 0; i < toDelete.length; i++) {
    const key = toDelete[i].ipaKey;
    if (key && !keepKeys.has(key)) {
      try { await deleteFile(KV, key); } catch (e) { /* 忽略 */ }
    }
  }
}

/* ---------- 导出 ---------- */

module.exports = {
  // 常量
  LATEST_KEY: LATEST_KEY,
  HISTORY_KEY: HISTORY_KEY,
  FILE_PREFIX: FILE_PREFIX,
  HISTORY_LIMIT: HISTORY_LIMIT,
  FILE_KEEP_BUILDS: FILE_KEEP_BUILDS,
  MAX_IPA_BYTES: MAX_IPA_BYTES,
  // 工具
  timingSafeEqual: timingSafeEqual,
  sha256Hex: sha256Hex,
  ok: ok,
  err: err,
  nowISO: nowISO,
  // KV 封装
  readLatest: readLatest,
  writeLatest: writeLatest,
  readHistory: readHistory,
  writeHistory: writeHistory,
  fileExists: fileExists,
  readFile: readFile,
  writeFile: writeFile,
  deleteFile: deleteFile,
  // 业务操作
  validateReleaseMeta: validateReleaseMeta,
  uploadIPA: uploadIPA,
  publishRelease: publishRelease,
  withdrawBuild: withdrawBuild,
  cleanupOldFiles: cleanupOldFiles
};
