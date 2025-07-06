#!/bin/bash

# ================================================================
# РУЧНОЕ СОЗДАНИЕ ТОПИКОВ KAFKA
# ================================================================

echo "================================================================"
echo "        СОЗДАНИЕ ТОПИКОВ KAFKA ВРУЧНУЮ"
echo "================================================================"

# Проверка что Kafka доступен
echo "🔍 Проверка доступности Kafka..."
if ! docker exec kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --list &>/dev/null; then
    echo "❌ Kafka недоступен! Убедитесь что контейнеры запущены."
    exit 1
fi

echo "✅ Kafka доступен"

# Создание топиков
echo ""
echo "📦 Создание топиков..."

echo "1. Создание топика user-events..."
docker exec kafka-broker-1 kafka-topics \
  --bootstrap-server localhost:9092 \
  --create \
  --if-not-exists \
  --topic user-events \
  --partitions 3 \
  --replication-factor 3 \
  --config cleanup.policy=delete \
  --config retention.ms=604800000 \
  --config compression.type=snappy \
  --config min.insync.replicas=2

echo "2. Создание топика processed-events..."
docker exec kafka-broker-1 kafka-topics \
  --bootstrap-server localhost:9092 \
  --create \
  --if-not-exists \
  --topic processed-events \
  --partitions 3 \
  --replication-factor 3 \
  --config cleanup.policy=delete \
  --config retention.ms=604800000 \
  --config compression.type=snappy \
  --config min.insync.replicas=2

echo "3. Создание топика analytics-events..."
docker exec kafka-broker-1 kafka-topics \
  --bootstrap-server localhost:9092 \
  --create \
  --if-not-exists \
  --topic analytics-events \
  --partitions 3 \
  --replication-factor 3 \
  --config cleanup.policy=delete \
  --config retention.ms=604800000 \
  --config compression.type=snappy \
  --config min.insync.replicas=2

echo "4. Создание топика purchase-events..."
docker exec kafka-broker-1 kafka-topics \
  --bootstrap-server localhost:9092 \
  --create \
  --if-not-exists \
  --topic purchase-events \
  --partitions 3 \
  --replication-factor 3 \
  --config cleanup.policy=delete \
  --config retention.ms=604800000 \
  --config compression.type=snappy \
  --config min.insync.replicas=2

echo "5. Создание топика error-events..."
docker exec kafka-broker-1 kafka-topics \
  --bootstrap-server localhost:9092 \
  --create \
  --if-not-exists \
  --topic error-events \
  --partitions 3 \
  --replication-factor 3 \
  --config cleanup.policy=delete \
  --config retention.ms=604800000 \
  --config compression.type=snappy \
  --config min.insync.replicas=2

echo ""
echo "✅ Все топики созданы!"

echo ""
echo "📋 Список созданных топиков:"
docker exec kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --list

echo ""
echo "📊 Детали топиков:"
for topic in user-events processed-events analytics-events purchase-events error-events; do
    echo ""
    echo "=== Топик: $topic ==="
    docker exec kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --describe --topic $topic
done

echo ""
echo "================================================================"
echo "        ТОПИКИ СОЗДАНЫ УСПЕШНО!"
echo "================================================================" 