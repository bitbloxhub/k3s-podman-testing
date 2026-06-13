{
  inputs,
  self,
  ...
}:
{
  flake-file.inputs.kubenix = {
    url = "github:hall/kubenix";
    inputs.nixpkgs.follows = "nixpkgs";
    inputs.treefmt.follows = "treefmt-nix";
    inputs.flake-compat.follows = "";
  };

  perSystem =
    {
      config,
      inputs',
      self',
      pkgs,
      system,
      ...
    }:
    {
      make-shells.default = {
        packages = [
          pkgs.kubectl
        ];

        shellHook = ''
          export KUBECONFIG=$(pwd)/.direnv/kubeconfig.yaml
        '';
      };

      packages.flux =
        pkgs.stdenv.mkDerivation {
          name = "flux";
          dontUnpack = true;
          installPhase = ''
            ${builtins.concatStringsSep "\n" (
              builtins.map (name: ''
                mkdir -p $out/${name}
                ${pkgs.yq-go}/bin/yq eval-all '[.] | sort_by((.metadata.annotations.apply-order | to_number) // 1000) | .[] | splitDoc' ${
                  self'.packages.flux.${name}.config.kubernetes.resultYAML
                } > $out/${name}/${name}.yaml
              '') (builtins.filter (name: name != "default") (builtins.attrNames self.modules.kubenix))
            )}
          '';
        }
        // (builtins.listToAttrs (
          builtins.map (name: {
            inherit name;
            value = inputs.kubenix.evalModules.${system} {
              module =
                {
                  kubenix,
                  kubenixCrdCustomTypes,
                  ...
                }:
                {
                  imports = [
                    kubenix.modules.k8s
                    self.modules.kubenix.default
                    self.modules.kubenix.${name}
                  ];
                  kubernetes.version = "1.35";
                  kubernetes.customTypes = kubenixCrdCustomTypes;
                };
              specialArgs = {
                inherit
                  inputs'
                  self
                  self'
                  system
                  ;
                kubenixCrdCustomTypes = config._module.args.kubenixCrdCustomTypes;
              };
            };
          }) (builtins.filter (name: name != "default") (builtins.attrNames self.modules.kubenix))
        ));
    };
}
