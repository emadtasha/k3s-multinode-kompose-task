#!/usr/bin/env bash
# Single script that stands up ONE k3d cluster running:
#   - Task 1: Helm-templated whoami app, routed via Traefik at /whoami
#   - Task 2: kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
#             with a custom ServiceMonitor watching a podinfo app
#   - Kubernetes Dashboard, for visual inspection of everything above
set -euo pipefail

# Run from this script's own directory regardless of where it's invoked from
cd "$(dirname "$0")"

CLUSTER_NAME="traefik-cluster"

echo "=================================================="
echo ">>> STEP 1: Cluster with Traefik (built-in on k3d)"
echo "=================================================="
if ! sudo k3d cluster list | grep -q "${CLUSTER_NAME}"; then
  sudo k3d cluster create "${CLUSTER_NAME}" --api-port 6550 -p "8081:80@loadbalancer"
else
  echo ">>> Cluster already exists, skipping creation."
fi

sudo k3d kubeconfig get "${CLUSTER_NAME}" > ~/.kube/config
chmod 600 ~/.kube/config
export KUBECONFIG=~/.kube/config

echo ">>> Verifying cluster + Traefik..."
kubectl get nodes
kubectl get pods -n kube-system | grep traefik

echo "=================================================="
echo ">>> STEP 2: Helm + whoami app (Task 1)"
echo "=================================================="
if ! command -v helm &> /dev/null; then
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

if [ ! -d my-webapp ]; then
  helm create my-webapp
fi

cp values-overrides.yaml my-webapp/values-overrides.yaml

kubectl apply -f middleware.yaml

helm upgrade --install my-webapp ./my-webapp -f my-webapp/values-overrides.yaml

echo ">>> Waiting for whoami pods..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=my-webapp --timeout=120s || true

echo "=================================================="
echo ">>> STEP 3: kube-prometheus-stack (Task 2)"
echo "=================================================="
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 2>/dev/null || true
helm repo update

kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.service.type=ClusterIP \
  --set prometheus.prometheusSpec.resources.requests.memory=256Mi \
  --set prometheus.prometheusSpec.resources.requests.cpu=100m \
  --set grafana.resources.requests.memory=128Mi \
  --set alertmanager.alertmanagerSpec.resources.requests.memory=64Mi \
  --wait --timeout 10m

echo ">>> Deploying target app (podinfo) + ServiceMonitor..."
kubectl apply -f manifests/app.yaml
kubectl apply -f manifests/servicemonitor.yaml

echo "=================================================="
echo ">>> STEP 4: Kubernetes Dashboard"
echo "=================================================="
kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml

kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: admin-user
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: admin-user
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: admin-user
  namespace: kubernetes-dashboard
EOF

kubectl wait --namespace kubernetes-dashboard --for=condition=ready pod \
  --selector=k8s-app=kubernetes-dashboard --timeout=120s || true

echo ">>> Patching Dashboard Service to NodePort 30443..."
kubectl -n kubernetes-dashboard patch svc kubernetes-dashboard \
  -p '{"spec":{"type":"NodePort","ports":[{"port":443,"targetPort":8443,"nodePort":30443}]}}'

MASTER_CONTAINER_IP=$(sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "k3d-${CLUSTER_NAME}-server-0")

echo ">>> Bridging Dashboard NodePort to host port 30443..."
sudo docker rm -f dashboard-proxy 2>/dev/null || true
sudo docker run -d --name dashboard-proxy --restart unless-stopped \
  -p 30443:30443 \
  alpine/socat tcp-listen:30443,fork,reuseaddr "tcp-connect:${MASTER_CONTAINER_IP}:30443"

echo ""
echo "=================================================="
echo ">>> DEPLOYMENT COMPLETE — SUMMARY"
echo "=================================================="
echo ""
echo "Task 1 - whoami via Traefik:"
echo "  curl http://localhost:8081/whoami"
echo ""
echo "Task 2 - Prometheus targets:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 --address 0.0.0.0 &"
echo "  Then open http://<EC2_IP>:9090 -> Status > Targets"
echo ""
echo "Grafana:"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 --address 0.0.0.0 &"
echo "  Then open http://<EC2_IP>:3000  (login: admin / prom-operator)"
echo ""
echo "Kubernetes Dashboard:"
echo "  https://<EC2_IP>:30443"
echo "  Token:"
kubectl -n kubernetes-dashboard create token admin-user --duration=168h
echo ""
echo "Remember to open Security Group ports: 8081, 9090, 3000, 30443 as needed."
