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

  flake.modules.tofunix.grafana-oidc =
    {
      ref,
      ...
    }:
    {
      variable = {
        authentik_url = {
          type = "string";
        };
        authentik_token = {
          type = "string";
          sensitive = true;
        };
        grafanaUrl = {
          type = "string";
        };
      };

      provider.authentik.default = {
        url = ref.var.authentik_url;
        token = ref.var.authentik_token;
      };

      data.authentik_flow.default_authorization_flow = {
        slug = "default-provider-authorization-implicit-consent";
      };
      data.authentik_flow.default_invalidation_flow = {
        slug = "default-provider-invalidation-flow";
      };

      data.authentik_property_mapping_provider_scope.scope_mappings = {
        managed_list = [
          "goauthentik.io/providers/oauth2/scope-openid"
          "goauthentik.io/providers/oauth2/scope-email"
          "goauthentik.io/providers/oauth2/scope-profile"
          "goauthentik.io/providers/oauth2/scope-entitlements"
        ];
      };
      resource.authentik_provider_oauth2.provider = {
        name = "Grafana";
        client_id = "grafana";
        client_type = "confidential";
        grant_types = [
          "authorization_code"
        ];

        authorization_flow = ref.data.authentik_flow.default_authorization_flow.id;
        invalidation_flow = ref.data.authentik_flow.default_invalidation_flow.id;

        property_mappings = ref.data.authentik_property_mapping_provider_scope.scope_mappings.ids;

        allowed_redirect_uris = [
          {
            matching_mode = "strict";
            url = "\${var.grafanaUrl}/login/generic_oauth";
          }
        ];
      };

      resource.authentik_application.application = {
        name = "Grafana";
        slug = "grafana";
        protocol_provider = ref.authentik_provider_oauth2.provider.id;
        meta_launch_url = ref.var.grafanaUrl;
      };

      output = {
        applicationPk.value = ref.authentik_application.application.id;
        applicationUuid.value = ref.authentik_application.application.uuid;
        providerPk.value = ref.authentik_provider_oauth2.provider.id;

        client_id.value = ref.authentik_provider_oauth2.provider.client_id;

        client_secret = {
          value = ref.authentik_provider_oauth2.provider.client_secret;
          sensitive = true;
        };

        auth_url.value = "\${var.authentik_url}/application/o/authorize/";
        token_url.value = "\${var.authentik_url}/application/o/token/";
        api_url.value = "\${var.authentik_url}/application/o/userinfo/";

        ready.value = true;
      };
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
        name = "tofu-controller";
      }
      {
        name = "authentik";
      }
    ];

    kustomization.healthChecks = [
      {
        apiVersion = "infra.contrib.fluxcd.io/v1alpha2";
        kind = "Terraform";
        name = "grafana-oidc";
        namespace = "grafana";
      }
      {
        apiVersion = "grafana.integreatly.org/v1beta1";
        kind = "Grafana";
        name = "grafana";
        namespace = "grafana";
      }
    ];

    kubernetes.resources.authentikusers.grafana = {
      metadata.namespace = "grafana";
      spec = {
        username = "grafana-tofu-setup";
        type = "service_account";
        permissions = {
          global = [
            "authentik_core.add_application"
            "authentik_providers_oauth2.add_oauth2provider"
            "authentik_flows.view_flow"
            "authentik_providers_oauth2.view_scopemapping"
          ];

          initial = [
            "view_application"
            "change_application"
            "delete_application"
            "view_oauth2provider"
            "change_oauth2provider"
            "delete_oauth2provider"
          ];
        };
      };
    };

    kubernetes.resources.authentiktokens.grafana = {
      metadata.namespace = "grafana";
      spec = {
        userRef.name = "grafana";
        username = "grafana-tofu-setup";
        identifier = "grafana-tofu-setup";
        description = "Grafana OpenTofu setup token";
        expiring = false;
        outputSecret.name = "grafana-authentik-api-token";
      };
    };

    kubernetes.resources.terraforms.grafana-oidc = {
      metadata.namespace = "grafana";
      spec = {
        interval = "1m";
        approvePlan = "auto";
        path = "./tofu-modules/grafana-oidc";
        sourceRef = {
          kind = "OCIRepository";
          name = "flux-system";
          namespace = "flux-system";
        };
        varsFrom = [
          {
            kind = "Secret";
            name = "grafana-authentik-api-token";
          }
        ];
        vars = [
          {
            name = "grafanaUrl";
            value = "http://grafana.k3s-podman-testing.localhost:4962";
          }
        ];
        writeOutputsToSecret = {
          name = "grafana-authentik-oauth";
          outputs = [
            "client_id:client-id"
            "client_secret:client-secret"
            "auth_url:auth-url"
            "token_url:token-url"
            "api_url:api-url"
          ];
        };
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
              {
                name = "AUTH_AUTH_URL";
                valueFrom.secretKeyRef = {
                  name = "grafana-authentik-oauth";
                  key = "auth-url";
                };
              }
              {
                name = "AUTH_TOKEN_URL";
                valueFrom.secretKeyRef = {
                  name = "grafana-authentik-oauth";
                  key = "token-url";
                };
              }
              {
                name = "AUTH_API_URL";
                valueFrom.secretKeyRef = {
                  name = "grafana-authentik-oauth";
                  key = "api-url";
                };
              }
            ];
          }
        ];
        config = {
          log.mode = "console";
          server.root_url = "http://grafana.k3s-podman-testing.localhost:4962";
          auth.disable_login_form = "true";
          "auth.basic".enabled = "false";
          "auth.generic_oauth" = {
            enabled = "true";
            name = "Authentik";
            allow_sign_up = "true";
            scopes = "openid profile email entitlements";
            use_pkce = "true";
            client_id = "$__env{AUTH_CLIENT_ID}";
            client_secret = "$__env{AUTH_CLIENT_SECRET}";
            auth_url = "http://authentik.k3s-podman-testing.localhost:4962/application/o/authorize/";
            token_url = "$__env{AUTH_TOKEN_URL}";
            api_url = "$__env{AUTH_API_URL}";
            role_attribute_path = "contains(groups[*], 'authentik Admins') && 'Admin' || 'Viewer'";
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
