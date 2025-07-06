#!/bin/bash

# Создание топика user-events в Yandex Cloud Kafka
# Используется kcat для создания топика

BROKER="rc1a-v063i1touj4ue341.mdb.yandexcloud.net:9091"
TOPIC="user-events"
USERNAME="kafka_user"
PASSWORD="kafka_password"
SSL_CERT="/usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt"

echo "================================================"
echo "    Создание топика user-events"
echo "================================================"

echo "[INFO] Создание топика: $TOPIC"
echo "[INFO] Брокер: $BROKER"

# Создаем топик с помощью kcat
kcat -b $BROKER \
     -X security.protocol=SASL_SSL \
     -X sasl.mechanism=SCRAM-SHA-512 \
     -X sasl.username="$USERNAME" \
     -X sasl.password="$PASSWORD" \
     -X ssl.ca.location="$SSL_CERT" \
     -L -t $TOPIC

echo ""
echo "[INFO] Отправка тестового сообщения для создания топика..."

# Отправляем тестовое сообщение (это создаст топик если его нет)
echo '{"userId": "test-user", "eventType": "test", "timestamp": "2024-01-01T00:00:00Z"}' | \
kcat -b $BROKER \
     -t $TOPIC \
     -X security.protocol=SASL_SSL \
     -X sasl.mechanism=SCRAM-SHA-512 \
     -X sasl.username="$USERNAME" \
     -X sasl.password="$PASSWORD" \
     -X ssl.ca.location="$SSL_CERT" \
     -P

echo ""
echo "[INFO] Проверка создания топика..."
kcat -b $BROKER \
     -X security.protocol=SASL_SSL \
     -X sasl.mechanism=SCRAM-SHA-512 \
     -X sasl.username="$USERNAME" \
     -X sasl.password="$PASSWORD" \
     -X ssl.ca.location="$SSL_CERT" \
     -L | grep $TOPIC

echo ""
echo "[INFO] Готово! Топик user-events создан." 