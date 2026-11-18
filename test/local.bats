load helpers

@test "new <repo> creates a local repo under the local owner with an init commit on main" {
  run "$grove" new scratch
  [ "$status" -eq 0 ]
  repo=$GROVE_ROOT/local/scratch
  [ "${lines[-1]}" = "$repo" ]
  [ "$(git -C "$repo" symbolic-ref --short HEAD)" = main ]
  [ "$(git -C "$repo" log --format=%s)" = "chore: init" ]
  [ -z "$(git -C "$repo" remote)" ]
  [ -z "$(git -C "$repo" status --porcelain)" ]
  [ "$(git -C "$repo" ls-files | LC_ALL=C sort | tr '\n' ' ')" = ".gitignore AGENTS.md CLAUDE.md README.md " ]
  grep -q '^# scratch$' "$repo/README.md"
}

@test "new <repo> honours GROVE_LOCAL_OWNER" {
  GROVE_LOCAL_OWNER=mine run "$grove" new scratch
  [ "${lines[-1]}" = "$GROVE_ROOT/mine/scratch" ]
}

@test "new <repo> of an existing repo only prints the path" {
  repo=$(local_repo scratch)
  commit_in "$repo" more
  run "$grove" new scratch
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "$repo" ]
  [ "$(git -C "$repo" rev-list --count HEAD)" -eq 2 ]
}

@test "the AGENTS.md skeleton covers related repos, run and test and has no secrets section" {
  repo=$(local_repo scratch)
  grep -qi '^## related repos' "$repo/AGENTS.md"
  grep -q '^- Depends on: <`owner/repo`: ' "$repo/AGENTS.md"
  grep -q '^- Used by: <`owner/repo`: ' "$repo/AGENTS.md"
  grep -qi '^## run' "$repo/AGENTS.md"
  grep -qi '^## test' "$repo/AGENTS.md"
  ! grep -qi secret "$repo/AGENTS.md"
}

@test "CLAUDE.md is the single line @AGENTS.md" {
  repo=$(local_repo scratch)
  [ "$(cat "$repo/CLAUDE.md")" = "@AGENTS.md" ]
  [ "$(wc -l <"$repo/CLAUDE.md")" -eq 1 ]
}

@test "new -t without GROVE_TEMPLATES fails with a clear error and creates nothing" {
  run "$grove" new scratch -t python
  [ "$status" -ne 0 ]
  [[ "$output" == *"-t needs GROVE_TEMPLATES"* ]]
  [ ! -e "$GROVE_ROOT/local/scratch" ]
}

@test "new -t runs nix flake init from GROVE_TEMPLATES and keeps the template's files" {
  nix_stub 'echo "template agents" >AGENTS.md; echo "{ }" >devenv.nix'
  GROVE_TEMPLATES=/flakes/mine run "$grove" new scratch -t python
  [ "$status" -eq 0 ]
  repo=$GROVE_ROOT/local/scratch
  [ "$(cat "$GH_STUB/nix-args")" = "flake init -t /flakes/mine#python" ]
  [ "$(cat "$repo/AGENTS.md")" = "template agents" ]
  [ "$(cat "$repo/CLAUDE.md")" = "@AGENTS.md" ]
  git -C "$repo" ls-files --error-unmatch devenv.nix README.md CLAUDE.md .gitignore
}

@test "new keeps the CLAUDE.md a template brings, as the template wrote it" {
  nix_stub 'printf "# Template rules\n\nSee AGENTS.md.\n" >CLAUDE.md'
  GROVE_TEMPLATES=/flakes/mine run "$grove" new scratch -t python
  [ "$status" -eq 0 ]
  repo=$GROVE_ROOT/local/scratch
  [ "$(cat "$repo/CLAUDE.md")" = "$(printf '# Template rules\n\nSee AGENTS.md.')" ]
  [ "$(git -C "$repo" show HEAD:CLAUDE.md)" = "$(cat "$repo/CLAUDE.md")" ]
  [ "$(git -C "$repo" log --format=%s)" = "chore: init" ]
}

@test "new <repo> whose template fails leaves nothing behind, so a retry creates it" {
  nix_stub 'echo partial >devenv.nix; exit 1'
  GROVE_TEMPLATES=/flakes/mine run "$grove" new scratch -t python
  [ "$status" -ne 0 ]
  [[ "$output" != *"unbound variable"* ]]
  [ ! -e "$GROVE_ROOT/local/scratch" ]
  run "$grove" new scratch
  [ "$status" -eq 0 ]
  [ "$(git -C "$GROVE_ROOT/local/scratch" log --format=%s)" = "chore: init" ]
}

@test "a failed new removes only its own repo when the root's path needs quoting" {
  mkdir -p "$T/my"
  echo keep >"$T/my/sentinel"
  export GROVE_ROOT="$T/my root's \$HOME \"dir\""
  mkdir -p "$GROVE_ROOT/local/other"
  nix_stub 'exit 1'
  GROVE_TEMPLATES=/flakes/mine run "$grove" new scratch -t python
  [ "$status" -ne 0 ]
  [[ "$output" != *"unbound variable"* ]]
  [ ! -e "$GROVE_ROOT/local/scratch" ]
  [ -d "$GROVE_ROOT/local/other" ]
  [ -f "$T/my/sentinel" ]
}

