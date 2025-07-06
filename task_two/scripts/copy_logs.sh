#!/bin/bash

# Копирование логов из папки logs в корень для отчета
echo "📁 Копирование логов из logs/ в корень..."

if [ -d "logs" ]; then
    # Копируем нужные файлы
    cp logs/producer_logs.txt producer_logs.txt 2>/dev/null || echo "❌ producer_logs.txt не найден"
    cp logs/consumer_logs.txt consumer_logs.txt 2>/dev/null || echo "❌ consumer_logs.txt не найден"
    cp logs/nifi_logs.txt nifi_logs.txt 2>/dev/null || echo "❌ nifi_logs.txt не найден"
    cp logs/kafka_consumer_logs.txt kafka_consumer_logs.txt 2>/dev/null || echo "❌ kafka_consumer_logs.txt не найден"
    
    echo "✅ Файлы скопированы:"
    echo "   📄 producer_logs.txt"
    echo "   📄 consumer_logs.txt"
    echo "   📄 nifi_logs.txt"
    echo "   📄 kafka_consumer_logs.txt"
else
    echo "❌ Директория logs/ не найдена"
    echo "💡 Сначала запустите: ./collect_logs.sh"
fi 