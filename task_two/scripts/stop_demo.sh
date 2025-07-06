#!/bin/bash

# ================================================================
# ОСТАНОВКА ДЕМОНСТРАЦИИ ЗАДАНИЯ 2
# ================================================================

echo "================================================================"
echo "        ОСТАНОВКА ДЕМОНСТРАЦИИ ЗАДАНИЯ 2"
echo "================================================================"

# Остановка Python consumer если запущен
if [ -f ".consumer_pid" ]; then
    CONSUMER_PID=$(cat .consumer_pid)
    if ps -p $CONSUMER_PID > /dev/null 2>&1; then
        echo "🛑 Остановка Python consumer (PID: $CONSUMER_PID)..."
        kill $CONSUMER_PID
        echo "✅ Python consumer остановлен"
    else
        echo "ℹ️  Python consumer уже остановлен"
    fi
    rm -f .consumer_pid
fi

# Остановка Docker Compose
echo "🛑 Остановка Docker Compose..."
docker compose down --volumes --remove-orphans

echo "🗑️  Удаление Docker образов (опционально)..."
read -p "Удалить Docker образы? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker compose down --rmi all --volumes --remove-orphans
    echo "✅ Docker образы удалены"
fi

# Очистка логов
echo "🧹 Очистка логов..."
rm -f python/consumer.log
rm -f python/producer.log

echo ""
echo "================================================================"
echo "        ДЕМОНСТРАЦИЯ ОСТАНОВЛЕНА"
echo "================================================================"
echo ""
echo "✅ Все сервисы остановлены"
echo "✅ Volumes удалены"
echo "✅ Логи очищены"
echo ""
echo "Для повторного запуска: ./demo_task2.sh" 