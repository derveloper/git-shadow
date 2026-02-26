#!/usr/bin/env bash
set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")" && pwd)/git-shadow"
SANDBOX="$(mktemp -d)"
export GIT_SHADOW_DIR="${SANDBOX}/shadows"
export GIT_AUTHOR_NAME="test" GIT_AUTHOR_EMAIL="test@test" GIT_COMMITTER_NAME="test" GIT_COMMITTER_EMAIL="test@test"

pass=0 fail=0 total=0

cleanup() {
    rm -rf "$SANDBOX"
    echo ""
    if (( fail == 0 )); then
        printf '\033[1;32mall %d tests passed\033[0m\n' "$total"
    else
        printf '\033[1;31m%d/%d failed\033[0m\n' "$fail" "$total"
        exit 1
    fi
}
trap cleanup EXIT

run_test() {
    local name="$1"
    shift
    total=$((total + 1))

    local workdir="${SANDBOX}/work/${name}"
    mkdir -p "$workdir"

    if (cd "$workdir" && "$@") &>/dev/null 2>&1; then
        pass=$((pass + 1))
        printf '  \033[32m✓\033[0m %s\n' "$name"
    else
        fail=$((fail + 1))
        printf '  \033[31m✗\033[0m %s\n' "$name"
    fi
}

# helper: create a repo with one commit
make_repo() {
    git init --quiet .
    echo "content" > file.txt
    git add file.txt
    git commit --quiet -m "initial"
}

echo "git-shadow tests"
echo ""

# --- init ---

run_test "init creates shadow repo" bash -c '
    "$1" init --quiet
    [[ -d "${GIT_SHADOW_DIR}" ]]
    shadow=$(ls "${GIT_SHADOW_DIR}" | head -1)
    [[ -n "$shadow" ]]
' _ "$SCRIPT"

run_test "init sets up remote" bash -c '
    "$1" init --quiet
    git remote get-url shadow &>/dev/null
' _ "$SCRIPT"

run_test "init installs all hooks" bash -c '
    "$1" init --quiet
    for h in post-commit post-merge post-rewrite; do
        [[ -x ".git/hooks/$h" ]] || exit 1
        grep -q "git-shadow" ".git/hooks/$h" || exit 1
    done
' _ "$SCRIPT"

run_test "init skips bare repos" bash -c '
    "$1" init --bare --quiet ./bare.git 2>&1 | grep -q "skipping"
' _ "$SCRIPT"

run_test "init with directory argument" bash -c '
    "$1" init --quiet subdir
    [[ -d subdir/.git ]]
    (cd subdir && git remote get-url shadow &>/dev/null)
' _ "$SCRIPT"

# --- commit -> shadow ---

run_test "commit reaches shadow" bash -c '
    "$1" init --quiet
    echo "hello" > test.txt
    git add test.txt
    git commit --quiet -m "test commit"
    sleep 1
    url="$(git remote get-url shadow)"
    git -C "$url" log --oneline | grep -q "test commit"
' _ "$SCRIPT"

run_test "multiple branches in shadow" bash -c '
    "$1" init --quiet
    echo a > a.txt && git add a.txt && git commit --quiet -m "on main"
    sleep 0.5
    git switch --quiet -c feature
    echo b > b.txt && git add b.txt && git commit --quiet -m "on feature"
    sleep 1
    url="$(git remote get-url shadow)"
    git -C "$url" branch | grep -q main
    git -C "$url" branch | grep -q feature
' _ "$SCRIPT"

run_test "amend force-pushes to shadow" bash -c '
    "$1" init --quiet
    echo v1 > f.txt && git add f.txt && git commit --quiet -m "original"
    sleep 0.5
    echo v2 >> f.txt && git add f.txt && git commit --quiet --amend -m "amended"
    sleep 1
    url="$(git remote get-url shadow)"
    git -C "$url" log --oneline | grep -q "amended"
    ! git -C "$url" log --oneline | grep -q "original"
' _ "$SCRIPT"

# --- enable ---

run_test "enable on existing repo" bash -c '
    git init --quiet .
    echo x > x.txt && git add x.txt && git commit --quiet -m "existing"
    "$1" enable
    git remote get-url shadow &>/dev/null
    url="$(git remote get-url shadow)"
    git -C "$url" log --oneline | grep -q "existing"
' _ "$SCRIPT"

run_test "enable fails outside git repo" bash -c '
    ! "$1" enable 2>/dev/null
' _ "$SCRIPT"

# --- disable ---

run_test "disable removes remote and hooks" bash -c '
    "$1" init --quiet
    "$1" disable
    ! git remote get-url shadow &>/dev/null 2>&1
    [[ ! -f .git/hooks/post-commit ]]
' _ "$SCRIPT"

run_test "disable keeps shadow repo" bash -c '
    "$1" init --quiet
    url="$(git remote get-url shadow)"
    "$1" disable
    [[ -d "$url" ]]
' _ "$SCRIPT"

# --- status ---

run_test "status shows active" bash -c '
    "$1" init --quiet
    "$1" status 2>&1 | grep -q "active"
' _ "$SCRIPT"

run_test "status shows not active" bash -c '
    git init --quiet .
    "$1" status 2>&1 | grep -q "not active"
' _ "$SCRIPT"

# --- list ---

run_test "list shows shadow repos" bash -c '
    mkdir proj && cd proj
    "$1" init --quiet
    "$1" list 2>&1 | grep -q "shadow.git"
' _ "$SCRIPT"

run_test "list marks deleted sources as gone" bash -c '
    mkdir ephemeral && cd ephemeral
    "$1" init --quiet
    cd ..
    rm -rf ephemeral
    "$1" list 2>&1 | grep -q "gone"
' _ "$SCRIPT"

# --- collision ---

run_test "dirname collision gets hash suffix" bash -c '
    mkdir -p a/myapp b/myapp
    (cd a/myapp && "$1" init --quiet)
    (cd b/myapp && "$1" init --quiet)
    count=$(ls -d "${GIT_SHADOW_DIR}"/myapp-shadow* | wc -l | xargs)
    [[ "$count" -eq 2 ]]
' _ "$SCRIPT"

# --- hooks coexist ---

run_test "hooks append to existing hooks" bash -c '
    git init --quiet .
    mkdir -p .git/hooks
    printf "#!/usr/bin/env bash\necho existing" > .git/hooks/post-commit
    chmod +x .git/hooks/post-commit
    "$1" enable
    grep -q "existing" .git/hooks/post-commit
    grep -q "git-shadow" .git/hooks/post-commit
' _ "$SCRIPT"

run_test "enable is idempotent" bash -c '
    "$1" init --quiet
    "$1" enable
    "$1" enable
    count=$(grep -c "git-shadow" .git/hooks/post-commit)
    [[ "$count" -eq 2 ]]  # marker + end marker, not duplicated
' _ "$SCRIPT"

# --- recovery ---

run_test "full recovery after rm -rf" bash -c '
    mkdir project && cd project
    "$1" init --quiet
    echo "important" > data.txt
    git add data.txt
    git commit --quiet -m "save me"
    sleep 1
    shadow="$(git remote get-url shadow)"
    cd ..
    rm -rf project
    git clone --quiet "$shadow" recovered
    [[ -f recovered/data.txt ]]
    grep -q "important" recovered/data.txt
' _ "$SCRIPT"
