# Combined Stack: Helm/Traefik + Prometheus Operator + Dashboard

One k3d cluster (`traefik-cluster`) running everything:
- **Task 1**: Helm-templated `traefik/whoami` app, routed at `/whoami` via
  Traefik with a prefix-stripping Middleware.
- **Task 2**: `kube-prometheus-stack` (Prometheus, Grafana, Alertmanager)
  with a custom `ServiceMonitor` auto-discovering a labeled `podinfo` app.
- **Kubernetes Dashboard**, for visually inspecting all of the above.

## One-command deploy
```bash
chmod +x deploy-all.sh
./deploy-all.sh
```

## Accessing everything

**Task 1 — whoami via Traefik:**
```bash
curl http://localhost:8081/whoami
```

**Task 2 — Prometheus targets:**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090 --address 0.0.0.0 &
```
Open `http://<EC2_IP>:9090` → Status > Targets → confirm
`metrics-emitter` shows UP.

**Grafana:**
```bash
kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 --address 0.0.0.0 &
```
Open `http://<EC2_IP>:3000` — login `admin` / `prom-operator`.

**Kubernetes Dashboard:**
```
https://<EC2_IP>:30443
```
Token printed at the end of `deploy-all.sh`, or regenerate:
```bash
kubectl -n kubernetes-dashboard create token admin-user --duration=168h
```

## Security Group ports to open
8081 (whoami), 9090 (Prometheus), 3000 (Grafana), 30443 (Dashboard)

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `/whoami` 404s | Middleware annotation string wrong | Must be exactly `default-strip-whoami-prefix@kubernetescrd` |
| kube-prometheus-stack pods Pending | Not enough CPU/RAM | `kubectl describe pod -n monitoring <pod>` |
| ServiceMonitor target missing | `release` label mismatch | Confirm `helm list -n monitoring` release name matches label |
| Dashboard "not secure" warning | Self-signed cert (expected) | Click through |

## Teardown
```bash
sudo docker rm -f dashboard-proxy
helm uninstall my-webapp
helm uninstall kube-prometheus-stack -n monitoring
sudo k3d cluster delete traefik-cluster
```
