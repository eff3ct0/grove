#!/usr/bin/env bash
# grove: one clone per repo at <root>/<owner>/<repo>, work in sibling worktrees at <repo>.wt/<branch>.
# Design and reasons: docs/decisions.md.
set -euo pipefail

root=${GROVE_ROOT:-$HOME/git}
root=${root%/}
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

is_dirty() {
  [ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]
}

# Commits of HEAD that are on no remote.
unpushed() {
  git -C "$1" rev-list --count HEAD --not --remotes 2>/dev/null || echo 0
}

# <owner>/<repo> of a GitHub remote URL, or nothing.
github_repo() {
  sed -nE 's#^(https://github\.com/|git@github\.com:)([^/]+/[^/]+)$#\2#p' <<<"${1%.git}"
}

# Merged: contained in origin/<default> (also a branch with no commits of its own), or with a merged PR
# (squash) whose head is HEAD, on origin or upstream (forks).
is_merged() {
  local wt=$1 branch=$2 head remote repo
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

# A process has its working directory inside $1.
has_process_in() {
  local dir=$1 p cwd
  for p in /proc/[0-9]*/cwd; do
    cwd=$(readlink "$p" 2>/dev/null) || continue
    case "$cwd/" in "$dir"/*) return 0 ;; esac
  done
  return 1
}

# In use: a process inside, or a file changed in the last hour.
in_use() {
  has_process_in "$1" ||
    [ -n "$(find "$1" -name node_modules -prune -o -name .git -prune -o -mmin -60 -print -quit)" ]
}

# "<path>\t<branch>" for every secondary worktree of every repo under the root (empty branch = detached).
all_worktrees() {
  local repo
  for repo in "$root"/*/*/.git; do
    [ -d "$repo" ] || continue
    repo=$(dirname "$repo")
    git -C "$repo" worktree prune
    git -C "$repo" worktree list --porcelain | awk -v main="$repo" '
      /^worktree / { wt = substr($0, 10); br = "" }
      /^branch /   { br = substr($0, 19) }
      /^$/         { if (wt != "" && wt != main) print wt "\t" br; wt = "" }
      END          { if (wt != "" && wt != main) print wt "\t" br }'
  done
}

remove_worktree() {
  local wt=$1 branch=$2 main
  main=$(main_of "$wt")
  git -C "$main" worktree remove "$wt"
  # The branch is on a remote (or merged): deleting the local copy loses nothing.
  if [ -n "$branch" ]; then git -C "$main" branch -D "$branch" >/dev/null || true; fi
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
    git -C "$main" fetch --quiet origin >&2 || true
    if git -C "$main" show-ref --verify --quiet "refs/heads/$branch"; then
      git -C "$main" worktree add "$dest" "$branch" >&2
    elif git -C "$main" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
      git -C "$main" worktree add --track -b "$branch" "$dest" "origin/$branch" >&2
    else
      # --no-track: the first push creates origin/<branch> (push.autoSetupRemote), never pushes to the default branch.
      base=${2:-origin/$(default_branch "$main")}
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
    pushed="$(unpushed "$path") unpushed"
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
  if [ "$(unpushed "$path")" -gt 0 ]; then die "$path has unpushed commits"; fi
  remove_worktree "$path" "$branch"
}

wt_gc() {
  local dry='' path branch rel
  if [ "${1:-}" = -n ]; then dry=1; fi
  all_worktrees | while IFS=$'\t' read -r path branch; do
    rel=${path#"$root"/}
    if [ -z "$branch" ]; then
      echo "keeping $rel: detached" >&2
    elif is_dirty "$path"; then
      echo "keeping $rel: uncommitted changes" >&2
    elif [ "$(unpushed "$path")" -gt 0 ]; then
      echo "keeping $rel: unpushed commits" >&2
    elif ! is_merged "$path" "$branch"; then
      echo "keeping $rel: branch not merged" >&2
    elif in_use "$path"; then
      echo "keeping $rel: in use or changed in the last hour" >&2
    elif [ -n "$dry" ]; then
      echo "would remove $rel" >&2
    else
      remove_worktree "$path" "$branch"
    fi
  done
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
  wt) cmd_wt "$@" ;;
  -h | --help | help) usage ;;
  *) usage ;;
esac
