#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

export CLUSTER=${CLUSTER-kind}
export CLUSTER_NAME=${CLUSTER_NAME-kind}
export REGISTRY=${REGISTRY-docker-daemon}
export NAMESPACE=${NAMESPACE-default}

basedir=$(realpath `dirname "${BASH_SOURCE[0]}"`/../..)
cd `dirname "${BASH_SOURCE[0]}"`

for test in simple; do
  echo "##[group]Run kustomize sample $test"
    kustomize build samples/${REGISTRY}/${test}
  echo "##[endgroup]"
done

for test in simple; do
  echo "##[group]Apply app $test"
    kubectl apply \
      -f <(kustomize build samples/${REGISTRY}/${test}) \
      --dry-run --namespace ${NAMESPACE}
  echo "##[endgroup]"
done

#echo "##[group]Skaffold"
#(cd ${basedir}; skaffold run && skaffold delete)
#echo "##[endgroup]"
