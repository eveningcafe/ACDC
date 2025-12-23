# Consul Multi-Datacenter

**Service mesh, service discovery, and configuration across datacenters**

> **Managed**: HCP Consul → **Self-hosted**: Consul OSS (for learning, WAN federation is free)

---

## Overview

Consul provides service discovery, health checking, and KV store across multiple datacenters. It's often used alongside other tools for cross-DC communication.

```
┌─────────────────────────┐         ┌─────────────────────────┐
│      Datacenter 1       │         │      Datacenter 2       │
│                         │         │                         │
│  ┌─────────────────┐    │   WAN   │    ┌─────────────────┐  │
│  │  Consul Server  │◄───┼─────────┼───►│  Consul Server  │  │
│  │    Cluster      │    │  Gossip │    │    Cluster      │  │
│  └────────┬────────┘    │         │    └────────┬────────┘  │
│           │             │         │             │           │
│     LAN Gossip          │         │       LAN Gossip        │
│           │             │         │             │           │
│  ┌────────▼────────┐    │         │    ┌────────▼────────┐  │
│  │  Consul Agents  │    │         │    │  Consul Agents  │  │
│  │   (Services)    │    │         │    │   (Services)    │  │
│  └─────────────────┘    │         │    └─────────────────┘  │
└─────────────────────────┘         └─────────────────────────┘
```

---

## Federation Types

### 1. Basic WAN Federation (Open Source)

Full mesh connectivity between all Consul servers across all DCs.

```
     DC1 Servers ◄──────────► DC2 Servers
          ▲                        ▲
          │                        │
          └────────► DC3 ◄─────────┘
                   Servers
```

**Requirements**:
- TCP/UDP port 8302 (WAN gossip) between all servers
- TCP port 8300 (RPC) between all servers
- TLS encryption with same CA
- All DC names in certificate SAN

**Pros**:
- Simple setup
- Works with open source

**Cons**:
- Exponential connections as DCs grow (N × N-1)
- Requires full mesh network connectivity

### 2. Advanced WAN Federation (Enterprise)

Hub-and-spoke topology for partially connected networks.

```
                    ┌─────────┐
         ┌─────────►│   HUB   │◄─────────┐
         │          │   DC    │          │
         │          └─────────┘          │
         │               ▲               │
         ▼               │               ▼
    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │ Spoke 1 │    │ Spoke 2 │    │ Spoke 3 │
    └─────────┘    └─────────┘    └─────────┘
```

**Requirements**:
- Only RPC connectivity needed (no WAN gossip)
- Enterprise license

**Pros**:
- Works with partial network connectivity
- Better for large deployments (10+ DCs)
- Reduced connection overhead

---

## Network Requirements

| Port | Protocol | Purpose |
|------|----------|---------|
| 8300 | TCP | RPC (server-to-server) |
| 8301 | TCP/UDP | LAN gossip (within DC) |
| 8302 | TCP/UDP | WAN gossip (cross DC) |
| 8500 | TCP | HTTP API |
| 8600 | TCP/UDP | DNS |

**Security**:
- TLS required for all server communication
- Same CA for all DCs
- ACL tokens for authentication

---

## Replication

### What Replicates Automatically

| Data | Replication | Notes |
|------|-------------|-------|
| Service catalog | Yes | Cross-DC service discovery works |
| Health checks | Yes | Know if services in other DCs are healthy |
| ACL policies | Yes (from primary) | Primary DC is authoritative |
| Connect CA | Yes (from primary) | Certificates for service mesh |
| Intentions | Yes (from primary) | Service-to-service auth policies |

### What Doesn't Replicate

| Data | Solution |
|------|----------|
| KV store | Use `consul-replicate` or manual sync |
| Prepared queries | Define in each DC |
| Local tokens | Create in each DC |

---

## Cross-DC Service Discovery

### Querying Services in Another DC

```bash
# DNS: service.datacenter.consul
dig @127.0.0.1 -p 8600 web.service.dc2.consul

# HTTP API
curl http://localhost:8500/v1/health/service/web?dc=dc2
```

### Prepared Queries for Failover

```json
{
  "Name": "web-failover",
  "Service": {
    "Service": "web",
    "Failover": {
      "Datacenters": ["dc2", "dc3"]
    }
  }
}
```

Query: `web-failover.query.consul` → tries dc1, then dc2, then dc3

---

## Deployment Patterns

### Pattern 1: Primary + Secondary (DR)

```
DC1 (Primary)              DC2 (Secondary)
┌─────────────┐            ┌─────────────┐
│ ACL Primary │───────────►│ ACL Replica │
│ All writes  │            │ Read-only   │
└─────────────┘            └─────────────┘
```

- DC1 handles all ACL/policy writes
- DC2 can take over if DC1 fails (manual promotion)

### Pattern 2: Active-Active Services

```
DC1                        DC2
┌─────────────┐            ┌─────────────┐
│ Service A   │◄──────────►│ Service A   │
│ Service B   │            │ Service B   │
└─────────────┘            └─────────────┘
         │                        │
         └────► Cross-DC ◄────────┘
              Discovery
```

- Services run in both DCs
- Clients can discover and call services in any DC
- Use prepared queries for automatic failover

---

## Best Practices

1. **Designate primary DC first**
   - Choose most stable/central DC
   - All global state originates here

2. **Use TLS everywhere**
   - Same CA across all DCs
   - Include all DC names in SAN

3. **Plan network connectivity**
   - Ensure firewall rules allow required ports
   - Consider latency for WAN gossip

4. **Monitor replication lag**
   - ACL replication status
   - Service catalog sync

5. **Test DC failure scenarios**
   - What happens when primary DC fails?
   - Can you promote secondary?

---

## Comparison: Consul vs Alternatives

| Feature | Consul | etcd | ZooKeeper |
|---------|--------|------|-----------|
| Multi-DC native | Yes | No (manual) | No (manual) |
| Service discovery | Yes | No | No |
| Service mesh | Yes (Connect) | No | No |
| KV store | Yes | Yes | Yes |
| Health checks | Yes | No | Session-based |

---

## References

- [Consul Multi-Cluster Reference Architecture](https://developer.hashicorp.com/consul/tutorials/production-multi-cluster/multi-cluster-reference-architecture)
- [WAN Federation](https://developer.hashicorp.com/consul/docs/connect/datacenters)
- [Prepared Queries](https://developer.hashicorp.com/consul/api-docs/query)
