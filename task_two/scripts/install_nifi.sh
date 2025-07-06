#!/bin/bash

# Apache NiFi Installation and Configuration Script
# Интеграция с Kafka кластером

set -e

# Переменные конфигурации
NIFI_VERSION="1.21.0"
NIFI_HOME="/opt/nifi"
NIFI_USER="nifi"
JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"

echo "=========================================="
echo "  Установка Apache NiFi"
echo "=========================================="

# Проверка прав root
if [[ $EUID -ne 0 ]]; then
   echo "Этот скрипт должен быть запущен с правами root" 
   exit 1
fi

echo "=== Шаг 1: Проверка Java ==="
if ! java -version 2>&1 | grep -q "11\|17"; then
    echo "Установка Java 11..."
    apt-get update
    apt-get install -y openjdk-11-jdk
else
    echo "✓ Java уже установлена"
fi

echo ""
echo "=== Шаг 2: Создание пользователя NiFi ==="
useradd -r -m -s /bin/bash $NIFI_USER || echo "Пользователь $NIFI_USER уже существует"

echo ""
echo "=== Шаг 3: Скачивание и установка Apache NiFi ==="
cd /opt

if [ ! -d "$NIFI_HOME" ]; then
    echo "Скачивание Apache NiFi ${NIFI_VERSION}..."
    wget "https://archive.apache.org/dist/nifi/${NIFI_VERSION}/nifi-${NIFI_VERSION}-bin.tar.gz"
    
    echo "Распаковка архива..."
    tar -xzf "nifi-${NIFI_VERSION}-bin.tar.gz"
    mv "nifi-${NIFI_VERSION}" nifi
    rm -f "nifi-${NIFI_VERSION}-bin.tar.gz"
    
    echo "✓ Apache NiFi установлен"
else
    echo "✓ Apache NiFi уже установлен"
fi

# Настройка прав доступа
chown -R $NIFI_USER:$NIFI_USER $NIFI_HOME

echo ""
echo "=== Шаг 4: Настройка конфигурации NiFi ==="

# Создание директорий
mkdir -p $NIFI_HOME/logs
mkdir -p $NIFI_HOME/database_repository
mkdir -p $NIFI_HOME/flowfile_repository
mkdir -p $NIFI_HOME/content_repository
mkdir -p $NIFI_HOME/provenance_repository

chown -R $NIFI_USER:$NIFI_USER $NIFI_HOME

# Настройка nifi.properties
NIFI_PROPERTIES="$NIFI_HOME/conf/nifi.properties"

# Backup original config
cp $NIFI_PROPERTIES $NIFI_PROPERTIES.backup

# Основные настройки для интеграции с Kafka
cat >> $NIFI_PROPERTIES << 'EOF'

# Custom settings for Kafka integration
nifi.web.http.host=0.0.0.0
nifi.web.http.port=8080
nifi.web.https.port=

# Security settings (disabled for demo)
nifi.security.user.login.identity.provider=
nifi.security.keystore=
nifi.security.keystoreType=
nifi.security.keystorePasswd=
nifi.security.keyPasswd=
nifi.security.truststore=
nifi.security.truststoreType=
nifi.security.truststorePasswd=
nifi.security.needClientAuth=

# Increase memory settings for production
nifi.jvm.heap.init=2g
nifi.jvm.heap.max=4g

# Performance tuning
nifi.flowcontroller.graceful.shutdown.period=20 sec
nifi.flowservice.writedelay.interval=2 sec
nifi.administrative.yield.duration=30 sec
nifi.bored.yield.duration=10 millis
nifi.processor.scheduling.timeout=1 min
EOF

echo ""
echo "=== Шаг 5: Настройка JVM параметров ==="
BOOTSTRAP_CONF="$NIFI_HOME/conf/bootstrap.conf"

# Обновление настроек JVM
sed -i 's/java.arg.2=-Xms512m/java.arg.2=-Xms2g/' $BOOTSTRAP_CONF
sed -i 's/java.arg.3=-Xmx512m/java.arg.3=-Xmx4g/' $BOOTSTRAP_CONF

# Добавление дополнительных JVM параметров
cat >> $BOOTSTRAP_CONF << 'EOF'

# Additional JVM settings for Kafka integration
java.arg.kafka.1=-Djava.net.preferIPv4Stack=true
java.arg.kafka.2=-Dcom.sun.management.jmxremote
java.arg.kafka.3=-Dcom.sun.management.jmxremote.port=9995
java.arg.kafka.4=-Dcom.sun.management.jmxremote.authenticate=false
java.arg.kafka.5=-Dcom.sun.management.jmxremote.ssl=false
EOF

echo ""
echo "=== Шаг 6: Создание systemd сервиса ==="

