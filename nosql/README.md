# NoSQL Multi-Region

**Distributed NoSQL databases with multi-datacenter replication**

> **Managed**: AWS DynamoDB Global Tables → **Self-hosted**: Apache Cassandra (multi-DC is free, core feature)

---

## Overview

NoSQL databases with native multi-region support for high availability and low latency across datacenters.

```
┌───────────────────┐     ┌───────────────────┐     ┌───────────────────┐
│     Region 1      │     │     Region 2      │     │     Region 3      │
│                   │     │                   │     │                   │
│   NoSQL Cluster   │◄───►│   NoSQL Cluster   │◄───►│   NoSQL Cluster   │
│                   │     │                   │     │                   │
└───────────────────┘     └───────────────────┘     └───────────────────┘
                              Replication
```

---

## Multi-Region Support Comparison

| Database | Multi-DC Free? | Managed | Self-hosted |
|----------|----------------|---------|-------------|
| **Cassandra** | Yes (core feature) | DataStax Astra | Apache Cassandra |
| **ScyllaDB** | Yes | ScyllaDB Cloud | ScyllaDB OSS |
| **CouchDB** | Yes | Cloudant | Apache CouchDB |
| Elasticsearch | No (X-Pack paid) | Elastic Cloud | Limited |
| MongoDB | No (Atlas only) | MongoDB Atlas | Limited |

---

## AWS DynamoDB Global Tables

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   DynamoDB Global Tables                        │
│                                                                 │
│   ┌─────────────────┐              ┌─────────────────┐          │
│   │   us-east-1     │   async      │   eu-west-1     │          │
│   │                 │◄────────────►│                 │          │
│   │  ┌───────────┐  │  <1s lag     │  ┌───────────┐  │          │
│   │  │  Table    │  │              │  │  Replica  │  │          │
│   │  │  Replica  │  │              │  │  Table    │  │          │
│   │  └───────────┘  │              │  └───────────┘  │          │
│   └─────────────────┘              └─────────────────┘          │
│                                                                 │
│            Active-Active (read/write anywhere)                  │
└─────────────────────────────────────────────────────────────────┘
```

### Key Features
- **Active-Active**: Read/write in any region
- **Replication**: Async, typically <1 second
- **Conflict resolution**: Last-writer-wins
- **Consistency**: Eventually consistent (cross-region)

### Setup
```bash
# Create global table via AWS CLI
aws dynamodb create-table \
  --table-name MyGlobalTable \
  --attribute-definitions AttributeName=pk,AttributeType=S \
  --key-schema AttributeName=pk,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --stream-specification StreamEnabled=true,StreamViewType=NEW_AND_OLD_IMAGES

# Add replica in another region
aws dynamodb update-table \
  --table-name MyGlobalTable \
  --replica-updates 'Create={RegionName=eu-west-1}'
```

---

## Apache Cassandra (Self-hosted)

### Why Cassandra?
- Multi-DC replication is **core feature** (not paid add-on)
- No single point of failure
- Linear scalability
- Used by Netflix, Apple, Discord

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Cassandra Cluster                           │
│                                                                 │
│   DC1 (us-east)              DC2 (eu-west)                     │
│   ┌─────────────┐            ┌─────────────┐                   │
│   │ ┌───┐ ┌───┐ │            │ ┌───┐ ┌───┐ │                   │
│   │ │N1 │ │N2 │ │◄──────────►│ │N1 │ │N2 │ │                   │
│   │ └───┘ └───┘ │  async     │ └───┘ └───┘ │                   │
│   │ ┌───┐ ┌───┐ │            │ ┌───┐ ┌───┐ │                   │
│   │ │N3 │ │N4 │ │            │ │N3 │ │N4 │ │                   │
│   │ └───┘ └───┘ │            │ └───┘ └───┘ │                   │
│   └─────────────┘            └─────────────┘                   │
│                                                                 │
│              Ring topology, no master node                      │
└─────────────────────────────────────────────────────────────────┘
```

### Multi-DC Configuration

```yaml
# cassandra.yaml
cluster_name: 'MyCluster'
num_tokens: 256
seed_provider:
  - class_name: org.apache.cassandra.locator.SimpleSeedProvider
    parameters:
      - seeds: "10.0.1.1,10.0.2.1"  # Seeds from each DC

endpoint_snitch: GossipingPropertyFileSnitch

# cassandra-rackdc.properties (per node)
dc=us-east
rack=rack1
```

### Replication Strategy

