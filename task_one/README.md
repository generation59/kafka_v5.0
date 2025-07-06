# Задание 1: Развёртывание и настройка Kafka-кластера

## Обзор

Этот проект содержит полную конфигурацию для развертывания продакшн-готового Kafka кластера с 3 брокерами, Zookeeper и Schema Registry. Все компоненты настроены с учетом best practices для продакшн-среды.

## Архитектура кластера

### Аппаратные ресурсы

**Kafka Брокеры (3 ноды):**
- CPU: 4 cores per broker
- RAM: 16 GB per broker  
- Disk: 500 GB SSD per broker (network-ssd в Yandex Cloud)
- Network: 10 Gbps

**Zookeeper (3 ноды):**
- CPU: 2 cores per node
- RAM: 8 GB per node
- Disk: 30 GB SSD per node

**Schema Registry (1 нода):**
- CPU: 2 cores
- RAM: 4 GB
- Disk: 30 GB SSD

### Конфигурация сети

- Kafka Broker 1: порт 9092
- Kafka Broker 2: порт 9093  
- Kafka Broker 3: порт 9094
- Zookeeper: порт 2181
- Schema Registry: порт 8081

## Структура проекта

```
task_one/
├── README.md                           # Эта документация
├── install_kafka.sh                    # Основной скрипт установки Kafka
├── install_schema_registry.sh          # Скрипт установки Schema Registry
├── config/                             # Конфигурационные файлы
│   ├── zookeeper.properties           # Конфигурация Zookeeper
│   ├── server-1.properties            # Конфигурация Kafka Broker 1
│   ├── server-2.properties            # Конфигурация Kafka Broker 2
│   └── server-3.properties            # Конфигурация Kafka Broker 3
├── schemas/                            # Avro схемы
│   └── user-event.avsc                # Схема пользовательских событий
├── python/                             # Python клиенты
│   ├── requirements.txt               # Python зависимости
│   ├── producer.py                    # Kafka продюсер
│   └── consumer.py                    # Kafka консьюмер
└── scripts/                           # Вспомогательные скрипты
    ├── setup_kafka_cluster.sh         # Полная настройка кластера
    └── register_schema.sh             # Регистрация схемы в Schema Registry
```

## Пошаговое развертывание

### Шаг 1: Подготовка сервера

```bash
# Обновление системы
sudo apt update && sudo apt upgrade -y

# Клонирование проекта
git clone <repository_url>
cd task_one
```

### Шаг 2: Запуск автоматической установки

```bash
# Делаем скрипты исполняемыми
chmod +x *.sh scripts/*.sh

# Запуск полной установки (требует root права)
sudo ./scripts/setup_kafka_cluster.sh
```

Этот скрипт выполнит:
- Установку Java 11
- Скачивание и настройку Kafka
- Создание пользователей kafka и zookeeper
- Настройку systemd сервисов
- Запуск всех компонентов
- Создание топика с репликацией
- Установку и настройку Schema Registry

### Шаг 3: Проверка статуса кластера

```bash
# Проверка статуса всех сервисов
sudo systemctl status zookeeper kafka kafka-2 kafka-3 schema-registry

# Просмотр логов
sudo journalctl -u kafka -f
sudo journalctl -u zookeeper -f
sudo journalctl -u schema-registry -f
```

### Шаг 4: Настройка топика

Топик `user-events` создается автоматически со следующими параметрами:

```bash
# Создание топика (автоматически выполняется скриптом)
/opt/kafka/bin/kafka-topics.sh --create \
    --bootstrap-server localhost:9092,localhost:9093,localhost:9094 \
    --topic user-events \
    --partitions 3 \
    --replication-factor 3 \
    --config cleanup.policy=delete \
    --config retention.ms=604800000 \
    --config segment.bytes=1073741824
```

### Шаг 5: Настройка Schema Registry

```bash
# Регистрация схемы
cd scripts
./register_schema.sh
```

## Конфигурация кластера

### Параметры репликации и хранения

**Настройки топика:**
- Количество партиций: 3
- Фактор репликации: 3
- Политика очистки: `delete`
- Время хранения: 7 дней (604800000 мс)
- Размер сегмента: 1 GB (1073741824 байт)
- Минимальный ISR: 2

**Настройки брокеров:**
- Компрессия: snappy
- Batch size: 16KB
- Linger time: 10ms
- Acks: all (для надежности)
- Идемпотентность: включена

### Важные параметры производительности

```properties
# Сетевые потоки
num.network.threads=8
num.io.threads=8

# Буферы
socket.send.buffer.bytes=102400
socket.receive.buffer.bytes=102400

# Репликация
replica.fetch.max.bytes=1048576
num.replica.fetchers=4

# Безопасность
unclean.leader.election.enable=false
min.insync.replicas=2
```

## Тестирование работы Kafka

### Проверка топиков

```bash
# Список всех топиков
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092

# Описание топика user-events
/opt/kafka/bin/kafka-topics.sh --describe --topic user-events --bootstrap-server localhost:9092
```

**Ожидаемый вывод команды describe:**
```
Topic: user-events
Partition: 0    Leader: 1       Replicas: 1,2,3        Isr: 1,2,3
Partition: 1    Leader: 2       Replicas: 2,3,1        Isr: 2,3,1
Partition: 2    Leader: 3       Replicas: 3,1,2        Isr: 3,1,2
```

### Проверка Schema Registry

```bash
# Проверка доступности
curl http://localhost:8081/subjects

# Просмотр зарегистрированных схем
curl http://localhost:8081/subjects/user-events-value/versions
```

### Запуск Python клиентов

