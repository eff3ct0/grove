#!/usr/bin/env bash
# grove: one clone per repo at <root>/<owner>/<repo>, work in sibling worktrees at <repo>.wt/<branch>.
# Design and reasons: docs/decisions.md.
set -euo pipefail

root=${GROVE_ROOT:-$HOME/git}
root=${root%/}
# git prints resolved paths; compare against the same spelling.
if [ -d "$root" ]; then root=$(cd "$root" && pwd -P); fi
local_owner=${GROVE_LOCAL_OWNER:-local}
default_visibility=${GROVE_DEFAULT_VISIBILITY:-private}
templates=${GROVE_TEMPLATES:-}

usage() {
  cat >&2 <<'EOF'
usage: grove <command>
  clone <owner>/<repo>|<url> [-- <git clone flags>]
                        clone to <root>/<owner>/<repo> and print the path; if it exists, only print the path.
  new <owner>/<repo> [--public|--private] [-t <template>]
                        create the repo on GitHub, with an initial commit on main, and print its path.
  new <repo> [-t <template>]
                        create a local repo (no remote) at <root>/<local owner>/<repo> and print its path.
  publish <owner> [--public|--private]
                        from inside a local repo: create it on GitHub, push main and the agent/* branches
                        that have a worktree, and move it (and its worktrees) to <root>/<owner>/.
  wt new <branch> [base]
                        create <repo>.wt/<branch with / -> -> from the current repo and print the path.
  wt ls                 list the worktrees of every repo under <root> with their state.
  wt rm <path>          remove a worktree; refuses if it has changes (or, with a remote, unpushed commits).
  wt gc [-n]            remove the worktrees that are clean, pushed, merged and unused for an hour. -n: dry run.

environment: GROVE_ROOT (default ~/git), GROVE_LOCAL_OWNER (default local),
             GROVE_DEFAULT_VISIBILITY (default private), GROVE_TEMPLATES (flake for -t, no default).
EOF
  exit 2
}

die() {
  echo "grove: $*" >&2
  exit 1
}

# <owner>/<repo> from a spec or a GitHub URL, as typed.
parse_spec() {
  local spec=$1
  spec=${spec#https://github.com/}
  spec=${spec#git@github.com:}
  spec=${spec%/}
  spec=${spec%.git}
  echo "$spec"
}

# Owner as GitHub spells it (users and organizations alike), or as typed when GitHub doesn't know it.
canonical_owner() {
  gh api "users/$1" -q .login 2>/dev/null || echo "$1"
}

cmd_clone() {
  [ $# -ge 1 ] || usage
  local spec full dest
  spec=$(parse_spec "$1")
  shift
  # Owner and name as GitHub spells them (case included), not as they were typed.
  full=$(gh repo view "$spec" --json nameWithOwner -q .nameWithOwner)
  dest=$root/$full
  if [ -e "$dest" ]; then
    echo "already exists" >&2
  else
    mkdir -p "$(dirname "$dest")"
    # On a fork, gh adds the upstream remote.
    gh repo clone "$full" "$dest" "$@" >&2
  fi
  echo "$dest"
}

visibility_flag() {
  case "$1" in
    private | public) echo "--$1" ;;
    *) die "visibility must be private or public, got '$1'" ;;
  esac
}

# Writes $2 with stdin unless $1/$2 already exists (a template may bring its own).
write_missing() {
  if [ -e "$1/$2" ]; then cat >/dev/null; else cat >"$1/$2"; fi
}

# init_repo <dir> <name> [template]: main branch with one commit, `chore: init`.
init_repo() {
  local dir=$1 name=$2 template=${3:-}
  mkdir -p "$dir"
  git -C "$dir" init --quiet -b main
  if [ -n "$template" ]; then (cd "$dir" && nix flake init -t "$templates#$template" >&2); fi
  write_missing "$dir" README.md <<EOF
# $name
EOF
  write_missing "$dir" AGENTS.md <<EOF
# $name

<What this project is, in one sentence.>

## Run

\`<command>\`

## Test

\`<command>\`
EOF
  write_missing "$dir" .gitignore <<'EOF'
.env
.direnv/
result
result-*
EOF
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m "chore: init"
}

cmd_new() {
  local spec='' template='' visibility=$default_visibility dest
  while [ $# -gt 0 ]; do
    case "$1" in
      --public) visibility=public ;;
      --private) visibility=private ;;
      -t)
        [ $# -ge 2 ] || usage
        template=$2
        shift
        ;;
      -*) usage ;;
      *)
        [ -z "$spec" ] || usage
        spec=$1
        ;;
    esac
    shift
  done
  [ -n "$spec" ] || usage
  if [ -n "$template" ] && [ -z "$templates" ]; then
    die "-t needs GROVE_TEMPLATES (a flake reference whose templates -t can name)"
  fi

  if [[ "$spec" != */* ]]; then
    dest=$root/$local_owner/$spec
    if [ -e "$dest" ]; then
      echo "already exists" >&2
    else
      # Leave nothing half-made behind.
      trap 'rm -rf "$dest"' EXIT
      init_repo "$dest" "$spec" "$template"
      trap - EXIT
    fi
    echo "$dest"
    return
  fi

  spec=$(parse_spec "$spec")
  spec=$(canonical_owner "${spec%%/*}")/${spec#*/}
  local flag
  flag=$(visibility_flag "$visibility")
  if gh repo view "$spec" --json nameWithOwner -q .nameWithOwner >/dev/null 2>&1; then
    die "$spec already exists on GitHub; use: grove clone $spec"
  fi
  dest=$root/$spec
  [ ! -e "$dest" ] || die "$dest already exists"
  trap 'rm -rf "$dest"' EXIT
  init_repo "$dest" "${spec#*/}" "$template"
  trap - EXIT
  # The only direct push to main grove makes. gh may have created the repo before failing, so the local one stays.
  if ! (cd "$dest" && gh repo create "$spec" "$flag" --source . --remote origin --push >&2); then
    die "creating $spec on GitHub failed; the local repo is at $dest. Check GitHub, then push it or remove both."
  fi
  echo "$dest"
}

