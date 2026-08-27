# kube-prometheus-stack + ServiceMonitor

This task sets up the Prometheus Operator stack and exposes application metrics with a ServiceMonitor.

## 1. Install the kube-prometheus-stack
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack --namespace monitoring --create-namespace
```

## 2. Deploy the sample app
Apply the app manifest in `manifests/app.yaml` to create the `app-dev` namespace and a sample `metrics-emitter` deployment.

## 3. Create the ServiceMonitor
Apply `manifests/servicemonitor.yaml` so the Prometheus Operator scrapes the app metrics endpoint.

```bash
kubectl apply -f manifests/app.yaml
kubectl apply -f manifests/servicemonitor.yaml
```

## 4. Validate
```bash
kubectl get pods -n monitoring
kubectl get servicemonitors -A
kubectl get pods -n app-dev
```

## 5. Access Grafana
```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80
```
Then open `http://localhost:3000` and log in with the default Grafana credentials from the chart values.

## Notes
- The `ServiceMonitor` resource is the key integration point between the app and the Prometheus Operator.
- The stack includes Prometheus, Alertmanager, and Grafana for monitoring and dashboards.
