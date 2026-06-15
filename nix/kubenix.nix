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

      packages.kubenix-evals =
        pkgs.runCommand "kubenix-evals-scope"
          {
            passthru.evaluated = builtins.listToAttrs (
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
            );
          }
          ''
            mkdir -p $out
          '';
    };
}
