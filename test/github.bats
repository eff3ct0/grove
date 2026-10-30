load helpers

@test "new <owner>/<repo> creates a private GitHub repo, pushes main and prints the path" {
  run "$grove" new acme/fresh
  [ "$status" -eq 0 ]
  repo=$GROVE_ROOT/acme/fresh
  [ "${lines[-1]}" = "$repo" ]
  [ "$(cat "$GH_STUB/repos/acme/fresh.git/visibility")" = private ]
  [ "$(git -C "$repo" config remote.origin.url)" = https://github.com/acme/fresh.git ]
  [ "$(git --git-dir="$GH_STUB/repos/acme/fresh.git" log --format=%s main)" = "chore: init" ]
  grep -q '^# fresh$' "$repo/AGENTS.md"
}

@test "new <owner>/<repo> --public creates a public repo" {
  "$grove" new acme/fresh --public
  [ "$(cat "$GH_STUB/repos/acme/fresh.git/visibility")" = public ]
}

@test "new <owner>/<repo> follows GROVE_DEFAULT_VISIBILITY" {
  GROVE_DEFAULT_VISIBILITY=public "$grove" new acme/fresh
  [ "$(cat "$GH_STUB/repos/acme/fresh.git/visibility")" = public ]
}

@test "new <owner>/<repo> refuses a repo that exists on GitHub and suggests clone" {
  remote_repo acme/taken
  run "$grove" new acme/taken
  [ "$status" -ne 0 ]
  [[ "$output" == *"grove clone acme/taken"* ]]
  [ ! -e "$GROVE_ROOT/acme/taken" ]
}

@test "a repo made with new <owner>/<repo> gets worktrees from its default branch" {
  repo=$("$grove" new acme/fresh 2>/dev/null)
  cd "$repo"
  run "$grove" wt new agent/x
  [ "$status" -eq 0 ]
  [ "$(git -C "${lines[-1]}" rev-parse HEAD)" = "$(git -C "$repo" rev-parse main)" ]
}

@test "publish moves a local repo and its worktrees to <owner>, pushing main and worktree agent branches" {
  repo=$(local_repo proj)
  cd "$repo"
  wt=$("$grove" wt new agent/feature 2>/dev/null)
  commit_in "$wt" feature
  git -C "$repo" branch agent/no-worktree
  run "$grove" publish acme
  [ "$status" -eq 0 ]
  new=$GROVE_ROOT/acme/proj
  [ "${lines[-1]}" = "$new" ]
  [ ! -e "$repo" ]
  [ ! -e "$repo.wt" ]
  [ "$(cat "$GH_STUB/repos/acme/proj.git/visibility")" = private ]
  bare=$GH_STUB/repos/acme/proj.git
  [ "$(git --git-dir="$bare" rev-parse main)" = "$(git -C "$new" rev-parse main)" ]
  [ "$(git --git-dir="$bare" rev-parse agent/feature)" = "$(git -C "$new.wt/agent-feature" rev-parse HEAD)" ]
  ! git --git-dir="$bare" rev-parse --verify --quiet agent/no-worktree
  # The moved worktree still works and is tracked from its new place.
  [ -z "$(git -C "$new.wt/agent-feature" status --porcelain)" ]
  git -C "$new" worktree list | grep -q "$new.wt/agent-feature"
  run "$grove" wt ls
  echo "$output" | grep -E '^acme/proj\.wt/agent-feature +agent/feature +0 unpushed'
}

@test "publish --public creates a public repo" {
  repo=$(local_repo proj)
  cd "$repo"
  "$grove" publish acme --public
  [ "$(cat "$GH_STUB/repos/acme/proj.git/visibility")" = public ]
}

@test "publish refuses when the name exists on GitHub" {
  remote_repo acme/proj
  repo=$(local_repo proj)
  cd "$repo"
  run "$grove" publish acme
  [ "$status" -ne 0 ]
  [ -d "$repo" ]
  [ -z "$(git -C "$repo" remote)" ]
}

@test "publish refuses when a worktree is in use" {
  repo=$(local_repo proj)
  cd "$repo"
  wt=$("$grove" wt new agent/busy 2>/dev/null)
  hold_cwd "$wt"
  run "$grove" publish acme
  [ "$status" -ne 0 ]
  [[ "$output" == *"$wt"* ]]
  [ -d "$repo" ]
  [ ! -e "$GH_STUB/repos/acme/proj.git" ]
}

@test "publish refuses repos that already have a remote" {
  repo=$(cloned acme/widget)
  cd "$repo"
  run "$grove" publish other
  [ "$status" -ne 0 ]
  [ -d "$repo" ]
}

@test "publish refuses when <owner>/<repo> already exists locally" {
  repo=$(local_repo proj)
  mkdir -p "$GROVE_ROOT/acme/proj"
  cd "$repo"
  run "$grove" publish acme
  [ "$status" -ne 0 ]
  [ ! -e "$GH_STUB/repos/acme/proj.git" ]
}
