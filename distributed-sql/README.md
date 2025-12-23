# Distributed SQL Multi-Region

**Globally distributed databases with multi-region replication**

> **Managed**: AWS Aurora Global → **Self-hosted**: TiDB (for learning, MySQL compatible)

---

## Overview

Distributed SQL databases provide ACID transactions across multiple regions with automatic failover and data locality.

```
┌─────────────────────────────────────────────────────────────────┐
│                   Distributed SQL Cluster                       │
│                                                                 │
│   ┌───────────┐      ┌───────────┐      ┌───────────┐          │
│   │  Region 1 │◄────►│  Region 2 │◄────►│  Region 3 │          │
│   │  (nodes)  │      │  (nodes)  │      │  (nodes)  │          │
│   └───────────┘      └───────────┘      └───────────┘          │
│         │                  │                  │                 │
│         └──────────────────┴──────────────────┘                 │
│                    Replication                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Options Comparison

| Solution | Managed | Self-hosted | Compatibility | Protocol |
|----------|---------|-------------|---------------|----------|
| Aurora Global | AWS | ✗ | MySQL/PostgreSQL | Proprietary |
| TiDB | TiDB Cloud | TiDB OSS | MySQL | Raft |
| CockroachDB | Cockroach Cloud | CockroachDB OSS | PostgreSQL | Raft |
| YugabyteDB | Yugabyte Cloud | YugabyteDB OSS | PostgreSQL | Raft |
| Cloud Spanner | GCP | ✗ | PostgreSQL-like | TrueTime |

---

## AWS Aurora Global Database

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Aurora Global Database                       │
│                                                                 │
│   ┌─────────────────┐              ┌─────────────────┐          │
│   │  Primary Region │   async      │ Secondary Region│          │
│   │   (us-east-1)   │ ──────────►  │   (eu-west-1)   │          │
│   │                 │  <1s lag     │                 │          │
│   │  ┌───────────┐  │              │  ┌───────────┐  │          │
│   │  │  Writer   │  │              │  │  Reader   │  │          │
│   │  │ Instance  │  │              │  │ Instances │  │          │
│   │  └───────────┘  │              │  └───────────┘  │          │
│   │  ┌───────────┐  │              │  ┌───────────┐  │          │
│   │  │  Reader   │  │              │  │  Storage  │  │          │
│   │  │ Instances │  │              │  │  (copy)   │  │          │
│   │  └───────────┘  │              │  └───────────┘  │          │
│   └─────────────────┘              └─────────────────┘          │
└─────────────────────────────────────────────────────────────────┘
```

### Key Features
- **Replication lag**: <1 second typical
- **Failover**: Promote secondary to primary (~1 minute)
- **Read scaling**: Read from any region
- **Write**: Single primary region only

### Failover
```
Normal:
  Primary (us-east-1) ──async──► Secondary (eu-west-1)
        ▲
     Writes

Failover:
  1. Detect primary failure
  2. Promote secondary to primary (~1 min)
  3. Update application endpoints
```

---

## TiDB (Self-hosted for Learning)

### Why TiDB?
- MySQL compatible (familiar syntax)
- Horizontal scaling
- Strong consistency (Raft)
- Open source, active community

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        TiDB Cluster                             │
│                                                                 │
│   ┌─────────┐  ┌─────────┐  ┌─────────┐                        │
│   │  TiDB   │  │  TiDB   │  │  TiDB   │   SQL Layer            │
│   │ Server  │  │ Server  │  │ Server  │   (stateless)          │
│   └────┬────┘  └────┬────┘  └────┬────┘                        │
│        │            │            │                              │
│        └────────────┼────────────┘                              │
│                     │                                           │
│   ┌─────────────────▼─────────────────┐                        │
│   │              PD Cluster           │   Placement Driver     │
│   │   (scheduling, timestamp oracle)  │   (metadata)           │
│   └─────────────────┬─────────────────┘                        │
│                     │                                           │
│   ┌─────────┬───────┼───────┬─────────┐                        │
│   │         │       │       │         │                        │
│   ▼         ▼       ▼       ▼         ▼                        │
│ ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐  Storage Layer    │
│ │TiKV │  │TiKV │  │TiKV │  │TiKV │  │TiKV │  (Raft groups)    │
│ └─────┘  └─────┘  └─────┘  └─────┘  └─────┘                    │
└─────────────────────────────────────────────────────────────────┘
```

### Multi-Region Setup

```
┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│     Region 1      │     │     Region 2      │     │     Region 3      │
│    (us-east-1)    │     │    (us-west-2)    │     │    (eu-west-1)    │
│                   │     │                   │     │                   │
│  TiDB + TiKV + PD │◄───►│  TiDB + TiKV + PD │◄───►│  TiDB + TiKV + PD │
│                   │     │                   │     │                   │
└───────────────────┘     └───────────────────┘     └───────────────────┘
                              Raft Replication
