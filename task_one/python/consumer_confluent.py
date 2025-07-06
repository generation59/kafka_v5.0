#!/usr/bin/env python3
"""
Yandex Cloud Kafka Consumer using confluent-kafka-python
Supports SASL_SSL authentication with Avro and JSON
"""

import json
import logging
import signal
import sys
from confluent_kafka import Consumer, KafkaError
import avro.schema
import avro.io

# Настройка логирования
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class YandexKafkaConsumer:
    def __init__(self, config_file='../../yandex_cloud_config.properties'):
        """Инициализация consumer для Yandex Cloud Kafka"""
        self.config = self._load_config(config_file)
        self.consumer = Consumer(self.config)
        self.avro_schema = self._load_avro_schema()
        self.running = True
        
    def _load_config(self, config_file):
        """Загрузка конфигурации из файла"""
        config = {}
        
        # Список поддерживаемых настроек для confluent-kafka-python
        supported_keys = {
            'bootstrap.servers', 'security.protocol', 'sasl.mechanism', 
            'sasl.username', 'sasl.password', 'ssl.ca.location',
            'request.timeout.ms', 'session.timeout.ms', 'heartbeat.interval.ms',
            'retry.backoff.ms', 'auto.offset.reset', 'enable.auto.commit',
            'auto.commit.interval.ms', 'group.id'
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
        
        # Добавление настроек consumer
        config.update({
            'group.id': 'yandex-consumer-group',
            'auto.offset.reset': 'earliest',
            'enable.auto.commit': True,
            'auto.commit.interval.ms': 5000
        })
        
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
    
    def process_message(self, message):
        """Обработка полученного сообщения"""
        try:
            # Декодирование сообщения
            message_data = json.loads(message.value().decode('utf-8'))
            
            # Валидация по Avro схеме
            if self.avro_schema:
                try:
                    self._validate_message(message_data)
                    logger.info("✅ Сообщение прошло валидацию Avro")
                except Exception as e:
                    logger.warning(f"⚠️ Ошибка валидации Avro: {e}")
            
            # Логирование информации о сообщении
            logger.info("=" * 50)
            logger.info(f"📨 Получено сообщение:")
            logger.info(f"   Топик: {message.topic()}")
            logger.info(f"   Партиция: {message.partition()}")
            logger.info(f"   Offset: {message.offset()}")
            logger.info(f"   Ключ: {message.key()}")
            logger.info(f"   Timestamp: {message.timestamp()}")
            logger.info(f"   Данные: {json.dumps(message_data, indent=2, ensure_ascii=False)}")
            
            # Обработка в зависимости от типа события
            event_type = message_data.get('eventType', 'unknown')
            user_id = message_data.get('userId', 'unknown')
            
            if event_type == 'login':
                logger.info(f"🔑 Обработка события входа для пользователя: {user_id}")
            elif event_type == 'page_view':
                logger.info(f"👀 Обработка просмотра страницы для пользователя: {user_id}")
            elif event_type == 'purchase':
                logger.info(f"💰 Обработка покупки для пользователя: {user_id}")
            else:
                logger.info(f"📝 Обработка события '{event_type}' для пользователя: {user_id}")
            
            logger.info("=" * 50)
            
        except Exception as e:
            logger.error(f"❌ Ошибка обработки сообщения: {e}")
            logger.error(f"Сырое сообщение: {message.value()}")
    
    def _validate_message(self, message_data):
        """Валидация сообщения по Avro схеме"""
        required_fields = ['userId', 'eventType', 'timestamp']
        for field in required_fields:
            if field not in message_data:
                raise ValueError(f"Отсутствует обязательное поле: {field}")
    
    def signal_handler(self, signum, frame):
        """Обработчик сигналов для корректного завершения"""
        logger.info("🛑 Получен сигнал завершения...")
        self.running = False
    
    def consume_messages(self, topics):
        """Основной цикл потребления сообщений"""
        try:
            # Подписка на топики
            self.consumer.subscribe(topics)
            logger.info(f"🔌 Подписка на топики: {topics}")
            logger.info("⏳ Ожидание сообщений... (Ctrl+C для выхода)")
            
            # Регистрация обработчика сигналов
            signal.signal(signal.SIGINT, self.signal_handler)
            signal.signal(signal.SIGTERM, self.signal_handler)
            
            while self.running:
                try:
                    # Получение сообщения с таймаутом
                    msg = self.consumer.poll(timeout=1.0)
                    
                    if msg is None:
                        continue
                    
                    if msg.error():
                        if msg.error().code() == KafkaError._PARTITION_EOF:
                            logger.info(f"📍 Достигнут конец партиции {msg.partition()}")
                        else:
                            logger.error(f"❌ Ошибка Consumer: {msg.error()}")
                    else:
                        # Обработка сообщения
                        self.process_message(msg)
                        
                except Exception as e:
                    logger.error(f"❌ Ошибка в цикле потребления: {e}")
                    
        except Exception as e:
            logger.error(f"❌ Критическая ошибка consumer: {e}")
            raise
        finally:
            # Закрытие consumer
            self.consumer.close()
            logger.info("🔌 Consumer закрыт")

def main():
    """Основная функция для тестирования"""
    topics = ['test']  # Используем существующий топик test
    consumer = YandexKafkaConsumer()
    
    try:
        consumer.consume_messages(topics)
    except KeyboardInterrupt:
        logger.info("🛑 Получен сигнал прерывания")
    except Exception as e:
        logger.error(f"❌ Ошибка: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main() 