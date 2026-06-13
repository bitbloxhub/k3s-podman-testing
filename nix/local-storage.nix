{
  flake.modules.kubenix.local-storage = {
    kustomization.healthChecks = [
      {
        apiVersion = "helm.toolkit.fluxcd.io/v2";
        kind = "HelmRelease";
        name = "local-path-provisioner";
        namespace = "local-storage";
      }
    ];

    kubernetes.resources.namespaces.local-storage = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.ocirepositories.local-path-provisioner = {
      metadata.namespace = "local-storage";
      spec = {
        interval = "10m0s";
        url = "oci://ghcr.io/rancher/local-path-provisioner/charts/local-path-provisioner";
        ref.tag = "0.0.36";
      };
    };

    kubernetes.resources.helmreleases.local-path-provisioner = {
      metadata.namespace = "local-storage";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "local-path-provisioner";
        };
      };
    };
  };
}
