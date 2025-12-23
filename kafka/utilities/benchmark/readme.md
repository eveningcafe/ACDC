```shell
kubectl -n kafka run kafka-bench -ti --image=quay.io/strimzi/kafka:0.35.1-kafka-3.4.0 --rm=true --restart=Never --

## https://engineering.linkedin.com/kafka/benchmarking-apache-kafka-2-million-writes-second-three-cheap-machines

## Single-thread async
bin/kafka-run-class.sh org.apache.kafka.tools.ProducerPerformance test6 50000 100 -1 acks=1 bootstrap.servers=esv4-hcl198.grid.linkedin.com:9092 buffer.memory=67108864 batch.size=8196
# Single-thread, sync 
bin/kafka-run-class.sh org.apache.kafka.tools.ProducerPerformance test 50000 100 -1 acks=-1 bootstrap.servers=esv4-hcl198.grid.linkedin.com:9092 buffer.memory=67108864 batch.size=64000

## Three Producers, async 
bin/kafka-run-class.sh org.apache.kafka.tools.ProducerPerformance test 50000 100 -1 acks=1 bootstrap.servers=esv4-hcl198.grid.linkedin.com:9092 buffer.memory=67108864 batch.size=8196

```
```shell
# 1
kubectl -n active-active run kafka-bench1 -ti --image=quay.io/strimzi/kafka:0.35.1-kafka-3.4.0 --rm=true --restart=Never -- bin/kafka-run-class.sh org.apache.kafka.tools.ProducerPerformance --topic active-active --num-records 50000 --throughput 500 --record-size 8196 --producer-props bootstrap.servers=cluster-local-dc1-kafka-bootstrap:9092 
kubectl -n active-active run kafka-bench2 -ti --image=quay.io/strimzi/kafka:0.35.1-kafka-3.4.0 --rm=true --restart=Never -- bin/kafka-run-class.sh org.apache.kafka.tools.ProducerPerformance --topic active-active --num-records 50000 --throughput 500 --record-size 8196 --producer-props bootstrap.servers=cluster-local-dc2-kafka-bootstrap:9092
kubectl -n active-active run kafka-bench -ti --image=quay.io/strimzi/kafka:0.35.1-kafka-3.4.0 --rm=true --restart=Never -- bin/kafka-run-class.sh org.apache.kafka.tools.ProducerPerformance --topic active-active --num-records 50000 --throughput 500 --record-size 8196 --producer-props bootstrap.servers=cluster-local-dc1-kafka-bootstrap:9092,cluster-local-dc2-kafka-bootstrap:9092
# 2
kubectl -n active-passive run kafka-bench -ti --image=quay.io/strimzi/kafka:0.35.1-kafka-3.4.0 --rm=true --restart=Never -- bin/kafka-run-class.sh org.apache.kafka.tools.ProducerPerformance --topic active-passive --num-records 50000 --throughput 500 --record-size 8196 --producer-props bootstrap.servers=cluster-dc1-kafka-bootstrap:9092
bin/kafka-run-class.sh org.apache.kafka.tools.ProducerPerformance --topic dc1-static-website --num-records 50000 --throughput 500 --record-size 8196 --producer-props bootstrap.servers=cluster-dc1-kafka-bootstrap:9092 

kubectl -n active-active run kafka-bench -ti --image=quay.io/strimzi/kafka:0.35.1-kafka-3.4.0 --rm=true --restart=Never --

```
# note 
```shell
  --topic TOPIC          produce messages to this topic
  --num-records NUM-RECORDS
                         number of messages to produce
  --payload-delimiter PAYLOAD-DELIMITER
                         provides delimiter to be used when --payload-file is provided.  Defaults  to  new line. Note that this parameter will be
                         ignored if --payload-file is not provided. (default: \n)
  --throughput THROUGHPUT
                         throttle maximum message throughput to *approximately* THROUGHPUT messages/sec. Set this to -1 to disable throttling.
  --producer-props PROP-NAME=PROP-VALUE [PROP-NAME=PROP-VALUE ...]
                         kafka producer related configuration  properties  like  bootstrap.servers,client.id  etc.  These configs take precedence
                         over those passed via --producer.config.
  --producer.config CONFIG-FILE
                         producer config properties file.
  --print-metrics        print out metrics at the end of the test. (default: false)
  --transactional-id TRANSACTIONAL-ID
                         The transactionalId to use  if  transaction-duration-ms  is  >  0.  Useful  when  testing  the performance of concurrent
                         transactions. (default: performance-producer-default-transactional-id)
  --transaction-duration-ms TRANSACTION-DURATION
                         The max age of each transaction. The  commitTransaction  will  be  called  after this time has elapsed. Transactions are
                         only enabled if this value is positive. (default: 0)

  either --record-size or --payload-file must be specified but not both.

  --record-size RECORD-SIZE
                         message size in bytes. Note that you must provide exactly one of --record-size or --payload-file.
  --payload-file PAYLOAD-FILE
                         file to read the message payloads from. This works only  for  UTF-8  encoded text files. Payloads will be read from this
                         file and a payload will be randomly selected when sending  messages. Note that you must provide exactly one of --record-
                         size or --payload-file.

```
