{
  lib,
  writeShellApplication,
  coreutils,
  findutils,
  gawk,
  gh,
  git,
  gnused,
  util-linux,
}:
writeShellApplication {
  name = "grove";
  runtimeInputs = [
    coreutils
    findutils
    gawk
    gh
    git
    gnused
    util-linux
  ];
  # `grove new` runs `nix flake init` for a template (`-t` or the owner's default) with the nix already on the PATH.
  text = builtins.readFile ../grove.sh;
  meta = {
    description = "One clone per repo, agent work in sibling worktrees";
    license = lib.licenses.mit;
    mainProgram = "grove";
  };
}
