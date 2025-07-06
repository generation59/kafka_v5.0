#!/bin/bash

# Скрипт для сбора логов всех компонентов
# Создает отдельные файлы логов для отчета

echo "================================================================"
echo "        СБОР ЛОГОВ ДЛЯ ОТЧЕТА"
echo "================================================================"

LOG_DIR="logs"
mkdir -p "$LOG_DIR"

echo "📁 Создание директории логов: $LOG_DIR"

# 1. Логи Apache NiFi
echo "🔄 Сбор логов Apache NiFi..."
docker compose logs nifi --tail=100 > "$LOG_DIR/nifi_logs.txt" 2>&1
echo "✅ Логи NiFi сохранены в: $LOG_DIR/nifi_logs.txt"

# 2. Логи Python Producer
echo "🔄 Сбор логов Python Producer..."
echo "=== Python Producer Test Run ===" > "$LOG_DIR/producer_logs.txt"
echo "Timestamp: $(date)" >> "$LOG_DIR/producer_logs.txt"
echo "" >> "$LOG_DIR/producer_logs.txt"

# Запуск producer для генерации логов
cd python
if [ -d "venv" ]; then
    source venv/bin/activate
else
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
fi

# Запуск producer с автоматическими настройками
echo "1" | echo "5" | echo "" | python3 test_producer_confluent.py >> "../$LOG_DIR/producer_logs.txt" 2>&1
cd ..

echo "✅ Логи Producer сохранены в: $LOG_DIR/producer_logs.txt"

# 3. Логи Python Consumer
echo "🔄 Сбор логов Python Consumer..."
echo "=== Python Consumer Test Run ===" > "$LOG_DIR/consumer_logs.txt"
echo "Timestamp: $(date)" >> "$LOG_DIR/consumer_logs.txt"
echo "" >> "$LOG_DIR/consumer_logs.txt"

# Запуск consumer в фоне на 30 секунд
cd python
source venv/bin/activate
timeout 30s python3 test_consumer_confluent.py >> "../$LOG_DIR/consumer_logs.txt" 2>&1 &
CONSUMER_PID=$!

# Ждем немного чтобы consumer успел подключиться
sleep 5

# Отправляем еще несколько сообщений для демонстрации
echo "📤 Отправка дополнительных сообщений для демонстрации..."
echo "1" | echo "3" | echo "0.5" | python3 test_producer_confluent.py >> "../$LOG_DIR/producer_logs.txt" 2>&1

# Ждем завершения consumer
wait $CONSUMER_PID 2>/dev/null || true
cd ..

echo "✅ Логи Consumer сохранены в: $LOG_DIR/consumer_logs.txt"

# 4. Логи Kafka Console Consumer
echo "🔄 Сбор логов Kafka Console Consumer..."
echo "=== Kafka Console Consumer Output ===" > "$LOG_DIR/kafka_consumer_logs.txt"
echo "Timestamp: $(date)" >> "$LOG_DIR/kafka_consumer_logs.txt"
echo "" >> "$LOG_DIR/kafka_consumer_logs.txt"

echo "--- Messages from user-events topic ---" >> "$LOG_DIR/kafka_consumer_logs.txt"
timeout 10s docker compose exec -T kafka-broker-1 kafka-console-consumer --bootstrap-server localhost:9092 --topic user-events --from-beginning --max-messages 10 >> "$LOG_DIR/kafka_consumer_logs.txt" 2>&1 || true

echo "" >> "$LOG_DIR/kafka_consumer_logs.txt"
echo "--- Messages from processed-events topic ---" >> "$LOG_DIR/kafka_consumer_logs.txt"
timeout 10s docker compose exec -T kafka-broker-1 kafka-console-consumer --bootstrap-server localhost:9092 --topic processed-events --from-beginning --max-messages 10 >> "$LOG_DIR/kafka_consumer_logs.txt" 2>&1 || true

echo "✅ Логи Kafka Consumer сохранены в: $LOG_DIR/kafka_consumer_logs.txt"

# 5. Дополнительные системные логи
echo "🔄 Сбор дополнительных системных логов..."

# Логи брокеров Kafka
echo "=== Kafka Broker 1 Logs ===" > "$LOG_DIR/kafka_broker_logs.txt"
docker compose logs kafka-broker-1 --tail=50 >> "$LOG_DIR/kafka_broker_logs.txt" 2>&1

