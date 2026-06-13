{
  flake.modules.kubenix.radar = {
    kubernetes.resources.namespaces.radar = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.helmrepositories.radar = {
      metadata.namespace = "radar";
      spec = {
        interval = "10m0s";
        url = "https://skyhook-io.github.io/helm-charts/";
      };
    };

    kubernetes.resources.helmreleases.radar = {
      metadata.namespace = "radar";
      spec = {
        interval = "10m0s";
        chart.spec = {
          chart = "radar";
          version = "1.7.6";
          sourceRef = {
            kind = "HelmRepository";
            name = "radar";
          };
        };
      };
    };

    kubernetes.resources.httproutes.radar = {
      metadata.namespace = "radar";
      spec = {
        parentRefs = [
          {
            name = "design";
            namespace = "gateway-system";
          }
        ];
        hostnames = [
          "radar.k3s-podman-testing.localhost"
        ];
        rules = [
          {
            backendRefs = [
              {
                kind = "Service";
                name = "radar";
                port = 9280;
              }
            ];
          }
        ];
      };
    };
  };
}