# Main checkout of the repo that contains $1 (also from inside a worktree).
main_of() {
  local common
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) ||
    die "$1 is not inside a git repository"
  dirname "$common"
}

# Default branch: origin's HEAD, else the branch the main checkout is on, else main.
default_branch() {
  local main
  main=$(main_of "$1")
  git -C "$main" symbolic-ref --short -q refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' && return
  git -C "$main" symbolic-ref --short -q HEAD || echo main
}

has_origin() {
  git -C "$1" config remote.origin.url >/dev/null 2>&1
}

# Dirty, or git can't tell: a doubt keeps the worktree.
is_dirty() {
  local out
  out=$(git -C "$1" status --porcelain 2>/dev/null) || return 0
  [ -n "$out" ]
}

# Commits of HEAD that are on no remote, or ? when git can't tell.
unpushed() {
  git -C "$1" rev-list --count HEAD --not --remotes 2>/dev/null || echo '?'
}

# <owner>/<repo> of a GitHub remote URL, or nothing.
github_repo() {
  sed -nE 's#^(https://github\.com/|git@github\.com:)([^/]+/[^/]+)$#\2#p' <<<"${1%.git}"
}

# Merged: contained in origin/<default> (also a branch with no commits of its own), or with a merged PR
# (squash) whose head is HEAD, on origin or upstream (forks). Without origin: contained in the local default branch.
is_merged() {
  local wt=$1 branch=$2 head remote repo
  if ! has_origin "$wt"; then
    git -C "$wt" merge-base --is-ancestor HEAD "refs/heads/$(default_branch "$wt")" 2>/dev/null
    return
  fi
  head=$(git -C "$wt" rev-parse HEAD)
  if git -C "$wt" merge-base --is-ancestor HEAD "origin/$(default_branch "$wt")" 2>/dev/null; then
    return 0
  fi
  for remote in origin upstream; do
    repo=$(github_repo "$(git -C "$wt" config "remote.$remote.url" || true)")
    [ -n "$repo" ] || continue
    if gh pr list -R "$repo" --head "$branch" --state merged --json headRefOid -q '.[].headRefOid' 2>/dev/null |
      grep -qx "$head"; then
      return 0
    fi
  done
  return 1
}

