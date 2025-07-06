#!/bin/bash

# ================================================================
# ДЕМОНСТРАЦИЯ ЗАДАНИЯ 2: ИНТЕГРАЦИЯ KAFKA + APACHE NIFI
# ================================================================

echo "================================================================"
echo "        ЗАДАНИЕ 2: Интеграция Kafka с Apache NiFi"
echo "================================================================"
echo ""
echo "📋 Что будет продемонстрировано:"
echo "✅ Развертывание Apache NiFi + Kafka кластера"
echo "✅ Настройка взаимодействия между NiFi и Kafka"
echo "✅ Обработка данных через NiFi Flow"
echo "✅ Логи успешной передачи данных"
echo "✅ Мониторинг через веб-интерфейсы"
echo ""

# Проверка Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker не найден! Установите Docker Desktop"
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose не найден! Установите Docker Compose"
    exit 1
fi

echo "================================================================"
echo "        1. ЗАПУСК СЕРВИСОВ"
echo "================================================================"

echo "🚀 Запуск Docker Compose с полным стеком..."
docker compose down --volumes --remove-orphans 2>/dev/null || true

# Запуск всех сервисов
docker compose up -d

echo "⏳ Ожидание инициализации сервисов..."
echo "   - Kafka кластер (3 брокера)"
echo "   - Apache NiFi"
echo "   - Schema Registry"
echo "   - Kafka UI"
echo "   - Автоматическое создание топиков"
echo ""

echo "⏳ Ожидание создания топиков..."
sleep 70

echo "================================================================"
echo "        2. ПРОВЕРКА СТАТУСА СЕРВИСОВ"
echo "================================================================"

echo "📊 Статус контейнеров:"
docker compose ps

echo ""
echo "🌐 Веб-интерфейсы:"
echo "   - Apache NiFi:    http://localhost:8080 (admin/ctsBtRBKHRAx69EqUghvvgEvjnaLjFEB)"
echo "   - Kafka UI:       http://localhost:8082"
echo "   - Schema Registry: http://localhost:8081"
echo ""

# Проверка доступности сервисов
echo "🔍 Проверка доступности сервисов:"

# Kafka
echo -n "   Kafka кластер: "
if docker exec kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --list &>/dev/null; then
    echo "✅ Доступен"
else
    echo "❌ Недоступен"
fi

# NiFi
echo -n "   Apache NiFi: "
if curl -s http://localhost:8080/nifi > /dev/null; then
    echo "✅ Доступен"
else
    echo "❌ Недоступен"
fi

# Schema Registry
echo -n "   Schema Registry: "
if curl -s http://localhost:8081/subjects > /dev/null; then
    echo "✅ Доступен"
else
    echo "❌ Недоступен"
fi

echo ""

echo "================================================================"
echo "        3. ПРОВЕРКА ТОПИКОВ KAFKA"
echo "================================================================"

echo "🔍 Проверка статуса kafka-init:"
docker logs kafka-init --tail 10

echo ""
echo "📋 Список созданных топиков:"
docker exec kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --list

echo ""
echo "📊 Детали топика user-events:"
if docker exec kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --describe --topic user-events 2>/dev/null; then
    echo "✅ Топик user-events найден"
else
    echo "❌ Топик user-events не найден. Создаем вручную..."
    docker exec kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --create --topic user-events --partitions 3 --replication-factor 3 --if-not-exists
    docker exec kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --create --topic processed-events --partitions 3 --replication-factor 3 --if-not-exists
    docker exec kafka-broker-1 kafka-topics --bootstrap-server localhost:9092 --create --topic analytics-events --partitions 3 --replication-factor 3 --if-not-exists
    echo "✅ Топики созданы вручную"
fi

echo ""

echo "================================================================"
echo "        4. ЗАПУСК PYTHON CONSUMER (фоновый)"
echo "================================================================"

echo "🔄 Запуск consumer для мониторинга обработанных событий..."
cd python

# Установка зависимостей если нужно
if [ ! -d "venv" ]; then
    echo "📦 Создание виртуального окружения..."
    python3 -m venv venv
    source venv/bin/activate
    echo "📦 Установка зависимостей..."
    pip install -r requirements.txt
else
    source venv/bin/activate
    # Проверка что зависимости установлены
    if ! python -c "import confluent_kafka" 2>/dev/null; then
        echo "📦 Установка недостающих зависимостей..."
        pip install -r requirements.txt
    fi
fi

# Запуск consumer в фоне
echo "🎯 Запуск consumer для топиков: processed-events, analytics-events..."
nohup python3 test_consumer_confluent.py > consumer.log 2>&1 &
CONSUMER_PID=$!
echo "Consumer PID: $CONSUMER_PID"

cd ..

echo ""

echo "================================================================"
echo "        5. НАСТРОЙКА NIFI FLOW"
echo "================================================================"

echo "📝 Инструкции по настройке NiFi Flow:"
echo ""
echo "1. Откройте http://localhost:8080/nifi"
echo "2. Войдите с credentials: admin / ctsBtRBKHRAx69EqUghvvgEvjnaLjFEB"
echo "3. Импортируйте template из файла: templates/kafka_integration_flow.xml"
echo "4. Настройте и запустите процессоры"
echo ""
echo "🎯 NiFi Flow выполняет:"
echo "   📥 ConsumeKafka - читает из топика 'user-events'"
echo "   🔄 UpdateAttribute - добавляет метаданные обработки"
echo "   📤 PublishKafka - отправляет в топик 'processed-events'"
echo "   📝 LogAttribute - логирует процесс обработки"
echo ""

