{
  flake.modules.kubenix.mimir = {
    kustomization.dependsOn = [
      {
        name = "local-storage";
      }
    ];
    kustomization.healthChecks = [
      {
        apiVersion = "helm.toolkit.fluxcd.io/v2";
        kind = "HelmRelease";
        name = "mimir-distributed";
        namespace = "mimir";
      }
      {
        apiVersion = "helm.toolkit.fluxcd.io/v2";
        kind = "HelmRelease";
        name = "versitygw";
        namespace = "mimir";
      }
    ];

    kubernetes.resources.namespaces.mimir = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.secrets.mimir-s3-credentials = {
      metadata.namespace = "mimir";
      stringData = {
        awsAccessKeyId = "mimir-versitygw-root";
        awsSecretAccessKey = "mimir-versitygw-root-secret";
      };
    };

    kubernetes.resources.helmreleases.versitygw = {
      metadata.namespace = "mimir";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "versitygw";
          namespace = "flux-system";
        };
        values = {
          image.tag = "v1.5.0";
          auth = {
            accessKey = "mimir-versitygw-root";
            secretKey = "mimir-versitygw-root-secret";
          };
          persistence = {
            enabled = true;
            create = true;
            storageClassName = "local-path";
          };
          resources = {
            requests = {
              cpu = "100m";
              memory = "512Mi";
            };
            limits = {
              cpu = "750m";
              memory = "2Gi";
            };
          };
        };
      };
    };

    kubernetes.resources.jobs.mimir-bucket-bootstrap = {
      metadata.namespace = "mimir";
      spec = {
        ttlSecondsAfterFinished = 300;
        template.spec = {
          restartPolicy = "OnFailure";
          containers = [
            {
              name = "create-buckets";
              image = "docker.io/amazon/aws-cli:2.28.17";
              command = [
                "/bin/sh"
                "-lc"
                ''
                  for bucket in mimir-alertmanager mimir-tsdb mimir-ruler; do
                    until aws --endpoint-url http://versitygw:7070 s3api head-bucket --bucket "$bucket" >/dev/null 2>&1; do
                      aws --endpoint-url http://versitygw:7070 s3api create-bucket --bucket "$bucket" >/dev/null 2>&1 || true
                      sleep 2
                    done
                  done
                ''
              ];
              env = [
                {
                  name = "AWS_ACCESS_KEY_ID";
                  valueFrom.secretKeyRef = {
                    name = "mimir-s3-credentials";
                    key = "awsAccessKeyId";
                  };
                }
                {
                  name = "AWS_SECRET_ACCESS_KEY";
                  valueFrom.secretKeyRef = {
                    name = "mimir-s3-credentials";
                    key = "awsSecretAccessKey";
                  };
                }
              ];
            }
          ];
        };
      };
    };

    kubernetes.resources.ocirepositories.mimir-distributed = {
      metadata.namespace = "mimir";
      spec = {
        interval = "10m0s";
        url = "oci://ghcr.io/grafana/helm-charts/mimir-distributed";
        ref.tag = "6.1.0-weekly.396";
      };
    };

    kubernetes.resources.helmreleases.mimir-distributed = {
      metadata.namespace = "mimir";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "mimir-distributed";
        };
        values = {
          minio.enabled = false;
          kafka.enabled = false;
          alertmanager = {
            persistentVolume.storageClass = "local-path";
            zoneAwareReplication.enabled = false;
          };
          compactor.persistentVolume.storageClass = "local-path";
          ingester = {
            replicas = 1;
            persistentVolume.storageClass = "local-path";
            zoneAwareReplication.enabled = false;
          };
          store_gateway = {
            replicas = 1;
            persistentVolume.storageClass = "local-path";
            zoneAwareReplication.enabled = false;
          };
          mimir.structuredConfig = {
            alertmanager_storage = {
              backend = "s3";
              s3 = {
                endpoint = "versitygw:7070";
                bucket_name = "mimir-alertmanager";
                access_key_id = "mimir-versitygw-root";
                secret_access_key = "mimir-versitygw-root-secret";
                insecure = true;
              };
            };
            blocks_storage = {
              backend = "s3";
              bucket_store.sync_dir = "/data/tsdb-sync";
              s3 = {
                endpoint = "versitygw:7070";
                bucket_name = "mimir-tsdb";
                access_key_id = "mimir-versitygw-root";
                secret_access_key = "mimir-versitygw-root-secret";
                insecure = true;
              };
              tsdb = {
                dir = "/data/tsdb";
                head_compaction_interval = "15m";
                wal_replay_concurrency = 3;
              };
            };
            ingest_storage.enabled = false;
            ingester.push_grpc_method_enabled = true;
            ruler_storage = {
              backend = "s3";
              s3 = {
                endpoint = "versitygw:7070";
                bucket_name = "mimir-ruler";
                access_key_id = "mimir-versitygw-root";
                secret_access_key = "mimir-versitygw-root-secret";
                insecure = true;
              };
            };
          };
        };
      };
    };
  };
}
