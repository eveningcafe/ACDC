# CockroachDB Multi-Region

**Distributed SQL database with native multi-region support**

> **Managed**: CockroachDB Cloud → **Self-hosted**: CockroachDB OSS (same features, for learning)

---

## Overview

CockroachDB is a distributed SQL database that provides native multi-region capabilities. Unlike traditional databases that require external replication tools, CockroachDB handles cross-region data distribution using SQL statements.

```
┌─────────────────────────────────────────────────────────────────┐
│                     CockroachDB Cluster                         │
│                                                                 │
│   ┌───────────┐      ┌───────────┐      ┌───────────┐          │
│   │  Region 1 │◄────►│  Region 2 │◄────►│  Region 3 │          │
│   │  (nodes)  │      │  (nodes)  │      │  (nodes)  │          │
│   └───────────┘      └───────────┘      └───────────┘          │
│         │                  │                  │                 │
│         └──────────────────┴──────────────────┘                 │
│                    Raft Consensus                               │
└─────────────────────────────────────────────────────────────────┘
```

**Key Benefit**: Multi-region is configured via SQL, not infrastructure.

---

## Core Concepts

### Cluster Region
Geographic region specified at node startup:
```bash
cockroach start --locality=region=us-east-1,zone=us-east-1a
```

### Database Region
Regions where a database operates:
```sql
ALTER DATABASE mydb PRIMARY REGION "us-east-1";
ALTER DATABASE mydb ADD REGION "us-west-2";
ALTER DATABASE mydb ADD REGION "eu-west-1";
```

### Survival Goals
How many failures the database can survive:

| Goal | Requirement | Survives |
|------|-------------|----------|
| `ZONE` (default) | 3+ zones in 1 region | Single zone failure |
| `REGION` | 3+ regions | Entire region failure |

```sql
-- Survive zone failure (default)
ALTER DATABASE mydb SURVIVE ZONE FAILURE;

-- Survive region failure
ALTER DATABASE mydb SURVIVE REGION FAILURE;
```

---

## Table Locality Patterns

### 1. REGIONAL BY TABLE (Default)

All data optimized for one region. Best for region-specific data.

```sql
-- Table optimized for us-east-1
ALTER TABLE users SET LOCALITY REGIONAL BY TABLE IN "us-east-1";
```

```
us-east-1          us-west-2          eu-west-1
┌─────────┐        ┌─────────┐        ┌─────────┐
│ ★ Data  │◄──────►│ Replica │◄──────►│ Replica │
│ (Lease) │        │         │        │         │
└─────────┘        └─────────┘        └─────────┘
     │
Fast reads/writes
```

**Use when**: Data belongs to a specific region (e.g., EU customers in EU region)

### 2. REGIONAL BY ROW

Different rows optimized for different regions. CockroachDB adds a hidden `crdb_region` column.

```sql
ALTER TABLE orders SET LOCALITY REGIONAL BY ROW;

-- Insert automatically uses node's region, or specify:
INSERT INTO orders (id, customer, crdb_region)
VALUES (1, 'Alice', 'us-east-1');
```

```
us-east-1          us-west-2          eu-west-1
┌─────────┐        ┌─────────┐        ┌─────────┐
│ Row 1 ★ │        │ Row 2 ★ │        │ Row 3 ★ │
│ Row 4   │        │ Row 5   │        │ Row 6   │
└─────────┘        └─────────┘        └─────────┘
```

