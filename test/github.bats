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

@test "new <owner>/<repo> uses GitHub's spelling of the owner" {
  mkdir -p "$GH_STUB/owners"
  echo Acme >"$GH_STUB/owners/acme"
  run "$grove" new acme/fresh
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "$GROVE_ROOT/Acme/fresh" ]
}

@test "new <owner>/<repo> keeps the local repo when creating it on GitHub fails" {
  GH_STUB_FAIL_PUSH=1 run "$grove" new acme/fresh
  [ "$status" -ne 0 ]
  [ -d "$GROVE_ROOT/acme/fresh/.git" ]
  [[ "$output" == *"$GROVE_ROOT/acme/fresh"* ]]
}

@test "new <owner>/<repo> whose template fails leaves nothing behind, here or on GitHub" {
  nix_stub 'echo partial >devenv.nix; exit 1'
  GROVE_TEMPLATES=/flakes/mine run "$grove" new acme/fresh -t python
  [ "$status" -ne 0 ]
  [[ "$output" != *"unbound variable"* ]]
  [ ! -e "$GROVE_ROOT/acme/fresh" ]
  [ ! -e "$GH_STUB/repos/acme/fresh.git" ]
  run "$grove" new acme/fresh
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$GH_STUB/repos/acme/fresh.git" log --format=%s main)" = "chore: init" ]
}

@test "publish works when run from inside one of the repo's worktrees" {
  repo=$(local_repo proj)
  cd "$repo"
  wt=$("$grove" wt new agent/feature 2>/dev/null)
  cd "$wt"
  run "$grove" publish acme
  [ "$status" -eq 0 ]
  [ -d "$GROVE_ROOT/acme/proj.wt/agent-feature" ]
}

@test "publish refuses when another process is inside the main checkout" {
  repo=$(local_repo proj)
  hold_cwd "$repo"
  cd "$repo"
  run "$grove" publish acme
  [ "$status" -ne 0 ]
  [ -d "$repo" ]
  [ ! -e "$GH_STUB/repos/acme/proj.git" ]
}

@test "publish uses GitHub's spelling of the owner" {
  mkdir -p "$GH_STUB/owners"
  echo Acme >"$GH_STUB/owners/acme"
  repo=$(local_repo proj)
  cd "$repo"
  run "$grove" publish acme
  [ "${lines[-1]}" = "$GROVE_ROOT/Acme/proj" ]
}

@test "publish run again finishes one that stopped after creating the GitHub repo" {
  repo=$(local_repo proj)
  cd "$repo"
  wt=$("$grove" wt new agent/feature 2>/dev/null)
  commit_in "$wt" feature
  gh repo create acme/proj --private --source . --remote origin --push >/dev/null
  run "$grove" publish acme
  [ "$status" -eq 0 ]
  [ -d "$GROVE_ROOT/acme/proj.wt/agent-feature" ]
  git --git-dir="$GH_STUB/repos/acme/proj.git" rev-parse --verify --quiet agent/feature
}

@test "publish refuses a repo whose origin is some other repo" {
  repo=$(local_repo proj)
  git -C "$repo" remote add origin https://github.com/acme/other.git
  cd "$repo"
  run "$grove" publish acme
  [ "$status" -ne 0 ]
  [ -d "$repo" ]
}

@test "publish and wt work when GROVE_ROOT goes through a symlink" {
  ln -s "$GROVE_ROOT" "$T/link"
  export GROVE_ROOT=$T/link
  repo=$(local_repo proj)
  cd "$repo"
  "$grove" wt new agent/x >/dev/null 2>&1
  run "$grove" wt ls
  [ "${#lines[@]}" -eq 1 ]
  run "$grove" publish acme
  [ "$status" -eq 0 ]
}

@test "new <owner>/<repo> without -t runs the owner's default template and pushes its files in chore: init" {
  nix_stub 'echo "{ }" >devenv.nix'
  GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES=acme=base,local=web run "$grove" new acme/x
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "$GROVE_ROOT/acme/x" ]
  [ "$(cat "$GH_STUB/nix-args")" = "flake init -t /flakes/mine#base" ]
  bare=$GH_STUB/repos/acme/x.git
  [ "$(git --git-dir="$bare" log --format=%s main)" = "chore: init" ]
  git --git-dir="$bare" cat-file -e main:devenv.nix
  [ "$(git --git-dir="$bare" show main:CLAUDE.md)" = "@AGENTS.md" ]
}

@test "the owner's default template matches GitHub's spelling of the owner, ignoring case" {
  mkdir -p "$GH_STUB/owners"
  echo Acme >"$GH_STUB/owners/acme"
  nix_stub
  GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES=ACME=base run "$grove" new acme/x
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "$GROVE_ROOT/Acme/x" ]
  [ "$(cat "$GH_STUB/nix-args")" = "flake init -t /flakes/mine#base" ]
}

@test "new <owner>/<repo> -t replaces the owner's default template" {
  nix_stub
  GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES=acme=base run "$grove" new acme/x -t other
  [ "$status" -eq 0 ]
  [ "$(cat "$GH_STUB/nix-args")" = "flake init -t /flakes/mine#other" ]
}

@test "new <owner>/<repo> runs no template for an owner GROVE_DEFAULT_TEMPLATES does not name" {
  nix_stub
  GROVE_TEMPLATES=/flakes/mine GROVE_DEFAULT_TEMPLATES=acme=base,local=base run "$grove" new other-owner/z
  [ "$status" -eq 0 ]
  [ "${lines[-1]}" = "$GROVE_ROOT/other-owner/z" ]
  [ ! -e "$GH_STUB/nix-args" ]
  bare=$GH_STUB/repos/other-owner/z.git
  [ "$(git --git-dir="$bare" ls-tree --name-only main | LC_ALL=C sort | tr '\n' ' ')" = ".gitignore AGENTS.md CLAUDE.md README.md " ]
}

@test "new <owner>/<repo> with a default template and no GROVE_TEMPLATES creates nothing, here or on GitHub" {
  GROVE_DEFAULT_TEMPLATES=acme=base run "$grove" new acme/x
  [ "$status" -ne 0 ]
  [[ "$output" == *"GROVE_DEFAULT_TEMPLATES gives acme the template base, which needs GROVE_TEMPLATES"* ]]
  [ ! -e "$GROVE_ROOT/acme/x" ]
  [ ! -e "$GH_STUB/repos/acme/x.git" ]
}
