{
  lib,
  ...
}:
{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    {
      make-shells.default = {
        packages = [
          pkgs.fluxcd
        ];
      };

      kubenix.crds = [
        (pkgs.fetchurl {
          url = "https://github.com/fluxcd/flux2/releases/download/v2.8.8/install.yaml";
          hash = "sha256-zCOEbchr7DfAYNhgwRiER+iWqT+h2eHjrKTiVybBrmE=";
        })
        (pkgs.fetchurl {
          url = "https://github.com/controlplaneio-fluxcd/flux-operator/releases/download/v0.50.0/install.yaml";
          hash = "sha256-i074UaixKW3JdI2H7CqRJity5bXfrLRpYS0zS5PcGCg=";
        })
      ];

      packages.flux = pkgs.stdenv.mkDerivation {
        name = "flux";
        dontUnpack = true;
        installPhase = ''
          ${builtins.concatStringsSep "\n" (
            builtins.map (name: ''
              mkdir -p $out/kubernetes/${name}
              ${pkgs.yq-go}/bin/yq eval-all '[.] | sort_by((.metadata.annotations.apply-order | to_number) // 1000) | .[] | splitDoc' ${
                self'.packages.kubenix-evals.evaluated.${name}.config.kubernetes.resultYAML
              } > $out/kubernetes/${name}/${name}.yaml
            '') (builtins.attrNames self'.packages.kubenix-evals.evaluated)
          )}

          ${builtins.concatStringsSep "\n" (
            builtins.map (name: ''
              mkdir -p $out/tofu-modules/${name}
              cp ${
                self'.packages.tofunix-evals.evaluated.${name}.config.finalPackage
              } $out/tofu-modules/${name}/main.tf.json
            '') (builtins.attrNames self'.packages.tofunix-evals.evaluated)
          )}
        '';
      };
    };

  flake.modules.kubenix.default = {
    options.kustomization = {
      wait = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };
      dependsOn = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              name = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = "";
              };
              namespace = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              readyExpr = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
            };
          }
        );
        default = [ ];
      };
      healthChecks = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              apiVersion = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              kind = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = "";
              };
              name = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = "";
              };
              namespace = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
            };
          }
        );
        default = [ ];
      };
      healthCheckExprs = lib.mkOption {
        type = lib.types.listOf (
          lib.types.submodule {
            options = {
              apiVersion = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = null;
              };
              kind = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = "";
              };
              current = lib.mkOption {
                type = lib.types.nonEmptyStr;
                default = "";
              };
              inProgress = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
              failed = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
              };
            };
          }
        );
        default = [ ];
      };
    };
  };

  flake.modules.kubenix.flux-system =
    {
      self',
      ...
    }:
    {
      config.kubernetes.resources.kustomizations = builtins.listToAttrs (
        builtins.map (name: {
          inherit name;
          value = {
            metadata.namespace = "flux-system";
            spec = {
              inherit (self'.packages.kubenix-evals.evaluated.${name}.config.kustomization) dependsOn;
              inherit (self'.packages.kubenix-evals.evaluated.${name}.config.kustomization) healthChecks;
              interval = "1m0s";
              path = "./kubernetes/${name}";
              prune = true;
              sourceRef = {
                kind = "OCIRepository";
                name = "flux-system";
              };
            };
          };
        }) (builtins.attrNames self'.packages.kubenix-evals.evaluated)
      );
    };

  flake.modules.kubenix.flux-operator =
    {
      pkgs,
      ...
    }:
    let
      fluxOperatorSrc = pkgs.fetchurl {
        url = "https://github.com/controlplaneio-fluxcd/flux-operator/releases/download/v0.50.0/install.yaml";
        hash = "sha256-i074UaixKW3JdI2H7CqRJity5bXfrLRpYS0zS5PcGCg=";
      };

      fluxOperatorImports = pkgs.runCommand "flux-operator-imports" { } ''
        mkdir -p $out
        ${pkgs.yq-go}/bin/yq eval-all -s 'strenv(out) + "/doc-" + $index + ".yaml"' . ${fluxOperatorSrc}
      '';
    in
    {
      kubernetes.imports = builtins.map (name: fluxOperatorImports + "/${name}") (
        builtins.attrNames (builtins.readDir fluxOperatorImports)
      );

      kustomization.dependsOn = [
        {
          name = "calico";
        }
      ];
      kustomization.healthChecks = [
        {
          apiVersion = "apps/v1";
          kind = "Deployment";
          name = "flux-operator";
          namespace = "flux-system";
        }
      ];
    };

  flake.modules.kubenix.flux-setup = {
    kustomization.dependsOn = [
      {
        name = "flux-operator";
      }
      {
        name = "registry";
      }
    ];

    kubernetes.resources.fluxinstances.flux = {
      metadata.namespace = "flux-system";
      metadata.annotations = {
        "fluxcd.controlplane.io/reconcileEvery" = "1m";
        "fluxcd.controlplane.io/reconcileTimeout" = "5m";
        apply-order = "10";
      };
      spec = {
        distribution = {
          registry = "ghcr.io/fluxcd";
          version = "2.8.8";
        };
        sync = {
          kind = "OCIRepository";
          url = "oci://registry.registry.svc.cluster.local:5000/k3s-podman-testing-flux";
          ref = "latest";
          path = "./kubernetes/flux-system";
        };
        kustomize.patches = [
          {
            patch = ''
              - op: add
                path: /spec/insecure
                value: true
            '';
            target = {
              kind = "(OCIRepository|Bucket)";
            };
          }
        ];
      };
    };
  };
}
