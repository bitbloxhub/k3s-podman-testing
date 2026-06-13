{
  flake.modules.kubenix.versitygw = {
    kubernetes.resources.ocirepositories.versitygw = {
      metadata.namespace = "flux-system";
      spec = {
        interval = "10m0s";
        url = "oci://ghcr.io/versity/versitygw/charts/versitygw";
        ref.tag = "0.3.1";
      };
    };
  };
}
