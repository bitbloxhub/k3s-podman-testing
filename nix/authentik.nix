{
  lib,
  self,
  ...
}:
let
  authentikUserSchema = {
    apiVersion = "v1alpha1";
    group = "authentik.k3s-podman-testing.localhost";
    kind = "AuthentikUser";
    scope = "Namespaced";

    spec = {
      username = "string | required=true";

      name = ''string | default=""'';
      email = ''string | default=""'';
      path = ''string | default="users"'';
      type = ''string | default="internal"'';
      isActive = "boolean | default=true";

      # Provider-compatible JSON string for arbitrary Authentik attrs.
      attributes = ''string | default="{}"'';

      # Raw Authentik IDs for now.
      groups = "[]string | default=[]";
      roles = "[]string | default=[]";

      passwordSecretRef = {
        name = ''string | default=""'';
        key = ''string | default="password"'';
      };

      permissions = {
        # Permission codenames, e.g. "authentik_core.view_user".
        global = "[]string | default=[]";
        initial = "[]string | default=[]";
      };
    };

    status = {
      username = "$" + "{terraform.metadata.name}";
      userPk = "$" + "{terraform.metadata.name}";
      rolePk = "$" + "{terraform.metadata.name}";
      ready = "$" + "{terraform.status != null}";
    };
  };

  authentikTokenSchema = {
    apiVersion = "v1alpha1";
    group = "authentik.k3s-podman-testing.localhost";
    kind = "AuthentikToken";
    scope = "Namespaced";

    spec = {
      # v0: token module still resolves user by username.
      # Keep userRef for later wiring when userPk can flow cleanly across runs.
      userRef = {
        name = "string | required=true";
      };

      username = "string | required=true";
      identifier = "string | required=true";
      description = ''string | default=""'';
      intent = ''string | default="api"'';
      expiring = "boolean | default=false";
      expires = ''string | default=""'';
      retrieveKey = "boolean | default=true";

      outputSecret = {
        name = ''string | default="authentik-provider-vars"'';
        tokenKey = ''string | default="authentik_token"'';
        urlKey = ''string | default="authentik_url"'';
      };
    };

    status = {
      identifier = "$" + "{terraform.metadata.name}";
      tokenSecretName = "$" + "{terraform.metadata.name}";
      ready = "$" + "{terraform.status != null}";
    };
  };
