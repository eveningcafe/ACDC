# API Gateway Multi-Region

**Traffic routing, rate limiting, and API management across datacenters**

> **Managed**: Cloudflare (global edge native) → **Self-hosted**: Kong (for learning, open-source)

---

## Overview

API Gateway is the entry point for all client requests. In multi-region setups, it handles routing, failover, and load balancing across datacenters.

```
Clients (worldwide)
   │
   ▼
┌─────────────────────────────────────────┐
│      Global API Gateway (Edge)          │
│   - Rate limiting                       │
│   - Authentication                      │
│   - Geo-routing                         │
└─────────────────────────────────────────┘
   │                    │
   ▼                    ▼
┌─────────┐        ┌─────────┐
│   DC1   │        │   DC2   │
│ Services│        │ Services│
└─────────┘        └─────────┘
```

---

## Multi-Region Support Comparison

| Solution | Multi-Region Native? | Type |
|----------|---------------------|------|
| **Cloudflare** | Yes (300+ edge locations) | Managed |
| **Kong (Konnect)** | Yes | Managed |
| AWS API Gateway | No (regional service) | Managed |
| **Kong OSS** | Manual setup | Self-hosted |
| **Traefik** | Manual setup | Self-hosted |

> **Note**: AWS API Gateway is **regional only**. For multi-region, you need Route 53 + multiple regional deployments.

---

## Multi-Region Patterns

### Pattern 1: Regional Gateways + DNS Failover

```
┌─────────────────────────────────────────────────────────┐
│                    DNS (Route 53)                       │
│              api.example.com                            │
└─────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
┌─────────────────┐            ┌─────────────────┐
│   Region 1      │            │   Region 2      │
│   Kong Gateway  │            │   Kong Gateway  │
│        │        │            │        │        │
│        ▼        │            │        ▼        │
│   Services      │            │   Services      │
└─────────────────┘            └─────────────────┘
```

- Each region has its own gateway
- DNS routes users to nearest/healthy region
- Simple, independent deployments

### Pattern 2: Global Gateway + Regional Backends

```
┌─────────────────────────────────────────────────────────┐
│              Global API Gateway (Edge)                  │
│         - CDN integration                               │
│         - Global rate limiting                          │
└─────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
┌─────────────────┐            ┌─────────────────┐
│   Region 1      │            │   Region 2      │
│   Services      │            │   Services      │
└─────────────────┘            └─────────────────┘
```

- Single global entry point
- Routes to backend regions based on latency/availability
- Centralized policy management

---

## Kong Multi-Region Setup

### Option 1: Shared Database (Hybrid Mode)

```
┌─────────────────┐            ┌─────────────────┐
│   Region 1      │            │   Region 2      │
│   Kong DP       │            │   Kong DP       │
│ (Data Plane)    │            │ (Data Plane)    │
└────────┬────────┘            └────────┬────────┘
         │                              │
         └──────────┬───────────────────┘
                    │
            ┌───────▼───────┐
            │   Kong CP     │
            │(Control Plane)│
            │   + Database  │
            └───────────────┘
```

- Control Plane manages config centrally
- Data Planes in each region handle traffic
- Config syncs automatically

### Option 2: Independent Clusters + Config Sync

```
┌─────────────────┐            ┌─────────────────┐
│   Region 1      │            │   Region 2      │
│   Kong + DB     │◄──sync────►│   Kong + DB     │
└─────────────────┘            └─────────────────┘
```

- Each region fully independent
- Sync config via decK (Kong declarative config)
- Higher availability, more operational overhead

---

## Key Features for Multi-Region

| Feature | Purpose |
|---------|---------|
| **Health Checks** | Detect unhealthy upstreams |
| **Circuit Breaker** | Prevent cascade failures |
| **Rate Limiting** | Global or per-region limits |
| **Load Balancing** | Round-robin, least-conn, consistent-hash |
| **Failover** | Route to backup upstream on failure |

---

## Kong Upstream Configuration

```yaml
# kong.yml (declarative config)
upstreams:
  - name: my-service
    algorithm: round-robin
    healthchecks:
      active:
        healthy:
          interval: 5
          successes: 2
        unhealthy:
          interval: 5
          http_failures: 3
    targets:
      - target: service-dc1.internal:8000
        weight: 100
      - target: service-dc2.internal:8000
        weight: 100

services:
  - name: my-api
    url: http://my-service
    routes:
      - name: my-route
        paths:
          - /api
```

---

## AWS API Gateway Multi-Region

### With Route 53 Failover

```
Route 53 (Failover Policy)
         │
    ┌────┴────┐
    ▼         ▼
┌───────┐ ┌───────┐
│API GW │ │API GW │
│Region1│ │Region2│
└───┬───┘ └───┬───┘
    │         │
    ▼         ▼
 Lambda/    Lambda/
 Services   Services
```

### With CloudFront (Edge)

```
CloudFront (Global Edge)
         │
         ▼
    API Gateway
    (Origin Region)
         │
         ▼
    Backend Services
```

---

## Comparison

| Aspect | Kong | AWS API Gateway |
|--------|------|-----------------|
| Deployment | Self-hosted | Managed |
| Multi-region | Manual setup | Per-region deployment |
| Plugins | 100+ (open source) | Limited, use Lambda |
| Cost | Infrastructure only | Per-request pricing |
| Vendor lock-in | None | AWS |

---

## Best Practices

1. **Deploy gateway close to users**
   - Reduce latency
   - Use DNS for geo-routing

2. **Implement health checks**
   - Active and passive checks
   - Fast failure detection

3. **Use circuit breakers**
   - Prevent cascade failures
   - Allow recovery time

4. **Centralize config management**
   - GitOps with decK
   - Consistent across regions

5. **Monitor globally**
   - Track latency per region
   - Alert on error rate spikes

---

## References

- [Kong Gateway](https://docs.konghq.com/)
- [Kong Hybrid Mode](https://docs.konghq.com/gateway/latest/production/deployment-topologies/hybrid-mode/)
- [AWS API Gateway Multi-Region](https://aws.amazon.com/blogs/compute/building-a-multi-region-serverless-application-with-amazon-api-gateway-and-aws-lambda/)