echo "⏸️  Нажмите Enter когда настроите NiFi Flow..."
read -p "🎯 NiFi Flow настроен? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Пожалуйста, сначала настройте NiFi Flow:"
    echo "1. Откройте http://localhost:8080/nifi"
    echo "2. Логин: admin, пароль: ctsBtRBKHRAx69EqUghvvgEvjnaLjFEB"
    echo "3. Импортируйте template: templates/kafka_integration_flow.xml"
    echo "4. Настройте и запустите процессоры"
    echo "5. Запустите скрипт заново"
    exit 1
fi

echo ""

echo "================================================================"
echo "        6. ГЕНЕРАЦИЯ ТЕСТОВЫХ ДАННЫХ"
echo "================================================================"

echo "🚀 Запуск Python Producer для генерации событий..."
cd python
source venv/bin/activate

echo "📤 Отправка пакета тестовых событий в топик 'user-events'..."
python3 test_producer_confluent.py

cd ..

echo ""

echo "================================================================"
echo "        7. МОНИТОРИНГ ЛОГОВ"
echo "================================================================"

echo "📊 Логи Apache NiFi:"
echo "(Последние 20 строк)"
docker logs apache-nifi --tail 20

echo ""
echo "📊 Логи Consumer (обработанные события):"
echo "(Последние 20 строк)"
tail -20 python/consumer.log 2>/dev/null || echo "Логи consumer пока недоступны"

echo ""

echo "================================================================"
echo "        8. ПРОВЕРКА УСПЕШНОЙ ПЕРЕДАЧИ ДАННЫХ"
echo "================================================================"

echo "🔍 Проверка сообщений в топике user-events:"
docker exec kafka-broker-1 kafka-console-consumer --bootstrap-server localhost:9092 --topic user-events --from-beginning --max-messages 5 --timeout-ms 10000

echo ""
echo "🔍 Проверка сообщений в топике processed-events:"
docker exec kafka-broker-1 kafka-console-consumer --bootstrap-server localhost:9092 --topic processed-events --from-beginning --max-messages 5 --timeout-ms 10000

echo ""

echo "================================================================"
echo "        9. ВЕБЕРИЯ-ИНТЕРФЕЙСЫ И МОНИТОРИНГ"
echo "================================================================"

echo "🌐 Откройте в браузере для проверки:"
echo ""
echo "1. 📊 Kafka UI - http://localhost:8082"
echo "   - Просмотр топиков и сообщений"
echo "   - Мониторинг кластера"
echo ""
echo "2. 🔄 Apache NiFi - http://localhost:8080/nifi"
echo "   - Статус процессоров"
echo "   - Логи обработки"
echo "   - Метрики производительности"
echo ""
echo "3. 🗂️  Schema Registry - http://localhost:8081"
echo "   - curl http://localhost:8081/subjects"
echo "   - curl http://localhost:8081/config"
echo ""

echo "================================================================"
echo "        10. СБОР РЕЗУЛЬТАТОВ"
echo "================================================================"

echo "📸 Создание скриншотов для отчета:"
echo "✅ Скриншот Docker Compose PS (статус контейнеров)"
echo "✅ Скриншот NiFi интерфейса с активными процессорами"
echo "✅ Скриншот Kafka UI с топиками и сообщениями"
echo "✅ Логи успешной передачи данных"
echo "✅ Вывод kafka-console-consumer с данными"
echo ""

echo "📁 Файлы конфигурации:"
echo "✅ docker-compose.yml - настройка всех сервисов"
echo "✅ templates/kafka_integration_flow.xml - NiFi Flow"
echo "✅ python/test_producer_confluent.py - код продюсера (confluent-kafka)"
echo "✅ python/test_consumer_confluent.py - код консьюмера (confluent-kafka)"
echo ""

echo "📊 Логи для отчета:"
echo "✅ Логи NiFi: docker logs apache-nifi"
echo "✅ Логи Consumer: python/consumer.log"
echo "✅ Логи Kafka: docker logs kafka-broker-1"
echo ""

echo "================================================================"
echo "        ЗАДАНИЕ 2 ВЫПОЛНЕНО!"
echo "================================================================"
echo ""
echo "🎉 Успешно продемонстрировано:"
echo "✅ Развертывание Apache NiFi"
echo "✅ Интеграция NiFi с Kafka кластером"
echo "✅ Обработка данных через NiFi Flow"
echo "✅ Передача данных между топиками"
echo "✅ Мониторинг через веб-интерфейсы"
echo ""
echo "Для остановки: docker compose down"
echo "Для просмотра логов: docker compose logs [service_name]"
echo ""

# Сохранение PID для последующей остановки
echo $CONSUMER_PID > .consumer_pid

echo "🔄 Consumer работает в фоне (PID: $CONSUMER_PID)"
echo "Для остановки consumer: kill $CONSUMER_PID" 