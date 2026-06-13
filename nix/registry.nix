{
  inputs,
  lib,
  self,
  ...
}:
{
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
      packages.registry-bootstrap =
        pkgs.runCommand "registry-bootstrap.yaml"
          {
            nativeBuildInputs = [ pkgs.yq-go ];
          }
          ''
            ${pkgs.yq-go}/bin/yq eval-all '[.] | sort_by((.metadata.annotations.apply-order | to_number) // 1000) | .[] | splitDoc' ${
              (inputs.kubenix.evalModules.${system} {
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
                      self.modules.kubenix.registry
                      {
                        registry.useLocalStorage = false;
                      }
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
              }).config.kubernetes.resultYAML
            } > "$out"
          '';
    };

  flake.modules.kubenix.registry =
    {
      config,
      ...
    }:
    let
      registryConfigJSON = builtins.toJSON {
        distSpecVersion = "1.1.1";
        storage.rootDirectory = "/var/lib/registry";
        http = {
          address = "0.0.0.0";
          port = "5000";
        };
        extensions = {
          ui.enable = true;
          search.enable = true;
        };
        log.level = "info";
      };
    in
    {
      options.registry.useLocalStorage = lib.mkOption {
        type = lib.types.bool;
        default = true;
      };

      config = {
        kustomization.dependsOn = [
          {
            name = "calico";
          }
        ]
        ++ lib.optionals config.registry.useLocalStorage [
          {
            name = "local-storage";
          }
        ];
        kustomization.healthChecks = [
          {
            apiVersion = "apps/v1";
            kind = "Deployment";
            name = "registry";
            namespace = "registry";
          }
        ];

        kubernetes.resources.namespaces.registry = {
          metadata.annotations.apply-order = "5";
        };

        kubernetes.resources.configMaps.registry-config = {
          metadata.namespace = "registry";
          data."config.json" = registryConfigJSON;
        };

        kubernetes.resources.persistentVolumeClaims = lib.mkIf config.registry.useLocalStorage {
          registry-data = {
            metadata = {
              name = "registry-data";
              namespace = "registry";
            };
            spec = {
              accessModes = [ "ReadWriteOnce" ];
              storageClassName = "local-path";
              resources.requests.storage = "2Gi";
            };
          };
        };

        kubernetes.resources.deployments.registry = {
          metadata.namespace = "registry";
          spec = {
            replicas = 1;
            strategy.type = "Recreate";
            selector.matchLabels.app = "registry";
            template = {
              metadata = {
                labels.app = "registry";
                annotations = {
                  "checksum/config" = builtins.hashString "sha256" registryConfigJSON;
                };
              };
              spec = {
                containers = [
                  {
                    name = "zot";
                    image = "ghcr.io/project-zot/zot:v2.1.17";
                    args = [
                      "serve"
                      "/etc/zot/config.json"
                    ];
                    ports = [
                      {
                        containerPort = 5000;
                        name = "http";
                      }
                    ];
                    readinessProbe.httpGet = {
                      path = "/v2/";
                      port = "http";
                    };
                    livenessProbe.httpGet = {
                      path = "/v2/";
                      port = "http";
                    };
                    volumeMounts = [
                      {
                        name = "config";
                        mountPath = "/etc/zot/config.json";
                        subPath = "config.json";
                      }
                      {
                        name = "data";
                        mountPath = "/var/lib/registry";
                      }
                    ];
                  }
                ];
                volumes = [
                  {
                    name = "config";
                    configMap.name = "registry-config";
                  }
                  (
                    if config.registry.useLocalStorage then
                      {
                        name = "data";
                        persistentVolumeClaim.claimName = "registry-data";
                      }
                    else
                      {
                        name = "data";
                        emptyDir = { };
                      }
                  )
                ];
              };
            };
          };
        };

        kubernetes.resources.services.registry = {
          metadata.namespace = "registry";
          spec = {
            selector.app = "registry";
            ports = [
              {
                name = "http";
                port = 5000;
                targetPort = "http";
              }
            ];
          };
        };
      };
    };
}
