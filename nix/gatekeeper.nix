{
  flake.lib.gatekeeperConstraintSpecToCrd =
    {
      pkgs,
      constraintSpec,
      group ? "constraints.gatekeeper.sh",
      version ? "v1beta1",
    }:
    let
      inherit (constraintSpec) names;
      parametersSchema = constraintSpec.validation.openAPIV3Schema;
    in
    pkgs.writeTextFile {
      name = "${names.plural}.${group}.crd.yaml";
      text = builtins.toJSON {
        apiVersion = "apiextensions.k8s.io/v1";
        kind = "CustomResourceDefinition";

        metadata.name = "${names.plural}.${group}";

        spec = {
          inherit group names;
          scope = "Cluster";

          versions = [
            {
              name = version;
              served = true;
              storage = true;

              schema.openAPIV3Schema = {
                type = "object";

                properties = {
                  spec = {
                    type = "object";

                    properties = {
                      enforcementAction = {
                        type = "string";
                        enum = [
                          "deny"
                          "dryrun"
                          "warn"
                        ];
                      };

                      match = {
                        type = "object";
                        x-kubernetes-preserve-unknown-fields = true;
                      };

                      parameters = parametersSchema;
                    };
                  };

                  status = {
                    type = "object";
                    x-kubernetes-preserve-unknown-fields = true;
                  };
                };
              };
            }
          ];
        };
      };
    };

  flake.lib.gatekeeperTemplateCrdSpec =
    crdSpec:
    crdSpec
    // {
      names = builtins.intersectAttrs {
        kind = null;
        shortNames = null;
      } crdSpec.names;
    };

  perSystem =
    {
      pkgs,
      ...
    }:
    {
      kubenix.crds = [
        (pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/open-policy-agent/gatekeeper/v3.22.2/deploy/gatekeeper.yaml";
          hash = "sha256-cmg/V/36TDTUqJLl5vRXpaflM+ugKT14HVPQjdZhSlo=";
        })
      ];
    };

  flake.modules.kubenix.gatekeeper = {
    kubernetes.resources.namespaces.gatekeeper = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.helmrepositories.gatekeeper = {
      metadata.namespace = "gatekeeper";
      spec = {
        interval = "10m0s";
        url = "https://open-policy-agent.github.io/gatekeeper/charts/";
      };
    };

    kubernetes.resources.helmreleases.gatekeeper = {
      metadata.namespace = "gatekeeper";
      spec = {
        interval = "10m0s";
        chart.spec = {
          chart = "gatekeeper";
          version = "3.22.2";
          sourceRef = {
            kind = "HelmRepository";
            name = "gatekeeper";
          };
        };
        values = {
          replicas = 1;
          pdb.controllerManager.minAvailable = 0;

          image = {
            repository = "docker.io/openpolicyagent/gatekeeper";
            crdRepository = "docker.io/openpolicyagent/gatekeeper-crds";
          };
          preInstall.crdRepository.image.repository = "docker.io/openpolicyagent/gatekeeper-crds";
          postInstall.labelNamespace = {
            image.repository = "docker.io/openpolicyagent/gatekeeper-crds";
            probeWebhook.image.repository = "docker.io/curlimages/curl";
          };
          postUpgrade.labelNamespace.image.repository = "docker.io/openpolicyagent/gatekeeper-crds";
          preUninstall.deleteWebhookConfigurations.image.repository = "docker.io/openpolicyagent/gatekeeper-crds";

          controllerManager = {
            readinessTimeout = 5;
            livenessTimeout = 5;
            resources = {
              requests = {
                cpu = "50m";
                memory = "256Mi";
              };
              limits.memory = "512Mi";
            };
          };

          audit = {
            readinessTimeout = 5;
            livenessTimeout = 5;
            resources = {
              requests = {
                cpu = "50m";
                memory = "256Mi";
              };
              limits.memory = "512Mi";
            };
          };
        };
      };
    };
  };
}
