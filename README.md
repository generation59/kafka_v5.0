# Kafka v5.0 Project

Проект демонстрации работы с Apache Kafka в различных конфигурациях.

## Структура проекта

### 📁 task_one/ - Yandex Cloud Kafka Production
**Реальная интеграция с Yandex Cloud Managed Kafka**

#### Основные компоненты:
- **Python клиенты** (`python/`) - confluent-kafka-python с SASL_SSL
- **Конфигурация** - готовые настройки для secure подключения
- **Схемы Avro** - валидация данных

#### Быстрый старт:
```bash
cd task_one/python
pip install -r requirements.txt
python producer_confluent.py
python consumer_confluent.py
```

### 📁 task_two/ - Docker Development Environment  
**Локальная разработочная среда с Kafka + NiFi**

#### Основные компоненты:
- **docker-compose.yml** - полный Kafka кластер (3 брокера + Zookeeper)
- **Apache NiFi** - интеграция и обработка данных
- **Schema Registry** - встроенный Schema Registry
- **Kafka UI** - веб-интерфейс для мониторинга
- **Python клиенты** - тестовые продюсеры и консьюмеры

#### Быстрый старт:
```bash
cd task_two
docker compose up -d
# Веб-интерфейсы:
# NiFi: http://localhost:8080/nifi
# Kafka UI: http://localhost:8082
# Schema Registry: http://localhost:8081
```

## Что реализовано

### ✅ Production (task_one)
- 🔐 SASL_SSL аутентификация с Yandex Cloud
- 📊 Avro схемы и валидация данных
- 🚀 Высокопроизводительные Python клиенты
- 📝 Schema Registry интеграция

### ✅ Development (task_two)
- 🐳 Docker контейнеризация
- 🌐 Web UI для мониторинга
- 🔄 Apache NiFi для ETL процессов
- 📈 JMX мониторинг
- 🧪 Тестовые окружения

## Технологии

- **Apache Kafka** 7.4.0 (Confluent Platform)
- **Python** 3.12+ с confluent-kafka-python
- **Avro** для сериализации данных
- **Docker** для контейнеризации
- **Apache NiFi** для интеграции данных
- **Yandex Cloud** Managed Kafka

## Использование

### Production тестирование (Yandex Cloud):
```bash
cd task_one/python
python producer_confluent.py
python consumer_confluent.py
```

### Development тестирование (Docker):
```bash
cd task_two
docker compose up -d

# Тестирование Python клиентов
cd python
python test_producer_confluent.py
python test_consumer_confluent.py
```

## Веб-интерфейсы

### Task Two (Docker):
- **NiFi UI**: http://localhost:8080/nifi
  - Логин: `admin`
  - Пароль: `ctsBtRBKHRAx69EqUghvvgEvjnaLjFEB`
- **Kafka UI**: http://localhost:8082
- **Schema Registry**: http://localhost:8081

## Документация

- [`task_one/README.md`](task_one/README.md) - Подробная документация по Yandex Cloud интеграции
- [`task_two/README.md`](task_two/README.md) - Руководство по Docker окружению

## Поддержка

Проект готов к production использованию с Yandex Cloud Managed Kafka и локальной разработке через Docker.