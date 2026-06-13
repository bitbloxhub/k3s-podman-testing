{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      kubenix.crds = [
        (pkgs.fetchurl {
          url = "https://github.com/cloudnative-pg/cloudnative-pg/releases/download/v1.29.1/cnpg-1.29.1.yaml";
          hash = "sha256-4MX/Qb9bAcB3W/IlkpuEI9VDzSPpdC5CdP596Emc+To=";
        })
      ];
    };

  kubenix.crdAttrNamePrefixOverrides = {
    "postgresql.cnpg.io" = "cnpg";
  };

  flake.modules.kubenix.cnpg = {
    kubernetes.resources.namespaces.cnpg-system = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.ocirepositories.cloudnative-pg = {
      metadata.namespace = "cnpg-system";
      spec = {
        interval = "10m0s";
        url = "oci://ghcr.io/cloudnative-pg/charts/cloudnative-pg";
        ref.tag = "0.28.3";
        layerSelector = {
          mediaType = "application/vnd.cncf.helm.chart.content.v1.tar+gzip";
          operation = "copy";
        };
      };
    };

    kubernetes.resources.helmreleases.cloudnative-pg = {
      metadata.namespace = "cnpg-system";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "cloudnative-pg";
        };
      };
    };
  };
}
