#!/bin/bash

version=${KIND_VERSION:-v1.15.7}
clusters=$(kind get clusters)
reg_name='registry'
reg_port='5000'

# desired cluster name; default is "kind"
KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-kind}"

function start_registry() {
	# create registry container unless it already exists
	running=$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)
	if [ "${running}" != 'true' ]; then
		docker run \
			   -d --restart=always -p "${reg_port}:5000" --name "${reg_name}" \
			   registry:2
	fi
}

function create_cluster() {
	version=$1
	reg_ip=$(docker inspect -f '{{.NetworkSettings.IPAddress}}' "${reg_name}")

	# create a cluster with the local registry enabled in containerd
	cat <<EOF | kind create cluster --image=kindest/node:${version} --name "${KIND_CLUSTER_NAME}" --config=-
kind: Cluster 
apiVersion: kind.x-k8s.io/v1alpha4
containerdConfigPatches: 
- |-
  [plugins."io.containerd.grpc.v1.cri".registry.mirrors."localhost:${reg_port}"]
    endpoint = ["http://${reg_ip}:${reg_port}"]
EOF
}

start_registry

if [[ "${clusters}" == *"${KIND_CLUSTER_NAME}"* ]]; then
	if [ "$1" != "--force" ]; then
		echo "Cluster already active: ${clusters}"
	else
		kind delete cluster
		create_cluster ${version}
	fi
else
	create_cluster ${version}
fi

echo Setting up kubeconfig
mkdir -p ~/.kube
kind get kubeconfig --internal > ~/.kube/kind-config-internal
kind get kubeconfig > ~/.kube/kind
KUBECONFIG=~/.kube/kind:~/.kube/config kubectl config view --merge --flatten > .config.yaml
mv .config.yaml ~/.kube/config
