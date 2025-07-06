#!/bin/bash

# Скрипт для регистрации схемы в Docker среде Schema Registry
# Версия: 1.0

set -e

# Конфигурация
SCHEMA_REGISTRY_URL="http://localhost:8081"
SCHEMA_FILE="../task_one/schemas/user-event.avsc"
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

# Проверка Docker Compose
check_docker_compose() {
    log_info "Проверка Docker Compose среды..."
    
    if docker-compose ps | grep -q "kafka-schema-registry"; then
        log_info "Schema Registry контейнер найден ✓"
    else
        log_error "Schema Registry контейнер не найден"
        log_error "Запустите Docker Compose: docker-compose up -d"
        exit 1
    fi
}

# Проверка доступности Schema Registry
check_schema_registry() {
    log_info "Проверка доступности Schema Registry..."
    
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if curl -s -f "$SCHEMA_REGISTRY_URL/subjects" > /dev/null 2>&1; then
            log_info "Schema Registry доступен ✓"
            return 0
        fi
        
        attempt=$((attempt + 1))
        log_info "Попытка $attempt/$max_attempts..."
        sleep 2
    done
    
    log_error "Schema Registry недоступен после $max_attempts попыток"
    log_error "Проверьте статус: docker-compose logs schema-registry"
    exit 1
}

# Регистрация схемы
register_schema() {
    log_info "Регистрация схемы '$SUBJECT_NAME'..."
    
    # Проверка файла схемы
    if [ ! -f "$SCHEMA_FILE" ]; then
        log_error "Файл схемы не найден: $SCHEMA_FILE"
        exit 1
    fi
    
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
            
            # Если схема уже существует, это нормально
            if [ "$error_code" = "40901" ]; then
                log_warn "Схема уже зарегистрирована"
            else
                log_error "Ошибка регистрации схемы: $error_code - $error_message"
                exit 1
            fi
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
    
    # Получение последней версии
    local latest_schema=$(curl -s "$SCHEMA_REGISTRY_URL/subjects/$SUBJECT_NAME/versions/latest")
    
    if echo "$latest_schema" | jq empty 2>/dev/null; then
        local schema_id=$(echo "$latest_schema" | jq -r '.id')
        local version=$(echo "$latest_schema" | jq -r '.version')
        log_info "Схема найдена: версия $version, ID $schema_id ✓"
        
        # Показать схему
        echo "$latest_schema" | jq '.schema' | jq -r . | jq .
    else
        log_error "Не удалось получить информацию о схеме"
        exit 1
    fi
}

# Показать все схемы
show_all_schemas() {
    log_info "Список всех зарегистрированных схем:"
    
    local subjects=$(curl -s "$SCHEMA_REGISTRY_URL/subjects")
    if [ "$subjects" = "[]" ]; then
        log_warn "Нет зарегистрированных схем"
    else
        echo "$subjects" | jq -r '.[]' | while read -r subject; do
            local versions=$(curl -s "$SCHEMA_REGISTRY_URL/subjects/$subject/versions")
            echo "  - $subject: версии $versions"
        done
    fi
}

# Главная функция
main() {
    echo "================================================"
    echo "  Регистрация схемы в Docker Schema Registry"
    echo "================================================"
    echo
    
    # Проверка аргументов
    if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo "Использование: $0 [опции]"
        echo "Опции:"
        echo "  --help, -h     Показать эту справку"
        echo "  --list         Показать все зарегистрированные схемы"
        echo "  --verify-only  Только проверить существующую схему"
        echo
        echo "Конфигурация:"
        echo "  Schema Registry URL: $SCHEMA_REGISTRY_URL"
        echo "  Файл схемы: $SCHEMA_FILE"
        echo "  Имя субъекта: $SUBJECT_NAME"
        echo
        echo "Перед запуском убедитесь, что Docker Compose запущен:"
        echo "  docker-compose up -d"
        exit 0
    fi
    
    # Проверка Docker среды
    check_docker_compose
    check_schema_registry
    
    if [ "$1" = "--list" ]; then
        show_all_schemas
        exit 0
    fi
    
    if [ "$1" != "--verify-only" ]; then
        register_schema
    fi
    
    verify_schema
    
    echo
    echo "================================================"
    log_info "Операция завершена успешно!"
    echo "================================================"
    echo
    log_info "Доступные веб-интерфейсы:"
    echo "  - Kafka UI: http://localhost:8082"
    echo "  - Schema Registry API: http://localhost:8081"
    echo "  - Apache NiFi: http://localhost:8080/nifi"
}

# Запуск основной функции
main "$@" 