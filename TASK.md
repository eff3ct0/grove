# Task: issue #3, default template per owner

Removed once the last critic passes.

## Request

> Implement https://github.com/eff3ct0/grove/issues/3. Read the repo's AGENTS.md first and follow ~/git/AGENTS.md:
> grove worktree on an agent/ branch, a critic before handing over, a pull request for the user to merge.

Correction sent while working:

> Note from the user's other session: eff3ct0/grove#2 ("feat: CLAUDE.md that imports AGENTS.md, in grove and in new
> repos") was merged into main a few minutes ago. It already makes grove new write CLAUDE.md (@AGENTS.md) without a
> template, which is the second half of this issue. Base your worktree on the updated origin/main (git -C
> ~/git/eff3ct0/grove pull --ff-only in the main checkout first, or rebase onto origin/main), build on that change
> instead of redoing it, and say in the pull request which part of #3 grove#2 already covers.

Base commit: `4f38312` (grove#2 merged). Spec: issue #3 and the nixos-config issues it links (#56 with its two
correction comments, #49).

## Decisions

- grove#2 already writes `CLAUDE.md` (`@AGENTS.md`) when missing, with a test and decision 8's paragraph. Left for this
  branch on that half: a test that a template's own `CLAUDE.md` is kept as the template wrote it.
- Encoding: `GROVE_DEFAULT_TEMPLATES` is `<owner>=<template>` pairs separated by commas or whitespace; the module
  writes them joined by commas. A pair without `=`, or with an empty side, is an error.
- Owners match ignoring case (GitHub logins do); a GitHub owner is looked up with GitHub's spelling, a local repo
  with `GROVE_LOCAL_OWNER`.
- A default that applies while `GROVE_TEMPLATES` is unset is an error naming the owner and template, like `-t`
  without it (decision 9); the module asserts `defaultTemplates` needs `templates`.
- `-t` keeps its early error; the default is resolved after the owner is known (after `canonical_owner`).
- To skip the default for one repo: `GROVE_DEFAULT_TEMPLATES=` (the wrapper's `--set-default` keeps a set, empty value).
- The module asserts owners carry no comma, `=` or whitespace, and the option's type does the same for templates;
  `nix/checks.nix` tests both and the `templates` assertion with `builtins.tryEval`, since home-manager's `config`
  throws on a failed assertion.

- After the first critic: `-t ''` still means no template (as at the base), empty map entries are skipped wherever
  they are, and the README and `nix/package.nix` say `nix` is needed for any template, not only `-t`.
- Kept out of this branch: `cmd_new`'s `trap 'rm -rf "$dest"' EXIT` fails with "dest: unbound variable" when
  `init_repo` fails (for example `nix flake init`), leaving a half-made repo. It predates this change (the base shows
  it with `-t`), so it goes to the user as a separate fix.

## Steps

- [x] `grove.sh`: `default_template`, `cmd_new`, usage text.
- [x] Tests: local and GitHub owner, `-t` replacing, unnamed owner, unset `GROVE_TEMPLATES`, malformed map, a
      template's own `CLAUDE.md` kept.
- [x] `nix/module.nix`: option, wrapper variable, assertion; `nix/checks.nix`: wrapper and assertion.
- [x] `docs/decisions.md` entry 13 and decision 9's variable list; README; usage.
- [x] bats, shellcheck, `nix flake check`; an end-to-end run with real `nix flake init` and a throwaway flake.
- [x] Critic; fixes.
- [ ] Recheck; remove this file; PR saying which part of #3 grove#2 covers.
