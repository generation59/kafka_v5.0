#!/bin/bash

# Получение сообщений из Yandex Cloud Kafka через kcat
# Использование: ./kcat_consumer.sh [topic] [offset]

BROKER="rc1a-v063i1touj4ue341.mdb.yandexcloud.net:9091"
TOPIC=${1:-"user-events"}
OFFSET=${2:-"beginning"}  # beginning, end, или конкретный offset
USERNAME="kafka_user"
PASSWORD="kafka_password"
SSL_CERT="/usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt"

echo "================================================"
echo "    Kafka Consumer (kcat)"
echo "================================================"
echo "Брокер: $BROKER"
echo "Топик: $TOPIC"
echo "Offset: $OFFSET"
echo "================================================"
echo "Нажмите Ctrl+C для выхода"
echo "================================================"

# Получаем сообщения
kcat -b $BROKER \
     -t $TOPIC \
     -C \
     -o $OFFSET \
     -f 'Partition: %p | Offset: %o | Timestamp: %T | Key: %k | Value: %s\n' \
     -X security.protocol=SASL_SSL \
     -X sasl.mechanism=SCRAM-SHA-512 \
     -X sasl.username="$USERNAME" \
     -X sasl.password="$PASSWORD" \
     -X ssl.ca.location="$SSL_CERT"

echo ""
echo "[INFO] Consumer завершен" 