```cql
-- Create keyspace with multi-DC replication
CREATE KEYSPACE myapp WITH replication = {
  'class': 'NetworkTopologyStrategy',
  'us-east': 3,    -- 3 replicas in us-east
  'eu-west': 3     -- 3 replicas in eu-west
};

-- Use keyspace
USE myapp;

-- Create table
CREATE TABLE users (
  user_id UUID PRIMARY KEY,
  name TEXT,
  email TEXT
);
```

### Consistency Levels

| Level | Description | Use Case |
|-------|-------------|----------|
| `LOCAL_ONE` | 1 replica in local DC | Fastest, lowest consistency |
| `LOCAL_QUORUM` | Majority in local DC | Good balance |
| `EACH_QUORUM` | Majority in each DC | Strong, high latency |
| `ALL` | All replicas | Strongest, highest latency |

```cql
-- Read with local quorum
CONSISTENCY LOCAL_QUORUM;
SELECT * FROM users WHERE user_id = ?;

-- Write with each quorum (ensure all DCs have data)
CONSISTENCY EACH_QUORUM;
INSERT INTO users (user_id, name) VALUES (?, ?);
```

### Quick Start (Docker)

```bash
# Start 2-DC cluster locally
docker network create cassandra-net

# DC1 nodes
docker run -d --name cass-dc1-n1 --network cassandra-net \
  -e CASSANDRA_CLUSTER_NAME=MyCluster \
  -e CASSANDRA_DC=dc1 \
  -e CASSANDRA_RACK=rack1 \
  -e CASSANDRA_ENDPOINT_SNITCH=GossipingPropertyFileSnitch \
  cassandra:4.1

# DC2 nodes (after DC1 is up)
docker run -d --name cass-dc2-n1 --network cassandra-net \
  -e CASSANDRA_CLUSTER_NAME=MyCluster \
  -e CASSANDRA_DC=dc2 \
  -e CASSANDRA_RACK=rack1 \
  -e CASSANDRA_SEEDS=cass-dc1-n1 \
  -e CASSANDRA_ENDPOINT_SNITCH=GossipingPropertyFileSnitch \
  cassandra:4.1

# Connect
docker exec -it cass-dc1-n1 cqlsh
```

---

## Multi-Region Patterns

### Pattern 1: Active-Active

```
┌─────────────────┐              ┌─────────────────┐
│    DC1          │◄────────────►│    DC2          │
│  (Read/Write)   │    async     │  (Read/Write)   │
└─────────────────┘              └─────────────────┘
```

- Both DCs accept reads/writes
- Conflict resolution: last-write-wins (timestamp)
- Use `LOCAL_QUORUM` for low latency

### Pattern 2: Active-Passive

```
┌─────────────────┐              ┌─────────────────┐
│    DC1          │─────────────►│    DC2          │
│  (Read/Write)   │    async     │  (Read only)    │
└─────────────────┘              └─────────────────┘
```

- DC1 handles writes
- DC2 for disaster recovery
- Simpler conflict handling

### Pattern 3: Geo-Local Writes

```
US Users ──► DC1 (US) ──writes──► user_us table
EU Users ──► DC2 (EU) ──writes──► user_eu table
                 │
                 └──► Replicate for reads
```

- Partition data by geography
- Each DC owns its data
- No write conflicts

---

## Comparison: DynamoDB vs Cassandra

| Aspect | DynamoDB Global | Cassandra |
|--------|-----------------|-----------|
| Managed | Yes (AWS) | Self-hosted |
| Multi-region | Built-in | Core feature |
| Consistency | Eventually | Tunable |
| Conflict resolution | Last-writer-wins | Last-writer-wins |
| Query language | API-based | CQL (SQL-like) |
| Cost | Per-request | Infrastructure |
| Vendor lock-in | AWS | None |

---

## Best Practices

1. **Use LOCAL_QUORUM for most operations**
   - Good consistency within DC
   - Low latency

2. **Design for eventual consistency**
   - Avoid read-after-write across DCs
   - Use idempotent operations

3. **Plan data modeling**
   - Denormalize for query patterns
   - Partition key affects distribution

4. **Monitor replication lag**
   - Track cross-DC latency
   - Alert on high lag

5. **Test DC failure**
   - Simulate DC outage
   - Verify automatic failover

---

## References

- [DynamoDB Global Tables](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/GlobalTables.html)
- [Cassandra Multi-DC](https://cassandra.apache.org/doc/latest/cassandra/architecture/dynamo.html)
- [Cassandra Consistency Levels](https://docs.datastax.com/en/cassandra-oss/3.x/cassandra/dml/dmlConfigConsistency.html)
- [ScyllaDB Multi-DC](https://docs.scylladb.com/stable/operating-scylla/procedures/cluster-management/create-cluster-multidc.html)
