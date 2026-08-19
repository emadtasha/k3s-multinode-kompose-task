# Resilient Application Deployment with Config, Ingress & Self-Healing

Deploys an NGINX-based app on a local k3d cluster with ConfigMap/Secret
injection, health probes, resource limits, a ClusterIP Service, and NGINX
Ingress routing — deployed automatically to an EC2 (Ubuntu) host via
GitHub Actions.

## Repo layout

```
manifests/
  configmap.yaml                 # web-config: APP_TITLE, APP_ENV
  secret.yaml                    # web-secret: API_KEY (base64)
  web-deployment.yaml            # 3 replicas, probes, resource limits
  web-service.yaml               # ClusterIP :80
  web-ingress.yaml               # routes myapp.local -> web-service
scripts/
  deploy.sh                      # idempotent setup script run on the EC2 host
.github/workflows/
  deploy-to-ec2.yml              # manual-trigger workflow: copy + deploy
```

## How deployment works

This repo is deployed via GitHub Actions, **manually triggered** (not on
every push) to avoid accidentally re-provisioning infrastructure on commits
that don't need it.

**Required repo secrets** (Settings → Secrets and variables → Actions):
- `HOST_IP` — public IP of the target EC2 instance
- `EC2_USER` — SSH username (`ubuntu` for this instance)
- `EC2_SSH_KEY` — private key (PEM/OpenSSH format, full contents including
  BEGIN/END lines) matching a public key already in the instance's
  `~/.ssh/authorized_keys`

**To deploy:**
1. GitHub repo → **Actions** tab → **Deploy to EC2 (k3d resilient app)** →
   **Run workflow**
2. The workflow copies this repo to `~/resilient-app-deploy` on the host,
   then runs `scripts/deploy.sh`, which:
   - Installs Docker, k3d, and kubectl if not already present (Ubuntu/apt)
   - Creates a k3d cluster named `resilient-app` with ports 80/443 mapped
     to the host (skips creation if it already exists)
   - Installs the NGINX Ingress Controller and patches its Service to
     `LoadBalancer` (required for k3d's proxy to route traffic correctly —
     the default NodePort type won't work with k3d's host port mapping)
   - Applies all manifests in `manifests/`
   - Waits for pods to be ready and prints final cluster state

## Manual deployment (without GitHub Actions)

```bash
git clone <this-repo-url>
cd <repo>
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

## Verification

```bash
kubectl get pods -o wide
kubectl get svc
kubectl get ingress
```

Test routing (from the EC2 host):
```bash
curl -H "Host: myapp.local" http://localhost
```

Test from your own machine (after adding the EC2's public IP to your
local `/etc/hosts` as `myapp.local`):
```bash
curl -H "Host: myapp.local" http://<EC2_PUBLIC_IP>
```
or add to `/etc/hosts`:
```
<EC2_PUBLIC_IP> myapp.local
```
then just visit `http://myapp.local` in a browser.

## Self-healing demo

```bash
kubectl get pods
kubectl delete pod <one-of-the-three-web-pods>
kubectl get pods -w
```
Watch the Deployment controller replace the deleted pod automatically.

## Requirements checklist

- [x] Local cluster (k3d) with Ingress Controller enabled
- [x] ConfigMap `web-config` (APP_TITLE, APP_ENV)
- [x] Secret `web-secret` (API_KEY, base64)
- [x] Env vars injected into container from both
- [x] Deployment: 3 replicas, readiness probe (5s), liveness probe (10s),
      resource requests/limits
- [x] ClusterIP Service `web-service` on port 80
- [x] Ingress routing `myapp.local` -> `web-service`
- [x] `/etc/hosts` step documented for external access

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `curl` gets empty reply / connection reset | ingress-nginx Service is NodePort, not LoadBalancer | `kubectl patch svc ingress-nginx-controller -n ingress-nginx -p '{"spec":{"type":"LoadBalancer"}}'` (deploy.sh does this automatically) |
| Pods stuck Pending | Cluster resources exhausted or port conflict with another running cluster on the same host | `k3d cluster list`, `docker ps` to check for competing clusters |
| SSH step in workflow fails: "no key found" | `EC2_SSH_KEY` secret is empty/malformed | Re-copy full private key contents including BEGIN/END lines into the secret |
