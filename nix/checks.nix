{
  pkgs,
  home-manager,
  module,
  src,
}:
let
  # A sample home with every option that shapes the generated text set.
  hm = home-manager.lib.homeManagerConfiguration {
    inherit pkgs;
    modules = [
      module
      {
        home = {
          username = "alice";
          homeDirectory = "/home/alice";
          stateVersion = "26.05";
        };
        programs.git = {
          enable = true;
          settings.user.name = "Alice Example";
        };
        programs.grove = {
          enable = true;
          templates = "github:acme/templates";
          extraAgentsDoc = "## Extra\n\nMachine rule.";
          secrets = {
            command = "with-secrets";
            paths."acme/api"."/stripe/api" = "payments";
          };
        };
      }
    ];
  };
  files = hm.config.home.file;
in
{
  tests =
    pkgs.runCommand "grove-tests"
      {
        nativeBuildInputs = with pkgs; [
          bats
          shellcheck
          git
          coreutils
          findutils
          gawk
          gnused
          util-linux
        ];
      }
      ''
        cp -r ${src} src
        chmod -R u+w src
        cd src
        patchShebangs grove.sh test/stub
        shellcheck grove.sh test/stub/gh test/helpers.bash
        bats test
        touch $out
      '';

  module =
    pkgs.runCommand "grove-module"
      {
        agents = files."git/AGENTS.md".text;
        claude = files."git/CLAUDE.md".text;
        passAsFile = [
          "agents"
          "claude"
        ];
      }
      ''
        cmp "$agentsPath" "$claudePath"
        grep -q '^# ~/git$' "$agentsPath"
        grep -q 'grove wt new agent/<topic>' "$agentsPath"
        grep -q '^Alice Example decides on PRs and merges.$' "$agentsPath"
        grep -q 'with-secrets <path> -- <cmd>' "$agentsPath"
        grep -q '^| `acme/api` | `/stripe/api` | payments |$' "$agentsPath"
        # extraAgentsDoc comes last.
        [ "$(tail -n1 "$agentsPath")" = "Machine rule." ]
        { ${hm.activationPackage}/home-path/bin/grove --help || true; } 2>&1 | grep -q GROVE_ROOT
        grep -q 'GROVE_TEMPLATES.*github:acme/templates' ${hm.activationPackage}/home-path/bin/grove
        touch $out
      '';
}