@test "new <repo> without -t runs the template GROVE_DEFAULT_TEMPLATES names for the local owner" {
  nix_stub 'echo "{ }" >devenv.nix'
  GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES=acme=web,local=base run "$grove" new scratch
  [ "$status" -eq 0 ]
  repo=$GROVE_ROOT/local/scratch
  [ "${lines[-1]}" = "$repo" ]
  [ "$(cat "$GH_STUB/nix-args")" = "flake init -t /flakes/mine#base" ]
  [ "$(git -C "$repo" log --format=%s)" = "chore: init" ]
  git -C "$repo" ls-files --error-unmatch devenv.nix AGENTS.md CLAUDE.md
}

@test "the local owner's default template follows GROVE_LOCAL_OWNER" {
  nix_stub
  GROVE_LOCAL_OWNER=mine GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES=$'local=web\nmine=base' \
    run "$grove" new scratch
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "$GROVE_ROOT/mine/scratch" ]
  [ "$(cat "$GH_STUB/nix-args")" = "flake init -t /flakes/mine#base" ]
}

@test "new <repo> -t replaces the local owner's default template" {
  nix_stub
  GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES=local=base run "$grove" new scratch -t other
  [ "$status" -eq 0 ]
  [ "$(cat "$GH_STUB/nix-args")" = "flake init -t /flakes/mine#other" ]
}

@test "new <repo> runs no template when GROVE_DEFAULT_TEMPLATES does not name the local owner" {
  nix_stub
  GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES=acme=base run "$grove" new scratch
  [ "$status" -eq 0 ]
  repo=$GROVE_ROOT/local/scratch
  [ ! -e "$GH_STUB/nix-args" ]
  [ "$(git -C "$repo" ls-files | LC_ALL=C sort | tr '\n' ' ')" = ".gitignore AGENTS.md CLAUDE.md README.md " ]
}

@test "a default template without GROVE_TEMPLATES fails with a clear error and creates nothing" {
  nix_stub
  GROVE_DEFAULT_TEMPLATES=local=base run "$grove" new scratch
  [ "$status" -ne 0 ]
  [[ "$output" == *"GROVE_DEFAULT_TEMPLATES gives local the template base, which needs GROVE_TEMPLATES"* ]]
  [ ! -e "$GROVE_ROOT/local/scratch" ]
  [ ! -e "$GH_STUB/nix-args" ]
}

@test "a GROVE_DEFAULT_TEMPLATES entry that is not <owner>=<template> fails and creates nothing" {
  nix_stub
  for map in acme local=base,acme 'local=base acme=' =base; do
    GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES=$map run "$grove" new scratch
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not <owner>=<template>"* ]]
    [ ! -e "$GROVE_ROOT/local/scratch" ]
  done
  [ ! -e "$GH_STUB/nix-args" ]
}

@test "empty entries in GROVE_DEFAULT_TEMPLATES are skipped wherever they are" {
  nix_stub
  GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES=',acme=web,,local=base,' run "$grove" new scratch
  [ "$status" -eq 0 ]
  [ "$(cat "$GH_STUB/nix-args")" = "flake init -t /flakes/mine#base" ]
}

@test "new <repo> -t '' runs no template even where the local owner has a default" {
  nix_stub
  GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES=local=base run "$grove" new scratch -t ''
  [ "$status" -eq 0 ]
  [ ! -e "$GH_STUB/nix-args" ]
}

@test "an empty GROVE_DEFAULT_TEMPLATES runs no template" {
  nix_stub
  GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES= run "$grove" new scratch
  [ "$status" -eq 0 ]
  [ ! -e "$GH_STUB/nix-args" ]
}

@test "wt new in a local repo branches from the local default branch without fetching" {
  repo=$(local_repo scratch)
  commit_in "$repo" second
  cd "$repo"
  run "$grove" wt new agent/x
  [ "$status" -eq 0 ]
  [ "$(git -C "$repo.wt/agent-x" rev-parse HEAD)" = "$(git -C "$repo" rev-parse main)" ]
}

@test "wt ls shows local instead of an unpushed count" {
  repo=$(local_repo scratch)
  (cd "$repo" && "$grove" wt new agent/x >/dev/null 2>&1)
  commit_in "$repo.wt/agent-x" one
  run "$grove" wt ls
  echo "$output" | grep -E '^local/scratch\.wt/agent-x +agent/x +local +clean +-'
}

@test "wt rm in a local repo needs nothing pushed and keeps an unmerged branch" {
  repo=$(local_repo scratch)
  cd "$repo"
  wt=$("$grove" wt new agent/x 2>/dev/null)
  commit_in "$wt" one
  run "$grove" wt rm "$wt"
  [ "$status" -eq 0 ]
  [ ! -e "$wt" ]
  git -C "$repo" show-ref --verify --quiet refs/heads/agent/x
}

@test "wt rm in a local repo deletes a merged branch" {
  repo=$(local_repo scratch)
  cd "$repo"
  wt=$("$grove" wt new agent/x 2>/dev/null)
  "$grove" wt rm "$wt"
  ! git -C "$repo" show-ref --verify --quiet refs/heads/agent/x
}

@test "wt gc in a local repo removes worktrees merged into the local default branch" {
  repo=$(local_repo scratch)
  cd "$repo"
  merged=$("$grove" wt new agent/merged 2>/dev/null)
  commit_in "$merged" done
  git -C "$repo" merge --quiet --ff-only agent/merged
  unmerged=$("$grove" wt new agent/unmerged 2>/dev/null)
  commit_in "$unmerged" wip
  recent=$("$grove" wt new agent/recent 2>/dev/null)
  age "$merged"; age "$unmerged"
  "$grove" wt gc
  [ ! -e "$merged" ]
  [ -d "$unmerged" ]
  [ -d "$recent" ]
}
