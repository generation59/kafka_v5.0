#!/usr/bin/env python3
"""
Test Producer для тестирования интеграции Kafka + NiFi
Отправляет тестовые события в топик user-events для обработки в NiFi
"""

import json
import time
import random
import uuid
from datetime import datetime
from typing import Dict, Any

from kafka import KafkaProducer
from kafka.errors import KafkaError
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
        self.producer = KafkaProducer(
            bootstrap_servers=bootstrap_servers,
            value_serializer=lambda v: json.dumps(v, ensure_ascii=False).encode('utf-8'),
            key_serializer=lambda k: k.encode('utf-8') if k else None,
            acks='all',  # Ждем подтверждения от всех реплик
            retries=3,
            batch_size=16384,
            linger_ms=10,
            compression_type='snappy',
            max_in_flight_requests_per_connection=1,
            enable_idempotence=True
        )
        
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

    def send_event(self, event: Dict[str, Any], key: str = None) -> None:
        """Отправка события в Kafka"""
        
        if not key:
            key = event['userId']
            
        try:
            future = self.producer.send(
                self.topic,
                key=key,
                value=event
            )
            
            # Добавляем callback
            future.add_callback(self._on_send_success)
            future.add_errback(self._on_send_error)
            
            logger.info(f"✓ Отправлено событие: {event['eventType']} для пользователя {event['userId']}")
            
        except Exception as e:
            logger.error(f"✗ Ошибка отправки события: {e}")

    def _on_send_success(self, record_metadata):
        """Callback при успешной отправке"""
        logger.info(f"  → Сообщение доставлено в топик '{record_metadata.topic}', "
                   f"партиция {record_metadata.partition}, offset {record_metadata.offset}")

    def _on_send_error(self, exception):
        """Callback при ошибке отправки"""
        logger.error(f"  ✗ Ошибка доставки сообщения: {exception}")

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
                
                time.sleep(interval)
                
        except KeyboardInterrupt:
            logger.info(f"\n⏹️ Получен сигнал остановки")
        
        finally:
            self.producer.flush()
            elapsed = time.time() - start_time
            actual_rate = events_sent / elapsed * 60
            logger.info(f"\n📈 Финальная статистика:")
            logger.info(f"   Отправлено: {events_sent} событий")
            logger.info(f"   Время работы: {elapsed:.1f} секунд")
            logger.info(f"   Средняя скорость: {actual_rate:.1f} событий/мин")

    def close(self):
        """Закрытие продюсера"""
        self.producer.close()
        logger.info("Продюсер закрыт")


def main():
    """Главная функция для тестирования"""
    # Конфигурация
    BOOTSTRAP_SERVERS = 'localhost:9092,localhost:9093,localhost:9094'
    TOPIC = 'user-events'
    
    try:
        # Создание продюсера
        producer = KafkaNiFiTestProducer(BOOTSTRAP_SERVERS, TOPIC)
        
        print("\nВыберите режим работы:")
        print("1. Отправить пакет событий")
        print("2. Непрерывная отправка событий")
        print("3. Отправить одно тестовое событие")
        
        choice = input("\nВведите номер режима (1-3): ").strip()
        
        if choice == '1':
            count = input("Количество событий (по умолчанию 50): ").strip()
            count = int(count) if count else 50
            
            delay = input("Задержка между событиями в секундах (по умолчанию 1.0): ").strip()
            delay = float(delay) if delay else 1.0
            
            producer.send_batch_events(count, delay)
            
        elif choice == '2':
            rate = input("События в минуту (по умолчанию 30): ").strip()
            rate = int(rate) if rate else 30
            
            duration = input("Продолжительность в минутах (по умолчанию 5): ").strip()
            duration = int(duration) if duration else 5
            
            producer.send_continuous_events(rate, duration)
            
        elif choice == '3':
            event = producer.generate_user_event()
            logger.info(f"Генерированное событие: {json.dumps(event, indent=2, ensure_ascii=False)}")
            producer.send_event(event)
            producer.producer.flush()
            
        else:
            logger.error("Неверный выбор!")
            return
        
        # Закрытие продюсера
        producer.close()
        
    except KeyboardInterrupt:
        logger.info("\nОстановка продюсера...")
    except Exception as e:
        logger.error(f"Ошибка: {e}")
        import traceback
        traceback.print_exc()


if __name__ == '__main__':
    main() 