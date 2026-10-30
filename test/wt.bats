load helpers

@test "wt new creates <repo>.wt/<slug> on a new branch from origin's default branch" {
  repo=$(cloned acme/widget)
  cd "$repo"
  run "$grove" wt new agent/fix-it
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "$repo.wt/agent-fix-it" ]
  [ "$(git -C "$repo.wt/agent-fix-it" symbolic-ref --short HEAD)" = agent/fix-it ]
  [ "$(git -C "$repo.wt/agent-fix-it" rev-parse HEAD)" = "$(git -C "$repo" rev-parse origin/main)" ]
}

@test "wt new from inside a worktree still lands next to the main checkout" {
  repo=$(cloned acme/widget)
  cd "$repo"
  cd "$("$grove" wt new agent/one 2>/dev/null)"
  run "$grove" wt new agent/two
  [ "${lines[-1]}" = "$repo.wt/agent-two" ]
}

@test "wt new reuses a branch that exists on origin" {
  repo=$(cloned acme/widget)
  git -C "$T/src/acme/widget" checkout --quiet -b agent/remote
  commit_in "$T/src/acme/widget" remote.txt
  git -C "$T/src/acme/widget" push --quiet "$GH_STUB/repos/acme/widget.git" agent/remote
  cd "$repo"
  "$grove" wt new agent/remote
  [ -f "$repo.wt/agent-remote/remote.txt" ]
}

@test "wt new of an existing worktree only prints the path" {
  repo=$(cloned acme/widget)
  cd "$repo"
  "$grove" wt new agent/x
  run "$grove" wt new agent/x
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "$repo.wt/agent-x" ]
}

@test "wt ls lists worktrees of every repo with unpushed count, state and merge status" {
  a=$(cloned acme/a)
  b=$(cloned acme/b)
  (cd "$a" && "$grove" wt new agent/clean >/dev/null 2>&1)
  (cd "$b" && "$grove" wt new agent/dirty >/dev/null 2>&1)
  commit_in "$b.wt/agent-dirty" one
  echo x >"$b.wt/agent-dirty/untracked"
  run "$grove" wt ls
  [ "$status" -eq 0 ]
  echo "$output" | grep -E '^acme/a\.wt/agent-clean +agent/clean +0 unpushed +clean +merged'
  echo "$output" | grep -E '^acme/b\.wt/agent-dirty +agent/dirty +1 unpushed +dirty +-'
}

@test "wt rm refuses unpushed commits and removes pushed worktrees and their local branch" {
  repo=$(cloned acme/widget)
  cd "$repo"
  wt=$("$grove" wt new agent/x 2>/dev/null)
  commit_in "$wt" one
  run "$grove" wt rm "$wt"
  [ "$status" -ne 0 ]
  [ -d "$wt" ]
  git -C "$wt" push --quiet origin agent/x
  run "$grove" wt rm "$wt"
  [ "$status" -eq 0 ]
  [ ! -e "$wt" ]
  ! git -C "$repo" show-ref --verify --quiet refs/heads/agent/x
}

@test "wt rm refuses uncommitted changes" {
  repo=$(cloned acme/widget)
  cd "$repo"
  wt=$("$grove" wt new agent/x 2>/dev/null)
  echo x >"$wt/new"
  run "$grove" wt rm "$wt"
  [ "$status" -ne 0 ]
  [ -d "$wt" ]
}

@test "wt gc removes merged, pushed, idle worktrees and keeps the rest" {
  repo=$(cloned acme/widget)
  cd "$repo"
  merged=$("$grove" wt new agent/merged 2>/dev/null)
  unmerged=$("$grove" wt new agent/unmerged 2>/dev/null)
  commit_in "$unmerged" work
  git -C "$unmerged" push --quiet origin agent/unmerged
  recent=$("$grove" wt new agent/recent 2>/dev/null)
  busy=$("$grove" wt new agent/busy 2>/dev/null)
  age "$merged"; age "$unmerged"; age "$busy"
  hold_cwd "$busy"
  run "$grove" wt gc
  [ "$status" -eq 0 ]
  [ ! -e "$merged" ]
  [ -d "$unmerged" ]
  [ -d "$recent" ]
  [ -d "$busy" ]
}

@test "wt gc treats a squash-merged PR whose head is HEAD as merged" {
  repo=$(cloned acme/widget)
  cd "$repo"
  wt=$("$grove" wt new agent/squashed 2>/dev/null)
  commit_in "$wt" work
  git -C "$wt" push --quiet origin agent/squashed
  mkdir -p "$GH_STUB/prs/acme/widget/agent"
  git -C "$wt" rev-parse HEAD >"$GH_STUB/prs/acme/widget/agent/squashed"
  age "$wt"
  "$grove" wt gc
  [ ! -e "$wt" ]
}

@test "wt gc -n removes nothing" {
  repo=$(cloned acme/widget)
  cd "$repo"
  wt=$("$grove" wt new agent/merged 2>/dev/null)
  age "$wt"
  run "$grove" wt gc -n
  [ -d "$wt" ]
  [[ "$output" == *"would remove acme/widget.wt/agent-merged"* ]]
}

@test "wt gc goes on after a worktree git refuses to remove" {
  repo=$(cloned acme/widget)
  cd "$repo"
  locked=$("$grove" wt new agent/a-locked 2>/dev/null)
  other=$("$grove" wt new agent/b-other 2>/dev/null)
  git -C "$repo" worktree lock "$locked"
  age "$locked"; age "$other"
  run "$grove" wt gc
  [ "$status" -eq 0 ]
  [ -d "$locked" ]
  [ ! -e "$other" ]
  git -C "$repo" show-ref --verify --quiet refs/heads/agent/a-locked
}

@test "wt ls and gc -n leave the worktree records of a missing directory alone" {
  repo=$(cloned acme/widget)
  cd "$repo"
  wt=$("$grove" wt new agent/x 2>/dev/null)
  mv "$wt" "$T/away"
  "$grove" wt ls
  "$grove" wt gc -n
  [ -d "$repo/.git/worktrees/agent-x" ]
}
