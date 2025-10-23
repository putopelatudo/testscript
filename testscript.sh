#!/bin/bash

# Добавляем обработку ошибок
set -euo pipefail

# Проверка на запуск от root
if [ "$(id -u)" -ne 0 ]; then
    echo "Этот скрипт должен запускаться от root (используйте sudo)."
    exit 1
fi

# Обновление списка пакетов и upgrade системы
echo "Обновление системы..."
apt update -y
apt upgrade -y

# Отключение IPv6
echo "Проверка текущего состояния IPv6..."
ip a | grep inet6 || echo "IPv6 уже отключен или не найден."

echo "Создание конфигурационного файла для отключения IPv6..."
cat << EOF > /etc/sysctl.d/10-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

echo "Применение изменений..."
sysctl -p /etc/sysctl.d/10-disable-ipv6.conf

echo "Проверка состояния IPv6 после отключения..."
ip a | grep inet6 || echo "IPv6 успешно отключен (нет записей inet6)."

# Функция для безопасного ввода пароля
get_password() {
    local password
    while true; do
        read -s -p "Введите пароль: " password
        echo
        read -s -p "Подтвердите пароль: " password_confirm
        echo

        if [ "$password" == "$password_confirm" ]; then
            echo "$password"
            break
        else
            echo "Пароли не совпадают. Попробуйте заново."
        fi
    done
}

# Функция для создания пользователя с безопасной обработкой пароля
create_user() {
    local USER=$1
    
    echo "Создание пользователя $USER..."
    adduser --gecos "" --disabled-password "$USER"
    
    # Безопасный ввод и установка пароля
    echo "Установка пароля для пользователя $USER:"
    local password=$(get_password)
    
    # Устанавливаем пароль без хранения в переменной
    echo "$USER:$password" | chpasswd
    
    # Очищаем переменные с паролями
    password=""
    password_confirm=""
    
    echo "Пользователь $USER создан и пароль установлен."

    # Добавление в группу sudo
    usermod -aG sudo "$USER"
    echo "$USER добавлен в группу sudo."
}

# Создание пользователей
create_user "putopelatudo"
create_user "reserveme"

echo "Установка завершена!"
