#!/usr/bin/env python3
"""
Test Consumer для тестирования интеграции Kafka + NiFi
Читает обработанные события из топиков processed-events, analytics-events и т.д.
Использует confluent-kafka-python для совместимости с Python 3.12
"""

import json
import time
import signal
import sys
from datetime import datetime
from typing import Dict, Any, List
from collections import defaultdict

from confluent_kafka import Consumer, KafkaError
import logging

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class KafkaNiFiTestConsumer:
    """Тестовый консьюмер для чтения обработанных событий из NiFi"""
    
    def __init__(self, bootstrap_servers: str, topics: List[str], group_id: str):
        """
        Инициализация консьюмера
        
        Args:
            bootstrap_servers: Адреса Kafka брокеров
            topics: Список топиков для чтения
            group_id: ID группы консьюмеров
        """
        self.topics = topics
        self.group_id = group_id
        self.running = True
        
        # Статистика
        self.stats = {
            'total_messages': 0,
            'messages_by_topic': defaultdict(int),
            'messages_by_type': defaultdict(int),
            'errors': 0,
            'start_time': time.time()
        }
        
        # Настройка консьюмера
        self.consumer = Consumer({
            'bootstrap.servers': bootstrap_servers,
            'group.id': group_id,
            'auto.offset.reset': 'latest',  # Читаем только новые сообщения
            'enable.auto.commit': True,
            'auto.commit.interval.ms': 1000,
            'session.timeout.ms': 30000,
            'heartbeat.interval.ms': 10000,
            'max.poll.interval.ms': 300000,
            'fetch.min.bytes': 1,
            'fetch.wait.max.ms': 500
        })
        
        # Подписка на топики
        self.consumer.subscribe(topics)
        
        logger.info(f"Консьюмер инициализирован для топиков: {topics}")
        logger.info(f"Группа консьюмеров: {group_id}")
        logger.info(f"Bootstrap серверы: {bootstrap_servers}")
        
        # Обработчик сигналов для корректного завершения
        signal.signal(signal.SIGINT, self._signal_handler)
        signal.signal(signal.SIGTERM, self._signal_handler)

    def _signal_handler(self, signum, frame):
        """Обработчик сигналов для корректного завершения"""
        logger.info(f"\nПолучен сигнал {signum}. Останавливаем консьюмер...")
        self.running = False

    def process_message(self, message) -> bool:
        """
        Обработка сообщения
        
        Args:
            message: Сообщение из Kafka
            
        Returns:
            bool: True если сообщение обработано успешно
        """
        try:
            topic = message.topic()
            partition = message.partition()
            offset = message.offset()
            key = message.key()
            value = message.value()
            timestamp = message.timestamp()
            
            # Декодирование ключа и значения
            key_str = key.decode('utf-8') if key else None
            
            # Парсинг JSON значения
            value_dict = None
            if value:
                try:
                    value_dict = json.loads(value.decode('utf-8'))
                except json.JSONDecodeError:
                    value_dict = {'raw_message': value.decode('utf-8', errors='ignore')}
            
            # Обновление статистики
            self.stats['total_messages'] += 1
            self.stats['messages_by_topic'][topic] += 1
            
            # Извлечение типа события (если есть)
            event_type = None
            if isinstance(value_dict, dict):
                event_type = value_dict.get('eventType', 'UNKNOWN')
                self.stats['messages_by_type'][event_type] += 1
            
            # Определение времени обработки (если есть метаданные NiFi)
            processing_time = None
            if isinstance(value_dict, dict) and 'nifi.processing.timestamp' in value_dict:
                try:
                    processing_timestamp = int(value_dict['nifi.processing.timestamp'])
                    original_timestamp = value_dict.get('timestamp', int(time.time() * 1000))
                    processing_time = processing_timestamp - original_timestamp
                except (ValueError, TypeError):
                    pass
            
            # Форматированный вывод сообщения
            timestamp_type, timestamp_value = timestamp
            if timestamp_type == 1:  # CREATE_TIME
                timestamp_str = datetime.fromtimestamp(timestamp_value / 1000).strftime('%H:%M:%S.%f')[:-3]
            else:
                timestamp_str = 'N/A'
            
            logger.info(f"📨 [{timestamp_str}] Топик: {topic}")
            logger.info(f"   📍 Партиция: {partition}, Offset: {offset}")
            logger.info(f"   🔑 Ключ: {key_str}")
            
            if event_type:
                logger.info(f"   📊 Тип события: {event_type}")
            
            if processing_time:
                logger.info(f"   ⏱️  Время обработки в NiFi: {processing_time}ms")
            
            # Подробности сообщения (если это JSON)
            if isinstance(value_dict, dict):
                logger.info(f"   📄 Данные: {self._format_message_data(value_dict)}")
            else:
                logger.info(f"   📄 Данные: {value_dict}")
            
            logger.info("-" * 60)
            
            return True
            
        except Exception as e:
            logger.error(f"✗ Ошибка обработки сообщения: {e}")
            self.stats['errors'] += 1
            return False

    def _format_message_data(self, data: Dict[str, Any]) -> str:
        """Форматирование данных сообщения для вывода"""
        important_fields = [
            'userId', 'eventType', 'timestamp', 'sessionId', 
            'productId', 'amount', 'source.topic', 'source.partition', 
            'nifi.processing.timestamp', 'nifi.processor.name'
        ]
        
        formatted_parts = []
        
        for field in important_fields:
            if field in data:
                value = data[field]
                if field == 'timestamp' or field == 'nifi.processing.timestamp':
                    # Преобразование timestamp в читаемый формат
                    try:
                        ts = int(value) / 1000
                        readable_time = datetime.fromtimestamp(ts).strftime('%Y-%m-%d %H:%M:%S')
                        formatted_parts.append(f"{field}={readable_time}")
                    except:
                        formatted_parts.append(f"{field}={value}")
                else:
                    formatted_parts.append(f"{field}={value}")
        
        # Добавляем другие поля если есть
        other_fields = {k: v for k, v in data.items() if k not in important_fields}
        if other_fields:
            other_str = ", ".join([f"{k}={v}" for k, v in other_fields.items() if not k.startswith('_')])
            if other_str:
                formatted_parts.append(f"other: {other_str}")
        
        return " | ".join(formatted_parts)

    def print_statistics(self):
        """Печать статистики"""
        elapsed = time.time() - self.stats['start_time']
        rate = self.stats['total_messages'] / elapsed if elapsed > 0 else 0
        
        logger.info("\n" + "=" * 50)
        logger.info("📊 СТАТИСТИКА КОНСЬЮМЕРА")
        logger.info("=" * 50)
        logger.info(f"⏱️  Время работы: {elapsed:.1f} секунд")
        logger.info(f"📦 Всего сообщений: {self.stats['total_messages']}")
        logger.info(f"📈 Скорость: {rate:.2f} сообщений/сек")
        logger.info(f"❌ Ошибок: {self.stats['errors']}")
        
        if self.stats['messages_by_topic']:
            logger.info("\n📋 По топикам:")
            for topic, count in self.stats['messages_by_topic'].items():
                percentage = (count / self.stats['total_messages']) * 100 if self.stats['total_messages'] > 0 else 0
                logger.info(f"   {topic}: {count} ({percentage:.1f}%)")
        
        if self.stats['messages_by_type']:
            logger.info("\n📊 По типам событий:")
            for event_type, count in self.stats['messages_by_type'].items():
                percentage = (count / self.stats['total_messages']) * 100 if self.stats['total_messages'] > 0 else 0
                logger.info(f"   {event_type}: {count} ({percentage:.1f}%)")

    def consume_messages(self, timeout_sec: int = None):
        """
        Основной цикл чтения сообщений
        
        Args:
            timeout_sec: Таймаут работы в секундах (None для бесконечной работы)
        """
        logger.info(f"\n🔄 Начинаем чтение сообщений из топиков: {self.topics}")
        logger.info("Для остановки нажмите Ctrl+C")
        
        end_time = None
        if timeout_sec:
            end_time = time.time() + timeout_sec
            logger.info(f"⏰ Автоматическая остановка через {timeout_sec} секунд")
        
        try:
            while self.running:
                # Проверка таймаута
                if end_time and time.time() > end_time:
                    logger.info("⏰ Достигнут таймаут, останавливаем консьюмер")
                    break
                
                # Чтение сообщения
                msg = self.consumer.poll(1.0)  # timeout 1 секунда
                
                if msg is None:
                    continue
                
                if msg.error():
                    if msg.error().code() == KafkaError._PARTITION_EOF:
                        # Достигнут конец партиции
                        logger.debug(f"Достигнут конец партиции {msg.topic()}[{msg.partition()}]")
                    else:
                        logger.error(f"Ошибка консьюмера: {msg.error()}")
                        self.stats['errors'] += 1
                else:
                    # Обработка сообщения
                    self.process_message(msg)
                
                # Печать статистики каждые 50 сообщений
                if self.stats['total_messages'] > 0 and self.stats['total_messages'] % 50 == 0:
                    self.print_statistics()
                    
        except KeyboardInterrupt:
            logger.info("\n⏹️  Остановка по запросу пользователя")
        except Exception as e:
            logger.error(f"❌ Критическая ошибка: {e}")
        finally:
            self.print_statistics()
            self.close()

    def check_topics_availability(self) -> bool:
        """Проверка доступности топиков"""
        try:
            metadata = self.consumer.list_topics(timeout=10)
            available_topics = set(metadata.topics.keys())
            
            logger.info(f"📋 Доступные топики: {sorted(available_topics)}")
            
            missing_topics = set(self.topics) - available_topics
            if missing_topics:
                logger.warning(f"⚠️  Отсутствующие топики: {missing_topics}")
                return False
            else:
                logger.info("✅ Все требуемые топики доступны")
                return True
                
        except Exception as e:
            logger.error(f"❌ Ошибка проверки топиков: {e}")
            return False

    def close(self):
        """Закрытие консьюмера"""
        logger.info("Закрытие консьюмера...")
        self.consumer.close()
        logger.info("✓ Консьюмер закрыт")


