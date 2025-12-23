# Kafka Multi-Datacenter

**Stretch Cluster, Active/Passive, and Active/Active patterns with Strimzi**

> **Managed**: Confluent Cloud → **Self-hosted**: Apache Kafka + Strimzi (for learning)

---

## Quick Navigation

| Pattern | Description | Folder | Difficulty |
|---------|-------------|--------|------------|
| [Stretch Cluster](#1-stretch-cluster) | Single cluster across 3 DCs | [`scenario/stretch-cluster/`](./scenario/stretch-cluster/) | Easy |
| [Active/Passive](#21-activepassive) | Primary + Standby with MirrorMaker | [`scenario/active-passive/`](./scenario/active-passive/) | Medium |
| [Active/Active](#22-activeactive) | Both DCs active with aggregation | [`scenario/active-active/`](./scenario/active-active/) | Hard |

---

## Prerequisites

### Required Knowledge
- Kubernetes basics (pods, deployments, services, namespaces)
- Kafka fundamentals (topics, partitions, consumer groups)
- Helm package manager

### Required Tools
```bash
# Kubernetes cluster (or minikube/kind for local testing)
kubectl version

# Helm 3
helm version

# (Optional) Strimzi CLI
kubectl krew install strimzi
```

### Install Strimzi Operator
```bash
# Add Strimzi Helm repo
helm repo add strimzi https://strimzi.io/charts/
helm repo update

# Install operator (choose your namespace)
kubectl create namespace kafka
helm install strimzi strimzi/strimzi-kafka-operator -n kafka
```

---

## Project Structure

```
kafka/
├── scenario/
│   ├── stretch-cluster/          # Pattern 1: Single cluster across 3 DCs
│   │   ├── DC1/, DC2/, DC3/      # Per-DC configurations
│   │   ├── kafka-persistent.yaml # Main Kafka cluster definition
│   │   └── ns.yaml               # Namespace
│   │
│   ├── active-passive/           # Pattern 2: Primary + Standby
│   │   ├── DC1/                  # Primary datacenter
│   │   │   ├── kafka/            # Kafka cluster configs
│   │   │   └── logstash/         # Log shipping
│   │   ├── DC2/                  # Standby datacenter
│   │   │   ├── kafka/            # Kafka + MirrorMaker
│   │   │   └── logstash/
│   │   └── client/               # Test producer/consumer
│   │
│   └── active-active/            # Pattern 3: Both DCs active
│       ├── DC1/
│       │   ├── kafka/            # Local + Aggregate clusters
│       │   └── logstash/
│       └── DC2/
│           ├── kafka/            # Local + Aggregate clusters
│           └── logstash/
│
└── utilities/                    # Supporting tools
    ├── operator/                 # Strimzi CRDs per scenario
    ├── prometheus/               # Metrics collection
    ├── grafana/                  # Dashboards
    ├── elasticsearch/            # Log storage
    ├── kibana/                   # Log visualization
    └── operation-cmd/            # Useful commands
```

---

## Learning Path

### Recommended Order

```
1. Stretch Cluster    →  Understand Kafka rack awareness, sync replication
         ↓
2. Active/Passive     →  Learn MirrorMaker 2, async replication, failover
         ↓
3. Active/Active      →  Master complex topologies, aggregation patterns
```

---

## 1. Stretch Cluster

A single Kafka cluster spanning 3 nearby data centers.

```
┌─────────┐     ┌─────────┐     ┌─────────┐
│   DC1   │     │   DC2   │     │   DC3   │
│         │     │         │     │         │
│ Broker1 │◄───►│ Broker2 │◄───►│ Broker3 │
│   ZK1   │     │   ZK2   │     │   ZK3   │
└─────────┘     └─────────┘     └─────────┘
     │               │               │
     └───────────────┴───────────────┘
              Sync Replication
```

### Requirements
- 3 nearby DCs with **low latency (<100ms)** and stable network
- At least 1 ZooKeeper + 1 Broker per DC
- Configure each DC as a "rack" for rack awareness

### Quick Start
```bash
cd scenario/stretch-cluster/

# 1. Create namespace
kubectl apply -f ns.yaml

# 2. Deploy Kafka cluster
kubectl apply -f kafka-persistent.yaml

# 3. (Optional) Add monitoring
kubectl apply -f kafka-metrics-configmap.yaml
kubectl apply -f strimzi-pod-monitor.yaml
```

### Key Files
| File | Purpose |
|------|---------|
| `kafka-persistent.yaml` | Main Kafka cluster with rack awareness |
| `kafka-metrics-configmap.yaml` | JMX metrics exporter config |

| Pros | Cons |
|------|------|
| Easy setup | Requires 3 nearby DCs |
| Auto failover | Higher latency |
| Zero data loss (RPO=0) | Costly infrastructure |

---

## 2. Asynchronous Replication

Uses **MirrorMaker 2** to sync between separate clusters.

---

### 2.1 Active/Passive

Primary cluster handles all traffic. Standby receives async replicated data.

```
┌─────────────────┐                    ┌─────────────────┐
│      DC1        │                    │      DC2        │
│    (Active)     │   MirrorMaker 2    │   (Passive)     │
│                 │ =================> │                 │
│  ┌───────────┐  │    async           │  ┌───────────┐  │
│  │   Kafka   │  │   replicate        │  │   Kafka   │  │
│  └───────────┘  │                    │  └───────────┘  │
│        ▲        │                    │                 │
│   Producers &   │                    │    Standby      │
│   Consumers     │                    │                 │
└─────────────────┘                    └─────────────────┘
```

### Quick Start
```bash
cd scenario/active-passive/

# 1. Create namespace
kubectl apply -f ns.yaml

# === DC1 (Primary) ===
kubectl apply -f DC1/kafka/

# === DC2 (Standby) ===
kubectl apply -f DC2/kafka/

# MirrorMaker is defined in DC2 to pull from DC1
```

### Key Files
| Location | File | Purpose |
|----------|------|---------|
| `DC1/kafka/` | `kafka-*.yaml` | Primary Kafka cluster |
| `DC2/kafka/` | `kafka-*.yaml` | Standby Kafka cluster |
| `DC2/kafka/` | `kafka-mirror-maker-*.yaml` | MirrorMaker 2 replication |

### Failover Procedure
```
Normal:   DC1 (Active) ──async──> DC2 (Passive)

Failover:
  1. Detect DC1 failure
  2. Stop MirrorMaker
  3. Promote DC2 to Active
  4. Redirect clients to DC2

Restore:
  1. Recover DC1
  2. Configure DC1 as new Passive
  3. Start MirrorMaker: DC2 -> DC1
```

| Pros | Cons |
|------|------|
| Low cost | Possible data loss |
| Simple operations | Manual failover |
| Works with high latency | Downtime during switch |

---

### 2.2 Active/Active

Both DCs serve traffic. Each DC has Local + Aggregate clusters.

```
┌──────────────────────────────┐     ┌──────────────────────────────┐
│            DC1               │     │            DC2               │
│                              │     │                              │
│  Producer ──► [Local]        │     │  Producer ──► [Local]        │
│                 │            │     │                 │            │
│                 ▼ mirror     │     │     mirror      ▼            │
│            [Aggregate] ◄─────┼─────┼────► [Aggregate]             │
│                 │            │     │           │                  │
│                 ▼            │     │           ▼                  │
│             Consumer         │     │       Consumer               │
└──────────────────────────────┘     └──────────────────────────────┘
```

### Quick Start
```bash
cd scenario/active-active/

# 1. Create namespace
kubectl apply -f ns.yaml

# === DC1 ===
kubectl apply -f DC1/kafka/kafka-local.yaml      # Local cluster
kubectl apply -f DC1/kafka/kafka-aggr.yaml       # Aggregate cluster

# === DC2 ===
kubectl apply -f DC2/kafka/kafka-local.yaml
kubectl apply -f DC2/kafka/kafka-aggr.yaml

# === MirrorMaker (bidirectional) ===
kubectl apply -f DC1/kafka/kafka-mirror-maker-*.yaml
kubectl apply -f DC2/kafka/kafka-mirror-maker-*.yaml
```

### Key Files
| Location | File | Purpose |
|----------|------|---------|
| `DC*/kafka/` | `kafka-local.yaml` | Local cluster for producers |
| `DC*/kafka/` | `kafka-aggr.yaml` | Aggregate cluster for global view |
| `DC*/kafka/` | `kafka-mirror-maker-*.yaml` | Cross-DC replication |

### Consumer Patterns
| Pattern | Use Case |
|---------|----------|
| Read from **Local** | Low latency, local data only |
| Read from **Aggregate** | Global view, higher latency |

| Pros | Cons |
|------|------|
| Near-zero RTO | Complex setup |
| Both DCs active | Higher cost (4 clusters) |
| Geo-locality | Eventual consistency |

---

## Comparison Matrix

| Aspect | Stretch Cluster | Active/Passive | Active/Active |
|--------|-----------------|----------------|---------------|
| **DCs Required** | 3 | 2 | 2 |
| **Clusters** | 1 | 2 | 4 (2 local + 2 aggr) |
| **RPO** | 0 | >0 | >0 |
| **RTO** | ~0 | >0 (manual) | ~0 |
| **Complexity** | Low | Medium | High |
| **Cost** | High | Low | Medium-High |
| **Failover** | Automatic | Manual | Semi-automatic |

---

## Utilities

### Monitoring Stack
```bash
cd utilities/

# Prometheus (metrics)
kubectl apply -f prometheus/

# Grafana (dashboards)
kubectl apply -f grafana/

# ELK Stack (logs)
kubectl apply -f elasticsearch/
kubectl apply -f kibana/
```

### Useful Commands
See [`utilities/operation-cmd/kafka.md`](./utilities/operation-cmd/kafka.md) for:
- Topic management
- Consumer group inspection
- Performance testing
- Troubleshooting

---

## References

- [Strimzi Documentation](https://strimzi.io/documentation/)
- [Kafka MirrorMaker 2](https://kafka.apache.org/documentation/#georeplication)
- [Confluent Multi-DC](https://docs.confluent.io/platform/current/multi-dc-deployments/index.html)
