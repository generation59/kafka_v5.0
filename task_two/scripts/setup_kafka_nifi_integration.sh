#!/bin/bash

# Скрипт для настройки интеграции Kafka с Apache NiFi
# Создает необходимые топики и настраивает окружение

set -e

echo "=========================================="
echo "  Настройка интеграции Kafka + NiFi"
echo "=========================================="

# Конфигурационные переменные
KAFKA_HOME="/opt/kafka"
SERVER_IP=$(hostname -I | awk '{print $1}')
BOOTSTRAP_SERVERS="$SERVER_IP:9092,$SERVER_IP:9093,$SERVER_IP:9094"

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть запущен с правами root" 
   exit 1
fi

echo "=== Шаг 1: Проверка работы Kafka кластера ==="

# Проверка статуса Kafka сервисов
services=("zookeeper" "kafka" "kafka-2" "kafka-3")
all_running=true

for service in "${services[@]}"; do
    if systemctl is-active --quiet $service; then
        echo "✓ $service: RUNNING"
    else
        echo "✗ $service: NOT RUNNING"
        all_running=false
    fi
done

if [ "$all_running" = false ]; then
    echo ""
    echo "Некоторые сервисы Kafka не запущены. Попытка запуска..."
    
    echo "Запуск Zookeeper..."
    systemctl start zookeeper
    sleep 10
    
    echo "Запуск Kafka брокеров..."
    systemctl start kafka kafka-2 kafka-3
    sleep 15
    
    echo "Проверка статуса после запуска..."
    for service in "${services[@]}"; do
        if systemctl is-active --quiet $service; then
            echo "✓ $service: RUNNING"
        else
            echo "✗ $service: FAILED TO START"
            echo "Проверьте логи: journalctl -u $service"
            exit 1
        fi
    done
fi

echo ""
echo "=== Шаг 2: Создание дополнительных топиков для NiFi ==="

# Функция для создания топика
create_topic() {
    local topic_name=$1
    local partitions=$2
    local replication_factor=$3
    local description=$4
    
    echo "Создание топика: $topic_name"
    
    if $KAFKA_HOME/bin/kafka-topics.sh --list --bootstrap-server $BOOTSTRAP_SERVERS | grep -q "^$topic_name$"; then
        echo "  ✓ Топик '$topic_name' уже существует"
    else
        $KAFKA_HOME/bin/kafka-topics.sh --create \
            --bootstrap-server $BOOTSTRAP_SERVERS \
            --topic $topic_name \
            --partitions $partitions \
            --replication-factor $replication_factor \
            --config cleanup.policy=delete \
            --config retention.ms=604800000 \
            --config segment.bytes=1073741824
        
        if [ $? -eq 0 ]; then
            echo "  ✓ Топик '$topic_name' создан успешно ($description)"
        else
            echo "  ✗ Ошибка создания топика '$topic_name'"
            exit 1
        fi
    fi
}

# Создание топиков для интеграции
create_topic "processed-events" 3 3 "Обработанные события из NiFi"
create_topic "analytics-events" 3 3 "События для аналитики"
create_topic "purchase-events" 3 3 "События покупок"
create_topic "error-events" 3 3 "События с ошибками"

echo ""
echo "=== Шаг 3: Проверка созданных топиков ==="

echo "Список всех топиков:"
$KAFKA_HOME/bin/kafka-topics.sh --list --bootstrap-server $BOOTSTRAP_SERVERS

echo ""
echo "Детальная информация о топиках:"
for topic in "user-events" "processed-events" "analytics-events" "purchase-events"; do
    echo ""
    echo "--- Топик: $topic ---"
    $KAFKA_HOME/bin/kafka-topics.sh --describe --topic $topic --bootstrap-server $BOOTSTRAP_SERVERS
done

echo ""
echo "=== Шаг 4: Установка и настройка Apache NiFi ==="

# Проверка установки NiFi
if [ ! -d "/opt/nifi" ]; then
    echo "Установка Apache NiFi..."
    bash "$(dirname "$0")/../install_nifi.sh"
else
    echo "✓ Apache NiFi уже установлен"
    
    # Проверка статуса NiFi
    if systemctl is-active --quiet nifi; then
        echo "✓ NiFi уже запущен"
    else
        echo "Запуск NiFi..."
        systemctl start nifi
        sleep 30
        
        if systemctl is-active --quiet nifi; then
            echo "✓ NiFi успешно запущен"
        else
            echo "✗ Ошибка запуска NiFi"
            echo "Проверьте логи: journalctl -u nifi -f"
        fi
    fi
fi

echo ""
echo "=== Шаг 5: Настройка конфигурации NiFi для Kafka ==="

NIFI_HOME="/opt/nifi"

# Добавление Kafka-специфических настроек в nifi.properties
if ! grep -q "# Kafka Integration Settings" $NIFI_HOME/conf/nifi.properties; then
    cat >> $NIFI_HOME/conf/nifi.properties << EOF

# Kafka Integration Settings
nifi.variable.registry.properties=$NIFI_HOME/conf/kafka-variables.properties

# Additional performance settings for Kafka processing
nifi.flowfile.repository.implementation=org.apache.nifi.controller.repository.WriteAheadFlowFileRepository
nifi.flowfile.repository.wal.implementation=org.apache.nifi.controller.repository.SequentialAccessWriteAheadLog
nifi.content.repository.implementation=org.apache.nifi.controller.repository.FileSystemRepository
nifi.content.repository.archive.max.retention.period=7 days
nifi.content.repository.archive.max.usage.percentage=50%

