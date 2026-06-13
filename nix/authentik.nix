_:
let
  oidcAppApiGroup = "identity.k3s-podman-testing.localhost";
  oidcAppKind = "OIDCApp";
  oidcAppPlural = "oidcapps";

  oidcAppOpenAPIV3Schema = {
    type = "object";
    properties = {
      spec = {
        type = "object";
        required = [
          "slug"
          "displayName"
          "redirectUris"
          "connectionSecretRef"
        ];
        properties = {
          slug = {
            type = "string";
            pattern = "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$";
          };
          displayName = {
            type = "string";
          };
          redirectUris = {
            type = "array";
            minItems = 1;
            items = {
              type = "string";
              format = "uri";
            };
          };
          logoutUri = {
            type = "string";
            format = "uri";
          };
          scopes = {
            type = "array";
            items = {
              type = "string";
              enum = [
                "openid"
                "profile"
                "email"
                "roles"
              ];
            };
          };
          connectionSecretRef = {
            type = "object";
            required = [
              "namespace"
              "name"
            ];
            properties = {
              namespace = {
                type = "string";
              };
              name = {
                type = "string";
              };
            };
          };
        };
      };
      status = {
        type = "object";
        properties = {
          workspaceName = {
            type = "string";
          };
          connectionSecretName = {
            type = "string";
          };
        };
      };
    };
  };

  oidcAppCrdManifest = {
    apiVersion = "apiextensions.k8s.io/v1";
    kind = "CustomResourceDefinition";
    metadata.name = "${oidcAppPlural}.${oidcAppApiGroup}";
    spec = {
      group = oidcAppApiGroup;
      scope = "Namespaced";
      names = {
        kind = oidcAppKind;
        plural = oidcAppPlural;
        singular = "oidcapp";
      };
      versions = [
        {
          name = "v1alpha1";
          served = true;
          storage = true;
          schema.openAPIV3Schema = oidcAppOpenAPIV3Schema;
        }
      ];
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
        ((pkgs.formats.yaml { }).generate "oidcapp-crd.yaml" oidcAppCrdManifest)
      ];
    };

  flake.modules.kubenix.authentik = {
    kubernetes.resources.namespaces.authentik = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.cnpgClusters.postgres = {
      metadata.namespace = "authentik";

      spec = {
        instances = 1;

        bootstrap.initdb = {
          database = "authentik";
          owner = "authentik";
        };

        storage = {
          size = "10Gi";
          storageClass = "local-path";
        };
      };
    };

    kubernetes.resources.ocirepositories.authentik = {
      metadata.namespace = "authentik";
      spec = {
        interval = "10m0s";
        url = "oci://ghcr.io/goauthentik/helm-charts/authentik";
        ref.tag = "2026.5.2";
      };
    };

    kubernetes.resources.secrets.authentik-app-secret = {
      metadata.namespace = "authentik";
      type = "Opaque";
      stringData.AUTHENTIK_SECRET_KEY = "2Hd+O2eDJiR3Gmzfi07lRyPSVRJqqO/7qM7OxuF6Mf7f2wcB6bh7lRvV6iGVRhGwLNXi+XeOgizVxqxN";
    };

    kubernetes.resources.secrets.authentik-api-token = {
      metadata.namespace = "authentik";
      type = "Opaque";
      stringData.token = "0JTwceHMm9wacJGqNhZJ1mq1dlx9XjScPhOv8L6qmDBWLpn6thVuvOgwO1ur";
    };

    kubernetes.resources.helmreleases.authentik = {
      metadata.namespace = "authentik";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "authentik";
        };
        values = {
          authentik = {
            postgresql = {
              host = "postgres-rw";
              port = 5432;
              name = "authentik";
              user = "authentik";
            };
          };
          global.env = [
            {
              name = "AUTHENTIK_SECRET_KEY";
              valueFrom.secretKeyRef = {
                name = "authentik-app-secret";
                key = "AUTHENTIK_SECRET_KEY";
              };
            }
            {
              name = "AUTHENTIK_POSTGRESQL__PASSWORD";
              valueFrom.secretKeyRef = {
                name = "postgres-app";
                key = "password";
              };
            }
            {
              name = "AUTHENTIK_POSTGRESQL__SSLMODE";
              value = "disable";
            }
          ];
        };
      };
    };

    kubernetes.resources.httproutes.authentik = {
      metadata.namespace = "authentik";
      spec = {
        parentRefs = [
          {
            name = "design";
            namespace = "gateway-system";
          }
        ];
        hostnames = [
          "authentik.k3s-podman-testing.localhost"
        ];
        rules = [
          {
            backendRefs = [
              {
                kind = "Service";
                name = "authentik-server";
                port = 80;
              }
            ];
          }
        ];
      };
    };
  };
}
