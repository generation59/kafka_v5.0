#!/bin/bash

# Генерация логов с реальными данными
echo "================================================================"
echo "        ГЕНЕРАЦИЯ ЛОГОВ С ДАННЫМИ"
echo "================================================================"

echo "⚠️  ВАЖНО: Перед запуском убедитесь что:"
echo "1. NiFi Flow настроен и запущен (http://localhost:8080/nifi)"
echo "2. Все Docker контейнеры работают"
echo ""

read -p "✅ NiFi Flow настроен и запущен? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Пожалуйста, сначала настройте NiFi:"
    echo "1. Откройте http://localhost:8080/nifi"
    echo "2. Логин: admin, пароль: ctsBtRBKHRAx69EqUghvvgEvjnaLjFEB"
    echo "3. Импортируйте template: templates/kafka_integration_flow.xml"
    echo "4. Настройте Bootstrap Servers в процессорах:"
    echo "   ConsumeKafka: kafka-broker-1:29092,kafka-broker-2:29093,kafka-broker-3:29094"
    echo "   PublishKafka: kafka-broker-1:29092,kafka-broker-2:29093,kafka-broker-3:29094"
    echo "5. Запустите все процессоры"
    echo "6. Запустите этот скрипт заново"
    exit 1
fi

echo "🔄 Начинаем генерацию данных и сбор логов..."

# Подготовка Python окружения
cd python
if [ ! -d "venv" ]; then
    echo "📦 Создание виртуального окружения..."
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
else
    source venv/bin/activate
fi
cd ..

# Очистка старых логов
rm -f producer_logs.txt consumer_logs.txt nifi_logs.txt kafka_consumer_logs.txt

echo "🚀 Шаг 1: Запуск Consumer в фоне..."
cd python
source venv/bin/activate
python3 test_consumer_confluent.py > ../consumer_logs.txt 2>&1 &
CONSUMER_PID=$!
cd ..

echo "Consumer PID: $CONSUMER_PID"
echo "⏳ Ждем 10 секунд для инициализации consumer..."
sleep 10

echo "📤 Шаг 2: Отправка первой партии сообщений..."
cd python
source venv/bin/activate
(echo "1"; echo "5"; echo "1") | python3 test_producer_confluent.py > ../producer_logs.txt 2>&1
cd ..

echo "⏳ Ждем 15 секунд для обработки NiFi..."
sleep 15

echo "📤 Шаг 3: Отправка второй партии сообщений..."
cd python
source venv/bin/activate
(echo "1"; echo "3"; echo "0.5") | python3 test_producer_confluent.py >> ../producer_logs.txt 2>&1
cd ..

echo "⏳ Ждем 10 секунд для завершения обработки..."
sleep 10

echo "🛑 Шаг 4: Остановка Consumer..."
kill $CONSUMER_PID 2>/dev/null || true
sleep 2

echo "📄 Шаг 5: Сбор логов NiFi..."
docker compose logs nifi --tail=100 > nifi_logs.txt 2>&1

echo "📄 Шаг 6: Сбор сообщений из топиков..."
{
    echo "=== Kafka Console Consumer Output ==="
    echo "Timestamp: $(date)"
    echo ""
    echo "--- Messages from user-events topic ---"
    timeout 10s docker compose exec -T kafka-broker-1 kafka-console-consumer --bootstrap-server localhost:9092 --topic user-events --from-beginning --max-messages 10 2>/dev/null || echo "No messages or timeout"
    echo ""
    echo "--- Messages from processed-events topic ---"
    timeout 10s docker compose exec -T kafka-broker-1 kafka-console-consumer --bootstrap-server localhost:9092 --topic processed-events --from-beginning --max-messages 10 2>/dev/null || echo "No messages or timeout"
} > kafka_consumer_logs.txt

echo "📊 Шаг 7: Проверка результатов..."
echo ""
echo "📋 Статистика логов:"
echo "   📄 producer_logs.txt: $(wc -l < producer_logs.txt 2>/dev/null || echo 0) строк"
echo "   📄 consumer_logs.txt: $(wc -l < consumer_logs.txt 2>/dev/null || echo 0) строк"
echo "   📄 nifi_logs.txt: $(wc -l < nifi_logs.txt 2>/dev/null || echo 0) строк"
echo "   📄 kafka_consumer_logs.txt: $(wc -l < kafka_consumer_logs.txt 2>/dev/null || echo 0) строк"

echo ""
echo "🔍 Краткий просмотр содержимого:"
echo "--- Producer (последние 5 строк) ---"
tail -5 producer_logs.txt 2>/dev/null || echo "Файл пуст или не найден"

echo ""
echo "--- Consumer (первые 5 строк) ---"
head -5 consumer_logs.txt 2>/dev/null || echo "Файл пуст или не найден"

echo ""
echo "--- Kafka Consumer (user-events) ---"
grep -A 5 "user-events topic" kafka_consumer_logs.txt 2>/dev/null || echo "Сообщения не найдены"

echo ""
echo "================================================================"
echo "        ГЕНЕРАЦИЯ ЛОГОВ ЗАВЕРШЕНА"
echo "================================================================"
echo ""
echo "✅ Файлы созданы:"
echo "   📄 producer_logs.txt"
echo "   📄 consumer_logs.txt"  
echo "   📄 nifi_logs.txt"
echo "   📄 kafka_consumer_logs.txt"
echo ""

if [ -s producer_logs.txt ] && [ -s consumer_logs.txt ]; then
    echo "🎉 Логи содержат данные - готовы для отчета!"
else
    echo "⚠️  Некоторые логи могут быть пустыми. Возможные причины:"
    echo "1. NiFi Flow не настроен или не запущен"
    echo "2. Неправильные Bootstrap Servers в NiFi процессорах"
    echo "3. Проблемы с сетью между контейнерами"
    echo ""
    echo "💡 Рекомендации:"
    echo "1. Проверьте статус NiFi процессоров в веб-интерфейсе"
    echo "2. Проверьте логи NiFi на ошибки: docker compose logs nifi --tail=50"
    echo "3. Убедитесь что топики созданы: docker compose exec kafka-broker-1 kafka-topics --list --bootstrap-server localhost:9092"
fi 