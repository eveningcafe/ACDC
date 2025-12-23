# Setting

```shell
PUT /_cluster/settings
{
   "persistent" : {
  "xpack.monitoring.collection.enabled": false
   }
}
PUT /some-index*/_settings
{
  "index.search.slowlog.threshold.query.trace": "0ms",
  "index.search.slowlog.threshold.fetch.trace": "0ms",
  "index.search.slowlog.level": "trace"
}

GET /_nodes/_all/settings

// get some setting, include_defaults
GET /energyip-logs-2023.05.16/_settings/index.search.slowlog.threshold.query.trace/?include_defaults
```

# Status incides

```shell
GET _cat/indices
```

# Excute search

```shell
GET static-website*/_search
{size: ...}
```