# Usage
https://dev-tool.vngcloud.tech/grafana/d/000000023/elasticsearch2?orgId=1&refresh=1m&from=now-30m&to=now&viewPanel=49
https://dev-tool.vngcloud.tech/grafana/d/000000023/elasticsearch2?orgId=1&refresh=1m&from=now-30m&to=now&viewPanel=15
https://dev-tool.vngcloud.tech/grafana/d/000000023/elasticsearch2?orgId=1&refresh=1m&from=now-30m&to=now&viewPanel=12
https://dev-tool.vngcloud.tech/grafana/d/000000127/system-dashboard?orgId=1&refresh=1m
Add CRD
```shell
helm repo add strimzi https://strimzi.io/charts/
kubectl create namespace acive-passive
helm install acive-passive strimzi/strimzi-kafka-operator --namespace=acive-passive
```
```shell
kubectl create clusterrolebinding strimzi-cluster-operator-namespaced --clusterrole=strimzi-cluster-operator-namespaced --serviceaccount my-namespace:strimzi-cluster-operator
kubectl create clusterrolebinding strimzi-cluster-operator-entity-operator-delegation --clusterrole=strimzi-entity-operator --serviceaccount my-namespace:strimzi-cluster-operator
kubectl create clusterrolebinding strimzi-cluster-operator-topic-operator-delegation --clusterrole=strimzi-topic-operator --serviceaccount my-namespace:strimzi-cluster-operator

```
Then
```shell
kubectl apply everything.yaml
```

# Uninstall

```shell
helm -n DC1 ls

helm -n kafka uninstall acive-passive

```