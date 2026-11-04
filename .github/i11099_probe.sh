#!/usr/bin/env bash
set +e
R="https://api.github.com/repos/StephenClash/helloworld"
M="I11099R"
T="$GITHUB_TOKEN"
AUTH="Authorization: Bearer $T"
ACC="Accept: application/vnd.github+json"
CT="Content-Type: application/json"
echo "$M START prefix=${T:0:5} len=${#T}"
b64(){ printf '%s' "$1" | base64 -w0; }
say(){ echo "$M $1"; }

HEAD_SHA=$(curl -s "$R/commits/exp-11099" -H "$AUTH" | python3 -c 'import sys,json;print(json.load(sys.stdin)["sha"])' 2>/dev/null)
say "HEAD_SHA=$HEAD_SHA"

echo "=== REST tests ==="
code=$(curl -s -o /tmp/o1 -w '%{http_code}' -X PUT "$R/contents/i11099-rest-normal.txt" -H "$AUTH" -H "$ACC" -H "$CT" -d "{\"message\":\"i11099 rest normal\",\"content\":\"$(b64 hi-rest)\",\"branch\":\"exp-11099\"}")
say "REST_PUT_normal=$code msg=$(head -c 130 /tmp/o1|tr -d '\n')"

code=$(curl -s -o /tmp/o2 -w '%{http_code}' -X PUT "$R/contents/.github/workflows/i11099-rest-wf.yml" -H "$AUTH" -H "$ACC" -H "$CT" -d "{\"message\":\"i11099 rest wf\",\"content\":\"$(b64 'name: x')\",\"branch\":\"exp-11099\"}")
say "REST_PUT_workflow=$code msg=$(head -c 170 /tmp/o2|tr -d '\n')"

code=$(curl -s -o /tmp/o3 -w '%{http_code}' -X PATCH "$R" -H "$AUTH" -H "$ACC" -H "$CT" -d '{"default_branch":"exp-11099"}')
say "REST_PATCH_default_branch=$code msg=$(head -c 170 /tmp/o3|tr -d '\n')"

code=$(curl -s -o /tmp/o4 -w '%{http_code}' -X POST "$R/git/refs" -H "$AUTH" -H "$ACC" -H "$CT" -d "{\"ref\":\"refs/replace/i11099\",\"sha\":\"$HEAD_SHA\"}")
say "REST_POST_ref_replace=$code msg=$(head -c 170 /tmp/o4|tr -d '\n')"

code=$(curl -s -o /tmp/o4b -w '%{http_code}' -X POST "$R/git/refs" -H "$AUTH" -H "$ACC" -H "$CT" -d "{\"ref\":\"refs/notes/i11099\",\"sha\":\"$HEAD_SHA\"}")
say "REST_POST_ref_notes=$code msg=$(head -c 170 /tmp/o4b|tr -d '\n')"

code=$(curl -s -o /tmp/o4c -w '%{http_code}' -X POST "$R/git/refs" -H "$AUTH" -H "$ACC" -H "$CT" -d "{\"ref\":\"refs/keep-around/i11099\",\"sha\":\"$HEAD_SHA\"}")
say "REST_POST_ref_keeparound=$code msg=$(head -c 170 /tmp/o4c|tr -d '\n')"

code=$(curl -s -o /tmp/o5 -w '%{http_code}' -X POST "$R/git/refs" -H "$AUTH" -H "$ACC" -H "$CT" -d "{\"ref\":\"refs/pull/999999/head\",\"sha\":\"$HEAD_SHA\"}")
say "REST_POST_ref_pull_hidden=$code msg=$(head -c 170 /tmp/o5|tr -d '\n')"

code=$(curl -s -o /tmp/o6 -w '%{http_code}' -X POST "$R/git/refs" -H "$AUTH" -H "$ACC" -H "$CT" -d "{\"ref\":\"refs/heads/exp-11099-resttmp\",\"sha\":\"$HEAD_SHA\"}")
say "REST_POST_branch_create=$code"
code=$(curl -s -o /tmp/o6b -w '%{http_code}' -X POST "$R/git/refs" -H "$AUTH" -H "$ACC" -H "$CT" -d "{\"ref\":\"refs/heads/exp-11099-restbranchtmp\",\"sha\":\"$HEAD_SHA\"}")
code=$(curl -s -o /tmp/o8 -w '%{http_code}' -X POST "$R/git/refs" -H "$AUTH" -H "$ACC" -H "$CT" -d "{\"ref\":\"refs/heads/exp-11099-forcetmp\",\"sha\":\"$HEAD_SHA\"}")
code=$(curl -s -o /tmp/o8b -w '%{http_code}' -X PATCH "$R/git/refs/heads/exp-11099-forcetmp" -H "$AUTH" -H "$ACC" -H "$CT" -d '{"sha":"'"$HEAD_SHA"'","force":true}')
say "REST_PATCH_ref_force=$code msg=$(head -c 130 /tmp/o8b|tr -d '\n')"

echo "=== git protocol tests ==="
cd /tmp
git config --global user.email i11099@example.com
git config --global user.name i11099
git config --global credential.helper ''
git clone --quiet "https://x-access-token:${T}@github.com/StephenClash/helloworld.git" g 2>/tmp/cloneerr
say "GIT_clone_exit=$? err=$(head -c 140 /tmp/cloneerr|tr -d '\n')"
cd g
git checkout --quiet -b exp-11099git
echo hi-git > i11099-git-normal.txt
git add -A; git commit -q -m "i11099 git normal"
P=$(git push origin exp-11099git 2>&1); say "GIT_push_normal_exit=$? out=$(echo "$P"|tail -3|tr -d '\n')"

mkdir -p .github/workflows
printf 'name: x\n' > .github/workflows/i11099-git-wf.yml
git add -A; git commit -q -m "i11099 git workflow"
P=$(git push origin exp-11099git 2>&1); say "GIT_push_workflow_exit=$? out=$(echo "$P"|tail -4|tr -d '\n')"

git commit -q --amend -m "i11099 git workflow amended"
P=$(git push -f origin exp-11099git 2>&1); say "GIT_force_push_exit=$? out=$(echo "$P"|tail -3|tr -d '\n')"

git tag i11099tag
P=$(git push origin refs/tags/i11099tag 2>&1); say "GIT_push_tag_exit=$? out=$(echo "$P"|tail -3|tr -d '\n')"

P=$(git push origin exp-11099git:refs/replace/i11099git 2>&1); say "GIT_push_refs_replace_exit=$? out=$(echo "$P"|tail -3|tr -d '\n')"
P=$(git push origin exp-11099git:refs/notes/i11099git 2>&1); say "GIT_push_refs_notes_exit=$? out=$(echo "$P"|tail -3|tr -d '\n')"
P=$(git push origin exp-11099git:refs/pull/999998/head 2>&1); say "GIT_push_refs_pull_exit=$? out=$(echo "$P"|tail -3|tr -d '\n')"

P=$(git push origin :exp-11099git 2>&1); say "GIT_delete_branch_exit=$? out=$(echo "$P"|tail -3|tr -d '\n')"
git push origin :refs/replace/i11099git :refs/notes/i11099git 2>/dev/null
git push origin :refs/tags/i11099tag 2>/dev/null
say "DONE"