# A process has its working directory inside $1, other than the pids listed in $2.
has_process_in() {
  local dir=$1 skip=" ${2:-} " p pid cwd
  for p in /proc/[0-9]*/cwd; do
    pid=${p#/proc/}
    pid=${pid%/cwd}
    case "$skip" in *" $pid "*) continue ;; esac
    cwd=$(readlink "$p" 2>/dev/null) || continue
    case "$cwd/" in "$dir"/*) return 0 ;; esac
  done
  return 1
}

# grove's pid and those of the processes that started it, such as the caller's shell.
ancestors() {
  local pid=$$
  while [ "$pid" -gt 1 ] && [ -r "/proc/$pid/stat" ]; do
    printf '%s ' "$pid"
    pid=$(sed -E 's/^.*\) . ([0-9]+) .*$/\1/' "/proc/$pid/stat")
  done
}

# In use: a process inside, or a file changed in the last hour.
in_use() {
  has_process_in "$1" ||
    [ -n "$(find "$1" -name node_modules -prune -o -name .git -prune -o -mmin -60 -print -quit)" ]
}

# "<path>\t<branch>" for every secondary worktree of the main checkout $1 whose directory exists
# (empty branch = detached).
worktrees_of() {
  local path branch
  git -C "$1" worktree list --porcelain | awk -v main="$1" '
    /^worktree / { wt = substr($0, 10); br = "" }
    /^branch /   { br = substr($0, 19) }
    /^$/         { if (wt != "" && wt != main) print wt "\t" br; wt = "" }
    END          { if (wt != "" && wt != main) print wt "\t" br }' |
    while IFS=$'\t' read -r path branch; do
      if [ -d "$path" ]; then printf '%s\t%s\n' "$path" "$branch"; fi
    done
}

repos() {
  local repo
  for repo in "$root"/*/*/.git; do
    if [ -d "$repo" ]; then dirname "$repo"; fi
  done
}

# worktrees_of for every repo under the root.
all_worktrees() {
  local repo
  repos | while read -r repo; do worktrees_of "$repo"; done
}

remove_worktree() {
  local wt=$1 branch=$2 main keep=''
  main=$(main_of "$wt")
  # Without a remote, an unmerged branch is the only copy of its commits.
  if [ -n "$branch" ] && ! has_origin "$wt" && ! is_merged "$wt" "$branch"; then keep=1; fi
  git -C "$main" worktree remove "$wt" || return 1
  if [ -n "$keep" ]; then
    echo "kept branch $branch: not merged" >&2
  elif [ -n "$branch" ]; then
    # The branch is on a remote or merged: deleting the local copy loses nothing.
    git -C "$main" branch -D "$branch" >/dev/null || true
  fi
  rmdir "$main.wt" 2>/dev/null || true
  echo "removed $wt" >&2
}

