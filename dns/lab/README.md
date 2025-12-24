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
│   │ │ minio          :9000   │◄┼────────────┼►│ minio          :9100   │ │  │
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
| MinIO | 9000, 9001 | 9100, 9101 |
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

# Setup MinIO site replication
mc alias set dc1 http://localhost:9000 minioadmin minioadmin123
mc alias set dc2 http://localhost:9100 minioadmin minioadmin123
mc admin replicate add dc1 dc2
```

## DNS Routing Patterns (Route 53 Style)

### 1. Setup Zone with Weighted Records

```bash
# Create zone on DC1 (syncs to DC2 via Lightning Stream)
curl -X POST http://localhost:8081/api/v1/servers/localhost/zones \
  -H "X-API-Key: changeme" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "example.com.",
    "kind": "Native",
    "nameservers": ["ns1.example.com."]
  }'

# Add weighted A records (70% DC1, 30% DC2)
# PowerDNS uses multiple A records - client randomly picks one
curl -X PATCH http://localhost:8081/api/v1/servers/localhost/zones/example.com. \
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
        {"content": "10.0.1.10", "disabled": false},
        {"content": "10.0.1.10", "disabled": false},
        {"content": "10.0.1.10", "disabled": false},
        {"content": "10.0.1.10", "disabled": false},
        {"content": "10.0.1.10", "disabled": false},
        {"content": "10.0.1.10", "disabled": false},
        {"content": "10.0.2.10", "disabled": false},
        {"content": "10.0.2.10", "disabled": false},
        {"content": "10.0.2.10", "disabled": false}
      ]
    }]
  }'
```

### 2. Weighted Routing Simulation

```
app.example.com → 10.0.1.10 (DC1) - 70%
                → 10.0.2.10 (DC2) - 30%
```

Test with multiple queries:
```bash
# Query multiple times to see distribution
for i in {1..10}; do
  dig @localhost -p 5353 app.example.com +short
done
```

### 3. Failover Routing (Active-Passive)

For failover, configure client-side or use health checks:

```bash
# Primary record
curl -X PATCH http://localhost:8081/api/v1/servers/localhost/zones/example.com. \
  -H "X-API-Key: changeme" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [{
      "name": "api.example.com.",
      "type": "A",
      "ttl": 60,
      "changetype": "REPLACE",
      "records": [
        {"content": "10.0.1.10", "disabled": false}
      ]
    }]
  }'

# When DC1 fails, update to DC2 (manual failover)
curl -X PATCH http://localhost:8081/api/v1/servers/localhost/zones/example.com. \
  -H "X-API-Key: changeme" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [{
      "name": "api.example.com.",
      "type": "A",
      "ttl": 60,
      "changetype": "REPLACE",
      "records": [
        {"content": "10.0.2.10", "disabled": false}
      ]
    }]
  }'
```

### 4. Multi-Value Answer (Active-Active)

```bash
# Both DCs active - client picks one
curl -X PATCH http://localhost:8081/api/v1/servers/localhost/zones/example.com. \
  -H "X-API-Key: changeme" \
  -H "Content-Type: application/json" \
  -d '{
    "rrsets": [{
      "name": "www.example.com.",
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

## Test Backend Services

```bash
# Test DC1 backend
curl http://localhost:8080
# {"dc": "DC1", "ip": "10.0.1.10", "message": "Hello from DC1"}

# Test DC2 backend
curl http://localhost:8180
# {"dc": "DC2", "ip": "10.0.2.10", "message": "Hello from DC2"}
```

## Simulate DNS-based Load Balancing

```bash
# Resolve and hit backend in loop
for i in {1..20}; do
  IP=$(dig @localhost -p 5353 app.example.com +short | head -1)
  if [ "$IP" = "10.0.1.10" ]; then
    curl -s http://localhost:8080 | jq -r '.dc'
  else
    curl -s http://localhost:8180 | jq -r '.dc'
  fi
done | sort | uniq -c
# Expected: ~14 DC1, ~6 DC2 (70/30 weighted)
```

## Client Configuration

### Option 1: Use Both DNS Servers (Failover)
```bash
# /etc/resolv.conf
nameserver 127.0.0.1  # DC1 via port forward
options port:5353
```

### Option 2: Local dnsdist (Active-Active)
```lua
-- Client-side dnsdist.conf
setLocal("127.0.0.1:53")
newServer({address="DC1_IP:5353", name="dc1", weight=70})
newServer({address="DC2_IP:5354", name="dc2", weight=30})
setServerPolicy(wrandom)  -- Weighted random
```

## Data Replication Flow

```
DC1: Record Change
       │
       ▼
PowerDNS Auth (LMDB)
       │
       ▼
Lightning Stream ──► MinIO DC1
                        │
                        ▼ (Site Replication)
                     MinIO DC2
                        │
                        ▼
                  Lightning Stream
                        │
                        ▼
               PowerDNS Auth (LMDB)
                     DC2: Record Synced
```

## Cleanup

```bash
# Delete DC1
kubectl delete -f dns/lab/backend/dc1.yaml
kubectl delete -f dns/lab/minio/dc1.yaml
kubectl delete -f dns/lab/powerdns/dc1.yaml

# Delete DC2
kubectl delete -f dns/lab/backend/dc2.yaml
kubectl delete -f dns/lab/minio/dc2.yaml
kubectl delete -f dns/lab/powerdns/dc2.yaml
```
