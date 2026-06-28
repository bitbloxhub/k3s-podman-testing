set shell := ["nu", "-c"]

dev:
	tilt up

bootstrap:
	#!/usr/bin/env nu
	let out = (nix build --no-link --print-out-paths --log-format raw .#flux | str trim)
	let registry_bootstrap = (nix build --no-link --print-out-paths --log-format raw .#registry-bootstrap | str trim)
	
	kubectl apply -f $"($out)/calico/calico.yaml"
	kubectl rollout status -n kube-system daemonset/calico-node --timeout=180s
	kubectl rollout status -n kube-system deployment/calico-kube-controllers --timeout=180s
	
	kubectl apply -f $registry_bootstrap
	kubectl rollout status -n registry deployment/registry --timeout=180s
	
	kubectl apply -f $"($out)/flux-operator/flux-operator.yaml"
	kubectl rollout status -n flux-system deployment/flux-operator --timeout=180s
	
	kubectl apply -f $"($out)/flux-setup/flux-setup.yaml"
	kubectl wait -n flux-system --for=create deployment/source-controller --timeout=300s
	kubectl wait -n flux-system --for=create deployment/kustomize-controller --timeout=300s
	kubectl rollout status -n flux-system deployment/source-controller --timeout=180s
	kubectl rollout status -n flux-system deployment/kustomize-controller --timeout=180s
	
	just push-flux
	
	kubectl wait -n local-storage --for=create helmrelease/local-path-provisioner --timeout=300s
	kubectl wait -n local-storage helmrelease/local-path-provisioner --for=condition=Ready --timeout=300s
	kubectl delete deployment -n registry registry --ignore-not-found
	kubectl wait -n registry --for=delete deployment/registry --timeout=180s
	kubectl apply -f $"($out)/registry/registry.yaml"
	kubectl rollout status -n registry deployment/registry --timeout=180s
	
	just push-flux
	kubectl wait -n flux-system fluxinstance/flux --for=condition=Ready --timeout=300s
	
	just reconcile-flux

push-flux:
	#!/usr/bin/env nu
	let out = (nix build --no-link --print-out-paths --log-format raw .#flux | str trim)
	let tmp = (mktemp -d | str trim)
	let port_forward = (job spawn --description registry-port-forward {
		kubectl port-forward -n registry svc/registry 5000:5000
	})
	sleep 2sec
	
	^cp -r --no-preserve=mode,ownership ...((glob $"($out)/*")) $tmp
	flux push artifact oci://localhost:5000/k3s-podman-testing-flux:latest --path $tmp --source=local --revision=latest
	job kill $port_forward
	
	print $"Pushed from ($tmp)"

reconcile-flux:
	#!/usr/bin/env nu
	kubectl wait -n flux-system fluxinstance/flux --for=condition=Ready --timeout=300s
	
	flux reconcile kustomization flux-system -n flux-system --with-source
	kubectl wait -n flux-system ocirepository/flux-system --for=condition=Ready --timeout=300s
