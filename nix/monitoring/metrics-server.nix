{
  flake.modules.kubenix.metrics-server = {
    kubernetes.resources.namespaces.metrics-server = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.helmrepositories.metrics-server = {
      metadata.namespace = "metrics-server";
      spec = {
        interval = "10m0s";
        url = "https://kubernetes-sigs.github.io/metrics-server/";
      };
    };

    kubernetes.resources.helmreleases.metrics-server = {
      metadata.namespace = "metrics-server";
      spec = {
        interval = "10m0s";
        chart.spec = {
          chart = "metrics-server";
          version = "3.13.1";
          sourceRef = {
            kind = "HelmRepository";
            name = "metrics-server";
          };
        };
        values = {
          replicas = 1;

          args = [
            "--kubelet-insecure-tls"
          ];

          resources = {
            requests = {
              cpu = "50m";
              memory = "64Mi";
            };
            limits.memory = "256Mi";
          };
        };
      };
    };
  };
}
