#!/usr/bin/env python3
"""
Test Producer для тестирования интеграции Kafka + NiFi
Отправляет тестовые события в топик user-events для обработки в NiFi
Использует confluent-kafka-python для совместимости с Python 3.12
"""

import json
import time
import random
import uuid
from datetime import datetime
from typing import Dict, Any

from confluent_kafka import Producer
import logging

# Настройка логирования
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class KafkaNiFiTestProducer:
    """Тестовый продюсер для отправки событий в Kafka для обработки в NiFi"""
    
    def __init__(self, bootstrap_servers: str, topic: str):
        """
        Инициализация продюсера
        
        Args:
            bootstrap_servers: Адреса Kafka брокеров
            topic: Имя топика для отправки
        """
        self.topic = topic
        
        # Настройка продюсера с оптимальными параметрами
        self.producer = Producer({
            'bootstrap.servers': bootstrap_servers,
            'acks': 'all',  # Ждем подтверждения от всех реплик
            'retries': 3,
            'batch.size': 16384,
            'linger.ms': 10,
            'compression.type': 'snappy',
            'max.in.flight.requests.per.connection': 1,
            'enable.idempotence': True
        })
        
        logger.info(f"Продюсер инициализирован для топика '{topic}'")
        logger.info(f"Bootstrap серверы: {bootstrap_servers}")

    def generate_user_event(self, event_type: str = None) -> Dict[str, Any]:
        """Генерация случайного пользовательского события"""
        
        event_types = ['LOGIN', 'LOGOUT', 'PURCHASE', 'VIEW_PRODUCT', 'ADD_TO_CART', 'REGISTER']
        users = [f"user_{i}" for i in range(1, 21)]  # 20 пользователей
        products = [f"product_{i}" for i in range(1, 51)]  # 50 продуктов
        
        user_id = random.choice(users)
        if not event_type:
            event_type = random.choice(event_types)
        
        # Базовое событие
        event = {
            'userId': user_id,
            'eventType': event_type,
            'timestamp': int(time.time() * 1000),
            'sessionId': str(uuid.uuid4()),
            'userAgent': f'Mozilla/5.0 (TestAgent {random.randint(1, 100)})',
            'ipAddress': f"192.168.{random.randint(1, 255)}.{random.randint(1, 255)}",
            'metadata': {
                'source': 'test_producer',
                'version': '2.0',
                'environment': 'integration_test'
            }
        }
        
        # Дополнительные поля в зависимости от типа события
        if event_type in ['PURCHASE', 'VIEW_PRODUCT', 'ADD_TO_CART']:
            event['productId'] = random.choice(products)
            
        if event_type == 'PURCHASE':
            event['amount'] = round(random.uniform(10.0, 1000.0), 2)
            event['currency'] = 'USD'
            
        if event_type == 'VIEW_PRODUCT':
            event['viewDuration'] = random.randint(10, 300)  # секунды
            
        if event_type == 'REGISTER':
            event['email'] = f"{user_id}@example.com"
            event['source'] = random.choice(['web', 'mobile', 'api'])
            
        return event

    def delivery_report(self, err, msg):
        """Callback при доставке сообщения"""
        if err is not None:
            logger.error(f'✗ Ошибка доставки сообщения: {err}')
        else:
            logger.info(f'✓ Сообщение доставлено в топик {msg.topic()}, '
                       f'партиция {msg.partition()}, offset {msg.offset()}')

    def send_event(self, event: Dict[str, Any], key: str = None) -> None:
        """Отправка события в Kafka"""
        
        if not key:
            key = event['userId']
            
        try:
            # Сериализация в JSON
            value = json.dumps(event, ensure_ascii=False).encode('utf-8')
            key_bytes = key.encode('utf-8') if key else None
            
            # Отправка сообщения
            self.producer.produce(
                topic=self.topic,
                key=key_bytes,
                value=value,
                callback=self.delivery_report
            )
            
            # Триггер доставки callbacks
            self.producer.poll(0)
            
            logger.info(f"📤 Отправлено событие: {event['eventType']} для пользователя {event['userId']}")
            
        except Exception as e:
            logger.error(f"✗ Ошибка отправки события: {e}")

    def send_batch_events(self, count: int = 50, delay: float = 1.0):
        """Отправка пакета тестовых событий"""
        logger.info(f"\n=== Отправка {count} тестовых событий для NiFi ===")
        
        event_types = ['LOGIN', 'LOGOUT', 'PURCHASE', 'VIEW_PRODUCT', 'ADD_TO_CART', 'REGISTER']
        
        # Распределение типов событий
        type_distribution = {
            'VIEW_PRODUCT': 0.4,  # 40% просмотров продуктов
            'LOGIN': 0.2,         # 20% входов
            'PURCHASE': 0.15,     # 15% покупок
            'ADD_TO_CART': 0.15,  # 15% добавлений в корзину
            'LOGOUT': 0.05,       # 5% выходов
            'REGISTER': 0.05      # 5% регистраций
        }
        
        events_sent = 0
        
        for i in range(count):
            # Выбор типа события согласно распределению
            rand = random.random()
            cumulative = 0
            selected_type = 'VIEW_PRODUCT'  # по умолчанию
            
            for event_type, probability in type_distribution.items():
                cumulative += probability
                if rand <= cumulative:
                    selected_type = event_type
                    break
            
            # Генерация и отправка события
            event = self.generate_user_event(selected_type)
            self.send_event(event)
            
            events_sent += 1
            
            # Статистика каждые 10 событий
            if events_sent % 10 == 0:
                logger.info(f"Прогресс: {events_sent}/{count} событий отправлено")
            
            # Задержка между событиями
            if delay > 0:
                time.sleep(delay)
        
        # Обеспечиваем доставку всех сообщений
        self.producer.flush()
        logger.info(f"\n✓ Все {count} событий отправлены и подтверждены")

    def send_continuous_events(self, events_per_minute: int = 30, duration_minutes: int = 5):
        """Отправка непрерывного потока событий"""
        logger.info(f"\n=== Непрерывная отправка событий ===")
        logger.info(f"Скорость: {events_per_minute} событий/минуту")
        logger.info(f"Продолжительность: {duration_minutes} минут")
        logger.info("Для остановки нажмите Ctrl+C")
        
        interval = 60.0 / events_per_minute  # интервал между событиями в секундах
        total_events = events_per_minute * duration_minutes
        events_sent = 0
        start_time = time.time()
        
        try:
            while events_sent < total_events:
                event = self.generate_user_event()
                self.send_event(event)
                events_sent += 1
                
                # Статистика каждые 20 событий
                if events_sent % 20 == 0:
                    elapsed = time.time() - start_time
                    rate = events_sent / elapsed * 60  # события в минуту
                    logger.info(f"Статистика: {events_sent}/{total_events} событий, "
                               f"скорость: {rate:.1f} событий/мин")
                
                # Задержка между событиями
                if interval > 0:
                    time.sleep(interval)
                    
        except KeyboardInterrupt:
            logger.info("\n⏹️  Остановка по запросу пользователя")
        
        # Обеспечиваем доставку всех сообщений
        self.producer.flush()
        logger.info(f"\n✓ Отправлено {events_sent} событий")

    def close(self):
        """Закрытие продюсера"""
        logger.info("Закрытие продюсера...")
        self.producer.flush()
        logger.info("✓ Продюсер закрыт")


