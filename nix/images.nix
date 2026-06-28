{
  flake-file.inputs = {
    nix-snapshotter = {
      url = "github:pdtpartners/nix-snapshotter";
      inputs.nixpkgs.follows = "nixpkgs";
      # inputs.globset.follows = "globset";
      inputs.flake-parts.follows = "flake-parts";
      inputs.flake-compat.follows = "";
    };
    nix-storage-plugin = {
      url = "github:bitbloxhub/nix-storage-plugin";
      inputs.crate2nix.follows = "";
      inputs.flake-file.follows = "flake-file";
      inputs.flake-parts.follows = "flake-parts";
      inputs.flint.follows = "flint";
      inputs.hegel.follows = "";
      inputs.import-tree.follows = "import-tree";
      inputs.make-shell.follows = "make-shell";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.treefmt-nix.follows = "treefmt-nix";
    };
  };

  perSystem =
    {
      pkgs,
      inputs',
      ...
    }:
    let
      cri-o-unwrapped = inputs'.nix-storage-plugin.packages.cri-o-unwrapped.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [
          pkgs.python3
        ];

        postPatch = (old.postPatch or "") + ''
          python3 - <<'PY'
          from pathlib import Path
          import sys

          path = Path("server/container_create.go")
          src = path.read_text()

          needle = """\tif os.Getenv(rootlessEnvName) != "" {
          \t\tmakeOCIConfigurationRootless(specgen)
          \t}
          """

          replacement = """\tif os.Getenv(rootlessEnvName) != "" {
          \t\tcgroupsPath := ""
          \t\tif specgen.Config.Linux != nil {
          \t\t\tcgroupsPath = specgen.Config.Linux.CgroupsPath
          \t\t}

          \t\tmakeOCIConfigurationRootless(specgen)

          \t\tif cgroupsPath != "" {
          \t\t\tspecgen.SetLinuxCgroupsPath(cgroupsPath)
          \t\t}
          \t}
          """

          count = src.count(needle)
          if count != 1:
            print(f"expected exactly one rootless config block, found {count}", file=sys.stderr)
            sys.exit(1)

          src = src.replace(needle, replacement, 1)
          path.write_text(src)
          PY

          gofmt -w server/container_create.go

          echo "== rootless cgroupsPath preserve patch =="
          grep -n -A18 -B4 'cgroupsPath :=' server/container_create.go
        '';
      });

      cri-o = inputs'.nix-storage-plugin.packages.cri-o.override {
        inherit cri-o-unwrapped;
      };
    in
    {
      packages.cri-o = cri-o;
      packages.image-singleNode = inputs'.nix-snapshotter.packages.nix-snapshotter.buildImage {
        name = "k3s-single-node-minimal";
        resolvedByNix = true;
        config = {
          entrypoint = [
            "/bin/start-finit"
          ];
        };
        copyToRoot = [
          (pkgs.buildEnv {
            name = "container-toolbox";
            paths = [
              pkgs.coreutils
              pkgs.gitMinimal
              pkgs.zsh
              pkgs.finit
              pkgs.cri-tools
              pkgs.k3s
              pkgs.cacert
              pkgs.conmon-rs
              pkgs.procps
              pkgs.ripgrep
              pkgs.gnused
              pkgs.findutils
              pkgs.gnugrep
              pkgs.gawk
              pkgs.bashInteractive
              pkgs.util-linux
              pkgs.psmisc
              pkgs.iproute2
              pkgs.iputils
              pkgs.curl
              pkgs.jq
              pkgs.fd
              pkgs.less
              pkgs.which
              pkgs.file
              pkgs.nftables
              pkgs.iptables
              pkgs.ipset
              pkgs.nftables
              pkgs.fuse3
            ];
            ignoreCollisions = true;
          })
          (pkgs.runCommandLocal "k3s-single-node-minimal-root" { } ''
            mkdir -p "$out"/{etc,run,var,tmp,root,bin,opt/cni/bin,persist}
            mkdir -p "$out/etc"/{finit.d,tmpfiles.d,crio,cni/net.d,containers/registries.conf.d,rancher/k3s}
            mkdir -p "$out/var"/{lib,log,empty}
            mkdir -p "$out/persist"/{k3s-state,kubelet-state,crio-state,cni-net.d,cni-state,calico-state,cni-bin,local-path-provisioner}
            : > "$out/persist/kubeconfig.yaml"

            cat > "$out/etc/fstab" <<'EOF'
            EOF

            : > "$out/etc/hostname"
            : > "$out/etc/hosts"
            : > "$out/etc/resolv.conf"

            cat > "$out/run/.containerenv" <<'EOF'
            EOF

            cat > "$out/etc/passwd" <<'EOF'
            root:x:0:0:root:/root:/bin/sh
            nobody:x:65534:65534:nobody:/var/empty:/sbin/nologin
            EOF

            cat > "$out/etc/group" <<'EOF'
            root:x:0:
            nogroup:x:65534:
            EOF

            cat > "$out/etc/shadow" <<'EOF'
            root:*:19000:0:99999:7:::
            nobody:*:19000:0:99999:7:::
            EOF

            cat > "$out/etc/finit.conf" <<'EOF'
            # /etc/finit.d/*.conf is auto-loaded by Finit
            log size:10M count:3
            EOF

            cat > "$out/etc/finit.d/base.conf" <<'EOF'
            # keep include glob non-empty
            EOF

            cat > "$out/bin/start-nix-storage-plugin-als" <<'EOF'
            #!/bin/sh
            exec ${inputs'.nix-storage-plugin.packages.default}/bin/nix-storage-plugin mount-store --mount-path /run/nix-storage-plugin/layer-store
            EOF
            chmod +x "$out/bin/start-nix-storage-plugin-als"

            cat > "$out/etc/finit.d/nix-storage-plugin-als.conf" <<'EOF'
            service [2345] name:nix-storage-plugin-als log:/var/log/nix-storage-plugin-als.log respawn /bin/start-nix-storage-plugin-als -- nix-storage-plugin ALS
            EOF

            cat > "$out/bin/start-nix-storage-plugin-registry" <<'EOF'
            #!/bin/sh
            exec ${inputs'.nix-storage-plugin.packages.default}/bin/nix-storage-plugin serve-image --bind 127.0.0.1:45123
            EOF
            chmod +x "$out/bin/start-nix-storage-plugin-registry"

            cat > "$out/etc/finit.d/nix-storage-plugin-registry.conf" <<'EOF'
            service [2345] name:nix-storage-plugin-registry log:/var/log/nix-storage-plugin-registry.log respawn /bin/start-nix-storage-plugin-registry -- nix-storage-plugin registry
            EOF

            cat > "$out/bin/start-crio" <<'EOF'
            #!/bin/sh
            for i in $(seq 1 60); do
              mountpoint -q /run/nix-storage-plugin/layer-store && break
              sleep 1
            done
            _CRIO_ROOTLESS=1 exec ${cri-o}/bin/crio
            EOF
            chmod +x "$out/bin/start-crio"

            cat > "$out/etc/finit.d/crio.conf" <<'EOF'
            # Start CRI-O from nix-storage-plugin overlay packages after ALS mount is up.
            service [2345] name:crio log:/var/log/crio.log respawn /bin/start-crio -- CRI-O
            EOF

            cat > "$out/bin/start-k3s" <<'EOF'
            #!/bin/sh
            for i in $(seq 1 60); do
              [ -S /run/crio/crio.sock ] && break
              sleep 1
            done
            exec ${pkgs.k3s}/bin/k3s server --config /etc/rancher/k3s/config.yaml
            EOF
            chmod +x "$out/bin/start-k3s"

            cat > "$out/etc/finit.d/k3s.conf" <<'EOF'
            service [2345] name:k3s log:/var/log/k3s.log respawn /bin/start-k3s -- K3s
            EOF

            cat > "$out/bin/export-kubeconfig" <<'EOF'
            #!/bin/sh
            while :; do
              if [ -s /etc/rancher/k3s/k3s.yaml ]; then
                sed 's#https://127.0.0.1:6443#https://127.0.0.1:3754#' /etc/rancher/k3s/k3s.yaml > /tmp/kubeconfig.yaml &&
                cat /tmp/kubeconfig.yaml > /persist/kubeconfig.yaml
                exit 0
              fi
              sleep 1
            done
            EOF
            chmod +x "$out/bin/export-kubeconfig"

            cat > "$out/etc/finit.d/export-kubeconfig.conf" <<'EOF'
            task [2345] name:export-kubeconfig log:/var/log/export-kubeconfig.log /bin/export-kubeconfig -- Export kubeconfig
            EOF

            cat > "$out/etc/crio/crio.conf" <<'EOF'
            [crio.api]
            listen = "/run/crio/crio.sock"

            [crio.runtime]
            cgroup_manager = "cgroupfs"
            conmon_cgroup = "pod"
            infra_ctr_oom_score_adj = 1000
            drop_infra_ctr = false
            default_runtime = "crun"
            log_level = "debug"

            [crio.runtime.runtimes.crun]
            runtime_path = "${pkgs.crun}/bin/crun"
            runtime_type = "pod"
            runtime_root = "/run/crun"
            monitor_path = "${pkgs.conmon-rs}/bin/conmonrs"
            monitor_cgroup = "pod"
            # Causes calico to get messaed up when USB devices change, potentially on suspend?
            privileged_without_host_devices = true

            [crio]
            root = "/var/lib/containers/storage"
            runroot = "/run/containers/runroot"
            log_dir = "/run/crio"
            log_level = "debug"
            EOF

            cat > "$out/etc/containers/storage.conf" <<'EOF'
            [storage]
            driver = "overlay"
            graphroot = "/var/lib/containers/storage"
            runroot = "/run/containers/runroot"

            [storage.options]
            additionallayerstores = ["/run/nix-storage-plugin/layer-store:ref"]

            [storage.options.overlay]
            mount_program = "${pkgs.fuse-overlayfs}/bin/fuse-overlayfs"
            mountopt = "nodev"
            ignore_chown_errors = "true"
            EOF

            cat > "$out/etc/fuse.conf" <<'EOF'
            user_allow_other
            EOF

            cat > "$out/etc/containers/registries.conf.d/90-nix-storage-plugin.conf" <<'EOF'
            [[registry]]
            prefix = "nix:0"
            location = "127.0.0.1:45123"
            insecure = true

            [[registry]]
            prefix = "flake-github:0"
            location = "127.0.0.1:45123/flake-github"
            insecure = true

            [[registry]]
            prefix = "flake-tarball-https:0"
            location = "127.0.0.1:45123/flake-tarball-https"
            insecure = true

            [[registry]]
            prefix = "flake-tarball-http:0"
            location = "127.0.0.1:45123/flake-tarball-http"
            insecure = true

            [[registry]]
            prefix = "flake-git-https:0"
            location = "127.0.0.1:45123/flake-git-https"
            insecure = true

            [[registry]]
            prefix = "flake-git-http:0"
            location = "127.0.0.1:45123/flake-git-http"
            insecure = true

            [[registry]]
            prefix = "flake-git-ssh:0"
            location = "127.0.0.1:45123/flake-git-ssh"
            insecure = true
            EOF

            cat > "$out/etc/containers/policy.json" <<'EOF'
            {
              "default": [{ "type": "insecureAcceptAnything" }]
            }
            EOF

            cat > "$out/etc/tmpfiles.d/crio.conf" <<'EOF'
            d /run/crio 0755 root root -
            d /run/containers 0755 root root -
            d /run/containers/storage 0700 root root -
            d /run/containers/runroot 0700 root root -
            EOF

            cat > "$out/etc/crictl.yaml" <<'EOF'
            runtime-endpoint: unix:///run/crio/crio.sock
            image-endpoint: unix:///run/crio/crio.sock
            timeout: 10
            debug: true
            EOF

            cat > "$out/etc/rancher/k3s/config.yaml" <<'EOF'
            disable:
              - traefik
              - servicelb
              - local-storage
              - metrics-server

            debug: true
            vmodule: "proxier=6,nftables*=6,runner=6,config=6,servicechangetracker=6,endpointschangetracker=6"

            flannel-backend: none
            disable-network-policy: true
            disable-kube-proxy: false
            kube-proxy-arg:
              - "proxy-mode=nftables"
            system-default-registry: docker.io

            container-runtime-endpoint: unix:///run/crio/crio.sock
            image-service-endpoint: unix:///run/crio/crio.sock
            kubelet-arg:
              - feature-gates=KubeletInUserNamespace=true
              - cgroup-driver=cgroupfs
              - fail-swap-on=false
              - cgroups-per-qos=true
              - enforce-node-allocatable=
              - cgroup-root=/init
            EOF

            mkdir -p "$out/lib/modules"

            mkdir -p "$out/var/lib/containers/storage" "$out/var/lib/rancher/k3s"

            cat > "$out/bin/start-finit" <<'EOF'
            #!/bin/sh
            set -eu

            log() {
              echo "[$(date -Iseconds)] [finit-cgroupv2] $*" >&2
            }

            mount -t tmpfs -o rw,nosuid,nodev,mode=755 tmpfs /run
            mount -t tmpfs -o rw,nosuid,nodev,mode=755 tmpfs /var
            mount -t tmpfs -o rw,nosuid,nodev,mode=1777 tmpfs /tmp
            mount -t tmpfs -o rw,nosuid,nodev,mode=755 tmpfs /lib/modules

            mkdir -p /run/podman-etc
            for f in hostname hosts resolv.conf; do
              if [ -e "/etc/$f" ]; then
                cp -a "/etc/$f" "/run/podman-etc/$f"
              fi
            done

            BASE_RW_DIRS="etc opt"
            mkdir -p /run/base-ro
            for d in $BASE_RW_DIRS; do
              mkdir -p "/run/base-ro/$d"
              cp -a "/$d/." "/run/base-ro/$d/"
            done
            for d in $BASE_RW_DIRS; do
              mount -t tmpfs -o rw,nosuid,nodev,mode=755 tmpfs "/$d"
            done
            mkdir -p /run/finit/cond/pid /run/finit/cond/sys /run/finit/cond/usr /run/finit/system
            mkdir -p /run/nix-storage-plugin /run/crio
            mkdir -p /var/lib /var/log /var/empty /var/lib/cni /var/lib/crio
            for d in $BASE_RW_DIRS; do
              cp -aL "/run/base-ro/$d/." "/$d/"
            done

            mkdir -p /etc/ssl/certs
            ln -sfn ${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt /etc/ssl/certs/ca-certificates.crt
            for f in hostname hosts resolv.conf; do
              if [ -e "/run/podman-etc/$f" ]; then
                cp -a "/run/podman-etc/$f" "/etc/$f"
              fi
            done

            mkdir -p /var/lib/rancher/k3s /var/lib/kubelet /var/lib/containers/storage
            mkdir -p /var/lib/cni /var/lib/calico /etc/cni/net.d /opt/cni/bin /opt/local-path-provisioner
            mount --bind /persist/k3s-state /var/lib/rancher/k3s
            mount --bind /persist/kubelet-state /var/lib/kubelet
            mount --bind /persist/crio-state /var/lib/containers
            mount --bind /persist/cni-net.d /etc/cni/net.d
            mount --bind /persist/cni-state /var/lib/cni
            mount --bind /persist/calico-state /var/lib/calico
            mount --bind /persist/cni-bin /opt/cni/bin
            mount --bind /persist/local-path-provisioner /opt/local-path-provisioner

            ln -sfn /run /var/run
            ln -sfn /proc/mounts /etc/mtab

            CG=/sys/fs/cgroup
            if [ -f "$CG/cgroup.controllers" ]; then
              log "cgroup v2 detected"
              log "root type: $(cat "$CG/cgroup.type" 2>/dev/null || echo unknown)"
              log "root controllers: $(cat "$CG/cgroup.controllers" 2>/dev/null || true)"
              log "root subtree_control before: $(cat "$CG/cgroup.subtree_control" 2>/dev/null || true)"

              mkdir -p "$CG/init/system"

              tries=0
              while :; do
                if [ ! -s "$CG/cgroup.procs" ]; then
                  break
                fi
                while read -r pid; do
                  [ -n "$pid" ] || continue
                  echo "$pid" > "$CG/init/system/cgroup.procs" 2>/dev/null || true
                done < "$CG/cgroup.procs"

                if [ ! -s "$CG/cgroup.procs" ]; then
                  break
                fi

                tries=$((tries + 1))
                if [ "$tries" -ge 20 ]; then
                  log "warning: root cgroup still has procs: $(tr '\n' ' ' < "$CG/cgroup.procs" 2>/dev/null || true)"
                  break
                fi
                sleep 0.1
              done

              echo $$ > "$CG/init/system/cgroup.procs" 2>/dev/null || true

              ctrls="$(cat "$CG/cgroup.controllers" 2>/dev/null || true)"
              if [ -n "$ctrls" ]; then
                for c in $ctrls; do
                  echo "+$c" > "$CG/cgroup.subtree_control" 2>/dev/null || log "failed root +$c"
                done
                for c in $ctrls; do
                  echo "+$c" > "$CG/init/cgroup.subtree_control" 2>/dev/null || log "failed /init +$c"
                done
              fi

              mkdir -p "$CG/init/kubepods" || true
              log "root subtree_control after: $(cat "$CG/cgroup.subtree_control" 2>/dev/null || true)"
              log "root type after: $(cat "$CG/cgroup.type" 2>/dev/null || echo unknown)"
              log "root procs after: $(tr '\n' ' ' < "$CG/cgroup.procs" 2>/dev/null || true)"
              log "/init subtree_control after: $(cat "$CG/init/cgroup.subtree_control" 2>/dev/null || true)"
              log "/init type: $(cat "$CG/init/cgroup.type" 2>/dev/null || echo unknown)"
            fi

            exec ${pkgs.finit}/bin/finit "$@"
            EOF
            chmod +x "$out/bin/start-finit"


            # Podman/container tools expect this; avoid Podman trying to create it.
            ln -s /proc/mounts "$out/etc/mtab"

            ln -s ${inputs'.nix-storage-plugin.packages.default}/bin/nix-storage-plugin "$out/bin/nix-storage-plugin"

            # CRI-O needs pinns
            ln -s ${inputs'.nix-storage-plugin.packages.cri-o}/bin/pinns "$out/bin/pinns"
          '')
        ];
      };
    };
}