wt_new() {
  [ $# -ge 1 ] || usage
  local branch=$1 main dest base
  main=$(main_of .)
  dest=$main.wt/${branch//\//-}
  if [ -e "$dest" ]; then
    echo "already exists" >&2
  else
    if has_origin "$main"; then git -C "$main" fetch --quiet origin >&2 || true; fi
    if git -C "$main" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$main" worktree add "$dest" "$branch" >&2
    elif git -C "$main" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      git -C "$main" worktree add --track -b "$branch" "$dest" "origin/$branch" >&2
    else
      # --no-track: the first push creates origin/<branch> (push.autoSetupRemote), never pushes to the default branch.
      base=${2:-$(default_branch "$main")}
      if [ $# -lt 2 ] && has_origin "$main"; then base=origin/$base; fi
      git -C "$main" worktree add --no-track -b "$branch" "$dest" "$base" >&2
    fi
  fi
  echo "$dest"
}

wt_ls() {
  local path branch state pushed merged
  all_worktrees | while IFS=$'\t' read -r path branch; do
    state=clean
    if is_dirty "$path"; then state=dirty; fi
    pushed=local
    if has_origin "$path"; then pushed="$(unpushed "$path") unpushed"; fi
    merged=-
    if [ -z "$branch" ]; then
      merged=detached
    elif is_merged "$path" "$branch"; then
      merged=merged
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "${path#"$root"/}" "${branch:-HEAD}" "$pushed" "$state" "$merged"
  done | column -t -s $'\t'
}

wt_rm() {
  [ $# -eq 1 ] || usage
  local path branch
  path=$(realpath "$1")
  branch=$(git -C "$path" symbolic-ref --short -q HEAD || true)
  if is_dirty "$path"; then die "$path has uncommitted changes"; fi
  if has_origin "$path" && [ "$(unpushed "$path")" != 0 ]; then die "$path has unpushed commits"; fi
  remove_worktree "$path" "$branch" || die "git could not remove $path"
}

wt_gc() {
  local dry='' path branch rel repo
  if [ "${1:-}" = -n ]; then
    dry=1
  else
    # Forget worktrees whose directory is gone; a dry run changes nothing.
    repos | while read -r repo; do git -C "$repo" worktree prune; done
  fi
  all_worktrees | while IFS=$'\t' read -r path branch; do
    rel=${path#"$root"/}
    if [ -z "$branch" ]; then
      echo "keeping $rel: detached" >&2
    elif is_dirty "$path"; then
      echo "keeping $rel: uncommitted changes" >&2
    elif has_origin "$path" && [ "$(unpushed "$path")" != 0 ]; then
      echo "keeping $rel: unpushed commits" >&2
    elif in_use "$path"; then
      echo "keeping $rel: in use or changed in the last hour" >&2
    elif ! is_merged "$path" "$branch"; then
      echo "keeping $rel: branch not merged" >&2
    elif [ -n "$dry" ]; then
      echo "would remove $rel" >&2
    else
      remove_worktree "$path" "$branch" || echo "keeping $rel: git could not remove it" >&2
    fi
  done
}

cmd_publish() {
  local owner='' visibility=$default_visibility main name dest flag path branch
  while [ $# -gt 0 ]; do
    case "$1" in
      --public) visibility=public ;;
      --private) visibility=private ;;
      -*) usage ;;
      *)
        [ -z "$owner" ] || usage
        owner=$1
        ;;
    esac
    shift
  done
  [ -n "$owner" ] || usage
  flag=$(visibility_flag "$visibility")
  owner=$(canonical_owner "$owner")
  main=$(main_of .)
  name=$(basename "$main")
  dest=$root/$owner/$name

  [ "$(dirname "$main")" = "$root/$local_owner" ] || die "publish works on repos under $root/$local_owner"
  # An origin that is already <owner>/<name>: an earlier publish created the repo and stopped part-way.
  local resume=''
  if has_origin "$main"; then
    [ "$(github_repo "$(git -C "$main" config remote.origin.url)")" = "$owner/$name" ] ||
      die "$main already has an origin"
    resume=1
  fi
  [ ! -e "$dest" ] && [ ! -e "$dest.wt" ] || die "$dest already exists"
  if [ -z "$resume" ] && gh repo view "$owner/$name" --json nameWithOwner -q .nameWithOwner >/dev/null 2>&1; then
    die "$owner/$name already exists on GitHub"
  fi

  # Moving a directory from under a running process leaves it in a path that no longer exists. grove itself and
  # the shell that ran it don't count: grove leaves for /, and the shell's directory moves along with the repo.
  local skip
  skip=$(ancestors)
  cd /
  local -a worktrees=() branches=()
  while IFS=$'\t' read -r path branch; do
    worktrees+=("$path")
    branches+=("$branch")
  done < <(worktrees_of "$main")
  for path in "$main" "${worktrees[@]}"; do
    if has_process_in "$path" "$skip"; then die "$path is in use by a running process"; fi
  done

  trap 'echo "grove: publish stopped part-way; run it again from the repo to finish" >&2' EXIT
  if [ -z "$resume" ]; then
    (cd "$main" && gh repo create "$owner/$name" "$flag" --source . --remote origin --push >&2)
  else
    git -C "$main" push --quiet --set-upstream origin HEAD >&2
  fi
  for branch in "${branches[@]}"; do
    case "$branch" in agent/*) git -C "$main" push --quiet --set-upstream origin "$branch" >&2 ;; esac
  done

  mkdir -p "$root/$owner"
  mv "$main" "$dest"
  if [ -d "$main.wt" ]; then mv "$main.wt" "$dest.wt"; fi
  if [ ${#worktrees[@]} -gt 0 ]; then
    git -C "$dest" worktree repair "${worktrees[@]/#"$main.wt"/"$dest.wt"}"
  fi
  trap - EXIT
  echo "$dest"
}

cmd_wt() {
  [ $# -ge 1 ] || usage
  local sub=$1
  shift
  case "$sub" in
    new) wt_new "$@" ;;
    ls) wt_ls ;;
    rm) wt_rm "$@" ;;
    gc) wt_gc "$@" ;;
    *) usage ;;
  esac
}

[ $# -ge 1 ] || usage
cmd=$1
shift
case "$cmd" in
  clone) cmd_clone "$@" ;;
  new) cmd_new "$@" ;;
  publish) cmd_publish "$@" ;;
  wt) cmd_wt "$@" ;;
  -h | --help | help) usage ;;
  *) usage ;;
esac
