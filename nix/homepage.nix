{
  flake.modules.kubenix.homepage = {
    kubernetes.resources.namespaces.homepage = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.ocirepositories.homepage = {
      metadata.namespace = "homepage";
      spec = {
        interval = "10m0s";
        url = "oci://ghcr.io/m0nsterrr/helm-charts/homepage";
        ref.tag = "4.12.1";
      };
    };

    kubernetes.resources.configMaps.homepage-config = {
      metadata = {
        namespace = "homepage";
      };

      data = {
        "settings.yaml" = builtins.toJSON {
          title = "Launchpad";
          hideVersion = true;
          disableUpdateCheck = true;
          theme = "dark";
          color = "slate";
          headerStyle = "clean";

          background = {
            image = "https://images.robinpro.gallery/v7/_origin_/uploads/ad86b0a1b9529ba3081458224a5da460.webp?ci_seal=a61d709bc2&org_if_sml=1";
          };
        };

        "services.yaml" = builtins.toJSON [
          {
            Observability = [
              {
                Grafana = {
                  href = "http://grafana.k3s-podman-testing.localhost:4962";
                  description = "Dashboards, logs, and metrics";
                  icon = "https://raw.githubusercontent.com/grafana/grafana/main/public/img/grafana_icon.svg";
                };
              }
            ];
          }
          {
            Cluster = [
              {
                Radar = {
                  href = "http://radar.k3s-podman-testing.localhost:4962";
                  description = "Kubernetes topology";
                  icon = "https://raw.githubusercontent.com/skyhook-io/radar/main/radar-icon.svg";
                };
              }
            ];
          }
        ];
        "bookmarks.yaml" = builtins.toJSON [ ];
        "widgets.yaml" = builtins.toJSON [ ];

        "kubernetes.yaml" = builtins.toJSON { };
        "docker.yaml" = builtins.toJSON { };
        "proxmox.yaml" = builtins.toJSON { };
        "custom.css" =
          # css
          ''
            @import url("https://cdn.jsdelivr.net/npm/@catppuccin/palette@1.8.0/css/catppuccin.css");

            html,
            body,
            * {
              font-family: "Fira Code", monospace !important;
            }

            html:root {
              --bg-color: from var(--ctp-mocha-base) r g b;

              --color-theme-50: from var(--ctp-mocha-rosewater) r g b;
              --color-theme-100: from var(--ctp-mocha-text) r g b;
              --color-theme-200: from var(--ctp-mocha-subtext1) r g b;
              --color-theme-300: from var(--ctp-mocha-subtext0) r g b;
              --color-theme-400: from var(--ctp-mocha-overlay2) r g b;
              --color-theme-500: from var(--ctp-mocha-overlay1) r g b;
              --color-theme-600: from var(--ctp-mocha-overlay0) r g b;
              --color-theme-700: from var(--ctp-mocha-surface2) r g b;
              --color-theme-800: from var(--ctp-mocha-surface0) r g b;
              --color-theme-900: from var(--ctp-mocha-mantle) r g b;

              color-scheme: dark;
            }

            html,
            body,
            #__next {
              background-color: var(--ctp-mocha-base) !important;
              color: var(--ctp-mocha-text) !important;
              font-family: "Fira Code", monospace !important;
            }

            html body a,
            html body a * {
              color: var(--ctp-mocha-mauve) !important;
            }

            /* Background tint */
            html body #background {
              position: fixed !important;
              inset: 0 !important;
              filter: none !important;
            }

            html body #background * {
              filter: none !important;
            }

            html body #background::after {
              content: "";
              position: fixed;
              inset: 0;
              pointer-events: none;
              background: rgb(from var(--ctp-mocha-base) r g b / 0.90);
            }

            /* Service/card surfaces: translucent, no blur */
            #__next [class*="bg-theme-900"],
            #__next [class*="bg-white/5"],
            #__next [class*="bg-white/10"],
            #__next [class*="dark:bg-theme-900"],
            #__next [class*="dark:bg-white/5"],
            #__next [class*="dark:bg-white/10"] {
              background-color: rgb(from var(--ctp-mocha-mantle) r g b / 0.62) !important;
              backdrop-filter: none !important;
              -webkit-backdrop-filter: none !important;
            }

            /* Hover surface */
            #__next [class*="hover:bg-white"]:hover,
            #__next [class*="hover:bg-theme"]:hover,
            #__next [class*="dark:hover:bg-white"]:hover,
            #__next [class*="dark:hover:bg-theme"]:hover {
              background-color: rgb(from var(--ctp-mocha-surface0) r g b / 0.72) !important;
            }

            /* Optional subtle border */
            #__next [class*="border-theme"],
            #__next [class*="dark:border-theme"] {
              border-color: rgb(from var(--ctp-mocha-surface2) r g b / 0.25) !important;
            }
          '';

        "custom.js" = "";
      };
    };

    kubernetes.resources.helmreleases.homepage = {
      metadata.namespace = "homepage";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "homepage";
        };
        values = {
          config.allowedHosts = [
            "homepage.k3s-podman-testing.localhost:4962"
          ];
        };
        postRenderers = [
          {
            kustomize = {
              patches = [
                {
                  target = {
                    version = "v1";
                    kind = "Deployment";
                    name = "homepage";
                  };

                  patch = builtins.toJSON [
                    {
                      op = "add";
                      path = "/spec/template/metadata/annotations";
                      value = {
                        "configmap.reloader.stakater.com/reload" = "homepage-config";
                      };
                    }
                    {
                      op = "remove";
                      path = "/spec/template/spec/volumes/0/emptyDir";
                    }
                    {
                      op = "add";
                      path = "/spec/template/spec/volumes/0/configMap";
                      value = {
                        name = "homepage-config";
                      };
                    }
                  ];
                }
              ];
            };
          }
        ];
      };
    };

    kubernetes.resources.httproutes.homepage = {
      metadata.namespace = "homepage";
      spec = {
        parentRefs = [
          {
            name = "design";
            namespace = "gateway-system";
          }
        ];
        hostnames = [
          "homepage.k3s-podman-testing.localhost"
        ];
        rules = [
          {
            backendRefs = [
              {
                kind = "Service";
                name = "homepage";
                port = 80;
              }
            ];
          }
        ];
      };
    };

    kubernetes.resources.httproutes.root-redirect-homepage = {
      metadata.namespace = "homepage";
      spec = {
        parentRefs = [
          {
            name = "design";
            namespace = "gateway-system";
          }
        ];
        hostnames = [
          "k3s-podman-testing.localhost"
        ];
        rules = [
          {
            matches = [
              {
                path = {
                  type = "PathPrefix";
                  value = "/";
                };
              }
            ];
            filters = [
              {
                type = "RequestRedirect";
                requestRedirect = {
                  hostname = "homepage.k3s-podman-testing.localhost";
                  port = 4962;
                  statusCode = 302;
                };
              }
            ];
          }
        ];
      };
    };
  };
}
