# vim: set ft=starlark: -*- mode: python; -*-

local_resource(
	"node",
	serve_cmd = """
		set -eu

		mkdir -p .direnv/node-state/k3s-state
		mkdir -p .direnv/node-state/kubelet-state
		mkdir -p .direnv/node-state/crio-state
		mkdir -p .direnv/node-state/cni-net.d
		mkdir -p .direnv/node-state/cni-state
		mkdir -p .direnv/node-state/calico-state
		mkdir -p .direnv/node-state/cni-bin
		mkdir -p .direnv/node-state/local-path-provisioner
		touch .direnv/kubeconfig.yaml

		exec podman run \
			--name k3s-podman-testing \
			--rm --replace \
			--privileged \
			--hostname k3s-podman-testing \
			--cgroupns=private --cgroups=enabled \
			-p 3754:6443 \
			--mount type=bind,src="$(pwd)/.direnv/node-state/k3s-state",dst=/persist/k3s-state,rw \
			--mount type=bind,src="$(pwd)/.direnv/node-state/kubelet-state",dst=/persist/kubelet-state,rw \
			--mount type=bind,src="$(pwd)/.direnv/node-state/crio-state",dst=/persist/crio-state,rw \
			--mount type=bind,src="$(pwd)/.direnv/node-state/cni-net.d",dst=/persist/cni-net.d,rw \
			--mount type=bind,src="$(pwd)/.direnv/node-state/cni-state",dst=/persist/cni-state,rw \
			--mount type=bind,src="$(pwd)/.direnv/node-state/calico-state",dst=/persist/calico-state,rw \
			--mount type=bind,src="$(pwd)/.direnv/node-state/cni-bin",dst=/persist/cni-bin,rw \
			--mount type=bind,src="$(pwd)/.direnv/node-state/local-path-provisioner",dst=/persist/local-path-provisioner,rw \
			--mount type=bind,src="$(pwd)/.direnv/kubeconfig.yaml",dst=/persist/kubeconfig.yaml,rw \
			nix:0$(nix build --print-out-paths --log-format raw ".#image-singleNode")
	""",
	readiness_probe = probe(
		initial_delay_secs = 1,
		timeout_secs = 2,
		period_secs = 2,
		exec = exec_action([
			"sh",
			"-lc",
			"""
				podman inspect -f '{{.State.Running}}' k3s-podman-testing | grep -q true &&
				test -s "$(pwd)/.direnv/kubeconfig.yaml" &&
				grep -q 'https://127.0.0.1:3754' "$(pwd)/.direnv/kubeconfig.yaml" &&
				KUBECONFIG="$(pwd)/.direnv/kubeconfig.yaml" kubectl --request-timeout=1s get --raw=/readyz >/dev/null 2>&1
			""",
		]),
	),
	trigger_mode = TRIGGER_MODE_MANUAL,
)

local_resource(
	"bootstrap",
	cmd = """
		if KUBECONFIG="$(pwd)/.direnv/kubeconfig.yaml" kubectl get -n flux-system fluxinstance/flux >/dev/null 2>&1; then
			echo 'Flux already bootstrapped; skipping bootstrap'
		else
			KUBECONFIG="$(pwd)/.direnv/kubeconfig.yaml" just bootstrap
		fi
	""",
	resource_deps = ["node"],
)

local_resource(
	"push-and-reconcile",
	cmd = "KUBECONFIG=\"$(pwd)/.direnv/kubeconfig.yaml\" just push-flux && KUBECONFIG=\"$(pwd)/.direnv/kubeconfig.yaml\" just reconcile-flux",
	resource_deps = ["bootstrap"],
	trigger_mode = TRIGGER_MODE_MANUAL,
	auto_init = False,
)

local_resource(
	name = "gateway-port-forward",
	cmd = "true",
	serve_cmd = """
		set -u

		NS=gateway-system
		GW=design
		LOCAL_PORT=4962
		REMOTE_PORT=80

		SELECTOR="gateway.envoyproxy.io/owning-gateway-name=${GW},gateway.envoyproxy.io/owning-gateway-namespace=${NS}"

		while true; do
			echo "gateway-port-forward: starting/restarting wait loop..."

			echo "waiting for Kubernetes API / namespace ${NS}..."
			until kubectl get ns "$NS" >/dev/null 2>&1; do
				sleep 2
			done

			echo "waiting for Gateway ${NS}/${GW} to exist..."
			until kubectl -n "$NS" get gateways.gateway.networking.k8s.io "$GW" >/dev/null 2>&1; do
				kubectl get gateways.gateway.networking.k8s.io -A || true
				sleep 2
			done

			echo "waiting for generated Envoy Service..."
			SVC=""
			until [ -n "$SVC" ]; do
				SVC="$(
					kubectl -n "$NS" get svc \\
						-l "$SELECTOR" \\
						-o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
				)"

				if [ -z "$SVC" ]; then
					echo "Service not found yet for selector: $SELECTOR"
					sleep 2
				fi
			done

			echo "found Service: svc/${SVC}"

			echo "waiting for Envoy proxy pod to exist..."
			until kubectl -n "$NS" get pod -l "$SELECTOR" -o name 2>/dev/null | grep -q .; do
				sleep 2
			done

			echo "waiting for Envoy proxy pod Ready=True..."
			if ! kubectl -n "$NS" wait pod \\
				-l "$SELECTOR" \\
				--for=condition=Ready \\
				--timeout=300s; then
				echo "pod did not become Ready; retrying..."
				sleep 2
				continue
			fi

			echo "waiting for endpoints on svc/${SVC}..."
			until kubectl -n "$NS" get endpoints "$SVC" \\
				-o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null | grep -q .; do
				sleep 2
			done

			echo "port-forwarding svc/${SVC}: ${LOCAL_PORT}:${REMOTE_PORT}"
			kubectl -n "$NS" port-forward "svc/${SVC}" "${LOCAL_PORT}:${REMOTE_PORT}" 2>&1 \
				| grep --line-buffered -v "Handling connection for ${LOCAL_PORT}"

			code="$?"
			echo "port-forward exited with code ${code}; restarting in 2s..."
			sleep 2
		done
	""",
	readiness_probe = probe(
		exec = exec_action([
			"sh",
			"-c",
			"curl -fsS -H 'Host: grafana.k3s-podman-testing.localhost' http://127.0.0.1:4962/ >/dev/null",
		]),
		initial_delay_secs = 1,
		period_secs = 2,
		timeout_secs = 1,
		failure_threshold = 3,
		success_threshold = 1,
	),
	allow_parallel = True,
	auto_init = True,
	links = [
		"http://grafana.k3s-podman-testing.localhost:4962/",
	],
)
