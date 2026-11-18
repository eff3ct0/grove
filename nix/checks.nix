{
  pkgs,
  home-manager,
  module,
  src,
}:
let
  homeWith =
    config:
    home-manager.lib.homeManagerConfiguration {
      inherit pkgs;
      modules = [
        module
        {
          home = {
            username = "alice";
            homeDirectory = "/home/alice";
            stateVersion = "26.05";
          };
        }
        config
      ];
    };

  # A sample home with every option that shapes the generated text and the wrapper set.
  hm = homeWith {
    programs.git = {
      enable = true;
      settings.user.name = "Alice Example";
    };
    programs.grove = {
      enable = true;
      templates = "github:acme/templates";
      defaultTemplates = {
        acme = "base";
        local = "base";
      };
      extraAgentsDoc = "## Extra\n\nMachine rule.";
      secrets = {
        command = "with-secrets";
        paths."acme/api"."/stripe/api" = "payments";
      };
    };
  };
  files = hm.config.home.file;

  # Whether a grove configuration passes the module's assertions and option types: home-manager throws otherwise. Each case below
  # differs from the first, which passes, in one setting.
  passes =
    grove:
    (builtins.tryEval
      (homeWith {
        programs.grove = {
          enable = true;
        }
        // grove;
      }).activationPackage.drvPath
    ).success;
  assertions = builtins.toJSON {
    withTemplates = passes {
      templates = "github:acme/templates";
      defaultTemplates.acme = "base";
    };
    withoutTemplates = passes { defaultTemplates.acme = "base"; };
    ownerWithComma = passes {
      templates = "github:acme/templates";
      defaultTemplates."acme,local" = "base";
    };
    templateWithSpace = passes {
      templates = "github:acme/templates";
      defaultTemplates.acme = "base other";
    };
  };
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
        inherit assertions;
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
        grep -q '"Related repos" section names the repos it depends on' "$agentsPath"
        grep -q 'tell Alice Example and offer a PR to that repo.$' "$agentsPath"
        grep -q 'with-secrets <path> -- <cmd>' "$agentsPath"
        grep -q '^| `acme/api` | `/stripe/api` | payments |$' "$agentsPath"
        # extraAgentsDoc comes last.
        [ "$(tail -n1 "$agentsPath")" = "Machine rule." ]
        { ${hm.activationPackage}/home-path/bin/grove --help || true; } 2>&1 | grep -q GROVE_ROOT
        grep -q 'GROVE_TEMPLATES.*github:acme/templates' ${hm.activationPackage}/home-path/bin/grove
        grep -q "GROVE_DEFAULT_TEMPLATES.*'acme=base,local=base'" ${hm.activationPackage}/home-path/bin/grove
        # defaultTemplates needs templates, and owners and templates that the encoding can carry.
        echo "$assertions"
        [ "$assertions" = '{"ownerWithComma":false,"templateWithSpace":false,"withTemplates":true,"withoutTemplates":false}' ]
        touch $out
      '';
}
