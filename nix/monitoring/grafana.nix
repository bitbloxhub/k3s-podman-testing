{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      kubenix.crds = [
        (pkgs.fetchurl {
          url = "https://github.com/grafana/grafana-operator/releases/download/v5.23.0/crds.yaml";
          hash = "sha256-PuwUiGBEEFECPUAGk8cWD9I8JyjrRt7AJ/a93wFyH8E=";
        })
      ];
    };

  flake.modules.kubenix.grafana-operator = {
    kustomization.healthChecks = [
      {
        apiVersion = "helm.toolkit.fluxcd.io/v2";
        kind = "HelmRelease";
        name = "grafana-operator";
        namespace = "grafana";
      }
    ];

    kubernetes.resources.namespaces.grafana = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.ocirepositories.grafana-operator = {
      metadata.namespace = "grafana";
      spec = {
        interval = "10m0s";
        url = "oci://ghcr.io/grafana/helm-charts/grafana-operator";
        ref.tag = "5.23.0";
      };
    };

    kubernetes.resources.helmreleases.grafana-operator = {
      metadata.namespace = "grafana";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "grafana-operator";
        };
        values = {
          namespaceScope = true;
          rbac.useClusterRole = false;
          crds.immutable = false;
        };
      };
    };
  };

  flake.modules.kubenix.grafana = {
    kustomization.dependsOn = [
      {
        name = "grafana-operator";
      }
      {
        name = "authentik";
      }
    ];

    kustomization.healthChecks = [
      {
        apiVersion = "grafana.integreatly.org/v1beta1";
        kind = "Grafana";
        name = "grafana";
        namespace = "grafana";
      }
    ];

    kubernetes.resources.secrets.grafana-authentik-oauth-input = {
      metadata.namespace = "grafana";
      type = "Opaque";
      stringData.client-secret = "replace-with-sops-generated-secret";
    };

    kubernetes.resources.secrets.grafana-authentik-oauth = {
      metadata = {
        name = "grafana-authentik-oauth";
        namespace = "grafana";
      };
      stringData = {
        client-id = "grafana";
        client-secret = "WrzMhsxWh528P2gIITjTwXES2iZ96UiYq8RWvKyDD3Ft7CiguzxGoZ8Ur2tmRsuNJ2BrMhZChhWGGEwn0gVyQW0zU1AV1HdWoYpgd7YcsVNgqagtQ06xSgMg8IkKCiSu";
      };
    };

    kubernetes.resources.grafanas.grafana = {
      metadata = {
        namespace = "grafana";
        labels = {
          dashboards = "grafana";
          instance = "grafana";
        };
      };
      spec = {
        version = "13.0.1-security-01";
        deployment.spec.template.spec.containers = [
          {
            name = "grafana";
            env = [
              {
                name = "AUTH_CLIENT_ID";
                valueFrom.secretKeyRef = {
                  name = "grafana-authentik-oauth";
                  key = "client-id";
                };
              }
              {
                name = "AUTH_CLIENT_SECRET";
                valueFrom.secretKeyRef = {
                  name = "grafana-authentik-oauth";
                  key = "client-secret";
                };
              }
            ];
          }
        ];
        config = {
          log.mode = "console";
          server.root_url = "http://grafana.k3s-podman-testing.localhost:4962";
          security = {
            admin_user = "root";
            admin_password = "secret";
          };
          "auth.generic_oauth" = {
            enabled = "true";
            name = "Authentik";
            allow_sign_up = "true";
            scopes = "openid profile email entitlements";
            use_pkce = "true";
            client_id = "$__env{AUTH_CLIENT_ID}";
            client_secret = "$__env{AUTH_CLIENT_SECRET}";
            auth_url = "http://authentik.k3s-podman-testing.localhost:4962/application/o/authorize/";
            token_url = "http://authentik-server.authentik.svc.cluster.local/application/o/token/";
            api_url = "http://authentik-server.authentik.svc.cluster.local/application/o/userinfo/";
            role_attribute_path = "contains(entitlements, 'Grafana Admins') && 'GrafanaAdmin' || contains(entitlements, 'Grafana Editors') && 'Editor' || 'Viewer'";
            role_attribute_strict = "true";
            allow_assign_grafana_admin = "true";
            signout_redirect_url = "http://authentik.k3s-podman-testing.localhost:4962/application/o/grafana/end-session/";
          };
        };
      };
    };

    kubernetes.resources.grafanadatasources.mimir = {
      metadata.namespace = "grafana";
      spec = {
        instanceSelector.matchLabels.dashboards = "grafana";
        datasource = {
          name = "Mimir";
          uid = "mimir";
          type = "prometheus";
          access = "proxy";
          url = "http://mimir-distributed-gateway.mimir.svc.cluster.local/prometheus";
          isDefault = true;
          jsonData = {
            tlsSkipVerify = true;
            timeInterval = "5s";
          };
        };
      };
    };

    kubernetes.resources.grafanadatasources.loki = {
      metadata.namespace = "grafana";
      spec = {
        instanceSelector = {
          matchLabels.dashboards = "grafana";
        };
        datasource = {
          name = "Loki";
          type = "loki";
          access = "proxy";
          url = "http://loki-gateway.loki.svc.cluster.local/";
          isDefault = false;
        };
      };
    };

    kubernetes.resources.httproutes.grafana = {
      metadata.namespace = "grafana";
      spec = {
        parentRefs = [
          {
            name = "design";
            namespace = "gateway-system";
          }
        ];
        hostnames = [
          "grafana.k3s-podman-testing.localhost"
        ];
        rules = [
          {
            backendRefs = [
              {
                kind = "Service";
                name = "grafana-service";
                port = 3000;
              }
            ];
          }
        ];
      };
    };
  };
}
