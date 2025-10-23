#!/bin/bash

# --- Начало конфигурации безопасности ---
# set -e: Немедленно выйти, если команда завершается с ошибкой.
# set -u: Обращаться к неустановленным переменным как к ошибке.
# set -o pipefail: Выходной статус конвейера (|) будет статусом последней команды, завершившейся с ошибкой.
set -euo pipefail

# --- Проверка на запуск от root ---
if [ "$(id -u)" -ne 0 ]; then
    echo "Этот скрипт должен запускаться от root (используйте sudo)."
    exit 1
fi

# --- Обновление системы ---
echo "Обновление списка пакетов и системы..."
apt-get update -y
apt-get upgrade -y

# --- Отключение IPv6 ---
echo "Отключение IPv6..."
# Создаем файл конфигурации. Если он уже существует, он будет перезаписан.
cat << EOF > /etc/sysctl.d/10-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

# Применяем изменения немедленно
sysctl -p /etc/sysctl.d/10-disable-ipv6.conf
echo "Изменения для отключения IPv6 применены."

# Проверяем, остался ли активный IPv6 адрес (кроме link-local fe80::)
if ip -6 addr | grep -q "inet6.*scope global"; then
    echo "Предупреждение: Глобальный IPv6 адрес все еще активен. Может потребоваться перезагрузка."
else
    echo "IPv6 успешно отключен."
fi

# --- Функция для безопасного запроса пароля ---
# Выносит повторяющуюся логику в одно место.
get_password() {
    local pass=""
    local pass_confirm=""
    while true; do
        read -s -p "Введите новый сложный пароль: " pass
        echo
        read -s -p "Подтвердите пароль: " pass_confirm
        echo
        if [ "$pass" == "$pass_confirm" ]; then
            if [ -z "$pass" ]; then
                echo "Пароль не может быть пустым. Попробуйте снова."
            else
                break # Пароли совпадают и не пустые
            fi
        else
            echo "Пароли не совпадают. Попробуйте снова."
        fi
    done
    # Возвращаем пароль через echo
    echo "$pass"
}

# --- Смена пароля текущего пользователя ---
echo "Смена пароля пользователя, запустившего скрипт..."

# Используем $SUDO_USER, чтобы определить, кто запустил sudo.
# Если скрипт запущен напрямую от root, $SUDO_USER будет пуст.
USERNAME=${SUDO_USER:-$(whoami)}

echo "Будет изменен пароль для пользователя: $USERNAME"
# Вызываем нашу новую функцию для получения пароля
PASSWORD=$(get_password)

# Применяем смену пароля
if echo "$USERNAME:$PASSWORD" | chpasswd; then
    echo "Пароль для пользователя '$USERNAME' успешно изменён."
else
    echo "Ошибка при смене пароля для '$USERNAME'."
    exit 1
fi

# --- Функция для создания/обновления пользователя ---
# Теперь она стала намного короче благодаря функции get_password
create_or_update_user() {
    local user="$1"

    if id -u "$user" > /dev/null 2>&1; then
        echo "Пользователь '$user' уже существует."
        read -p "Обновить пароль для '$user'? (y/n): " -n 1 -r
        echo # Переход на новую строку
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            local new_pass
            new_pass=$(get_password)
            if echo "$user:$new_pass" | chpasswd; then
                echo "Пароль для '$user' обновлён."
            else
                echo "Ошибка при обновлении пароля для '$user'."
            fi
        fi
    else
        echo "Создание пользователя '$user'..."
        # --gecos "" - не запрашивать доп. информацию
        # --disabled-password - создать пользователя без пароля, установим его позже
        adduser --gecos "" --disabled-password "$user"
        
        local new_pass
        new_pass=$(get_password)
        if echo "$user:$new_pass" | chpasswd; then
            echo "Пользователь '$user' создан и пароль установлен."
        else
            echo "Ошибка при установке пароля для '$user'."
        fi
    fi

    # Добавление в группу sudo
    if ! groups "$user" | grep -qw "sudo"; then
        usermod -aG sudo "$user"
        echo "Пользователь '$user' добавлен в группу sudo."
    else
        echo "Пользователь '$user' уже состоит в группе sudo."
    fi
}

# --- Создание пользователей ---
create_or_update_user "putopelatudo"
create_or_update_user "reserveme"

# --- Здесь будут добавляться следующие задачи ---

echo "Настройка системы успешно завершена!"
