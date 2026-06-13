{
  perSystem =
    {
      pkgs,
      ...
    }:
    {
      kubenix.crds = [
        (pkgs.fetchurl {
          url = "https://github.com/grafana/alloy-operator/releases/download/alloy-operator-0.5.8/collectors.grafana.com_alloy.yaml";
          hash = "sha256-sj7vPTr4Naix3eESQGHHNKnsi5Ij+1wWKtNG3zkDhJM=";
        })
      ];
    };

  flake.modules.kubenix.alloy-operator = {
    kubernetes.resources.namespaces.alloy = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.ocirepositories.alloy-operator = {
      metadata.namespace = "alloy";
      spec = {
        interval = "10m0s";
        url = "oci://ghcr.io/grafana/helm-charts/alloy-operator";
        ref.tag = "0.5.8";
      };
    };

    kubernetes.resources.helmreleases.alloy-operator = {
      metadata.namespace = "alloy";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "alloy-operator";
        };
      };
    };
  };

  flake.modules.kubenix.alloy = {
    kubernetes.resources.alloys.alloy = {
      metadata.namespace = "alloy";
      spec.alloy = {
        enableReporting = false; # I only want telemetry *INSIDE* my cluster!
        configMap.content =
          # It's not HCL but nvim-treesitter has no alloy grammar
          let
            sharedPodLabelingRules =
              # hcl
              ''
                // Add the Kubernetes namespace as a label.
                rule {
                  action = "replace"
                  source_labels = ["__meta_kubernetes_namespace"]
                  target_label = "namespace"
                }

                // Add the pod name as a label.
                rule {
                  action = "replace"
                  source_labels = ["__meta_kubernetes_pod_name"]
                  target_label = "pod"
                }

                // Add the container name as a label.
                rule {
                  action = "replace"
                  source_labels = ["__meta_kubernetes_pod_container_name"]
                  target_label = "container"
                }

                // Add the node name so telemetry can be filtered by Kubernetes node.
                rule {
                  action = "replace"
                  source_labels = ["__meta_kubernetes_pod_node_name"]
                  target_label = "node"
                }

                // Copy common app.kubernetes.io labels when present.
                rule {
                  action = "replace"
                  source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_name"]
                  regex = "(.+)"
                  target_label = "app"
                  replacement = "$1"
                }

                rule {
                  action = "replace"
                  source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_instance"]
                  regex = "(.+)"
                  target_label = "app_instance"
                  replacement = "$1"
                }

                rule {
                  action = "replace"
                  source_labels = ["__meta_kubernetes_pod_label_app_kubernetes_io_component"]
                  regex = "(.+)"
                  target_label = "app_component"
                  replacement = "$1"
                }

                // Add the direct Kubernetes owner kind.
                // Deployment pods usually have workload_kind="ReplicaSet" because pods are
                // owned by ReplicaSets, and ReplicaSets are owned by Deployments.
                rule {
                  action = "replace"
                  source_labels = ["__meta_kubernetes_pod_controller_kind"]
                  target_label = "workload_kind"
                }

                // Add the direct Kubernetes owner name.
                // For Deployment pods this is usually the ReplicaSet name.
                rule {
                  action = "replace"
                  source_labels = ["__meta_kubernetes_pod_controller_name"]
                  target_label = "workload"
                }

                // Derive a clean Deployment name from a ReplicaSet owner name.
                // Example: grafana-deployment-86cfcc4dff -> grafana-deployment
                rule {
                  action = "replace"
                  source_labels = [
                    "__meta_kubernetes_pod_controller_kind",
                    "__meta_kubernetes_pod_controller_name",
                  ]
                  separator = ";"
                  regex = "ReplicaSet;(.+)-[a-z0-9]{9,10}"
                  target_label = "deployment"
                  replacement = "$1"
                }

                // Add StatefulSet name for pods directly owned by a StatefulSet.
                rule {
                  action = "replace"
                  source_labels = [
                    "__meta_kubernetes_pod_controller_kind",
                    "__meta_kubernetes_pod_controller_name",
                  ]
                  separator = ";"
                  regex = "StatefulSet;(.+)"
                  target_label = "statefulset"
                  replacement = "$1"
                }

                // Add DaemonSet name for pods directly owned by a DaemonSet.
                rule {
                  action = "replace"
                  source_labels = [
                    "__meta_kubernetes_pod_controller_kind",
                    "__meta_kubernetes_pod_controller_name",
                  ]
                  separator = ";"
                  regex = "DaemonSet;(.+)"
                  target_label = "daemonset"
                  replacement = "$1"
                }

                // Add Kubernetes Job name for pods directly owned by a Job.
                // Use k8s_job instead of job because Loki/Prometheus commonly use job as a
                // generic scrape/application grouping label.
                rule {
                  action = "replace"
                  source_labels = [
                    "__meta_kubernetes_pod_controller_kind",
                    "__meta_kubernetes_pod_controller_name",
                  ]
                  separator = ";"
                  regex = "Job;(.+)"
                  target_label = "k8s_job"
                  replacement = "$1"
                }

                // Default job label for bare pods or pods without a controller.
                // Example: grafana/grafana-deployment-86cfcc4dff-kmw4n
                rule {
                  action = "replace"
                  source_labels = ["__meta_kubernetes_namespace", "__meta_kubernetes_pod_name"]
                  separator = "/"
                  regex = "(.+)/(.+)"
                  target_label = "job"
                  replacement = "$1/$2"
                }

                // Override job for Deployment-owned pods with namespace/deployment.
                // Example: grafana/grafana-deployment
                rule {
                  action = "replace"
                  source_labels = [
                    "__meta_kubernetes_namespace",
                    "__meta_kubernetes_pod_controller_kind",
                    "__meta_kubernetes_pod_controller_name",
                  ]
                  separator = ";"
                  regex = "(.+);ReplicaSet;(.+)-[a-z0-9]{9,10}"
                  target_label = "job"
                  replacement = "$1/$2"
                }

                // Override job for StatefulSet, DaemonSet, and Kubernetes Job pods with
                // namespace/controller-name.
                // Examples: mimir/mimir-ingester, alloy/alloy, default/example-job
                rule {
                  action = "replace"
                  source_labels = [
                    "__meta_kubernetes_namespace",
                    "__meta_kubernetes_pod_controller_kind",
                    "__meta_kubernetes_pod_controller_name",
                  ]
                  separator = ";"
                  regex = "(.+);(StatefulSet|DaemonSet|Job);(.+)"
                  target_label = "job"
                  replacement = "$1/$3"
                }
              '';
          in
          # hcl
          ''
            logging {
              level = "info"
              format = "logfmt"
            }

            discovery.kubernetes "pods" {
              role = "pod"
            }

            discovery.kubernetes "nodes" {
              role = "node"
            }

            /// Prometheus
            discovery.relabel "pods" {
              targets = discovery.kubernetes.pods.targets

              // Only scrape running pods.
              rule {
                action = "keep"
                source_labels = ["__meta_kubernetes_pod_phase"]
                regex = "Running"
              }

              // Only scrape pods that explicitly opt in.
              rule {
                action = "keep"
                source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scrape"]
                regex = "true"
              }

              // Require an explicit metrics port annotation.
              rule {
                action = "keep"
                source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_port"]
                regex = "\\d+"
              }

              // Store the annotated metrics port in a temporary label.
              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_port"]
                target_label = "__tmp_prometheus_io_port"
              }

              // Keep only the discovered container port matching prometheus.io/port.
              // This prevents duplicate scrapes when a pod exposes multiple ports.
              rule {
                action = "keepequal"
                source_labels = ["__meta_kubernetes_pod_container_port_number"]
                target_label = "__tmp_prometheus_io_port"
              }

              // Optional prometheus.io/path override.
              // Defaults to /metrics when absent.
              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_path"]
                regex = "(.+)"
                target_label = "__metrics_path__"
                replacement = "$1"
              }

              // Optional prometheus.io/scheme override.
              // Defaults to http when absent.
              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_pod_annotation_prometheus_io_scheme"]
                regex = "(https?)"
                target_label = "__scheme__"
                replacement = "$1"
              }

              ${sharedPodLabelingRules}
            }

            prometheus.scrape "pods" {
              targets = discovery.relabel.pods.output
              forward_to = [prometheus.remote_write.mimir.receiver]
              scrape_interval = "10s"
            }

            discovery.relabel "nodes_metrics" {
              targets = discovery.kubernetes.nodes.targets

              rule {
                action = "replace"
                target_label = "job"
                replacement = "kubelet"
              }

              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_node_name"]
                target_label = "node"
              }

              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_node_name"]
                target_label = "instance"
              }
            }

            prometheus.scrape "nodes_metrics" {
              targets = discovery.relabel.nodes_metrics.output
              forward_to = [prometheus.remote_write.mimir.receiver]
              scheme = "https"
              bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"

              tls_config {
                ca_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
                insecure_skip_verify = true
              }

              scrape_interval = "10s"
            }

            discovery.relabel "nodes_cadvisor" {
              targets = discovery.kubernetes.nodes.targets

              rule {
                action = "replace"
                target_label = "job"
                replacement = "kubelet/cadvisor"
              }

              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_node_name"]
                target_label = "node"
              }

              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_node_name"]
                target_label = "instance"
              }

              rule {
                action = "replace"
                target_label = "__address__"
                replacement = "kubernetes.default.svc.cluster.local:443"
              }

              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_node_name"]
                regex = "(.+)"
                replacement = "/api/v1/nodes/''${1}/proxy/metrics/cadvisor"
                target_label = "__metrics_path__"
              }
            }

            prometheus.scrape "nodes_cadvisor" {
              targets = discovery.relabel.nodes_cadvisor.output
              forward_to = [prometheus.remote_write.mimir.receiver]
              scheme = "https"
              bearer_token_file = "/var/run/secrets/kubernetes.io/serviceaccount/token"

              tls_config {
                ca_file = "/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
                insecure_skip_verify = true
              }

              scrape_interval = "10s"
            }

            prometheus.remote_write "mimir" {
              endpoint {
                url = "http://mimir-distributed-gateway.mimir.svc.cluster.local/api/v1/push"
              }
            }

            /// Loki
            discovery.relabel "pod_logs" {
              targets = discovery.kubernetes.pods.targets

              // Internal labels used by loki.source.kubernetes to identify which pod logs to tail.
              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_namespace"]
                target_label = "__pod_namespace__"
              }

              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_pod_name"]
                target_label = "__pod_name__"
              }

              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_pod_container_name"]
                target_label = "__pod_container_name__"
              }

              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_pod_uid"]
                target_label = "__pod_uid__"
              }

              // Add the pod phase. Keeping this helps find completed Job logs with
              // pod_phase="Succeeded" or failed pods with pod_phase="Failed".
              rule {
                action = "replace"
                source_labels = ["__meta_kubernetes_pod_phase"]
                target_label = "pod_phase"
              }

              ${sharedPodLabelingRules}
            }

            loki.source.kubernetes "pods" {
              targets = discovery.relabel.pod_logs.output
              forward_to = [loki.write.endpoint.receiver]
            }

            loki.write "endpoint" {
              endpoint {
                url = "http://loki-gateway.loki.svc.cluster.local:80/loki/api/v1/push"
                tenant_id = "local"
              }
            }
          '';
      };
    };
  };
}
