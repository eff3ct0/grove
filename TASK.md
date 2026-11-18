# Task: grove new leaves a half-made repo when init_repo fails

Removed once the last critic passes.

## Request

The user's answer, verbatim, to the offer to fix this in a separate pull request:

> si arreglalo en un PR

What it refers to (found by the critic of #5, reproduced at `9c1f5bf`): when `init_repo` fails inside `grove new`, for
example because `nix flake init` fails, the `trap 'rm -rf "$dest"' EXIT` in `cmd_new` prints
`grove.sh: line 1: dest: unbound variable` and removes nothing: bash runs the EXIT trap after the function's locals
are gone. What is left is `<root>/<owner>/<repo>` holding only an empty `.git`. A retry of `grove new <owner>/<repo>`
dies with "already exists"; a retry of `grove new <repo>` prints "already exists" and the path with exit 0, handing
back a repo with no commits.

Base commit: `9c1f5bf` (main, with #5 merged).

## Decisions

- Fix the trap so the path is fixed when it is set (`printf %q`), in one helper both `cmd_new` paths use.
- Behaviour otherwise unchanged: the exit status stays the failed command's, and a failure after `init_repo` (creating
  the repo on GitHub) still keeps the local repo, as decision 7 says.

## Steps

- [x] `grove.sh`: the helper and both call sites.
- [x] bats: a failing template leaves nothing, local and GitHub paths (nothing on the stub GitHub either), a retry
      works, and a root path that needs quoting.
- [x] bats, shellcheck, `nix flake check`.
- [ ] Critic, recheck if needed; remove this file; PR.
