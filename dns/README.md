# DNS Multi-Region

**Global traffic management, failover, and load balancing**

> **Managed**: AWS Route 53 → **Self-hosted**: PowerDNS (for learning)

## Lab

**[→ Hands-on Lab: PowerDNS Multi-DC ](./lab/)**

---

## Overview

DNS is the foundation of multi-region architecture. It's the first layer that decides which datacenter handles a user's request.

```
User Request
     │
     ▼
┌─────────────────────────────────────────┐
│           DNS (Route 53 / PowerDNS)     │
│   Which DC should handle this request?  │
└─────────────────────────────────────────┘
     │                    │
     ▼                    ▼
┌─────────┐          ┌─────────┐
│   DC1   │          │   DC2   │
└─────────┘          └─────────┘
```

---

## Key Challenges

| Challenge | Problem |
|-----------|---------|
| **TTL Caching** | DNS records are cached. Failover isn't instant |
| **Health Checks** | How to detect if a DC is healthy? |
| **Propagation Delay** | DNS changes take time to propagate globally |

---

## Routing Policies

### 1. Simple Routing
```
example.com → 1.2.3.4
```

### 2. Weighted Routing
```
example.com → DC1 (70%)
            → DC2 (30%)
```

### 3. Failover Routing (Active-Passive)
```
example.com → Primary (DC1) ← Health Check
                  │
             if unhealthy
                  ▼
             Secondary (DC2)
```

### 4. Round-Robin (Active-Active)
```
example.com → DC1 ✓
            → DC2 ✓
```

---

## TTL vs Failover Speed

| TTL | Failover Time | DNS Query Load |
|-----|---------------|----------------|
| 60s | ~1-2 minutes | High |
| 300s | ~5-10 minutes | Medium |
| 3600s | ~1+ hour | Low |

---

## Lab Architecture

```
┌─────────────────┐         ┌─────────────────┐
│      DC1        │◄───────►│      DC2        │
│   PowerDNS      │  sync   │   PowerDNS      │
│   + dnsdist     │  (MinIO)│   + dnsdist     │
└─────────────────┘         └─────────────────┘
```

**Components:**
- **dnsdist** - DNS load balancer (port 53)
- **PowerDNS Auth** - Authoritative DNS server
- **PowerDNS Recursor** - Forwards unknown zones to 8.8.8.8
- **Lightning Stream** - Syncs zones via MinIO S3

### Quick Start

```bash
cd dns/lab

# Deploy
kubectl apply -f powerdns/dc1-port53.yaml
kubectl apply -f powerdns/dc2-port53.yaml
kubectl apply -f minio/dc1.yaml
kubectl apply -f minio/dc2.yaml

# Create zone
curl -X POST http://<DC1_IP>:8081/api/v1/servers/localhost/zones \
  -H "X-API-Key: changeme" \
  -H "Content-Type: application/json" \
  -d '{"name":"example.com.","kind":"Native","nameservers":["ns1.example.com."]}'

# Test
nslookup example.com <DC1_IP>
```

### Test Replication

```bash
# Add record on DC1
curl -X PATCH http://<DC1_IP>:8081/api/v1/servers/localhost/zones/example.com. \
  -H "X-API-Key: changeme" \
  -H "Content-Type: application/json" \
  -d '{"rrsets":[{"name":"www.example.com.","type":"A","ttl":60,"changetype":"REPLACE",
       "records":[{"content":"1.2.3.4","disabled":false}]}]}'

# Wait 10s, then verify on DC2
nslookup www.example.com <DC2_IP>
```

### Failover Test

```bash
# Kill DC1
kubectl scale deployment powerdns -n dns-dc1 --replicas=0

# DC2 still works (zone was replicated)
nslookup www.example.com <DC2_IP>
```

---

## References

- [Route 53 Routing Policies](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html)
- [PowerDNS Documentation](https://doc.powerdns.com/)
- [Lightning Stream](https://doc.powerdns.com/lightningstream/)
