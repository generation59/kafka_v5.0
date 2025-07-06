#!/bin/bash

# Быстрый сбор логов в отдельные файлы
echo "🔄 Сбор логов для отчета..."

# 1. Логи Apache NiFi
echo "📄 Создание nifi_logs.txt..."
docker compose logs nifi --tail=100 > nifi_logs.txt 2>&1

# 2. Логи Python Producer
echo "📄 Создание producer_logs.txt..."
echo "=== Python Producer Test Run ===" > producer_logs.txt
echo "Timestamp: $(date)" >> producer_logs.txt
echo "" >> producer_logs.txt

# Запуск producer для генерации логов
cd python
if [ -d "venv" ]; then
    source venv/bin/activate
else
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
fi

# Автоматический запуск producer (5 сообщений)
(echo "1"; echo "5"; echo "") | python3 test_producer_confluent.py >> "../producer_logs.txt" 2>&1
cd ..

# 3. Логи Python Consumer
echo "📄 Создание consumer_logs.txt..."
echo "=== Python Consumer Test Run ===" > consumer_logs.txt
echo "Timestamp: $(date)" >> consumer_logs.txt
echo "" >> consumer_logs.txt

# Запуск consumer на 20 секунд
cd python
source venv/bin/activate
timeout 20s python3 test_consumer_confluent.py >> "../consumer_logs.txt" 2>&1 &
CONSUMER_PID=$!

# Ждем 5 секунд для подключения consumer
sleep 5

# Отправляем еще сообщения для демонстрации
(echo "1"; echo "3"; echo "0.5") | python3 test_producer_confluent.py >> "../producer_logs.txt" 2>&1

# Ждем завершения consumer
wait $CONSUMER_PID 2>/dev/null || true
cd ..

# 4. Логи Kafka Console Consumer
echo "📄 Создание kafka_consumer_logs.txt..."
echo "=== Kafka Console Consumer Output ===" > kafka_consumer_logs.txt
echo "Timestamp: $(date)" >> kafka_consumer_logs.txt
echo "" >> kafka_consumer_logs.txt

echo "--- Messages from user-events topic ---" >> kafka_consumer_logs.txt
timeout 10s docker compose exec -T kafka-broker-1 kafka-console-consumer --bootstrap-server localhost:9092 --topic user-events --from-beginning --max-messages 10 >> kafka_consumer_logs.txt 2>&1 || true

echo "" >> kafka_consumer_logs.txt
echo "--- Messages from processed-events topic ---" >> kafka_consumer_logs.txt
timeout 10s docker compose exec -T kafka-broker-1 kafka-console-consumer --bootstrap-server localhost:9092 --topic processed-events --from-beginning --max-messages 10 >> kafka_consumer_logs.txt 2>&1 || true

echo ""
echo "✅ Логи созданы:"
echo "   📄 producer_logs.txt"
echo "   📄 consumer_logs.txt"
echo "   📄 nifi_logs.txt"
echo "   📄 kafka_consumer_logs.txt"
echo ""
echo "🎯 Готово для отчета!" 