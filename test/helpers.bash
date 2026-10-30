# Shared setup: a throwaway GROVE_ROOT, HOME and git config, and the gh stub first on the PATH.

setup() {
  T=$(mktemp -d)
  export HOME=$T/home GROVE_ROOT=$T/root GH_STUB=$T/gh
  mkdir -p "$HOME" "$GROVE_ROOT" "$GH_STUB/repos"
  export PATH="$BATS_TEST_DIRNAME/stub:$PATH"
  unset GROVE_LOCAL_OWNER GROVE_DEFAULT_VISIBILITY GROVE_TEMPLATES
  export GIT_CONFIG_GLOBAL=$T/gitconfig GIT_CONFIG_NOSYSTEM=1
  git config --global user.name Test
  git config --global user.email test@example.com
  git config --global init.defaultBranch main
  git config --global protocol.file.allow always
  git config --global "url.file://$GH_STUB/repos/.insteadOf" https://github.com/
  grove=$BATS_TEST_DIRNAME/../grove.sh
}

teardown() {
  # Background processes started by a test (see hold_cwd) must not outlive it.
  jobs -p | xargs -r kill 2>/dev/null || true
  chmod -R u+w "$T" 2>/dev/null || true
  rm -rf "$T"
}

# remote_repo <owner>/<repo> [parent]: a "GitHub" repo with one commit on main; parent makes it a fork.
remote_repo() {
  local src=$T/src/$1
  mkdir -p "$src"
  git -C "$src" init --quiet -b main
  echo "$1" >"$src/README.md"
  git -C "$src" add README.md
  git -C "$src" commit --quiet -m init
  git clone --quiet --bare "$src" "$GH_STUB/repos/$1.git"
  if [ -n "${2:-}" ]; then echo "$2" >"$GH_STUB/repos/$1.git/parent"; fi
}

# cloned <owner>/<repo>: the repo exists on "GitHub" and is cloned under GROVE_ROOT.
cloned() {
  remote_repo "$1"
  "$grove" clone "$1" >/dev/null 2>&1
  echo "$GROVE_ROOT/$1"
}

# local_repo <repo>: a repo with no remote under the local owner.
local_repo() {
  "$grove" new "$1" 2>/dev/null
}

# commit_in <dir> <file>: add and commit a file.
commit_in() {
  echo "$2" >"$1/$2"
  git -C "$1" add "$2"
  git -C "$1" commit --quiet -m "add $2"
}

# age <dir>: make every file look untouched for two hours.
age() {
  find "$1" -exec touch -h -d '2 hours ago' {} +
}

# hold_cwd <dir>: a background process whose working directory is <dir>.
hold_cwd() {
  (cd "$1" && exec sleep 60) &
  sleep 0.2
}