```bash
# Установка зависимостей
cd python
pip3 install -r requirements.txt

# Запуск продюсера
python3 producer.py

# В другом терминале - запуск консьюмера
python3 consumer.py
```

## Схема данных

Файл: `schemas/user-event.avsc`

Схема описывает события пользователей с полями:
- userId (string) - идентификатор пользователя
- eventType (enum) - тип события (LOGIN, LOGOUT, PURCHASE, VIEW_PRODUCT, ADD_TO_CART, REGISTER)
- timestamp (long) - временная метка события
- sessionId (string, optional) - идентификатор сессии
- productId (string, optional) - идентификатор продукта
- amount (double, optional) - сумма для покупок
- userAgent (string, optional) - информация о браузере
- ipAddress (string, optional) - IP адрес пользователя
- metadata (map<string>, optional) - дополнительные метаданные

## Мониторинг и JMX

Каждый компонент настроен с JMX мониторингом:

- Zookeeper JMX: порт 9999
- Kafka Broker 1 JMX: порт 9991
- Kafka Broker 2 JMX: порт 9992  
- Kafka Broker 3 JMX: порт 9993
- Schema Registry JMX: порт 9994

### Подключение JConsole

```bash
jconsole localhost:9991  # для Kafka Broker 1
jconsole localhost:9999  # для Zookeeper
```

## Результаты тестирования

### Скриншоты команд curl

**Команда проверки Schema Registry:**
```bash
curl http://localhost:8081/subjects
```
Ожидаемый ответ: `["user-events-value"]`

**Команда получения версий схемы:**
```bash
curl http://localhost:8081/subjects/user-events-value/versions
```
Ожидаемый ответ: `[1]`

### Логи продюсера

При запуске `python3 producer.py` ожидаются логи вида:
```
Продюсер инициализирован для топика 'user-events'
Bootstrap серверы: localhost:9092,localhost:9093,localhost:9094

=== Отправка 20 тестовых событий ===
✓ Отправлено событие: LOGIN для пользователя user_3
  → Сообщение доставлено в топик 'user-events', партиция 1, offset 0
✓ Отправлено событие: PURCHASE для пользователя user_1
  → Сообщение доставлено в топик 'user-events', партиция 0, offset 0
...
✓ Все 20 событий отправлены и подтверждены
```

### Логи консьюмера

При запуске `python3 consumer.py` ожидаются логи вида:
```
Консьюмер инициализирован для топика 'user-events'
Группа консьюмеров: user-events-processor

🚀 Начинаем чтение сообщений из топика 'user-events'...

=== Получено событие ===
Ключ: user_3
Топик: user-events
Партиция: 1
Offset: 0
Время: 2024-01-20 15:30:45
---
Пользователь: user_3
Тип события: LOGIN
Сессия: 123e4567-e89b-12d3-a456-426614174000
IP: 192.168.1.100
  → Пользователь user_3 вошел в систему
```

## Управление кластером

### Основные команды systemctl

```bash
# Перезапуск всех сервисов
sudo systemctl restart zookeeper kafka kafka-2 kafka-3 schema-registry

# Остановка кластера
sudo systemctl stop kafka kafka-2 kafka-3 schema-registry zookeeper

# Запуск кластера
sudo systemctl start zookeeper
sleep 10
sudo systemctl start kafka kafka-2 kafka-3
sleep 10  
sudo systemctl start schema-registry
```

### Очистка данных (осторожно!)

```bash
# Остановка сервисов
sudo systemctl stop kafka kafka-2 kafka-3 schema-registry zookeeper

# Очистка логов Kafka
sudo rm -rf /var/kafka-logs-*/*

# Очистка данных Zookeeper
sudo rm -rf /var/lib/zookeeper/*

# Пересоздание myid для Zookeeper
echo "1" | sudo tee /var/lib/zookeeper/myid
sudo chown zookeeper:zookeeper /var/lib/zookeeper/myid
```

## Безопасность

В данной конфигурации используются базовые настройки безопасности:
- Отключение небезопасных операций (`unclean.leader.election.enable=false`)
- Минимальный ISR для записи (`min.insync.replicas=2`)
- Ожидание подтверждения от всех реплик (`acks=all`)

Для продакшн среды рекомендуется добавить:
- SSL/TLS шифрование
- SASL аутентификацию
- ACL авторизацию
- Сетевые фильтры

## Диагностика проблем

### Проверка логов

```bash
# Логи Kafka
sudo journalctl -u kafka -n 50
sudo tail -f /opt/kafka/logs/server.log

# Логи Zookeeper  
sudo journalctl -u zookeeper -n 50
sudo tail -f /opt/kafka/logs/zookeeper.out

# Логи Schema Registry
sudo journalctl -u schema-registry -n 50
```

### Проверка сетевых соединений

```bash
# Проверка портов
sudo netstat -tlnp | grep -E "(9092|9093|9094|2181|8081)"

# Проверка подключений
sudo ss -tlnp | grep -E "(9092|9093|9094|2181|8081)"
```

### Проверка дискового пространства

```bash
# Использование диска
df -h /var/kafka-logs-*

# Размер логов по топикам
du -sh /var/kafka-logs-*/*
```

## Заключение

Данная конфигурация обеспечивает:
- Высокую доступность (3 брокера, 3 Zookeeper)
- Надежность данных (репликация 3, min ISR 2)
- Производительность (оптимизированные настройки)
- Мониторинг (JMX метрики)
- Управление схемами (Schema Registry)

Кластер готов для продакшн нагрузок и может обрабатывать тысячи сообщений в секунду с гарантией доставки и порядка. 