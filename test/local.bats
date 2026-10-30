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
  [ "$(git -C "$repo" ls-files | LC_ALL=C sort | tr '\n' ' ')" = ".gitignore AGENTS.md README.md " ]
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

@test "the AGENTS.md skeleton covers run and test and has no secrets section" {
  repo=$(local_repo scratch)
  grep -qi '^## run' "$repo/AGENTS.md"
  grep -qi '^## test' "$repo/AGENTS.md"
  ! grep -qi secret "$repo/AGENTS.md"
}

@test "new -t without GROVE_TEMPLATES fails with a clear error and creates nothing" {
  run "$grove" new scratch -t python
  [ "$status" -ne 0 ]
  [[ "$output" == *"-t needs GROVE_TEMPLATES"* ]]
  [ ! -e "$GROVE_ROOT/local/scratch" ]
}

@test "new -t runs nix flake init from GROVE_TEMPLATES and keeps the template's files" {
  mkdir -p "$T/bin"
  cat >"$T/bin/nix" <<'STUB'
#!/usr/bin/env bash
echo "$*" >"$GH_STUB/nix-args"
echo "template agents" >AGENTS.md
echo "{ }" >devenv.nix
STUB
  chmod +x "$T/bin/nix"
  PATH=$T/bin:$PATH GROVE_TEMPLATES=/flakes/mine run "$grove" new scratch -t python
  [ "$status" -eq 0 ]
  repo=$GROVE_ROOT/local/scratch
  [ "$(cat "$GH_STUB/nix-args")" = "flake init -t /flakes/mine#python" ]
  [ "$(cat "$repo/AGENTS.md")" = "template agents" ]
  git -C "$repo" ls-files --error-unmatch devenv.nix README.md .gitignore
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