# Kafka specific JVM settings
nifi.processor.scheduling.timeout=5 min
EOF

    echo "✓ Добавлены настройки Kafka в nifi.properties"
fi

# Создание файла переменных для Kafka
cat > $NIFI_HOME/conf/kafka-variables.properties << EOF
# Kafka Configuration Variables for NiFi
kafka.bootstrap.servers=$BOOTSTRAP_SERVERS
kafka.security.protocol=PLAINTEXT
kafka.acks=all
kafka.retries=3
kafka.batch.size=16384
kafka.linger.ms=10
kafka.compression.type=snappy
kafka.session.timeout.ms=30000
kafka.enable.auto.commit=true
kafka.auto.commit.interval.ms=1000
kafka.max.poll.records=500

# Topic Names
kafka.topic.input=user-events
kafka.topic.processed=processed-events
kafka.topic.analytics=analytics-events
kafka.topic.purchase=purchase-events
kafka.topic.errors=error-events

# Consumer Group
kafka.consumer.group.id=nifi-consumer-group
EOF

chown nifi:nifi $NIFI_HOME/conf/kafka-variables.properties

echo "✓ Создан файл переменных Kafka"

echo ""
echo "=== Шаг 6: Создание директории для NiFi templates ==="
mkdir -p $NIFI_HOME/conf/templates
chown nifi:nifi $NIFI_HOME/conf/templates

# Копирование template
if [ -f "$(dirname "$0")/../templates/kafka_integration_flow.xml" ]; then
    cp "$(dirname "$0")/../templates/kafka_integration_flow.xml" $NIFI_HOME/conf/templates/
    chown nifi:nifi $NIFI_HOME/conf/templates/kafka_integration_flow.xml
    echo "✓ Template скопирован в NiFi"
fi

echo ""
echo "=== Шаг 7: Перезапуск NiFi для применения настроек ==="
systemctl restart nifi

echo "Ожидание запуска NiFi (может занять 2-3 минуты)..."
sleep 60

# Проверка статуса
attempt=1
max_attempts=6

while [ $attempt -le $max_attempts ]; do
    if systemctl is-active --quiet nifi; then
        echo "✓ NiFi успешно перезапущен"
        break
    else
        echo "Попытка $attempt/$max_attempts: NiFi еще запускается..."
        sleep 30
        ((attempt++))
    fi
done

if [ $attempt -gt $max_attempts ]; then
    echo "✗ NiFi не смог запуститься в течение отведенного времени"
    echo "Проверьте логи: journalctl -u nifi -f"
    echo "Или: tail -f $NIFI_HOME/logs/nifi-app.log"
fi

echo ""
echo "=== Шаг 8: Проверка доступности веб-интерфейса ==="

WEB_URL="http://$SERVER_IP:8080/nifi"
attempt=1
max_attempts=5

while [ $attempt -le $max_attempts ]; do
    if curl -f -s "$WEB_URL" > /dev/null; then
        echo "✓ NiFi веб-интерфейс доступен: $WEB_URL"
        break
    else
        echo "Попытка $attempt/$max_attempts: Веб-интерфейс еще недоступен..."
        sleep 15
        ((attempt++))
    fi
done

if [ $attempt -gt $max_attempts ]; then
    echo "⚠ Веб-интерфейс NiFi недоступен, но сервис может быть все еще запускается"
    echo "Попробуйте обратиться к $WEB_URL через несколько минут"
fi

echo ""
echo "=== Шаг 9: Установка Python зависимостей для тестирования ==="
if command -v pip3 &> /dev/null; then
    pip3 install kafka-python confluent-kafka avro-python3 requests
    echo "✓ Python зависимости установлены"
else
    echo "⚠ pip3 не найден. Установите Python зависимости вручную:"
    echo "  pip3 install kafka-python confluent-kafka avro-python3 requests"
fi

echo ""
echo "=========================================="
echo "  Интеграция Kafka + NiFi настроена!"
echo "=========================================="
echo ""
echo "Информация о настроенной интеграции:"
echo ""
echo "Kafka кластер:"
echo "  Bootstrap серверы: $BOOTSTRAP_SERVERS"
echo "  Топики для интеграции:"
echo "    - user-events (входящие события)"
echo "    - processed-events (обработанные события)"
echo "    - analytics-events (аналитические события)"
echo "    - purchase-events (события покупок)"
echo "    - error-events (события с ошибками)"
echo ""
echo "Apache NiFi:"
echo "  Веб-интерфейс: $WEB_URL"
echo "  Конфигурация: $NIFI_HOME/conf/"
echo "  Логи: $NIFI_HOME/logs/"
echo "  Templates: $NIFI_HOME/conf/templates/"
echo ""
echo "Для загрузки template в NiFi:"
echo "1. Откройте веб-интерфейс: $WEB_URL"
echo "2. Drag and drop значок Template на canvas"
echo "3. Выберите 'Kafka Integration Flow'"
echo "4. Настройте и запустите processors"
echo ""
echo "Управление сервисами:"
echo "  Kafka: systemctl {start|stop|restart} kafka kafka-2 kafka-3"
echo "  NiFi:  systemctl {start|stop|restart} nifi"
echo ""
echo "Тестирование:"
echo "  cd $(dirname "$0")/../python"
echo "  python3 producer.py"
echo "  python3 consumer.py" 