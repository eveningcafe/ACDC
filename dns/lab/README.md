# PowerDNS Multi-DC Lab

Kubernetes lab for PowerDNS cross-AZ DNS with weighted routing simulation.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Host Network                                    │
│                                                                              │
│   DC1 (dns-dc1)                              DC2 (dns-dc2)                  │
│   ┌────────────────────────────┐            ┌────────────────────────────┐  │
│   │ powerdns deployment        │            │ powerdns deployment        │  │
│   │ ┌────────────────────────┐ │            │ ┌────────────────────────┐ │  │
│   │ │ dnsdist       :5353    │ │            │ │ dnsdist       :5354    │ │  │
│   │ │ pdns-auth     :5300    │ │            │ │ pdns-auth     :5400    │ │  │
│   │ │ pdns-recursor :5301    │ │            │ │ pdns-recursor :5401    │ │  │
│   │ │ lightning-stream       │ │            │ │ lightning-stream       │ │  │
│   │ └───────────┬────────────┘ │            │ └───────────┬────────────┘ │  │
│   │             │ LMDB         │            │             │ LMDB         │  │
│   │             ▼              │            │             ▼              │  │
│   │ ┌────────────────────────┐ │            │ ┌────────────────────────┐ │  │
│   │ │ minio          :9000   │◄┼────────────┼►│ minio          :9200   │ │  │
│   │ └────────────────────────┘ │ Site Repl  │ └────────────────────────┘ │  │
│   │                            │            │                            │  │
│   │ ┌────────────────────────┐ │            │ ┌────────────────────────┐ │  │
│   │ │ backend        :8080   │ │            │ │ backend        :8180   │ │  │
│   │ │ {"dc": "DC1"}          │ │            │ │ {"dc": "DC2"}          │ │  │
│   │ └────────────────────────┘ │            │ └────────────────────────┘ │  │
│   └────────────────────────────┘            └────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Port Mapping

| Component | DC1 | DC2 |
|-----------|-----|-----|
| dnsdist | 5353 | 5354 |
| PowerDNS Auth | 5300, 8081 | 5400, 8181 |
| PowerDNS Recursor | 5301, 8082 | 5401, 8182 |
| dnsdist Web | 8083 | 8183 |
| Lightning Stream | 8084 | 8184 |
| MinIO | 9000, 9001 | 9200, 9201 |
| Backend | 8080 | 8180 |

## File Structure

```
dns/lab/
├── powerdns/
│   ├── dc1.yaml    # dnsdist + pdns-auth + pdns-recursor + lightning-stream
│   └── dc2.yaml
├── minio/
│   ├── dc1.yaml    # MinIO S3 storage
│   └── dc2.yaml
├── backend/
│   ├── dc1.yaml    # Simple nginx backend (returns {"dc": "DC1"})
│   └── dc2.yaml
└── README.md
```

## Prerequisites

- Kubernetes cluster with 2+ nodes
- Node selector is configured in YAMLs (update `kubernetes.io/hostname` values if needed)
- MinIO site replication must be set up for zone sync between DCs

## Quick Start

```bash
# Deploy DC1
kubectl apply -f dns/lab/powerdns/dc1.yaml
kubectl apply -f dns/lab/minio/dc1.yaml
kubectl apply -f dns/lab/backend/dc1.yaml

# Deploy DC2
kubectl apply -f dns/lab/powerdns/dc2.yaml
kubectl apply -f dns/lab/minio/dc2.yaml
kubectl apply -f dns/lab/backend/dc2.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app=powerdns -n dns-dc1 --timeout=120s
kubectl wait --for=condition=ready pod -l app=powerdns -n dns-dc2 --timeout=120s

# Setup MinIO site replication (optional, if Lightning Stream is enabled)
mc alias set dc1 http://localhost:9000 minioadmin minioadmin123
mc alias set dc2 http://localhost:9200 minioadmin minioadmin123
mc admin replicate add dc1 dc2
```

## DNS Routing Patterns

### Create Zone

```bash
# Create zone on DC1 (syncs to DC2 via Lightning Stream)
curl -X POST http://<DC1_IP>:8081/api/v1/servers/localhost/zones \
  -H "X-API-Key: changeme" \
  -H "Content-Type: application/json" \
  -d '{"name": "example.com.", "kind": "Native", "nameservers": ["ns1.example.com."]}'
```

### Active-Active (Round-Robin)

Both DCs serve traffic, client picks one:

```bash
curl -X PATCH http://<DC1_IP>:8081/api/v1/servers/localhost/zones/example.com. \
  -H "X-API-Key: changeme" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [{
      "name": "app.example.com.",
      "type": "A",
      "ttl": 60,
      "changetype": "REPLACE",
      "records": [
        {"content": "10.0.1.10", "disabled": false},
        {"content": "10.0.2.10", "disabled": false}
      ]
    }]
  }'
```

