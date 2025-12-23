# DNS Multi-Region

**Global traffic management, failover, and load balancing**

> **Managed**: AWS Route 53 → **Self-hosted**: PowerDNS (for learning)

---

## Overview

DNS is the foundation of multi-region architecture. It's the first layer that decides which datacenter handles a user's request.

```
User Request
     │
     ▼
┌─────────────────────────────────────────┐
│           DNS (Route 53 / etc)          │
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
| **TTL Caching** | DNS records are cached by clients/resolvers. Failover isn't instant (depends on TTL) |
| **Health Checks** | How to detect if a DC is healthy? Who decides? |
| **Propagation Delay** | DNS changes take time to propagate globally |
| **Client Behavior** | Some clients ignore TTL, cache longer than expected |

---

## AWS Route 53 Routing Policies

### Simple Routing
```
example.com → 1.2.3.4
```
- One record, one destination
- No health checks

### Weighted Routing
```
example.com → DC1 (70%)
            → DC2 (30%)
```
- Distribute traffic by percentage
- Good for gradual rollouts, A/B testing

### Latency-Based Routing
```
User in Asia    → DC-Singapore
User in Europe  → DC-Frankfurt
User in US      → DC-Virginia
```
- Route to lowest latency region
- Requires resources in multiple regions

### Geolocation Routing
```
User from Vietnam  → DC-Singapore
User from Germany  → DC-Frankfurt
Default            → DC-Virginia
```
- Route based on user's geographic location
- Good for compliance, localized content

### Failover Routing (Active-Passive)
```
┌─────────────────────────────────────────────────────────┐
│                    Route 53                             │
│                                                         │
│   example.com ──► Primary (DC1) ◄── Health Check       │
│                        │                                │
│                   if unhealthy                          │
│                        ▼                                │
│                   Secondary (DC2)                       │
└─────────────────────────────────────────────────────────┘
```
- Primary handles all traffic when healthy
- Automatic failover to secondary when primary fails
- Requires health checks

### Multi-Value Answer Routing
```
example.com → 1.2.3.4 (DC1) ✓ healthy
            → 5.6.7.8 (DC2) ✓ healthy
            → 9.10.11.12 (DC3) ✗ unhealthy (excluded)
```
- Returns multiple healthy IPs
- Client chooses one (usually first)
- Simple load balancing with health checks

---

## Failover Patterns

### Active-Passive Failover

```
Normal:
  Route 53 ──► DC1 (Primary) ✓
               DC2 (Secondary) standby

DC1 Fails:
  Route 53 ──► DC1 (Primary) ✗ health check fails
           ──► DC2 (Secondary) ✓ now active
```

**TTL Consideration**: Lower TTL = faster failover, but more DNS queries

| TTL | Failover Time | DNS Query Load |
|-----|---------------|----------------|
| 60s | ~1-2 minutes | High |
| 300s | ~5-10 minutes | Medium |
| 3600s | ~1+ hour | Low |

### Active-Active with Health Checks

```
Route 53 (Weighted + Health Checks)
     │
     ├──► DC1 (50%) ✓
     │
     └──► DC2 (50%) ✓

If DC1 fails:
     └──► DC2 (100%) ✓
```

---

## Route 53 Application Recovery Controller (ARC)

For mission-critical applications, Route 53 ARC provides:

```
┌─────────────────────────────────────────────────────────┐
│                Route 53 ARC                             │
│                                                         │
│   ┌─────────────┐    ┌─────────────┐                    │
│   │  Routing    │    │  Readiness  │                    │
│   │  Controls   │    │   Checks    │                    │
│   │ (on/off)    │    │             │                    │
│   └─────────────┘    └─────────────┘                    │
│          │                  │                           │
│          ▼                  ▼                           │
│   Manual/Auto          Are resources                    │
│   failover             ready in DR?                     │
└─────────────────────────────────────────────────────────┘
```

- **Routing Controls**: On/off switches for traffic routing (data plane operation, not control plane)
- **Readiness Checks**: Verify DR region has required resources
- **5 Regional Endpoints**: High availability for the failover mechanism itself

---

## Best Practices

1. **Set appropriate TTL**
   - Lower for critical services (60-300s)
   - Higher for stable services (3600s+)

2. **Health check strategy**
   - Check application health, not just TCP port
   - Use multiple health check locations
   - Consider dependencies (DB, cache)

3. **Test failover regularly**
   - DR drills with real traffic
   - Document failover procedures

4. **Monitor DNS**
   - Track resolution times
   - Alert on health check failures

---

## Comparison with Other Solutions

| Solution | Pros | Cons |
|----------|------|------|
| **Route 53** | Integrated with AWS, global anycast, ARC | AWS-specific |
| **Self-hosted (BIND/PowerDNS)** | Full control | Operational burden |

---

## References

- [Route 53 Routing Policies](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy.html)
- [Route 53 Failover Routing](https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-policy-failover.html)
- [Route 53 Application Recovery Controller](https://aws.amazon.com/blogs/networking-and-content-delivery/building-highly-resilient-applications-using-amazon-route-53-application-recovery-controller-part-2-multi-region-stack/)
- [Multi-Region Failover Strategies](https://aws.amazon.com/blogs/networking-and-content-delivery/manual-failover-and-failback-strategy-with-amazon-route53/)
