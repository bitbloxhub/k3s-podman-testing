{
  flake.modules.tofunix.radar-oidc =
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
        radar_url = {
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
      data.authentik_certificate_key_pair.signing_key = {
        name = "authentik Self-signed Certificate";
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
        name = "Radar";
        client_id = "radar";
        client_type = "confidential";
        grant_types = [
          "authorization_code"
        ];

        signing_key = ref.data.authentik_certificate_key_pair.signing_key.id;

        authorization_flow = ref.data.authentik_flow.default_authorization_flow.id;
        invalidation_flow = ref.data.authentik_flow.default_invalidation_flow.id;

        property_mappings = ref.data.authentik_property_mapping_provider_scope.scope_mappings.ids;

        allowed_redirect_uris = [
          {
            matching_mode = "strict";
            redirect_uri_type = "authorization";
            url = "\${var.radar_url}/auth/callback";
          }
        ];
      };

      resource.authentik_application.application = {
        name = "Radar";
        slug = "radar";
        protocol_provider = ref.authentik_provider_oauth2.provider.id;
        meta_launch_url = ref.var.radar_url;
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

        issuer.value = "http://authentik.k3s-podman-testing.localhost/application/o/radar/";
        callback_url.value = "\${var.radar_url}/auth/callback";

        ready.value = true;
      };
    };

  flake.modules.kubenix.radar = {
    kubernetes.resources.namespaces.radar = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.authentikusers.radar = {
      metadata.namespace = "radar";
      spec = {
        username = "radar-tofu-setup";
        type = "service_account";
        permissions = {
          global = [
            "authentik_core.add_application"
            "authentik_providers_oauth2.add_oauth2provider"
            "authentik_flows.view_flow"
            "authentik_providers_oauth2.view_scopemapping"
            "authentik_crypto.view_certificatekeypair"
            "authentik_crypto.view_certificatekeypair_certificate"
            # absurdly insecure to just get the UUID but it works
            "authentik_crypto.view_certificatekeypair_key"
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

    kubernetes.resources.authentiktokens.radar = {
      metadata.namespace = "radar";
      spec = {
        userRef.name = "radar";
        username = "radar-tofu-setup";
        identifier = "radar-tofu-setup";
        description = "Radar OpenTofu setup token";
        expiring = false;
        outputSecret.name = "radar-authentik-api-token";
      };
    };

    kubernetes.resources.terraforms.radar-oidc = {
      metadata.namespace = "radar";
      spec = {
        interval = "1m";
        approvePlan = "auto";
        path = "./tofu-modules/radar-oidc";
        sourceRef = {
          kind = "OCIRepository";
          name = "flux-system";
          namespace = "flux-system";
        };
        varsFrom = [
          {
            kind = "Secret";
            name = "radar-authentik-api-token";
          }
        ];
        vars = [
          {
            name = "radar_url";
            value = "http://radar.k3s-podman-testing.localhost:4962";
          }
        ];
        writeOutputsToSecret = {
          name = "radar-authentik-oauth";
          outputs = [
            "client_id:client-id"
            "client_secret:client-secret"
            "issuer:issuer"
            "callback_url:callback_url"
          ];
        };
      };
    };

    kubernetes.resources.helmrepositories.radar = {
      metadata.namespace = "radar";
      spec = {
        interval = "10m0s";
        url = "https://skyhook-io.github.io/helm-charts/";
      };
    };

    kubernetes.resources.helmreleases.radar = {
      metadata.namespace = "radar";
      spec = {
        interval = "10m0s";
        chart.spec = {
          chart = "radar";
          version = "1.7.6";
          sourceRef = {
            kind = "HelmRepository";
            name = "radar";
          };
        };
        values = {
          auth.mode = "oidc";
          auth.secret = "radar-auth-secret";
          auth.oidc = {
            issuerURL = "http://authentik.k3s-podman-testing.localhost:4962/application/o/radar/";
            clientID = "radar";

            existingSecret = "radar-authentik-oauth";
            clientSecretKey = "client-secret";

            redirectURL = "http://radar.k3s-podman-testing.localhost:4962/auth/callback";

            scopes = [
              "openid"
              "profile"
              "email"
              "entitlements"
            ];

            groupsClaim = "entitlements";
            adminGroups = [
              "authentik Admins"
            ];

            defaultRole = "member";
          };
        };
        postRenderers = [
          {
            kustomize.patches = [
              {
                target = {
                  kind = "Deployment";
                  name = "radar";
                };

                patch =
                  # yaml
                  ''
                    - op: add
                      path: /spec/template/spec/hostAliases
                      value:
                        - ip: "127.0.0.1"
                          hostnames:
                            - "authentik.k3s-podman-testing.localhost"

                    - op: add
                      path: /spec/template/spec/containers/-
                      value:
                        name: authentik-issuer-loopback
                        image: ghcr.io/nicolaka/netshoot:v0.15
                        command:
                          - socat
                        args:
                          - TCP-LISTEN:4962,fork,reuseaddr
                          - TCP:authentik-server.authentik.svc.cluster.local:80
                        securityContext:
                          allowPrivilegeEscalation: false
                          capabilities:
                            drop:
                              - ALL
                          readOnlyRootFilesystem: true
                          runAsNonRoot: true
                          runAsUser: 65532
                  '';
              }
            ];
          }
        ];
      };
    };

    kubernetes.resources.httproutes.radar = {
      metadata.namespace = "radar";
      spec = {
        parentRefs = [
          {
            name = "design";
            namespace = "gateway-system";
          }
        ];
        hostnames = [
          "radar.k3s-podman-testing.localhost"
        ];
        rules = [
          {
            backendRefs = [
              {
                kind = "Service";
                name = "radar";
                port = 9280;
              }
            ];
          }
        ];
      };
    };
  };
}
