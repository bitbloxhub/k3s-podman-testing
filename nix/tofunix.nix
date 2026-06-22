{
  lib,
  flake-parts-lib,
  inputs,
  self,
  ...
}:
{
  config.flake-file.inputs.tofunix.url = "gitlab:TECHNOFAB/tofunix?dir=lib";

  options = {
    perSystem = flake-parts-lib.mkPerSystemOption {
      options.tofunix.providers = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        example = lib.literalExpression ''
          [
            (tofunix-lib.mkOpentofuProvider {
              owner = "bunnyway";
              repo = "bunnynet";
              version = "0.7.0";
              hash = "sha256-GvgAD+E/3potxlZJ3QF3UKB0r4I7lU/NGoV+/8R7RuU=";
            })
          ]
        '';
      };
    };
  };

  config.flake.modules.tofunix.default = { };

  config.perSystem =
    {
      config,
      pkgs,
      inputs',
      self',
      system,
      tofunix-lib,
      ...
    }:
    {
      _module.args.tofunix-lib = inputs.tofunix.lib { inherit lib pkgs; };

      packages.tofunix-evals =
        pkgs.runCommand "tofunix-evals-scope"
          {
            passthru.evaluated = builtins.listToAttrs (
              builtins.map (name: {
                inherit name;
                value = tofunix-lib.mkModule {
                  sources = config.tofunix.providers;

                  moduleConfig = {
                    imports = [
                      self.modules.tofunix.default
                      self.modules.tofunix.${name}
                    ];

                    _module.args = {
                      inherit
                        inputs'
                        self'
                        system
                        tofunix-lib
                        ;
                    };
                  };
                };
              }) (builtins.filter (name: name != "default") (builtins.attrNames self.modules.tofunix))
            );
          }
          ''
            mkdir -p $out
          '';
    };
}