in
{
  perSystem =
    {
      pkgs,
      tofunix-lib,
      ...
    }:
    {
      tofunix.providers = [
        (tofunix-lib.mkOpentofuProvider {
          owner = "goauthentik";
          repo = "authentik";
          version = "2026.5.0";
          hash = "sha256-7oStYmFgNlbpJCe5zICnQs/JoNwH5po06nqDrrJG8vo=";
        })
      ];
      kubenix.crds = [
        (self.lib.kroSchemaToCrd {
          inherit pkgs;
          name = "authentik-user";
          schema = authentikUserSchema;
        })
        (self.lib.kroSchemaToCrd {
          inherit pkgs;
          name = "authentik-token";
          schema = authentikTokenSchema;
        })
      ];
    };

  flake.modules.tofunix.authentik-user =
    {
      ref,
      ...
    }:
    let
      userResourceName = "user";
      roleResourceName = "role";
      globalPermissionsResourceName = "global_permissions";
      initialPermissionsLookupName = "initial_permissions_lookup";
      initialPermissionsResourceName = "initial_permissions";

      userRef = ref.authentik_user.${userResourceName};
      roleRef = ref.authentik_rbac_role.${roleResourceName};
    in
    {
      variable = {
        authentik_url = {
          type = "string";
        };
        authentik_token = {
          type = "string";
          sensitive = true;
        };

        username = {
          type = "string";
        };
        name = {
          type = "string";
          default = "";
        };
        email = {
          type = "string";
          default = "";
        };
        path = {
          type = "string";
          default = "users";
        };
        type = {
          type = "string";
          default = "internal";
        };
        isActive = {
          type = "bool";
          default = true;
        };

        attributes = {
          type = "string";
          default = "{}";
        };
        groups = {
          type = "list(string)";
          default = [ ];
        };
        roles = {
          type = "list(string)";
          default = [ ];
        };
        permissionsGlobal = {
          type = "list(string)";
          default = [ ];
        };
        permissionsInitial = {
          type = "list(string)";
          default = [ ];
        };

        # Password must be resolved before entering this Tofunix module.
        password = {
          type = "string";
          sensitive = true;
          default = null;
          nullable = true;
        };
      };

      provider.authentik.default = {
        url = ref.var.authentik_url;
        token = ref.var.authentik_token;
      };

      resource.authentik_rbac_role.${roleResourceName} = {
        name = "k8s-${ref.var.username}-role";
      };

      resource.authentik_rbac_permission_role.${globalPermissionsResourceName} = {
        for_each = "\${toset(var.permissionsGlobal)}";
        role = roleRef.id;
        permission = "\${each.value}";
      };

      data.authentik_rbac_permission.${initialPermissionsLookupName} = {
        for_each = "\${toset(var.permissionsInitial)}";
        codename = "\${each.value}";
      };

      resource.authentik_rbac_initial_permissions.${initialPermissionsResourceName} = {
        count = "\${length(var.permissionsInitial) > 0 ? 1 : 0}";
        name = "k8s-${ref.var.username}-initial-permissions";
        role = roleRef.id;
        permissions = "\${[for p in values(data.authentik_rbac_permission.initial_permissions_lookup) : tonumber(p.id)]}";
      };

      resource.authentik_user.${userResourceName} = {
        username = ref.var.username;
        name = ref.var.name;
        email = ref.var.email;
        path = ref.var.path;
        type = ref.var.type;
        is_active = ref.var.isActive;
        attributes = ref.var.attributes;
        groups = ref.var.groups;
        roles = "\${concat(var.roles, [authentik_rbac_role.role.id])}";
        password = ref.var.password;
      };

      output = {
        username.value = userRef.username;
        userPk.value = userRef.id;
        rolePk.value = roleRef.id;
        ready.value = true;
      };
    };

  flake.modules.tofunix.authentik-token =
    {
      ref,
      ...
    }:
    let
      userLookupName = "user";
      tokenResourceName = "token";

      userRef = ref.data.authentik_user.${userLookupName};
      tokenRef = ref.authentik_token.${tokenResourceName};
    in
    {
      variable = {
        authentik_url = {
          type = "string";
        };
        authentik_token = {
          type = "string";
          sensitive = true;
        };

        username = {
          type = "string";
        };
        identifier = {
          type = "string";
        };
        description = {
          type = "string";
          default = "";
        };
        intent = {
          type = "string";
          default = "api";
        };
        expiring = {
          type = "bool";
          default = false;
        };
        expires = {
          type = "string";
          default = "";
        };
        retrieveKey = {
          type = "bool";
          default = true;
        };
      };

      provider.authentik.default = {
        url = ref.var.authentik_url;
        token = ref.var.authentik_token;
      };

      data.authentik_user.${userLookupName} = {
        username = ref.var.username;
      };

      resource.authentik_token.${tokenResourceName} = {
        identifier = ref.var.identifier;
        user = userRef.id;

        description = ref.var.description;
        intent = ref.var.intent;
        expiring = ref.var.expiring;
        expires = "\${var.expires != \"\" ? var.expires : null}";
        retrieve_key = ref.var.retrieveKey;
      };

      output = {
        identifier.value = tokenRef.identifier;

        authentik_token = {
          value = tokenRef.key;
          sensitive = true;
        };

        authentik_url.value = ref.var.authentik_url;
        ready.value = true;
      };
    };

  flake.modules.kubenix.authentik =
    {
      pkgs,
      ...
    }:
    let
      authentikBootstrapToken = "REPLACE_WITH_LONG_RANDOM_TOKEN";
      expr = path: "\${" + path + "}";
      authentikUserTerraformName =
        "authentik-user-" + expr "schema.metadata.namespace" + "-" + expr "schema.metadata.name";
      authentikTokenTerraformName =
        "authentik-token-" + expr "schema.metadata.namespace" + "-" + expr "schema.metadata.name";
    in
    {
      kustomization.dependsOn = [
        {
          name = "tofu-controller";
        }
      ];
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

      kubernetes.resources.secrets.authentik-bootstrap-blueprint = {
        metadata.namespace = "authentik";
        type = "Opaque";
        data."k8s-tofu-bootstrap.yaml" = builtins.readFile (
          pkgs.runCommand "k8s-tofu-bootstrap.yaml.b64" { } ''
            printf '%s' ${
              lib.escapeShellArg
                # yaml
                ''
                  version: 1
                  metadata:
                    labels:
                      blueprints.goauthentik.io/instantiate: "true"
                    name: k8s-tofu-bootstrap
                  entries:
                    - model: authentik_core.user
                      id: tofu-bootstrap-user
                      state: present
                      identifiers:
                        username: k8s-tofu-bootstrap
                      attrs:
                        name: Kubernetes OpenTofu Bootstrap
                        type: service_account
                        is_active: true
                        groups:
                          - !Find [authentik_core.group, [name, "authentik Admins"]]

                    - model: authentik_core.token
                      state: present
                      identifiers:
                        identifier: k8s-tofu-bootstrap
                      attrs:
                        user: !KeyOf tofu-bootstrap-user
                        intent: api
                        expiring: false
                        key: ${builtins.toJSON authentikBootstrapToken}
                ''
            } | base64 -w0 > "$out"
          ''
        );
      };

      kubernetes.resources.secrets.authentik-bootstrap-provider-vars = {
        metadata = {
          name = "authentik-bootstrap-provider-vars";
          namespace = "authentik";
        };

        type = "Opaque";

        data = {
          authentik_url = builtins.readFile (
            pkgs.runCommand "authentik_url.b64" { } ''
              printf '%s' ${lib.escapeShellArg "http://authentik-server.authentik.svc.cluster.local"} | base64 -w0 > "$out"
            ''
          );
          authentik_token = builtins.readFile (
            pkgs.runCommand "authentik_token.b64" { } ''
              printf '%s' ${lib.escapeShellArg authentikBootstrapToken} | base64 -w0 > "$out"
            ''
          );
        };
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
            blueprints.secrets = [
              "authentik-bootstrap-blueprint"
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

      kubernetes.resources.clusterRoleBindings.bitbloxhub-cluster-admin = {
        roleRef = {
          apiGroup = "rbac.authorization.k8s.io";
          kind = "ClusterRole";
          name = "cluster-admin";
        };

        subjects = [
          {
            kind = "User";
            apiGroup = "rbac.authorization.k8s.io";
            name = "bitbloxhub@local.invalid";
          }
        ];
      };

      kubernetes.resources.resourcegraphdefinitions.authentik-user = {
        metadata.namespace = "authentik";
        spec = {
          schema = authentikUserSchema;
          resources = [
            {
              id = "terraform";
              template = {
                apiVersion = "infra.contrib.fluxcd.io/v1alpha2";
                kind = "Terraform";
                metadata = {
                  name = authentikUserTerraformName;
                  namespace = "authentik";
                  labels = {
                    "authentik.k3s-podman-testing.localhost/owner-namespace" = expr "schema.metadata.namespace";
                    "authentik.k3s-podman-testing.localhost/owner-name" = expr "schema.metadata.name";
                  };
                };
                spec = {
                  interval = "1m";
                  approvePlan = "auto";
                  path = "./tofu-modules/authentik-user";
                  sourceRef = {
                    kind = "OCIRepository";
                    name = "flux-system";
                    namespace = "flux-system";
                  };
                  varsFrom = [
                    {
                      kind = "Secret";
                      name = "authentik-bootstrap-provider-vars";
                    }
                  ];
                  vars = [
                    {
                      name = "username";
                      value = expr "schema.spec.username";
                    }
                    {
                      name = "name";
                      value = expr "schema.spec.name";
                    }
                    {
                      name = "email";
                      value = expr "schema.spec.email";
                    }
                    {
                      name = "path";
                      value = expr "schema.spec.path";
                    }
                    {
                      name = "type";
                      value = expr "schema.spec.type";
                    }
                    {
                      name = "isActive";
                      value = expr "schema.spec.isActive";
                    }
                    {
                      name = "attributes";
                      value = expr "schema.spec.attributes";
                    }
                    {
                      name = "groups";
                      value = expr "schema.spec.groups";
                    }
                    {
                      name = "roles";
                      value = expr "schema.spec.roles";
                    }
                    {
                      name = "permissionsGlobal";
                      value = expr "schema.spec.permissions.global";
                    }
                    {
                      name = "permissionsInitial";
                      value = expr "schema.spec.permissions.initial";
                    }
                  ];
                  writeOutputsToSecret = {
                    name = authentikUserTerraformName + "-outputs";
                  };
                };
              };
            }
          ];
        };
      };

      kubernetes.resources.resourcegraphdefinitions.authentik-token = {
        metadata.namespace = "authentik";
        spec = {
          schema = authentikTokenSchema;
          resources = [
            {
              id = "terraform";
              template = {
                apiVersion = "infra.contrib.fluxcd.io/v1alpha2";
                kind = "Terraform";
                metadata = {
                  name = authentikTokenTerraformName;
                  namespace = "authentik";
                  labels = {
                    "authentik.k3s-podman-testing.localhost/owner-namespace" = expr "schema.metadata.namespace";
                    "authentik.k3s-podman-testing.localhost/owner-name" = expr "schema.metadata.name";
                  };
                };
                spec = {
                  interval = "1m";
                  approvePlan = "auto";
                  path = "./tofu-modules/authentik-token";
                  sourceRef = {
                    kind = "OCIRepository";
                    name = "flux-system";
                    namespace = "flux-system";
                  };
                  varsFrom = [
                    {
                      kind = "Secret";
                      name = "authentik-bootstrap-provider-vars";
                    }
                  ];
                  vars = [
                    {
                      name = "username";
                      value = expr "schema.spec.username";
                    }
                    {
                      name = "identifier";
                      value = expr "schema.spec.identifier";
                    }
                    {
                      name = "description";
                      value = expr "schema.spec.description";
                    }
                    {
                      name = "intent";
                      value = expr "schema.spec.intent";
                    }
                    {
                      name = "expiring";
                      value = expr "schema.spec.expiring";
                    }
                    {
                      name = "expires";
                      value = expr "schema.spec.expires";
                    }
                    {
                      name = "retrieveKey";
                      value = expr "schema.spec.retrieveKey";
                    }
                  ];
                  writeOutputsToSecret = {
                    name = expr "schema.spec.outputSecret.name";
                    outputs = [
                      "authentik_token"
                      "authentik_url"
                    ];
                    annotations = {
                      "reflector.v1.k8s.emberstack.com/reflection-allowed" = "true";
                      "reflector.v1.k8s.emberstack.com/reflection-allowed-namespaces" = expr "schema.metadata.namespace";
                      "reflector.v1.k8s.emberstack.com/reflection-auto-enabled" = "true";
                      "reflector.v1.k8s.emberstack.com/reflection-auto-namespaces" = expr "schema.metadata.namespace";
                    };
                  };
                };
              };
            }
          ];
        };
      };
    };
}