def main():
    """Основная функция для тестирования"""
    try:
        # Настройки подключения для Docker Compose
        bootstrap_servers = 'localhost:9092,localhost:9093,localhost:9094'
        topic = 'user-events'
        
        # Создание продюсера
        producer = KafkaNiFiTestProducer(bootstrap_servers, topic)
        
        logger.info("\n🎯 Режимы работы:")
        logger.info("1. Отправка пакета событий (по умолчанию)")
        logger.info("2. Непрерывная отправка событий")
        
        mode = input("\nВыберите режим (1/2) [1]: ").strip() or "1"
        
        if mode == "1":
            count = input("Количество событий [50]: ").strip()
            count = int(count) if count.isdigit() else 50
            
            delay = input("Задержка между событиями в сек [1.0]: ").strip()
            delay = float(delay) if delay else 1.0
            
            producer.send_batch_events(count, delay)
            
        elif mode == "2":
            rate = input("События в минуту [30]: ").strip()
            rate = int(rate) if rate.isdigit() else 30
            
            duration = input("Продолжительность в минутах [5]: ").strip()
            duration = int(duration) if duration.isdigit() else 5
            
            producer.send_continuous_events(rate, duration)
        
        producer.close()
        
    except KeyboardInterrupt:
        logger.info("\n⏹️  Программа остановлена пользователем")
    except Exception as e:
        logger.error(f"❌ Ошибка: {e}")


if __name__ == "__main__":
    main() 