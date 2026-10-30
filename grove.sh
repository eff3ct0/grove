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

[ $# -ge 1 ] || usage
cmd=$1
shift
case "$cmd" in
  clone) cmd_clone "$@" ;;
  -h | --help | help) usage ;;
  *) usage ;;
esac
