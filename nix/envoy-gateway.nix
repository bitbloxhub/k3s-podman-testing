{
  self,
  ...
}:
let
  gatewayDomainConstraintSpec = {
    names = {
      kind = "GatewayDomain";
      plural = "gatewaydomains";
      singular = "gatewaydomain";
      listKind = "GatewayDomainList";
    };

    validation.openAPIV3Schema = {
      type = "object";
      properties = {
        allowedDomains = {
          type = "array";
          items.type = "string";
        };
      };
    };
  };
in
{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      kubenix.crds = [
        (pkgs.fetchurl {
          url = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/experimental-install.yaml";
          hash = "sha256-ZOx2YJpqyIXgQF3qecpQnCKfoBnTQvCFeqi2vci4upI=";
        })
        (pkgs.fetchurl {
          url = "https://github.com/envoyproxy/gateway/releases/download/v1.8.1/envoy-gateway-crds.yaml";
          hash = "sha256-cCwld4sM3Im1zMFJbH+CAA66/VgEXiwb5eKP2t4bxMM=";
        })
        (self.lib.gatekeeperConstraintSpecToCrd {
          inherit pkgs;
          constraintSpec = gatewayDomainConstraintSpec;
        })
      ];
    };

  flake.modules.kubenix.envoy-gateway = {
    kustomization.dependsOn = [
      {
        name = "calico";
      }
    ];
    kustomization.healthChecks = [
      # TODO: add these
    ];

    kubernetes.resources.namespaces.gateway-system = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.ocirepositories.envoy-gateway = {
      metadata.namespace = "gateway-system";
      spec = {
        interval = "10m0s";
        url = "oci://docker.io/envoyproxy/gateway-helm";
        ref.tag = "v1.8.1";
      };
    };

    kubernetes.resources.helmreleases.envoy-gateway = {
      metadata.namespace = "gateway-system";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "envoy-gateway";
        };
      };
    };

    kubernetes.resources.gatewayclasses.envoy = {
      metadata.namespace = "gateway-system";
      spec.controllerName = "gateway.envoyproxy.io/gatewayclass-controller";
    };

    kubernetes.resources.envoyproxies.design = {
      metadata.namespace = "gateway-system";
      spec.provider = {
        type = "Kubernetes";
        kubernetes.envoyService.type = "ClusterIP";
      };
    };

    # If this was a real cluster I'd proxy through Hoid
    kubernetes.resources.gateways.design = {
      metadata.namespace = "gateway-system";
      spec = {
        gatewayClassName = "envoy";
        infrastructure.parametersRef = {
          group = "gateway.envoyproxy.io";
          kind = "EnvoyProxy";
          name = "design";
        };
        listeners = [
          {
            name = "http-root";
            protocol = "HTTP";
            port = 80;
            hostname = "k3s-podman-testing.localhost";
            allowedRoutes.namespaces.from = "All";
          }
          {
            name = "http-wildcard";
            protocol = "HTTP";
            port = 80;
            hostname = "*.k3s-podman-testing.localhost";
            allowedRoutes.namespaces.from = "All";
          }
        ];
      };
    };

    kubernetes.resources.constrainttemplates.gatewaydomain = {
      spec = {
        crd.spec = self.lib.gatekeeperTemplateCrdSpec gatewayDomainConstraintSpec;
        targets = [
          {
            target = "admission.k8s.gatekeeper.sh";
            rego =
              # rego
              ''
                package gatewaydomain

                default allowed = false

                allowed_hostname(hostname) {
                  domain := input.parameters.allowedDomains[_]
                  hostname == domain
                }

                allowed_hostname(hostname) {
                  domain := input.parameters.allowedDomains[_]
                  suffix := concat("", [".", domain])
                  endswith(hostname, suffix)
                }

                allowed_hostname(hostname) {
                  domain := input.parameters.allowedDomains[_]
                  wildcard := concat("", ["*.", domain])
                  hostname == wildcard
                }

                gateway_hostname[hostname] {
                  input.review.kind.kind == "Gateway"
                  listener := input.review.object.spec.listeners[_]
                  hostname := listener.hostname
                }

                httproute_hostname[hostname] {
                  input.review.kind.kind == "HTTPRoute"
                  hostname := input.review.object.spec.hostnames[_]
                }

                violation[{"msg": msg}] {
                  hostname := gateway_hostname[_]
                  not allowed_hostname(hostname)
                  msg := sprintf("Gateway listener hostname %q is outside allowed domains %v", [hostname, input.parameters.allowedDomains])
                }

                violation[{"msg": msg}] {
                  hostname := httproute_hostname[_]
                  not allowed_hostname(hostname)
                  msg := sprintf("HTTPRoute hostname %q is outside allowed domains %v", [hostname, input.parameters.allowedDomains])
                }
              '';
          }
        ];
      };
    };
  };

  flake.modules.kubenix.gateway-policies = {
    kustomization.dependsOn = [
      {
        name = "envoy-gateway";
      }
    ];
    kubernetes.resources.gatewaydomains.localhost-only = {
      metadata.name = "localhost-only";

      spec = {
        enforcementAction = "deny";
        match.kinds = [
          {
            apiGroups = [ "gateway.networking.k8s.io" ];
            kinds = [
              "Gateway"
              "HTTPRoute"
            ];
          }
        ];
        parameters.allowedDomains = [
          "k3s-podman-testing.localhost"
        ];
      };
    };
  };
}