### Active-Passive (Manual Failover)

```bash
# Normal: point to DC1
curl -X PATCH http://<DC1_IP>:8081/api/v1/servers/localhost/zones/example.com. \
  -H "X-API-Key: changeme" \
  -H "Content-Type: application/json" \
  -d '{"rrsets": [{"name": "api.example.com.", "type": "A", "ttl": 60, "changetype": "REPLACE",
       "records": [{"content": "10.0.1.10", "disabled": false}]}]}'

# Failover: switch to DC2
curl -X PATCH http://<DC1_IP>:8081/api/v1/servers/localhost/zones/example.com. \
  -H "X-API-Key: changeme" \
  -H "Content-Type: application/json" \
  -d '{"rrsets": [{"name": "api.example.com.", "type": "A", "ttl": 60, "changetype": "REPLACE",
       "records": [{"content": "10.0.2.10", "disabled": false}]}]}'
```

## Test Services

From inside a client pod (`kubectl run client --image=nicolaka/netshoot -it --rm --restart=Never -- bash`):

```bash
# Test backends
curl http://<DC1_IP>:8080   # {"dc": "DC1", ...}
curl http://<DC2_IP>:8180   # {"dc": "DC2", ...}

# Test DNS round-robin
dig @<DC1_IP> -p 5353 app.example.com +short
# Returns: 10.0.1.10 and 10.0.2.10
```

## Client Testing

Client runs inside the cluster as a pod:

```
┌──────────────────────────────────────────────────────────────────────────┐
│                           Kubernetes Cluster                             │
│                                                                          │
│   Node 1 (DC1_IP)                      Node 2 (DC2_IP)                   │
│   ┌─────────────────┐                  ┌─────────────────┐               │
│   │ DC1             │                  │ DC2             │               │
│   │ DNS: :5353      │                  │ DNS: :5354      │               │
│   │ Backend: :8080  │                  │ Backend: :8180  │               │
│   └─────────────────┘                  └─────────────────┘               │
│                                                                          │
│   ┌─────────────────────────────────────────────────────────────────┐    │
│   │  CLIENT POD (netshoot)                                          │    │
│   │  - dig @DC1_IP -p 5353 app.example.com                          │    │
│   │  - curl http://DC1_IP:8080                                      │    │
│   └─────────────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────────────┘
```

```bash
# Interactive client pod
kubectl run client --image=nicolaka/netshoot -it --rm --restart=Never -- bash

# Inside the pod:
dig @<DC1_IP> -p 5353 app.example.com
curl http://<DC1_IP>:8080   # DC1 backend
curl http://<DC2_IP>:8180   # DC2 backend
```

## Failover Testing

### Zone Sync Flow

```
DC1: Record Change → LMDB → Lightning Stream → MinIO DC1
                                                    ↓ (Site Replication)
DC2: LMDB ← Lightning Stream ← MinIO DC2 ←─────────┘
```

### Verify Zone Replication

```bash
# Add record on DC1
curl -X PATCH http://<DC1_IP>:8081/api/v1/servers/localhost/zones/example.com. \
  -H "X-API-Key: changeme" -H "Content-Type: application/json" \
  -d '{"rrsets": [{"name": "www.example.com.", "type": "A", "ttl": 60, "changetype": "REPLACE",
       "records": [{"content": "1.2.3.4", "disabled": false}]}]}'

# Wait for sync, then query DC2
sleep 10
dig @<DC2_IP> -p 5400 www.example.com +short
# Expected: 1.2.3.4
```

### Simulate DC1 Failure

```bash
# Scale down DC1
kubectl scale deployment powerdns -n dns-dc1 --replicas=0

# DC2 continues serving (zone was replicated)
dig @<DC2_IP> -p 5400 www.example.com +short

# Restore DC1
kubectl scale deployment powerdns -n dns-dc1 --replicas=1
```

### Client-side Auto-Failover (dnsdist)

```bash
kubectl run dns-client --image=powerdns/dnsdist-19:latest --restart=Never -- sh -c '
cat > /tmp/dnsdist.conf << EOF
setLocal("127.0.0.1:53")
newServer({address="<DC1_IP>:5353", name="dc1", checkInterval=1, maxCheckFailures=2})
newServer({address="<DC2_IP>:5354", name="dc2", checkInterval=1, maxCheckFailures=2, order=2})
setServerPolicy(firstAvailable)
EOF
dnsdist -C /tmp/dnsdist.conf --supervised'

# Failover happens in 1-3 seconds when DC1 goes down
kubectl exec -it dns-client -- dig @127.0.0.1 www.example.com +short
```

## Cleanup

```bash
kubectl delete ns dns-dc1 dns-dc2
```
