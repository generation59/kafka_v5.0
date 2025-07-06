#!/bin/bash

# Скрипт для настройки SSL сертификата Yandex Cloud
# Версия: 1.0

set -e

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

# Основная функция
main() {
    echo "================================================"
    echo "    Настройка SSL для Yandex Cloud Kafka"
    echo "================================================"
    echo
    
    # Проверка ОС
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        log_info "Обнаружена Linux система"
        setup_linux_ssl
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        log_info "Обнаружена macOS система"
        setup_macos_ssl
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
        log_info "Обнаружена Windows система"
        setup_windows_ssl
    else
        log_error "Неподдерживаемая операционная система: $OSTYPE"
        exit 1
    fi
}

# Настройка для Linux
setup_linux_ssl() {
    log_info "Скачивание корневого сертификата Yandex..."
    
    # Создание директории
    sudo mkdir -p /usr/local/share/ca-certificates/Yandex
    
    # Скачивание сертификата
    sudo wget -O /usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt \
        "https://storage.yandexcloud.net/cloud-certs/CA.pem"
    
    # Обновление доверенных сертификатов
    sudo update-ca-certificates
    
    log_info "SSL сертификат установлен для Linux ✓"
    log_info "Путь: /usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt"
}

# Настройка для macOS
setup_macos_ssl() {
    log_info "Скачивание корневого сертификата Yandex..."
    
    # Создание директории
    sudo mkdir -p /usr/local/share/ca-certificates/Yandex
    
    # Скачивание сертификата
    sudo curl -o /usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt \
        "https://storage.yandexcloud.net/cloud-certs/CA.pem"
    
    log_info "SSL сертификат установлен для macOS ✓"
    log_info "Путь: /usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt"
}

# Настройка для Windows
setup_windows_ssl() {
    log_warn "Для Windows выполните следующие шаги:"
    echo
    echo "1. Скачайте сертификат:"
    echo "   https://storage.yandexcloud.net/cloud-certs/CA.pem"
    echo
    echo "2. Сохраните как YandexInternalRootCA.crt"
    echo
    echo "3. Укажите путь в конфигурации Python:"
    echo "   ssl_ca_location=C:\\path\\to\\YandexInternalRootCA.crt"
    echo
    log_info "Альтернативно, используйте WSL с Linux инструкциями"
}

# Проверка установки
verify_ssl() {
    local cert_path="/usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt"
    
    if [ -f "$cert_path" ]; then
        log_info "Сертификат найден ✓"
        
        # Проверка срока действия
        openssl x509 -in "$cert_path" -text -noout | grep -E "Not Before|Not After"
        
        return 0
    else
        log_error "Сертификат не найден: $cert_path"
        return 1
    fi
}

# Тестирование подключения
test_connection() {
    log_info "Тестирование подключения к Yandex Cloud Kafka..."
    
    # Использование kcat если доступен
    if command -v kcat >/dev/null 2>&1; then
        log_info "Тестирование с помощью kcat..."
        timeout 10 kcat -L \
            -b rc1a-v063i1touj4ue341.mdb.yandexcloud.net:9091 \
            -X security.protocol=SASL_SSL \
            -X sasl.mechanism=SCRAM-SHA-512 \
            -X sasl.username="kafka_user" \
            -X sasl.password="kafka_password" \
            -X ssl.ca.location=/usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt \
            || log_warn "Не удалось подключиться с kcat"
    else
        log_warn "kcat не установлен, пропуск тестирования"
    fi
    
    # Тестирование с Python
    if command -v python3 >/dev/null 2>&1; then
        log_info "Тестирование с Python..."
        python3 -c "
import ssl
import socket
try:
    context = ssl.create_default_context()
    context.load_verify_locations('/usr/local/share/ca-certificates/Yandex/YandexInternalRootCA.crt')
    with socket.create_connection(('rc1a-v063i1touj4ue341.mdb.yandexcloud.net', 9091), timeout=10) as sock:
        with context.wrap_socket(sock, server_hostname='rc1a-v063i1touj4ue341.mdb.yandexcloud.net') as ssock:
            print('✓ SSL подключение успешно')
except Exception as e:
    print(f'✗ SSL ошибка: {e}')
"
    fi
}

# Запуск основной функции
if [ "$1" = "--verify" ]; then
    verify_ssl
elif [ "$1" = "--test" ]; then
    test_connection
elif [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Использование: $0 [опции]"
    echo "Опции:"
    echo "  --verify    Проверить установленный сертификат"
    echo "  --test      Протестировать подключение"
    echo "  --help      Показать эту справку"
else
    main
    verify_ssl
    test_connection
fi

echo
log_info "Настройка SSL завершена!"
echo "Теперь можно использовать Python клиенты для Yandex Cloud" 