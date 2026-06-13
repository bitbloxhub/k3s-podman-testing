{
  flake.modules.kubenix.loki = {
    kustomization.healthChecks = [
      # TODO: add these
    ];

    kubernetes.resources.namespaces.loki = {
      metadata.annotations.apply-order = "5";
    };

    kubernetes.resources.ocirepositories.loki = {
      metadata.namespace = "loki";
      spec = {
        interval = "10m0s";
        url = "oci://ghcr.io/grafana/helm-charts/loki";
        ref.tag = "7.0.0";
      };
    };

    kubernetes.resources.helmreleases.versitygw = {
      metadata.namespace = "loki";
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
            accessKey = "loki-versitygw-root";
            secretKey = "loki-versitygw-root-secret";
          };
          persistence = {
            enabled = true;
            create = true;
            storageClassName = "local-path";
          };
        };
      };
    };

    kubernetes.resources.jobs.loki-bucket-bootstrap = {
      metadata.namespace = "loki";
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
                  for bucket in loki-chunks loki-ruler loki-admin; do
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
                  value = "loki-versitygw-root";
                }
                {
                  name = "AWS_SECRET_ACCESS_KEY";
                  value = "loki-versitygw-root-secret";
                }
              ];
            }
          ];
        };
      };
    };

    kubernetes.resources.helmreleases.loki = {
      metadata.namespace = "loki";
      spec = {
        interval = "10m0s";
        chartRef = {
          kind = "OCIRepository";
          name = "loki";
        };
        values = {
          loki = {
            commonConfig = {
              replication_factor = 1;
            };
            schemaConfig.configs = [
              {
                from = "2024-04-01";
                store = "tsdb";
                object_store = "s3";
                schema = "v13";
                index = {
                  prefix = "loki_index_";
                  period = "24h";
                };
              }
            ];
            ingester.chunk_encoding = "snappy";
            querier.max_concurrent = 4;
            pattern_ingester.enabled = true;
            limits_config = {
              allow_structured_metadata = true;
              volume_enabled = true;
            };
            auth_enabled = false;
            storage = {
              type = "s3";
              bucketNames = {
                chunks = "loki-chunks";
                ruler = "loki-ruler";
                admin = "loki-admin";
              };
              s3 = {
                endpoint = "http://versitygw:7070";
                region = "us-east-1";
                accessKeyId = "loki-versitygw-root";
                secretAccessKey = "loki-versitygw-root-secret";
                s3ForcePathStyle = true;
                insecure = true;
              };
            };
          };
          deploymentMode = "SimpleScalable";
          backend = {
            replicas = 1;
            persistence = {
              storageClass = "local-path";
              size = "10Gi";
            };
          };
          read = {
            replicas = 1;
            persistence = {
              storageClass = "local-path";
              size = "10Gi";
            };
          };
          write = {
            replicas = 1;
            persistence = {
              storageClass = "local-path";
              size = "10Gi";
            };
          };

          memcached = {
            image = {
              repository = "docker.io/library/memcached";
              tag = "1.6.39-alpine";
            };
          };
          memcachedExporter = {
            image = {
              repository = "docker.io/prom/memcached-exporter";
              tag = "v0.15.4";
            };
          };
        };
      };
    };
  };
}
