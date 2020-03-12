#!/bin/bash

version=v1.15.7
clusters=$(kind get clusters)
if [[ "${clusters}" == *kind* ]]; then
	if [ "$1" != "--force" ]; then
		echo "Cluster already active: ${clusters}"
	else
		kind delete cluster		
		kind create cluster --image=kindest/node:${version}
	fi
else
	kind create cluster --image=kindest/node:${version}
fi

echo Setting up kubeconfig
mkdir -p ~/.kube
kind get kubeconfig --internal > ~/.kube/kind-config-internal
kind get kubeconfig > ~/.kube/kind
KUBECONFIG=~/.kube/kind:~/.kube/config kubectl config view --merge --flatten > .config.yaml
mv .config.yaml ~/.kube/config
