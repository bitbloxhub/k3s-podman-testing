{
  flake.modules.kubenix.reloader = {
    kubernetes.resources.namespaces.reloader = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.helmrepositories.reloader = {
      metadata.namespace = "reloader";
      spec = {
        interval = "10m0s";
        url = "https://stakater.github.io/stakater-charts/";
      };
    };

    kubernetes.resources.helmreleases.reloader = {
      metadata.namespace = "reloader";
      spec = {
        interval = "10m0s";
        chart.spec = {
          chart = "reloader";
          version = "2.2.12";
          sourceRef = {
            kind = "HelmRepository";
            name = "reloader";
          };
        };
      };
    };
  };
}
