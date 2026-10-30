{
  description = "grove: one clone per repo, agent work in sibling worktrees";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Only for the module checks; consumers bring their own home-manager.
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        grove = pkgs.callPackage ./nix/package.nix { };
        default = grove;
      });

      homeManagerModules.default = import ./nix/module.nix self;

      checks = forAllSystems (
        pkgs:
        import ./nix/checks.nix {
          inherit pkgs home-manager;
          module = self.homeManagerModules.default;
          src = ./.;
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            bats
            shellcheck
            nixfmt
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
