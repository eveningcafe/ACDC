#!/bin/bash

user=$1
password=$2

## create keystore for user
/usr/java/jdk1.8.0_271-amd64/bin/keytool -genkey -keystore ${user}.key -alias ${user} -dname CN=${user} -keyalg RSA -validity 3650 -storepass ${password}
/usr/java/jdk1.8.0_271-amd64/bin/keytool -certreq -keystore ${user}.key -alias ${user} -file ${user}.unsigned.crt -storepass ${password}
openssl x509 -req -CA /opt/kafka/ssl/ca.crt -CAkey /opt/kafka/ssl/ca.key -in ${user}.unsigned.crt -out ${user}.crt -days 3650 -CAcreateserial -passin pass:Jeyp8upeB3KUziCD
/usr/java/jdk1.8.0_271-amd64/bin/keytool -import -file /opt/kafka/ssl/ca.crt -keystore ${user}.key -alias ca -storepass ${password} -noprompt
/usr/java/jdk1.8.0_271-amd64/bin/keytool -import -file ${user}.crt -keystore ${user}.key -alias ${user} -storepass ${password} -noprompt
rm -f ${user}.crt ${user}.unsigned.crt
