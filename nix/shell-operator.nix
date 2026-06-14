{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      packages.shell-operator = pkgs.buildGoModule rec {
        pname = "shell-operator";
        version = "1.19.5";

        src = pkgs.fetchFromGitHub {
          owner = "flant";
          repo = "shell-operator";
          rev = "v${version}";
          hash = "sha256-9S8BaisVUl6oVF4GZIuX5NqTR3SWzjvnAh+DL9QxTgQ=";
        };

        vendorHash = "sha256-Y4kUxNZYwi62MC+N4Cb2OqZ3Xtau/adQACKrRY2Fg+E=";

        postPatch = ''
          # TODO: remove once nixpkgs gets go 1.26.4
          substituteInPlace go.mod \
            --replace-fail "go 1.26.4" "go 1.26.3"
        '';

        subPackages = [
          "cmd/shell-operator"
        ];

        ldflags = [
          "-s"
          "-w"
          "-X github.com/flant/shell-operator/pkg/app.Version=v${version}"
        ];

        meta.mainProgram = "shell-operator";
      };
    };

  # Example:
  # flake.modules.kubenix.shell-operator-test =
  #   {
  #     pkgs,
  #     inputs',
  #     self',
  #     ...
  #   }:
  #   let
  #     ns = "shell-operator-test";
  #     app = "shell-operator-test";
  #     watchLabel = "shell-operator-test.bitbloxhub.local/watch";
  #
  #     hooks = pkgs.runCommand "shell-operator-test-hooks" { } ''
  #       mkdir -p "$out/hooks"
  #
  #       cat > "$out/hooks/00-configmap-smoke.sh" <<'EOF'
  #       #!${pkgs.bash}/bin/bash
  #       set -euo pipefail
  #
  #       if [[ "''${1:-}" == "--config" ]]; then
  #         cat <<'JSON'
  #       {
  #         "configVersion": "v1",
  #         "kubernetes": [
  #           {
  #             "name": "watched-configmaps",
  #             "apiVersion": "v1",
  #             "kind": "ConfigMap",
  #             "namespace": {
  #               "nameSelector": {
  #                 "matchNames": ["shell-operator-test"]
  #               }
  #             },
  #             "labelSelector": {
  #               "matchLabels": {
  #                 "shell-operator-test.bitbloxhub.local/watch": "true"
  #               }
  #             },
  #             "executeHookOnEvent": ["Added", "Modified", "Deleted"]
  #           }
  #         ]
  #       }
  #       JSON
  #         exit 0
  #       fi
  #
  #       echo "shell-operator smoke hook fired"
  #       ${pkgs.jq}/bin/jq . "$BINDING_CONTEXT_PATH"
  #       EOF
  #
  #       chmod +x "$out/hooks/00-configmap-smoke.sh"
  #     '';
  #
  #     image = inputs'.nix-snapshotter.packages.nix-snapshotter.buildImage {
  #       name = app;
  #       tag = "latest";
  #       resolvedByNix = true;
  #
  #       copyToRoot = pkgs.buildEnv {
  #         name = "${app}-root";
  #         paths = [
  #           self'.packages.shell-operator
  #           hooks
  #         ];
  #         pathsToLink = [ "/hooks" ];
  #       };
  #
  #       config = {
  #         Entrypoint = [ "${self'.packages.shell-operator}/bin/shell-operator" ];
  #         Cmd = [ "start" ];
  #         Env = [
  #           "SHELL_OPERATOR_HOOKS_DIR=/hooks"
  #           "LOG_TYPE=json"
  #           "LOG_LEVEL=info"
  #         ];
  #       };
  #     };
  #   in
  #   {
  #     kubernetes.resources.namespaces.${ns} = {
  #       metadata.annotations.apply-order = "5";
  #     };
  #
  #     kubernetes.resources.serviceAccounts.${app} = {
  #       metadata.namespace = ns;
  #     };
  #
  #     kubernetes.resources.roles.${app} = {
  #       metadata.namespace = ns;
  #       rules = [
  #         {
  #           apiGroups = [ "" ];
  #           resources = [ "configmaps" ];
  #           verbs = [
  #             "get"
  #             "list"
  #             "watch"
  #           ];
  #         }
  #       ];
  #     };
  #
  #     kubernetes.resources.roleBindings.${app} = {
  #       metadata.namespace = ns;
  #       subjects = [
  #         {
  #           kind = "ServiceAccount";
  #           name = app;
  #           namespace = ns;
  #         }
  #       ];
  #       roleRef = {
  #         apiGroup = "rbac.authorization.k8s.io";
  #         kind = "Role";
  #         name = app;
  #       };
  #     };
  #
  #     kubernetes.resources.deployments.${app} = {
  #       metadata.namespace = ns;
  #       spec = {
  #         replicas = 1;
  #         selector.matchLabels.app = app;
  #         template = {
  #           metadata.labels.app = app;
  #           spec = {
  #             serviceAccountName = app;
  #             containers = [
  #               {
  #                 name = "shell-operator";
  #                 inherit (image) image;
  #                 imagePullPolicy = "IfNotPresent";
  #                 volumeMounts = [
  #                   {
  #                     name = "tmp";
  #                     mountPath = "/tmp";
  #                   }
  #                 ];
  #               }
  #             ];
  #             volumes = [
  #               {
  #                 name = "tmp";
  #                 emptyDir = { };
  #               }
  #             ];
  #           };
  #         };
  #       };
  #     };
  #
  #     kubernetes.resources.configMaps.shell-operator-test-trigger = {
  #       metadata = {
  #         namespace = ns;
  #         labels.${watchLabel} = "true";
  #       };
  #       data.message = "hello from shell-operator-test";
  #     };
  #   };
}
