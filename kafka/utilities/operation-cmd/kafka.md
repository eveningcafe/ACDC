
Produce consumer: 

Exec to kafka pod and run

```shell
cd bin 

./kafka-topics.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --list

./kafka-acls --bootstrap-server my-cluster-kafka-bootstrap:9092 --list

./bin/kafka-console-producer.sh --broker-list my-cluster-kafka-bootstrap:9092 --topic my-topic

./bin/kafka-console-consumer.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic my-topic --from-beginning

```

Uninstall

```shell
helm -n kafka ls

helm -n kafka uninstall my-release

```