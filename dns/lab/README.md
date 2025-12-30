# PowerDNS Multi-DC Lab

See **[../README.md](../README.md)** for full documentation.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Kubernetes Cluster                              │
│                                                                              │
│   DC1 (dns-dc1)                              DC2 (dns-dc2)                   │
│   ┌────────────────────────────┐            ┌────────────────────────────┐   │
│   │ powerdns pod               │            │ powerdns pod               │   │
│   │                            │            │                            │   │
│   │  ┌──────────────────────┐  │            │  ┌──────────────────────┐  │   │
│   │  │ dnsdist        :53   │  │            │  │ dnsdist        :53   │  │   │
│   │  │ pdns-auth      :5300 │  │            │  │ pdns-auth      :5300 │  │   │
│   │  │ pdns-recursor  :5301 │  │            │  │ pdns-recursor  :5301 │  │   │
│   │  │ lightning-stream     │  │            │  │ lightning-stream     │  │   │
│   │  └──────────┬───────────┘  │            │  └──────────┬───────────┘  │   │
│   │             │ LMDB sync    │            │             │ LMDB sync    │   │
│   │             ▼              │            │             ▼              │   │
│   │  ┌──────────────────────┐  │            │  ┌──────────────────────┐  │   │
│   │  │ minio         :9000  │◄─┼────────────┼─►│ minio         :9000  │  │   │
│   │  └──────────────────────┘  │ Site Repl  │  └──────────────────────┘  │   │
│   └────────────────────────────┘            └────────────────────────────┘   │
│                                                                              │
│   Query Flow:                                                                │
│   User → dnsdist:53 → pdns-auth (if zone exists)                            │
│                     → pdns-recursor → 8.8.8.8 (if zone not found)           │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Components

| Component | Purpose |
|-----------|---------|
| **dnsdist** | DNS load balancer (port 53) |
| **pdns-auth** | Authoritative DNS for your zones |
| **pdns-recursor** | Forwards unknown zones to 8.8.8.8 |
| **lightning-stream** | Syncs LMDB zones via MinIO S3 |
| **minio** | S3 storage for zone replication |

## File Structure

```
dns/lab/
├── powerdns/
│   ├── dc1.yaml           # Port 5353 setup
│   ├── dc2.yaml           # Port 5354 setup
│   ├── dc1-port53.yaml    # Standard port 53 (recommended)
│   └── dc2-port53.yaml
├── minio/
│   ├── dc1.yaml           # MinIO S3 for Lightning Stream
│   └── dc2.yaml
├── backend/
│   ├── dc1.yaml           # Test backend {"dc": "DC1"}
│   └── dc2.yaml
└── README.md
```

## Cleanup

```bash
kubectl delete ns dns-dc1 dns-dc2
```