**Use when**: Data access patterns vary by row (e.g., user data accessed from user's region)

### 3. GLOBAL

Optimized for low-latency reads from any region. Writes are slower.

```sql
ALTER TABLE config SET LOCALITY GLOBAL;
```

```
us-east-1          us-west-2          eu-west-1
┌─────────┐        ┌─────────┐        ┌─────────┐
│ ★ Full  │        │ ★ Full  │        │ ★ Full  │
│  Copy   │        │  Copy   │        │  Copy   │
└─────────┘        └─────────┘        └─────────┘
     │                  │                  │
     └──── Fast reads from anywhere ──────┘
```

**Use when**: Reference data, config, read-heavy lookup tables

---

## Locality Comparison

| Locality | Read Latency | Write Latency | Use Case |
|----------|--------------|---------------|----------|
| REGIONAL BY TABLE | Low (in region) | Low (in region) | Region-specific data |
| REGIONAL BY ROW | Low (from row's region) | Low (to row's region) | Per-user/per-tenant data |
| GLOBAL | Low (everywhere) | High (consensus needed) | Reference data, configs |

---

## Survival Goals Deep Dive

### ZONE Survival (Default)

```
Region: us-east-1
┌─────────┐  ┌─────────┐  ┌─────────┐
│ Zone A  │  │ Zone B  │  │ Zone C  │
│  Node1  │  │  Node2  │  │  Node3  │
│ Replica │  │ Replica │  │ Replica │
└─────────┘  └─────────┘  └─────────┘
      ▲
  Zone A fails?
  Still operational!
```

- 3 replicas across zones
- Survives 1 zone failure
- Lower latency (all in same region)

### REGION Survival

```
┌─────────┐      ┌─────────┐      ┌─────────┐
│us-east-1│      │us-west-2│      │eu-west-1│
│ 2 nodes │      │ 2 nodes │      │ 1 node  │
│2 replica│      │2 replica│      │1 replica│
└─────────┘      └─────────┘      └─────────┘
      ▲
  Region fails?
  Still operational!
```

- 5 replicas (2 in primary, rest distributed)
- Survives entire region failure
- Requires 3+ regions
- Higher write latency (cross-region consensus)

---

## Setup Example

### 1. Start Nodes with Locality

```bash
# Region 1
cockroach start --locality=region=us-east-1,zone=us-east-1a ...
cockroach start --locality=region=us-east-1,zone=us-east-1b ...

# Region 2
cockroach start --locality=region=us-west-2,zone=us-west-2a ...
cockroach start --locality=region=us-west-2,zone=us-west-2b ...

# Region 3
cockroach start --locality=region=eu-west-1,zone=eu-west-1a ...
```

### 2. Configure Database

```sql
-- Create multi-region database
CREATE DATABASE myapp PRIMARY REGION "us-east-1";
ALTER DATABASE myapp ADD REGION "us-west-2";
ALTER DATABASE myapp ADD REGION "eu-west-1";

-- Enable region survival
ALTER DATABASE myapp SURVIVE REGION FAILURE;
```

### 3. Configure Tables

```sql
-- User data: regional by row (users access from their region)
CREATE TABLE users (
    id UUID PRIMARY KEY,
    email STRING,
    region crdb_internal_region
) LOCALITY REGIONAL BY ROW;

-- Config: global (read from anywhere)
CREATE TABLE config (
    key STRING PRIMARY KEY,
    value STRING
) LOCALITY GLOBAL;

-- Orders: regional by row (accessed from customer's region)
CREATE TABLE orders (
    id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    total DECIMAL
) LOCALITY REGIONAL BY ROW;
```

---

## Trade-offs

| Aspect | Single Region | Multi-Region |
|--------|---------------|--------------|
| Latency | Low | Higher (cross-region) |
| Availability | Zone survival | Region survival |
| Complexity | Simple | More planning needed |
| Cost | Lower | Higher (network, nodes) |

---

## Best Practices

1. **Start with locality planning**
   - Which data needs to be where?
   - What are the access patterns?

2. **Use REGIONAL BY ROW for user data**
   - Data follows user location
   - Low latency for user operations

3. **Use GLOBAL sparingly**
   - Only for read-heavy reference data
   - Writes are expensive

4. **Plan for 3+ regions for REGION survival**
   - Can't survive region failure with only 2 regions

5. **Monitor cross-region latency**
   - Use CockroachDB console
   - Track p99 latencies

---

## References

- [Multi-Region Capabilities Overview](https://www.cockroachlabs.com/docs/stable/multiregion-overview)
- [Choosing a Multi-Region Configuration](https://www.cockroachlabs.com/docs/stable/choosing-a-multi-region-configuration.html)
- [Multi-Region Topology Patterns](https://www.cockroachlabs.com/blog/multi-region-topology-patterns/)
- [Survive Region Outages](https://www.cockroachlabs.com/blog/under-the-hood-multi-region/)
