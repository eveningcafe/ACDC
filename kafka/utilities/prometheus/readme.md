USAGE

```shell
curl -s https://raw.githubusercontent.com/coreos/prometheus-operator/master/bundle.yaml | sed -e '/[[:space:]]*namespace: [a-zA-Z0-9-]*$/s/namespace:[[:space:]]*[a-zA-Z0-9-]*$/namespace: my-namespace/' > prometheus-operator-deployment.yaml
```

Change my-namespace to your namespace that you want to monitor . meaning each namespace you should create one prometheus (grafana can use common, add datasource prometheus)

```shell
curl -s https://raw.githubusercontent.com/coreos/prometheus-operator/master/bundle.yaml | sed -e '/[[:space:]]*namespace: [a-zA-Z0-9-]*$/s/namespace:[[:space:]]*[a-zA-Z0-9-]*$/namespace: active-active/' > prometheus-operator-deployment.yaml
kubectl create -f prometheus-operator-deployment.yaml --namespace active-active

curl -s https://raw.githubusercontent.com/coreos/prometheus-operator/master/bundle.yaml | sed -e '/[[:space:]]*namespace: [a-zA-Z0-9-]*$/s/namespace:[[:space:]]*[a-zA-Z0-9-]*$/namespace: active-passive/' > prometheus-operator-deployment.yaml
kubectl create -f prometheus-operator-deployment.yaml --namespace active-passive

curl -s https://raw.githubusercontent.com/coreos/prometheus-operator/master/bundle.yaml | sed -e '/[[:space:]]*namespace: [a-zA-Z0-9-]*$/s/namespace:[[:space:]]*[a-zA-Z0-9-]*$/namespace: stretch-cluster/' > prometheus-operator-deployment.yaml
kubectl create -f prometheus-operator-deployment.yaml 
```

Then, sure:
```shell
kubectl apply everything.yaml 
```

Manual import dashboard json in folder grafana-dashboard to your environment 
