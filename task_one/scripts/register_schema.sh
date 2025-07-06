#!/bin/bash

# Скрипт для регистрации Avro схемы в Schema Registry
# Версия: 1.0

set -e

# Конфигурация
SCHEMA_REGISTRY_URL="http://localhost:8081"
SCHEMA_FILE="../schemas/user-event.avsc"
SUBJECT_NAME="user-events-value"

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Проверка доступности Schema Registry
check_schema_registry() {
    log_info "Проверка доступности Schema Registry..."
    
    if curl -s -f "$SCHEMA_REGISTRY_URL/subjects" > /dev/null; then
        log_info "Schema Registry доступен ✓"
    else
        log_error "Schema Registry недоступен по адресу $SCHEMA_REGISTRY_URL"
        log_error "Убедитесь, что Schema Registry запущен и доступен"
        exit 1
    fi
}

# Проверка файла схемы
check_schema_file() {
    log_info "Проверка файла схемы..."
    
    if [ ! -f "$SCHEMA_FILE" ]; then
        log_error "Файл схемы не найден: $SCHEMA_FILE"
        exit 1
    fi
    
    # Проверка валидности JSON
    if jq empty "$SCHEMA_FILE" 2>/dev/null; then
        log_info "Файл схемы валиден ✓"
    else
        log_error "Файл схемы содержит невалидный JSON"
        exit 1
    fi
}

# Регистрация схемы
register_schema() {
    log_info "Регистрация схемы '$SUBJECT_NAME'..."
    
    # Подготовка JSON для отправки
    local schema_json=$(jq -c . "$SCHEMA_FILE")
    local request_body=$(jq -n --arg schema "$schema_json" '{schema: $schema}')
    
    # Отправка запроса
    local response=$(curl -s -X POST \
        -H "Content-Type: application/vnd.schemaregistry.v1+json" \
        -d "$request_body" \
        "$SCHEMA_REGISTRY_URL/subjects/$SUBJECT_NAME/versions")
    
    # Проверка результата
    if echo "$response" | jq empty 2>/dev/null; then
        if echo "$response" | jq -e '.error_code' > /dev/null 2>&1; then
            local error_code=$(echo "$response" | jq -r '.error_code')
            local error_message=$(echo "$response" | jq -r '.message')
            log_error "Ошибка регистрации схемы: $error_code - $error_message"
            exit 1
        else
            local schema_id=$(echo "$response" | jq -r '.id')
            log_info "Схема успешно зарегистрирована с ID: $schema_id ✓"
        fi
    else
        log_error "Получен неожиданный ответ: $response"
        exit 1
    fi
}

# Проверка зарегистрированной схемы
verify_schema() {
    log_info "Проверка зарегистрированной схемы..."
    
    # Получение списка версий
    local versions=$(curl -s "$SCHEMA_REGISTRY_URL/subjects/$SUBJECT_NAME/versions")
    log_info "Версии схемы: $versions"
    
    # Получение последней версии
    local latest_schema=$(curl -s "$SCHEMA_REGISTRY_URL/subjects/$SUBJECT_NAME/versions/latest")
    local schema_id=$(echo "$latest_schema" | jq -r '.id')
    local version=$(echo "$latest_schema" | jq -r '.version')
    
    log_info "Последняя версия схемы: $version (ID: $schema_id)"
    
    # Проверка совместимости
    log_info "Проверка обратной совместимости..."
    local compatibility=$(curl -s "$SCHEMA_REGISTRY_URL/config/$SUBJECT_NAME")
    log_info "Настройки совместимости: $compatibility"
}

# Показать все зарегистрированные схемы
show_all_schemas() {
    log_info "Список всех зарегистрированных схем:"
    
    local subjects=$(curl -s "$SCHEMA_REGISTRY_URL/subjects")
    echo "$subjects" | jq -r '.[]' | while read -r subject; do
        local versions=$(curl -s "$SCHEMA_REGISTRY_URL/subjects/$subject/versions")
        echo "  - $subject: версии $versions"
    done
}

# Главная функция
main() {
    echo "================================================"
    echo "    Регистрация Avro схемы в Schema Registry"
    echo "================================================"
    echo
    
    # Проверка аргументов
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "Использование: $0 [опции]"
        echo "Опции:"
        echo "  --help, -h       Показать эту справку"
        echo "  --list           Показать все зарегистрированные схемы"
        echo "  --verify-only    Только проверить существующую схему"
        echo
        echo "Конфигурация:"
        echo "  Schema Registry URL: $SCHEMA_REGISTRY_URL"
        echo "  Файл схемы: $SCHEMA_FILE"
        echo "  Имя субъекта: $SUBJECT_NAME"
        exit 0
    fi
    
    if [ "$1" = "--list" ]; then
        check_schema_registry
        show_all_schemas
        exit 0
    fi
    
    # Основной процесс
    check_schema_registry
    check_schema_file
    
    if [ "$1" != "--verify-only" ]; then
        register_schema
    fi
    
    verify_schema
    
    echo
    echo "================================================"
    log_info "Схема успешно зарегистрирована!"
    echo "================================================"
    echo
    log_info "Для использования схемы в приложении:"
    echo "  Schema Registry URL: $SCHEMA_REGISTRY_URL"
    echo "  Subject Name: $SUBJECT_NAME"
    echo "  Schema ID: получите через API"
    echo
    log_info "Пример использования в Python:"
    echo "  from confluent_kafka import avro"
    echo "  avro_consumer = avro.AvroConsumer({'bootstrap.servers': 'localhost:9092',"
    echo "                                     'schema.registry.url': '$SCHEMA_REGISTRY_URL'})"
}

# Обработка сигналов
trap 'log_error "Регистрация прервана пользователем"; exit 1' INT TERM

# Запуск основной функции
main "$@" 