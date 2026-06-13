{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      kubenix.crds = [
        (pkgs.fetchurl {
          url = "https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/calico.yaml";
          hash = "sha256-vMq8YHaFVR25GPZtpySJPso+aaUMWj4wdwKbAturjTU=";
        })
      ];
    };

  flake.modules.kubenix.calico =
    {
      pkgs,
      ...
    }:
    let
      calicoSrc = pkgs.fetchurl {
        url = "https://raw.githubusercontent.com/projectcalico/calico/v3.32.0/manifests/calico.yaml";
        hash = "sha256-vMq8YHaFVR25GPZtpySJPso+aaUMWj4wdwKbAturjTU=";
      };

      calicoRootless = pkgs.runCommand "calico-rootless" { } ''
        cp ${calicoSrc} calico.yaml
        # Update calico image for https://github.com/projectcalico/calico/pull/12660
        ${pkgs.yq-go}/bin/yq eval '
          (
            .. |
            select(tag == "!!map" and has("image")) |
            .image
          ) |= sub(":v3\\.32\\.0$", ":v3.32.0-64-gfa804f609e3a")
        ' -i calico.yaml

        # Remove ebpf stuff that fails in rootless
        ${pkgs.yq-go}/bin/yq eval 'del(
          select(.kind == "DaemonSet" and .metadata.name == "calico-node" and .metadata.namespace == "kube-system")
            .spec.template.spec.initContainers[]
            | select(.name == "ebpf-bootstrap")
        )' -i calico.yaml
        ${pkgs.yq-go}/bin/yq eval 'del(
          select(.kind == "DaemonSet" and .metadata.name == "calico-node" and .metadata.namespace == "kube-system")
            .spec.template.spec.containers[]
            | select(.name == "calico-node")
            .volumeMounts[]
            | select(.name == "bpffs")
        )' -i calico.yaml
        ${pkgs.yq-go}/bin/yq eval 'del(
          select(.kind == "DaemonSet" and .metadata.name == "calico-node" and .metadata.namespace == "kube-system")
            .spec.template.spec.volumes[]
            | select(.name == "sys-fs" or .name == "bpffs" or .name == "nodeproc")
        )' -i calico.yaml

        # More ebpf disabling and nftables/cidr config
        ${pkgs.yq-go}/bin/yq eval '
          with(
            select(.kind == "DaemonSet" and .metadata.name == "calico-node");
            .spec.template.spec.initContainers |= map(select(.name != "ebpf-bootstrap" and .name != "mount-bpffs"))
            |
            (.spec.template.spec.containers[] | select(.name == "calico-node") | .volumeMounts) |= map(select(.name != "bpffs"))
            |
            .spec.template.spec.volumes |= map(select(.name != "sys-fs" and .name != "bpffs" and .name != "nodeproc"))
            |
            (
              .spec.template.spec.containers[] | select(.name == "calico-node") | .env
            ) |= (
              map(select(
              .name != "CLUSTER_TYPE" and
              .name != "FELIX_XDPENABLED" and
              .name != "FELIX_BPFKUBEPROXYIPTABLESCLEANUPENABLED" and
              .name != "FELIX_BPFCONNECTTIMELOADBALANCING" and
              .name != "FELIX_BPFHOSTNETWORKEDNATWITHOUTCTLB" and
              .name != "FELIX_IPTABLESBACKEND" and
              .name != "FELIX_NFTABLESMODE" and
              .name != "CALICO_IPV4POOL_CIDR" and
              .name != "CALICO_IPV4POOL_IPIP" and
              .name != "CALICO_IPV4POOL_VXLAN"
              ))
              + [
                {"name": "CLUSTER_TYPE", "value": "k8s"},
                {"name": "FELIX_XDPENABLED", "value": "false"},
                {"name": "FELIX_BPFKUBEPROXYIPTABLESCLEANUPENABLED", "value": "false"},
                {"name": "FELIX_BPFCONNECTTIMELOADBALANCING", "value": "Disabled"},
                {"name": "FELIX_BPFHOSTNETWORKEDNATWITHOUTCTLB", "value": "Disabled"},
                {"name": "FELIX_NFTABLESMODE", "value": "Enabled"},
                {"name": "CALICO_IPV4POOL_CIDR", "value": "10.42.0.0/16"},
                {"name": "CALICO_IPV4POOL_IPIP", "value": "Never"},
                {"name": "CALICO_IPV4POOL_VXLAN", "value": "Always"}
              ]
            )
            |
            (.spec.template.spec.containers[] | select(.name == "calico-node") | .readinessProbe.exec.command) |= map(select(. != "-bird-ready"))
            |
            (.spec.template.spec.containers[] | select(.name == "calico-node") | .livenessProbe.exec.command) |= map(select(. != "-bird-live"))
          )
          |
          with(
            select(.kind == "ConfigMap" and .metadata.name == "calico-config");
            .data.calico_backend = "vxlan"
          )
        ' -i calico.yaml

        mkdir -p $out
        ${pkgs.yq-go}/bin/yq eval-all -s 'strenv(out) + "/doc-" + $index + ".yaml"' . calico.yaml
      '';

      calicoImports = builtins.map (name: calicoRootless + "/${name}") (
        builtins.attrNames (builtins.readDir calicoRootless)
      );
    in
    {
      kubernetes.imports = calicoImports;

      kustomization.dependsOn = [ ];
      kustomization.healthChecks = [
        {
          apiVersion = "apps/v1";
          kind = "DaemonSet";
          name = "calico-node";
          namespace = "kube-system";
        }
        {
          apiVersion = "apps/v1";
          kind = "Deployment";
          name = "calico-kube-controllers";
          namespace = "kube-system";
        }
      ];
    };
}
