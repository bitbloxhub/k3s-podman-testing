{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      kubenix.crds = [
        (pkgs.fetchurl {
          url = "https://github.com/flux-iac/tofu-controller/releases/download/v0.16.4/tofu-controller.crds.yaml";
          hash = "sha256-vO4UurdvmZvoPglEbvfLi6I+QYyql7O15iIblLV/rNI=";
        })
      ];
    };

  flake.modules.kubenix.tofu-controller = {
    kustomization.healthChecks = [
      {
        apiVersion = "helm.toolkit.fluxcd.io/v2";
        kind = "HelmRelease";
        name = "tofu-controller";
        namespace = "flux-system";
      }
    ];

    kubernetes.resources.ocirepositories.tofu-controller = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "10m0s";
        url = "oci://ghcr.io/flux-iac/charts/tofu-controller";
        ref.tag = "0.16.4";
      };
    };

    kubernetes.resources.helmreleases.tofu-controller = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "tofu-controller";
        };

        install.crds = "CreateReplace";
        upgrade.crds = "CreateReplace";

        values = {
          allowCrossNamespaceRefs = true;
          runner.serviceAccount.allowedNamespaces = [
            "authentik"
            "grafana"
            "radar"
          ];
        };
      };
    };
  };
}
