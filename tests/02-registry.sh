#!/bin/bash

CURR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
[ -d "$CURR_DIR" ] || { echo "FATAL: no current dir (maybe running in zsh?)";  exit 1; }

# shellcheck source=./common.sh
source "$CURR_DIR/common.sh"

#########################################################################################

REGISTRY="registry.localhost:5000"
TEST_IMAGE="nginx:latest"

FIXTURES_DIR=$CURR_DIR/fixtures

# a dummy registries.yaml file
REGISTRIES_YAML=$FIXTURES_DIR/01-registries-empty.yaml


#########################################################################################

info "Creating two clusters (with a registry)..."
$EXE create --wait 60 --name "c1" --api-port 6443 --enable-registry || failed "could not create cluster c1"
$EXE create --wait 60 --name "c2" --api-port 6444 --enable-registry --registries-file "$REGISTRIES_YAML" || failed "could not create cluster c2"

check_k3d_clusters "c1" "c2" || failed "error checking cluster"
dump_registries_yaml_in "c1" "c2"

check_registry || abort "local registry not available at $REGISTRY"
passed "Local registry running at $REGISTRY"

info "Deleting c1 cluster: the registry should remain..."
$EXE delete --name "c1" || failed "could not delete the cluster c1"
check_registry || abort "local registry not available at $REGISTRY after removing c1"
passed "The local registry is still running"

info "Pulling a test image..."
docker pull $TEST_IMAGE
docker tag $TEST_IMAGE $REGISTRY/$TEST_IMAGE

info "Pushing to $REGISTRY..."
docker push $REGISTRY/$TEST_IMAGE

info "Using the image in the registry in the first cluster..."
cat <<EOF | kubectl apply --kubeconfig=$($EXE get-kubeconfig --name "c2") -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-registry
  labels:
    app: test-registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test-registry
  template:
    metadata:
      labels:
        app: test-registry
    spec:
      containers:
      - name: test-registry
        image: $REGISTRY/$TEST_IMAGE
        ports:
        - containerPort: 80
EOF

kubectl --kubeconfig=$($EXE get-kubeconfig --name "c2") wait --for=condition=available --timeout=600s deployment/test-registry
[ $? -eq 0 ] || abort "deployment with local registry failed"
passed "Local registry seems to be usable"

info "Deleting c2 cluster: the registry should be removed now..."
$EXE delete --name "c2" || failed "could not delete the cluster c2"
check_registry && abort "local registry still running at $REGISTRY"
passed "The local registry has been removed"

exit 0
