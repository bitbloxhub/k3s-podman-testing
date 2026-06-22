{
  flake.modules.kubenix.reflector = {
    kubernetes.resources.namespaces.reflector = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.ocirepositories.reflector = {
      metadata.namespace = "reflector";
      spec = {
        interval = "10m0s";
        url = "oci://ghcr.io/emberstack/helm-charts/reflector";
        ref.tag = "10.0.50";
      };
    };

    kubernetes.resources.helmreleases.reflector = {
      metadata.namespace = "reflector";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "reflector";
        };
        values = {
          image.repository = "ghcr.io/emberstack/kubernetes-reflector";
        };
      };
    };
  };
}