# Топики и их статус
echo "=== Kafka Topics Status ===" > "$LOG_DIR/kafka_topics_status.txt"
echo "Timestamp: $(date)" >> "$LOG_DIR/kafka_topics_status.txt"
echo "" >> "$LOG_DIR/kafka_topics_status.txt"

echo "--- Available Topics ---" >> "$LOG_DIR/kafka_topics_status.txt"
docker compose exec -T kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --list >> "$LOG_DIR/kafka_topics_status.txt" 2>&1

echo "" >> "$LOG_DIR/kafka_topics_status.txt"
echo "--- Topic Details: user-events ---" >> "$LOG_DIR/kafka_topics_status.txt"
docker compose exec -T kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --describe --topic user-events >> "$LOG_DIR/kafka_topics_status.txt" 2>&1

echo "" >> "$LOG_DIR/kafka_topics_status.txt"
echo "--- Topic Details: processed-events ---" >> "$LOG_DIR/kafka_topics_status.txt"
docker compose exec -T kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --describe --topic processed-events >> "$LOG_DIR/kafka_topics_status.txt" 2>&1

echo "✅ Системные логи сохранены"

# 6. Статус Docker контейнеров
echo "🔄 Сбор статуса Docker контейнеров..."
echo "=== Docker Compose Status ===" > "$LOG_DIR/docker_status.txt"
echo "Timestamp: $(date)" >> "$LOG_DIR/docker_status.txt"
echo "" >> "$LOG_DIR/docker_status.txt"

docker compose ps >> "$LOG_DIR/docker_status.txt" 2>&1

echo "✅ Статус Docker сохранен"

# Создание итогового отчета
echo "🔄 Создание итогового отчета..."
cat > "$LOG_DIR/README.md" << 'EOF'
# Логи интеграции Apache NiFi + Kafka

## Описание файлов

### Основные логи компонентов:
- `producer_logs.txt` - логи Python Producer (отправка сообщений)
- `consumer_logs.txt` - логи Python Consumer (получение обработанных сообщений)
- `nifi_logs.txt` - логи Apache NiFi (обработка потоков данных)
- `kafka_consumer_logs.txt` - логи Kafka Console Consumer (просмотр сообщений)

### Системные логи:
- `kafka_broker_logs.txt` - логи Kafka брокера
- `kafka_topics_status.txt` - статус топиков и их конфигурация
- `docker_status.txt` - статус Docker контейнеров

## Архитектура потока данных

```
Python Producer → user-events → NiFi Flow → processed-events → Python Consumer
```

## Демонстрируемые возможности

1. **Отправка сообщений**: Python Producer генерирует события пользователей
2. **Обработка в NiFi**: Apache NiFi читает события, добавляет метаданные и отправляет в другой топик
3. **Получение результатов**: Python Consumer читает обработанные события
4. **Мониторинг**: Kafka Console Consumer показывает содержимое топиков

## Ключевые особенности

- Использование confluent-kafka-python для совместимости с Python 3.12
- Автоматическое добавление метаданных обработки в NiFi
- Подробное логирование всех операций
- Мониторинг через веб-интерфейсы (Kafka UI, NiFi UI)
EOF

echo "✅ Итоговый отчет создан: $LOG_DIR/README.md"

echo ""
echo "================================================================"
echo "        СБОР ЛОГОВ ЗАВЕРШЕН"
echo "================================================================"
echo ""
echo "📁 Все логи сохранены в директории: $LOG_DIR"
echo ""
echo "📋 Созданные файлы:"
echo "   📄 producer_logs.txt - логи Python Producer"
echo "   📄 consumer_logs.txt - логи Python Consumer"
echo "   📄 nifi_logs.txt - логи Apache NiFi"
echo "   📄 kafka_consumer_logs.txt - логи Kafka Console Consumer"
echo "   📄 kafka_broker_logs.txt - логи Kafka брокера"
echo "   📄 kafka_topics_status.txt - статус топиков"
echo "   📄 docker_status.txt - статус контейнеров"
echo "   📄 README.md - описание логов"
echo ""
echo "🎯 Логи готовы для включения в отчет!" 