def main():
    """Основная функция для тестирования"""
    try:
        # Настройки подключения для Docker Compose
        bootstrap_servers = 'localhost:9092,localhost:9093,localhost:9094'
        topics = ['processed-events', 'analytics-events', 'purchase-events']
        group_id = 'nifi-test-consumer-group'
        
        # Создание консьюмера
        consumer = KafkaNiFiTestConsumer(bootstrap_servers, topics, group_id)
        
        # Проверка доступности топиков
        if not consumer.check_topics_availability():
            logger.warning("⚠️  Некоторые топики недоступны, но продолжаем...")
        
        logger.info("\n🎯 Режимы работы:")
        logger.info("1. Непрерывное чтение (по умолчанию)")
        logger.info("2. Чтение с таймаутом")
        
        mode = input("\nВыберите режим (1/2) [1]: ").strip() or "1"
        
        if mode == "1":
            consumer.consume_messages()
        elif mode == "2":
            timeout = input("Таймаут в секундах [60]: ").strip()
            timeout = int(timeout) if timeout.isdigit() else 60
            consumer.consume_messages(timeout)
        
    except KeyboardInterrupt:
        logger.info("\n⏹️  Программа остановлена пользователем")
    except Exception as e:
        logger.error(f"❌ Ошибка: {e}")


if __name__ == "__main__":
    main() 