```

### Placement Rules (Data Locality)

```sql
-- Place data for EU users in EU region
CREATE PLACEMENT POLICY eu_policy
  PRIMARY_REGION="eu-west-1"
  REGIONS="eu-west-1,us-east-1,us-west-2";

-- Apply to table
ALTER TABLE eu_users PLACEMENT POLICY eu_policy;
```

### Quick Start (Docker)

```bash
# Start TiDB cluster locally
curl --proto '=https' --tlsv1.2 -sSf https://tiup-mirrors.pingcap.com/install.sh | sh
tiup playground --tag multi-region \
  --pd 3 \
  --tikv 3 \
  --tidb 2

# Connect with MySQL client
mysql -h 127.0.0.1 -P 4000 -u root
```

---

## Multi-Region Patterns

### Pattern 1: Single Writer, Multi-Reader

```
         Writes
            │
            ▼
┌─────────────────┐              ┌─────────────────┐
│  Primary Region │   async      │ Secondary Region│
│     (Writer)    │ ──────────►  │    (Reader)     │
└─────────────────┘              └─────────────────┘
                                        │
                                        ▼
                                    Local Reads
```

- **Aurora Global**: Native support
- **TiDB**: Use follower-read or placement rules
- **Trade-off**: Simple, but writes have single point

### Pattern 2: Multi-Writer (Active-Active)

```
┌─────────────────┐              ┌─────────────────┐
│    Region 1     │◄────────────►│    Region 2     │
│  (Read/Write)   │    sync      │  (Read/Write)   │
└─────────────────┘              └─────────────────┘
```

- **TiDB/CockroachDB**: Supported with Raft
- **Aurora**: Not supported (single writer)
- **Trade-off**: Higher latency for consistency

### Pattern 3: Geo-Partitioned

```
EU Users ──► EU Region (EU data lives here)
US Users ──► US Region (US data lives here)
Asia Users ──► Asia Region (Asia data lives here)
```

- Data stays in user's region
- Low latency for local operations
- Compliance friendly (data residency)

---

## Comparison: Aurora vs TiDB

| Aspect | Aurora Global | TiDB |
|--------|---------------|------|
| Managed | Yes (AWS) | Self-hosted or TiDB Cloud |
| Multi-writer | No | Yes |
| Replication | Async (<1s) | Sync (Raft) |
| Consistency | Eventual (cross-region) | Strong |
| Failover | ~1 minute | Automatic (Raft) |
| Compatibility | MySQL/PostgreSQL | MySQL |
| Vendor lock-in | AWS | None |

---

## Best Practices

1. **Choose based on write pattern**
   - Single writer → Aurora Global (simpler)
   - Multi-writer → TiDB/CockroachDB

2. **Plan data locality**
   - Keep data close to users
   - Use placement policies

3. **Understand consistency trade-offs**
   - Sync replication = higher latency
   - Async replication = possible data loss

4. **Test failover**
   - Automate failover procedures
   - Measure RTO/RPO

5. **Monitor replication lag**
   - Alert on high lag
   - Track cross-region latency

---

## References

- [Aurora Global Database](https://docs.aws.amazon.com/AmazonRDS/latest/AuroraUserGuide/aurora-global-database.html)
- [TiDB Multi-Region](https://docs.pingcap.com/tidb/stable/multi-data-centers-in-one-city-deployment)
- [TiDB Placement Rules](https://docs.pingcap.com/tidb/stable/placement-rules-in-sql)
- [CockroachDB Multi-Region](https://www.cockroachlabs.com/docs/stable/multiregion-overview)
