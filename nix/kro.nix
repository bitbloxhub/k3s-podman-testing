{
  self,
  ...
}:
{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      packages.kro-schema-to-crd = pkgs.buildGoModule {
        pname = "kro-schema-to-crd";
        version = "1.0.0";

        src = ../kro-schema-to-crd;

        vendorHash = "sha256-o3MSo/lAPO4yvMCXsPIospl3b8xZAjkQ31Tw47MsoOo=";
      };

      kubenix.crds = [
        (pkgs.fetchurl {
          url = "https://github.com/kro-run/kro/releases/download/v0.9.2/kro-core-install-manifests.yaml";
          hash = "sha256-1fAiWXTC+zmhPe+yKPn3+flqgJr0+frYwJmzcbZlYNs=";
        })
      ];
    };

  flake.lib.kroSchemaToCrd =
    {
      pkgs,
      name,
      schema,
      resources ? [ ],
      tool ? self.packages.${pkgs.stdenv.hostPlatform.system}.kro-schema-to-crd,
    }:
    let
      rgd = {
        apiVersion = "kro.run/v1alpha1";
        kind = "ResourceGraphDefinition";
        metadata.name = name;

        spec = {
          inherit schema resources;
        };
      };

      rgdJson = pkgs.writeText "${name}-rgd.json" (builtins.toJSON rgd);
    in
    pkgs.runCommand "${name}-typegen-crd.yaml" { } ''
      ${tool}/bin/kro-schema-to-crd generate ${rgdJson} > "$out"
    '';

  flake.modules.kubenix.kro = {
    kubernetes.resources.namespaces.kro = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.ocirepositories.kro = {
      metadata.namespace = "kro";
      spec = {
        interval = "10m0s";
        url = "oci://registry.k8s.io/kro/charts/kro";
        ref.tag = "0.9.2";
      };
    };

    kubernetes.resources.helmreleases.kro = {
      metadata.namespace = "kro";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "kro";
        };
      };
    };
  };
}