cat > /etc/systemd/system/nifi.service << EOF
[Unit]
Description=Apache NiFi
After=network.target
Wants=network.target

[Service]
Type=forking
User=$NIFI_USER
Group=$NIFI_USER
ExecStart=$NIFI_HOME/bin/nifi.sh start
ExecStop=$NIFI_HOME/bin/nifi.sh stop
ExecReload=$NIFI_HOME/bin/nifi.sh restart
KillMode=process
Restart=on-failure
RestartSec=30
TimeoutStopSec=60

Environment=JAVA_HOME=$JAVA_HOME
Environment=NIFI_HOME=$NIFI_HOME

[Install]
WantedBy=multi-user.target
EOF

echo ""
echo "=== Шаг 7: Настройка logback для логирования ==="

# Создание настроенного logback.xml
cat > $NIFI_HOME/conf/logback.xml << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<configuration scan="true" scanPeriod="30 seconds">
    <contextListener class="ch.qos.logback.classic.jul.LevelChangePropagator">
        <resetJUL>true</resetJUL>
    </contextListener>
    
    <appender name="APP_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <file>${org.apache.nifi.bootstrap.config.log.dir}/nifi-app.log</file>
        <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
            <fileNamePattern>${org.apache.nifi.bootstrap.config.log.dir}/nifi-app_%d{yyyy-MM-dd_HH}_%i.log</fileNamePattern>
            <maxFileSize>100MB</maxFileSize>
            <maxHistory>30</maxHistory>
            <totalSizeCap>10GB</totalSizeCap>
        </rollingPolicy>
        <encoder class="ch.qos.logback.classic.encoder.PatternLayoutEncoder">
            <pattern>%date %level [%thread] %logger{40} %msg%n</pattern>
            <immediateFlush>true</immediateFlush>
        </encoder>
    </appender>
    
    <appender name="KAFKA_FILE" class="ch.qos.logback.core.rolling.RollingFileAppender">
        <file>${org.apache.nifi.bootstrap.config.log.dir}/nifi-kafka.log</file>
        <rollingPolicy class="ch.qos.logback.core.rolling.SizeAndTimeBasedRollingPolicy">
            <fileNamePattern>${org.apache.nifi.bootstrap.config.log.dir}/nifi-kafka_%d{yyyy-MM-dd}_%i.log</fileNamePattern>
            <maxFileSize>50MB</maxFileSize>
            <maxHistory>7</maxHistory>
            <totalSizeCap>1GB</totalSizeCap>
        </rollingPolicy>
        <encoder>
            <pattern>%date %level [%thread] %logger %msg%n</pattern>
        </encoder>
    </appender>

    <logger name="org.apache.kafka" level="INFO" additivity="false">
        <appender-ref ref="KAFKA_FILE" />
    </logger>
    
    <logger name="org.apache.nifi.processors.kafka" level="DEBUG" additivity="false">
        <appender-ref ref="KAFKA_FILE" />
    </logger>

    <root level="INFO">
        <appender-ref ref="APP_FILE"/>
    </root>
</configuration>
EOF

chown $NIFI_USER:$NIFI_USER $NIFI_HOME/conf/logback.xml

echo ""
echo "=== Шаг 8: Настройка firewall (если требуется) ==="
if command -v ufw &> /dev/null; then
    ufw allow 8080/tcp
    echo "✓ Открыт порт 8080 для NiFi веб-интерфейса"
fi

echo ""
echo "=== Шаг 9: Включение и запуск сервиса ==="
systemctl daemon-reload
systemctl enable nifi

echo "Запуск NiFi (это может занять 2-3 минуты)..."
systemctl start nifi

echo ""
echo "=== Проверка статуса ==="
sleep 30

if systemctl is-active --quiet nifi; then
    echo "✓ NiFi успешно запущен"
else
    echo "✗ Ошибка запуска NiFi"
    echo "Проверьте логи: journalctl -u nifi -f"
    echo "Или: tail -f $NIFI_HOME/logs/nifi-app.log"
fi

echo ""
echo "=========================================="
echo "  Установка Apache NiFi завершена!"
echo "=========================================="
echo ""
echo "Информация о NiFi:"
echo "Веб-интерфейс: http://$(hostname -I | awk '{print $1}'):8080/nifi"
echo "Домашняя директория: $NIFI_HOME"
echo "Пользователь: $NIFI_USER"
echo "Логи: $NIFI_HOME/logs/"
echo ""
echo "Управление сервисом:"
echo "  Статус:     systemctl status nifi"
echo "  Запуск:     systemctl start nifi"
echo "  Остановка:  systemctl stop nifi"
echo "  Перезапуск: systemctl restart nifi"
echo "  Логи:       journalctl -u nifi -f"
echo ""
echo "JMX мониторинг доступен на порту 9995" 