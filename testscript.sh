#!/bin/bash
set -euo pipefail

# Логирование
LOGFILE="/var/log/testscript.log"
exec > >(tee -a "$LOGFILE") 2>&1

SCRIPT_START=$(date +%s)

echo "=== Старт установки: $(date) ==="

# Проверка на запуск от root
if [ "$(id -u)" -ne 0 ]; then
    echo "❌ Этот скрипт должен запускаться от root (используйте sudo)."
    exit 1
fi

# Настройки для apt — не задавать вопросов
export DEBIAN_FRONTEND=noninteractive

# Обновление пакетов
echo "🔄 Обновление системы..."
apt update
apt -y upgrade

# Отключение IPv6
echo "🌐 Проверка текущего состояния IPv6..."
if ip a | grep -q inet6; then
    echo "IPv6 активен — создаём конфигурационный файл для его отключения."
    cat << EOF > /etc/sysctl.d/10-disable-ipv6.conf
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
EOF

    echo "Применение настроек IPv6..."
    sysctl --system
else
    echo "IPv6 уже отключён или интерфейсы без inet6."
fi

# Определение пользователя
CURRENT_USER=${SUDO_USER:-$(whoami)}
read -p "Введите имя пользователя для смены пароля (по умолчанию: $CURRENT_USER): " USERNAME
USERNAME=${USERNAME:-$CURRENT_USER}

# Смена пароля пользователя
while true; do
    read -s -p "Введите новый сложный пароль: " PASSWORD
    echo
    read -s -p "Подтвердите пароль: " PASSWORD_CONFIRM
    echo

    if [ "$PASSWORD" == "$PASSWORD_CONFIRM" ]; then
        break
    else
        echo "⚠️  Пароли не совпадают. Повторите ввод."
    fi
done

echo "$USERNAME:$PASSWORD" | chpasswd && echo "✅ Пароль для $USERNAME успешно изменён."
unset PASSWORD PASSWORD_CONFIRM

# Функция создания / обновления пользователя
create_user() {
    local USER=$1
    if [ -z "$USER" ]; then
        echo "Ошибка: имя пользователя не может быть пустым."
        return 1
    fi

    if id -u "$USER" >/dev/null 2>&1; then
        echo "👤 Пользователь $USER уже существует."
        read -p "Обновить пароль для $USER? (y/n): " UPDATE_PASSWORD
        if [ "$UPDATE_PASSWORD" == "y" ]; then
            while true; do
                read -s -p "Введите новый пароль для $USER: " PASS
                echo
                read -s -p "Подтвердите пароль: " PASS_CONFIRM
                echo
                if [ "$PASS" == "$PASS_CONFIRM" ]; then
                    echo "$USER:$PASS" | chpasswd
                    echo "🔑 Пароль для $USER обновлён."
                    break
                else
                    echo "⚠️  Пароли не совпадают. Попробуйте заново."
                fi
            done
            unset PASS PASS_CONFIRM
        else
            echo "⏭ Пропуск обновления пароля для $USER."
        fi
    else
        echo "➕ Создание пользователя $USER..."
        adduser --quiet --gecos "" --disabled-password "$USER"
        
        while true; do
            read -s -p "Введите пароль для $USER: " PASS
            echo
            read -s -p "Подтвердите пароль: " PASS_CONFIRM
            echo
            if [ "$PASS" == "$PASS_CONFIRM" ]; then
                echo "$USER:$PASS" | chpasswd
                echo "✅ Пользователь $USER создан и пароль установлен."
                break
            else
                echo "⚠️  Пароли не совпадают. Попробуйте заново."
            fi
        done
        unset PASS PASS_CONFIRM
    fi

    if ! groups "$USER" | grep -q sudo; then
        usermod -aG sudo "$USER"
        echo "🔧 $USER добавлен в группу sudo."
    else
        echo "ℹ️  $USER уже в группе sudo."
    fi
}

# Создание пользователей
create_user "putopelatudo"
create_user "reserveme"

RUNTIME=$(( $(date +%s) - SCRIPT_START ))
echo "✅ Установка завершена за ${RUNTIME} секунд ($(date))."
