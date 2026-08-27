# Dynamic Helm Templating & Traefik Ingress Routing

## 1. Cluster with Traefik
```bash
k3d cluster create traefik-cluster --api-port 6550 -p "8081:80@loadbalancer"
kubectl get pods -n kube-system | grep traefik
```

## 2. Helm + chart scaffold
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm create my-webapp
```

## 3. values.yaml changes
Edit `my-webapp/values.yaml` (see `values-overrides.yaml` for the exact block):
```yaml
replicaCount: 2
image:
  repository: traefik/whoami
  tag: "latest"
service:
  type: ClusterIP
  port: 80
ingress:
  enabled: true
  className: "traefik"
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: default-strip-whoami-prefix@kubernetescrd
  hosts:
    - host: ""
      paths:
        - path: /whoami
          pathType: Prefix
```

## 4. Middleware (strips /whoami prefix)
```bash
kubectl apply -f middleware.yaml
```

## 5. Deploy
```bash
helm install my-webapp ./my-webapp
```

## 6. Verify
```bash
curl http://localhost:8081/whoami
```
Should return whoami output, not a 404.

## 7. Kubernetes Dashboard (required)
```bash
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

kubectl -n kubernetes-dashboard create token admin-user --duration=168h
```
Expose via NodePort + socat bridge (same pattern as before) or `kubectl proxy` if only accessing from the host itself. See prior task's approach for the full external-access chain (NodePort patch -> socat -> Security Group rule).

## Troubleshooting
| Symptom | Cause | Fix |
|---|---|---|
| 404 on /whoami | Middleware annotation string wrong | Must be exactly `<namespace>-<middleware-name>@kubernetescrd` |
| Ingress has no address | Traefik not running, or className mismatch | `kubectl get pods -n kube-system \| grep traefik` |
| `no matches for kind Middleware` | Not running k3d/k3s (no Traefik CRDs) | Confirm cluster type |
