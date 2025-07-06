#!/usr/bin/env python3
"""
Test Consumer для тестирования интеграции Kafka + NiFi
Читает обработанные события из топиков processed-events, analytics-events и т.д.
"""

import json
import time
import signal
import sys
from datetime import datetime
from typing import Dict, Any, List
from collections import defaultdict

from kafka import KafkaConsumer
from kafka.errors import KafkaError
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
        self.consumer = KafkaConsumer(
            *topics,
            bootstrap_servers=bootstrap_servers,
            group_id=group_id,
            auto_offset_reset='latest',  # Читаем только новые сообщения
            enable_auto_commit=True,
            auto_commit_interval_ms=1000,
            value_deserializer=lambda m: json.loads(m.decode('utf-8')) if m else None,
            key_deserializer=lambda k: k.decode('utf-8') if k else None,
            session_timeout_ms=30000,
            heartbeat_interval_ms=10000,
            max_poll_records=100,
            fetch_min_bytes=1,
            fetch_max_wait_ms=500
        )
        
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
            topic = message.topic
            partition = message.partition
            offset = message.offset
            key = message.key
            value = message.value
            timestamp = message.timestamp
            
            # Обновление статистики
            self.stats['total_messages'] += 1
            self.stats['messages_by_topic'][topic] += 1
            
            # Извлечение типа события (если есть)
            event_type = None
            if isinstance(value, dict):
                event_type = value.get('eventType', 'UNKNOWN')
                self.stats['messages_by_type'][event_type] += 1
            
            # Определение времени обработки (если есть метаданные NiFi)
            processing_time = None
            if isinstance(value, dict) and 'nifi.processing.timestamp' in value:
                try:
                    processing_timestamp = int(value['nifi.processing.timestamp'])
                    original_timestamp = value.get('timestamp', int(time.time() * 1000))
                    processing_time = processing_timestamp - original_timestamp
                except (ValueError, TypeError):
                    pass
            
            # Форматированный вывод сообщения
            timestamp_str = datetime.fromtimestamp(timestamp / 1000).strftime('%H:%M:%S.%f')[:-3] if timestamp else 'N/A'
            
            logger.info(f"📨 [{timestamp_str}] Топик: {topic}")
            logger.info(f"   📍 Партиция: {partition}, Offset: {offset}")
            logger.info(f"   🔑 Ключ: {key}")
            
            if event_type:
                logger.info(f"   📊 Тип события: {event_type}")
            
            if processing_time:
                logger.info(f"   ⏱️  Время обработки в NiFi: {processing_time}ms")
            
            # Подробности сообщения (если это JSON)
            if isinstance(value, dict):
                logger.info(f"   📄 Данные: {self._format_message_data(value)}")
            else:
                logger.info(f"   📄 Данные: {value}")
            
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
            logger.info("\n🏷️  По типам событий:")
            for event_type, count in self.stats['messages_by_type'].items():
                percentage = (count / self.stats['total_messages']) * 100 if self.stats['total_messages'] > 0 else 0
                logger.info(f"   {event_type}: {count} ({percentage:.1f}%)")
        
        logger.info("=" * 50)

    def consume_messages(self, timeout_sec: int = None):
        """
        Основной цикл чтения сообщений
        
        Args:
            timeout_sec: Таймаут в секундах (None для бесконечного чтения)
        """
        logger.info(f"\n🚀 Начинаем чтение сообщений из топиков: {self.topics}")
        logger.info("Для остановки нажмите Ctrl+C")
        
        start_time = time.time()
        last_stats_time = start_time
        
        try:
            while self.running:
                # Проверка таймаута
                if timeout_sec and (time.time() - start_time) > timeout_sec:
                    logger.info(f"⏰ Достигнут таймаут {timeout_sec} секунд")
                    break
                
                # Печать статистики каждые 30 секунд
                if time.time() - last_stats_time > 30:
                    self.print_statistics()
                    last_stats_time = time.time()
                
                # Чтение сообщений
                message_batch = self.consumer.poll(timeout_ms=1000)
                
                if not message_batch:
                    continue
                
                # Обработка полученных сообщений
                for topic_partition, messages in message_batch.items():
                    for message in messages:
                        if not self.running:
                            break
                        
                        self.process_message(message)
                
                # Коммит offset'ов
                self.consumer.commit()
                
        except KeyboardInterrupt:
            logger.info("\n⏹️ Получен сигнал остановки")
        
        except Exception as e:
            logger.error(f"❌ Критическая ошибка в консьюмере: {e}")
            import traceback
            traceback.print_exc()
        
        finally:
            logger.info("🔚 Завершение работы консьюмера...")
            self.print_statistics()
            self.consumer.close()
            logger.info("✅ Консьюмер остановлен")

    def check_topics_availability(self) -> bool:
        """Проверка доступности топиков"""
        try:
            metadata = self.consumer.list_consumer_group_offsets(self.group_id)
            available_topics = self.consumer.topics()
            
            logger.info("\n📋 Проверка доступности топиков:")
            
            all_available = True
            for topic in self.topics:
                if topic in available_topics:
                    partitions = self.consumer.partitions_for_topic(topic)
                    logger.info(f"  ✅ {topic}: доступен ({len(partitions) if partitions else 0} партиций)")
                else:
                    logger.warning(f"  ❌ {topic}: недоступен")
                    all_available = False
            
            return all_available
            
        except Exception as e:
            logger.error(f"❌ Ошибка проверки топиков: {e}")
            return False


def main():
    """Главная функция"""
    # Конфигурация
    BOOTSTRAP_SERVERS = 'localhost:9092,localhost:9093,localhost:9094'
    
    # Доступные топики для мониторинга
    available_topics = {
        '1': ['processed-events'],
        '2': ['analytics-events'], 
        '3': ['purchase-events'],
        '4': ['error-events'],
        '5': ['processed-events', 'analytics-events', 'purchase-events'],
        '6': ['user-events', 'processed-events', 'analytics-events', 'purchase-events', 'error-events']
    }
    
    try:
        print("\nВыберите топики для мониторинга:")
        print("1. processed-events (основной выходной топик NiFi)")
        print("2. analytics-events (аналитические события)")
        print("3. purchase-events (события покупок)")
        print("4. error-events (события с ошибками)")
        print("5. Все выходные топики NiFi")
        print("6. Все топики (включая входной user-events)")
        
        choice = input("\nВведите номер (1-6): ").strip()
        
        if choice not in available_topics:
            logger.error("Неверный выбор!")
            return
        
        topics = available_topics[choice]
        
        # Настройка группы консьюмеров
        group_id = f"nifi-test-consumer-{int(time.time())}"
        
        # Создание консьюмера
        consumer = KafkaNiFiTestConsumer(
            BOOTSTRAP_SERVERS, 
            topics, 
            group_id
        )
        
        # Проверка доступности топиков
        if not consumer.check_topics_availability():
            logger.warning("⚠️ Некоторые топики недоступны, но продолжаем...")
        
        # Настройка таймаута
        timeout_input = input("\nТаймаут в секундах (Enter для бесконечного чтения): ").strip()
        timeout = int(timeout_input) if timeout_input else None
        
        # Запуск чтения сообщений
        consumer.consume_messages(timeout)
        
    except KeyboardInterrupt:
        logger.info("\nОстановка консьюмера...")
    except Exception as e:
        logger.error(f"Ошибка: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    main() 