#!/bin/bash

# Отправка сообщений в Yandex Cloud Kafka через kcat
# Использование: ./kcat_producer.sh [topic] [message]

BROKER="rc1a-v063i1touj4ue341.mdb.yandexcloud.net:9091"
TOPIC=${1:-"user-events"}
MESSAGE=${2:-'{"userId": "user-123", "eventType": "login", "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "metadata": {"source": "kcat-script"}}'}
USERNAME="kafka_user"
PASSWORD="kafka_password"
SSL_CERT="/usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt"

echo "================================================"
echo "    Kafka Producer (kcat)"
echo "================================================"
echo "Брокер: $BROKER"
echo "Топик: $TOPIC"
echo "Сообщение: $MESSAGE"
echo "================================================"

# Отправляем сообщение
echo "$MESSAGE" | kcat -b $BROKER \
     -t $TOPIC \
     -X security.protocol=SASL_SSL \
     -X sasl.mechanism=SCRAM-SHA-512 \
     -X sasl.username="$USERNAME" \
     -X sasl.password="$PASSWORD" \
     -X ssl.ca.location="$SSL_CERT" \
     -P

if [ $? -eq 0 ]; then
    echo "[INFO] Сообщение успешно отправлено ✓"
else
    echo "[ERROR] Ошибка отправки сообщения ✗"
fi

echo "================================================" 