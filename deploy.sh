#!/usr/bin/env bash
# Sets up a k3d cluster with NGINX Ingress and deploys the resilient app stack.
# Designed for Ubuntu. Safe to re-run — skips steps already done.
set -euo pipefail

CLUSTER_NAME="resilient-app"

echo ">>> Checking prerequisites..."

if ! command -v docker &> /dev/null; then
  echo ">>> Installing Docker..."
  sudo apt-get update -y
  sudo apt-get install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  sudo chmod a+r /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt-get update -y
  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Ensure current user can run Docker without sudo
if command -v docker &> /dev/null; then
  if ! id -nG "$USER" | grep -qw docker; then
    echo ">>> Adding $USER to the docker group to allow k3d to run without sudo..."
    sudo usermod -aG docker "$USER" || true
    echo ">>> Added $USER to docker group. You may need to log out and back in for this to take effect." 
  fi
fi

if ! command -v k3d &> /dev/null; then
  echo ">>> Installing k3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi

if ! command -v kubectl &> /dev/null; then
  echo ">>> Installing kubectl..."
  curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
  chmod +x kubectl
  sudo mv kubectl /usr/local/bin/kubectl
fi

echo ">>> Ensuring cluster exists..."
if ! k3d cluster list | grep -q "${CLUSTER_NAME}"; then
  k3d cluster create "${CLUSTER_NAME}" -p "80:80@loadbalancer" -p "443:443@loadbalancer"
else
  echo ">>> Cluster already exists, skipping creation."
fi

echo ">>> Installing NGINX Ingress Controller..."
k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-merge-default
export KUBECONFIG=~/.kube/config

# Verify kubectl can reach the cluster
echo ">>> Verifying cluster access with 'kubectl get nodes'..."
if ! kubectl get nodes --no-headers -o custom-columns=":metadata.name" | grep -q .; then
  echo ">>> Error: kubectl cannot see any nodes. Aborting." >&2
  kubectl cluster-info || true
  exit 1
fi

kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/cloud/deploy.yaml || true

echo ">>> Waiting for Ingress Controller to be ready..."
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=180s || true

echo ">>> Patching ingress-nginx Service to LoadBalancer (k3d compatibility)..."
kubectl patch svc ingress-nginx-controller -n ingress-nginx \
  -p '{"spec": {"type": "LoadBalancer"}}' || true

echo ">>> Applying application manifests..."
kubectl apply -f configmap.yaml
kubectl apply -f secret.yaml
kubectl apply -f web-deployment.yaml
kubectl apply -f web-service.yaml
kubectl apply -f web-ingress.yaml

echo ">>> Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=web --timeout=120s || true

echo ">>> Deployment complete. Current state:"
kubectl get pods -o wide
kubectl get svc
kubectl get ingress

echo ">>> Test with: curl -H \"Host: myapp.local\" http://localhost"
