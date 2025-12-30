# MinIO Multi-DC Lab

## Scenario: N-Way Replication (3 Sites)

```
┌─────────┐     ┌─────────┐     ┌─────────┐
│  DC1    │◄───►│  DC2    │◄───►│  DC3    │
│  (R/W)  │     │  (R/W)  │     │  (R/W)  │
└─────────┘     └─────────┘     └─────────┘
     ▲                               ▲
     └───────────────────────────────┘
```

Uses **Site Replication** (`mc admin replicate add dc1 dc2 dc3`) which syncs:
- All buckets (auto-created on all sites)
- IAM users/policies
- Bucket policies & configurations

## Quick Start

```bash
# Deploy DC1, DC2, DC3
kubectl apply -f dc1.yaml
kubectl apply -f dc2.yaml
kubectl apply -f dc3.yaml

# Wait for pods
kubectl wait --for=condition=ready pod -l app=minio -n minio-dc1 --timeout=120s
kubectl wait --for=condition=ready pod -l app=minio -n minio-dc2 --timeout=120s
kubectl wait --for=condition=ready pod -l app=minio -n minio-dc3 --timeout=120s

# Setup 3-site replication
kubectl apply -f setup-replication.yaml
```

## Test Replication

```bash
# Create file on DC1, verify on DC2 and DC3
kubectl run mc --rm -it --restart=Never --image=quay.io/minio/mc -- sh -c '
  mc alias set dc1 http://minio.minio-dc1.svc:9000 minioadmin minioadmin123
  mc alias set dc2 http://minio.minio-dc2.svc:9000 minioadmin minioadmin123
  mc alias set dc3 http://minio.minio-dc3.svc:9000 minioadmin minioadmin123

  echo "hello from dc1" | mc pipe dc1/test-bucket/hello.txt
  sleep 5

  echo "=== DC2 ===" && mc cat dc2/test-bucket/hello.txt
  echo "=== DC3 ===" && mc cat dc3/test-bucket/hello.txt
'
```

## Real-World Use Cases

| Company | Pattern | Purpose |
|---------|---------|---------|
| Netflix | Multi-region | Video assets globally replicated |
| Spotify | Active-Active | Audio files served from nearest region |
| AWS S3 CRR | One-way/Two-way | Cross-Region Replication for DR |

## Cleanup

```bash
kubectl delete ns minio-dc1 minio-dc2 minio-dc3
```
