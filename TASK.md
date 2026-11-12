# Task: a "Related repos" section in every repo's AGENTS.md

## Request (p3rkins, verbatim)

> vale, prepara lo de la sección de relaciones en los AGENTS.md

Context from the same conversation, verbatim:

> no me hace gracia que la home tenga una carpeta areas, me gusta mas la idea de ser agnostico, que referencie como se
> estructuran los repos y que de ahi entienda el repo. Si por ejemplo encuentra un repo que no queda bien explicado
> puede sugerir abrir una PR haciendo lo que se considera que es ese areas, pero dentro del repo en cuestion no en el
> repo home.

## Decisions

- Each repo explains itself: its AGENTS.md says what it is, which repos it depends on and which depend on it (with
  what passes between them), and how to run and test it. No central map of repos anywhere.
- The rule lives in grove's generic `agentsDoc` ("## Each repo"), rendered into `<root>/AGENTS.md` on every machine.
- An agent that finds a repo it is not changing badly explained tells the user and offers a PR to that repo.
- `grove new`'s AGENTS.md skeleton and eff3ct0/nixos-config's `templates/*/AGENTS.md` get a "## Related repos"
  section with two lines: "Depends on" and "Used by".
- Existing repos are not filled in now: that happens per repo, through the PRs above. Open decision for p3rkins:
  the critic read "en los AGENTS.md" as possibly asking to fill the existing repos too.
- The two repos changed here get the section in their own AGENTS.md, as the new rule asks. grove's names no
  consumer repo: grove is public and generic, eff3ct0/nixos-config is private.
- The module text reaches hefesto once grove's main is in eff3ct0/nixos-config's `flake.lock` (the nightly
  `update-flake-lock` moves it).

## Steps

- [x] grove (branch `agent/repo-relations`): module text, skeleton in `grove.sh`, tests, README, decision 8.
- [x] eff3ct0/nixos-config (branch `agent/repo-relations`): `templates/{node,python,rust,scala}/AGENTS.md`.
- [x] First critic: failed Done (no section in grove's and nixos-config's own AGENTS.md) and Resume (this list).
- [x] Fix: the section in both repos' own AGENTS.md, this list, README wrap.
- [ ] Recheck by a fresh critic; remove this file once it passes.
