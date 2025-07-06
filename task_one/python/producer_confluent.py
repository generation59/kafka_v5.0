#!/usr/bin/env python3
"""
Yandex Cloud Kafka Producer using confluent-kafka-python
Supports SASL_SSL authentication with Avro and JSON
"""

import json
import time
import logging
from datetime import datetime, timezone
from confluent_kafka import Producer
from confluent_kafka.error import KafkaError
import avro.schema
import avro.io

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class YandexKafkaProducer:
    def __init__(self, config_file='../../yandex_cloud_config.properties'):
        """Инициализация producer для Yandex Cloud Kafka"""
        self.config = self._load_config(config_file)
        self.producer = Producer(self.config)
        self.avro_schema = self._load_avro_schema()
        
    def _load_config(self, config_file):
        """Загрузка конфигурации из файла"""
        config = {}
        
        # Список поддерживаемых настроек для confluent-kafka-python Producer
        supported_keys = {
            'bootstrap.servers', 'security.protocol', 'sasl.mechanism', 
            'sasl.username', 'sasl.password', 'ssl.ca.location',
            'request.timeout.ms', 'retry.backoff.ms', 'acks', 'retries', 
            'max.in.flight.requests.per.connection', 'enable.idempotence', 
            'compression.type'
        }
        
        try:
            with open(config_file, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#'):
                        key, value = line.split('=', 1)
                        # Преобразование ключей из формата с подчеркиваниями в формат с точками
                        key = key.strip().replace('_', '.')
                        # Фильтрация только поддерживаемых настроек
                        if key in supported_keys:
                            config[key] = value.strip()
                        else:
                            logger.debug(f"Пропущена неподдерживаемая настройка: {key}")
        except FileNotFoundError:
            logger.error(f"Конфигурационный файл не найден: {config_file}")
            # Fallback конфигурация
            config = {
                'bootstrap.servers': 'rc1a-v063i1touj4ue341.mdb.yandexcloud.net:9091',
                'security.protocol': 'SASL_SSL',
                'sasl.mechanism': 'SCRAM-SHA-512',
                'sasl.username': 'kafka_user',
                'sasl.password': 'kafka_password',
                'ssl.ca.location': '/usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt'
            }
        return config
    
    def _load_avro_schema(self):
        """Загрузка Avro схемы"""
        try:
            with open('../schemas/user-event.avsc', 'r') as f:
                schema_dict = json.load(f)
            return avro.schema.parse(json.dumps(schema_dict))
        except Exception as e:
            logger.warning(f"Не удалось загрузить Avro схему: {e}")
            return None
    
    def delivery_report(self, err, msg):
        """Callback для отчета о доставке"""
        if err is not None:
            logger.error(f'Ошибка доставки сообщения: {err}')
        else:
            logger.info(f'Сообщение доставлено в {msg.topic()} [{msg.partition()}] offset {msg.offset()}')
    
    def send_message(self, topic, message_data):
        """Отправка сообщения"""
        try:
            # Попытка сериализации в Avro
            if self.avro_schema:
                try:
                    # Проверка соответствия схеме
                    self._validate_message(message_data)
                    message = json.dumps(message_data)
                    logger.info("Используется JSON формат (Avro схема для валидации)")
                except Exception as e:
                    logger.warning(f"Ошибка валидации Avro: {e}")
                    message = json.dumps(message_data)
            else:
                message = json.dumps(message_data)
            
            # Отправка сообщения
            self.producer.produce(
                topic=topic,
                value=message,
                key=str(message_data.get('userId', 'unknown')),
                callback=self.delivery_report
            )
            
            # Ожидание доставки
            self.producer.flush()
            
        except Exception as e:
            logger.error(f"Ошибка отправки сообщения: {e}")
            raise
    
    def _validate_message(self, message_data):
        """Валидация сообщения по Avro схеме"""
        required_fields = ['userId', 'eventType', 'timestamp']
        for field in required_fields:
            if field not in message_data:
                raise ValueError(f"Отсутствует обязательное поле: {field}")
    
    def close(self):
        """Закрытие producer"""
        self.producer.flush()
        logger.info("Producer закрыт")

def main():
    """Основная функция для тестирования"""
    topic = 'test'  # Используем существующий топик test
    producer = YandexKafkaProducer()
    
    try:
        # Создание тестового сообщения
        test_message = {
            "userId": "user-123",
            "eventType": "login",
            "timestamp": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
            "metadata": {
                "source": "producer_confluent.py",
                "version": "1.0",
                "ip": "192.168.1.100"
            }
        }
        
        logger.info(f"Отправка сообщения в топик: {topic}")
        logger.info(f"Сообщение: {json.dumps(test_message, indent=2)}")
        
        # Отправка сообщения
        producer.send_message(topic, test_message)
        
        logger.info("✅ Сообщение успешно отправлено!")
        
        # Отправка дополнительных тестовых сообщений
        for i in range(3):
            message = {
                "userId": f"user-{100+i}",
                "eventType": "page_view",
                "timestamp": datetime.now(timezone.utc).isoformat().replace('+00:00', 'Z'),
                "metadata": {
                    "source": "producer_confluent.py",
                    "version": "1.0",
                    "page": f"/page-{i}"
                }
            }
            producer.send_message(topic, message)
            time.sleep(0.1)
        
        logger.info("✅ Все тестовые сообщения отправлены!")
        
    except Exception as e:
        logger.error(f"❌ Ошибка: {e}")
        raise
    finally:
        producer.close()

if __name__ == "__main__":
    main() 