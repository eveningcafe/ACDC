# MinIO Multi-Site Replication

**S3-compatible object storage with active-active replication**

---

## Overview

MinIO supports multi-site active-active replication, allowing objects to be synchronized across multiple MinIO deployments. This feature is available in the **open-source version** (not enterprise-only).

```
┌─────────────────┐         ┌─────────────────┐
│   Site 1        │◄───────►│   Site 2        │
│   MinIO         │  async  │   MinIO         │
│                 │  sync   │                 │
└────────┬────────┘         └────────┬────────┘
         │                           │
         └─────────┬─────────────────┘
                   │
                   ▼
          ┌─────────────────┐
          │   Site 3        │
          │   MinIO         │
          └─────────────────┘
```

---

## Replication Modes

### 1. One-Way Replication (Source → Target)

```
┌─────────┐           ┌─────────┐
│ Source  │──────────►│ Target  │
│ (R/W)   │  replicate│ (R only)│
└─────────┘           └─────────┘
```

### 2. Two-Way Replication (Active-Active)

```
┌─────────┐           ┌─────────┐
│ Site 1  │◄─────────►│ Site 2  │
│ (R/W)   │ replicate │ (R/W)   │
└─────────┘           └─────────┘
```

### 3. Multi-Site Mesh (N-Way)

```
      Site 1
        ▲
       /│\
      / │ \
     ▼  │  ▼
Site 2◄─┼─►Site 3
        │
        ▼
      Site 4
```

All sites can read/write, changes propagate to all others.

---

## Key Features

| Feature | Supported |
|---------|-----------|
| Object replication | Yes |
| Delete replication | Yes |
| Delete markers | Yes |
| Existing objects | Yes (with resync) |
| Metadata changes | Yes |
| Versioning required | Yes |

---

## Requirements

### All Sites Must Have

```
┌─────────────────────────────────────────────────────────────┐
│  ✓ Same bucket name                                         │
│  ✓ Versioning enabled                                       │
│  ✓ Same object locking config (if used)                     │
│  ✓ Same encryption settings                                 │
│  ✓ Sufficient network bandwidth                             │
└─────────────────────────────────────────────────────────────┘
```

### Network Considerations

| Factor | Requirement |
|--------|-------------|
| Bandwidth | Must exceed replication throughput needs |
| Latency | Higher latency = slower replication |
| Bottleneck | Replication speed = slowest link in mesh |

---

## Setup Guide

### 1. Enable Versioning on All Sites

```bash
# Site 1
mc version enable site1/mybucket

# Site 2
mc version enable site2/mybucket

# Site 3
mc version enable site3/mybucket
```

### 2. Add Remote Targets

```bash
# On Site 1: add Site 2 as remote target
mc admin bucket remote add site1/mybucket \
   https://accesskey:secretkey@site2.example.com/mybucket \
   --service replication

# Returns ARN like: arn:minio:replication::xxxx:mybucket
```

### 3. Configure Replication Rules

```bash
# Enable replication from Site 1 to Site 2
mc replicate add site1/mybucket \
   --remote-bucket "arn:minio:replication::xxxx:mybucket" \
   --replicate "delete,delete-marker,existing-objects"
```

### 4. Repeat for All Direction Pairs

For active-active between Site 1 and Site 2:
```bash
# Site 1 → Site 2 (already done above)
# Site 2 → Site 1
mc admin bucket remote add site2/mybucket \
   https://accesskey:secretkey@site1.example.com/mybucket \
   --service replication

mc replicate add site2/mybucket \
   --remote-bucket "arn:minio:replication::yyyy:mybucket" \
   --replicate "delete,delete-marker,existing-objects"
```

---

## Replication Status

Objects have replication status in metadata:

| Status | Meaning |
|--------|---------|
| `PENDING` | Queued for replication |
| `COMPLETED` | Successfully replicated |
| `FAILED` | Replication failed |
| `REPLICA` | This is a replicated copy |

Check status:
```bash
mc stat site1/mybucket/myobject
```

---

## Architecture Patterns

### Pattern 1: DR (Active-Passive)

```
┌─────────────────┐         ┌─────────────────┐
│   Primary       │────────►│   DR Site       │
│   (Active)      │  async  │   (Standby)     │
│   R/W traffic   │         │   Warm standby  │
└─────────────────┘         └─────────────────┘
```

- Primary handles all traffic
- DR site receives replicated data
- Manual failover when needed

### Pattern 2: Active-Active (Two Sites)

```
┌─────────────────┐         ┌─────────────────┐
│   Site 1        │◄───────►│   Site 2        │
│   R/W traffic   │  async  │   R/W traffic   │
└─────────────────┘         └─────────────────┘
         ▲                           ▲
         │                           │
    Users in                    Users in
    Region 1                    Region 2
```

- Both sites accept writes
- Users connect to nearest site
- Eventual consistency between sites

### Pattern 3: Global Mesh

```
        ┌─────────┐
        │ US-East │
        └────┬────┘
             │
    ┌────────┼────────┐
    │        │        │
    ▼        ▼        ▼
┌──────┐ ┌──────┐ ┌──────┐
│EU    │ │US-   │ │Asia  │
│      │ │West  │ │      │
└──────┘ └──────┘ └──────┘
```

- All sites sync with each other
- Data available everywhere
- Highest complexity

---

## Conflict Resolution

MinIO uses **last-write-wins** based on object version timestamps:

```
Site 1: PUT object (t=100)
Site 2: PUT object (t=101)  ← This wins

Result: Site 2's version replicated to Site 1
```

**Important**: Ensure clock synchronization (NTP) across sites!

---

## Monitoring

### Check Replication Status

```bash
# Replication status for bucket
mc replicate status site1/mybucket

# List replication rules
mc replicate ls site1/mybucket

# Check remote target status
mc admin bucket remote ls site1/mybucket
```

### Metrics to Watch

| Metric | What it means |
|--------|---------------|
| Pending count | Objects waiting to replicate |
| Failed count | Objects that failed replication |
| Replication lag | Time between write and replication |
| Bandwidth usage | Network between sites |

---

## Trade-offs

| Aspect | Single Site | Multi-Site |
|--------|-------------|------------|
| Complexity | Simple | More setup |
| Availability | Zone-level | Region-level |
| Latency | Low | Eventually consistent |
| Cost | Lower | Network + storage costs |
| Consistency | Strong | Eventual |

---

## Best Practices

1. **Enable versioning first**
   - Required for replication
   - Can't disable after objects exist

2. **Match configurations across sites**
   - Same bucket settings
   - Same encryption
   - Same lifecycle policies

3. **Plan bandwidth**
   - Estimate replication throughput
   - Consider peak write loads

4. **Sync clocks (NTP)**
   - Critical for conflict resolution
   - Use same NTP source if possible

5. **Monitor replication lag**
   - Alert on high pending counts
   - Track failed replications

6. **Test failover**
   - Verify clients can switch sites
   - Test data consistency

---

## References

- [MinIO Multi-Site Active-Active Replication](https://blog.min.io/minio-multi-site-active-active-replication/)
- [MinIO Bucket Replication](https://min.io/docs/minio/linux/administration/bucket-replication.html)
- [mc replicate command](https://min.io/docs/minio/linux/reference/minio-mc/mc-replicate.html)
