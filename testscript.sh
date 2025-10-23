#!/bin/bash

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

# Смена пароля пользователя
echo "Смена пароля пользователя..."

# Запрос имени пользователя (по умолчанию - текущий)
CURRENT_USER=$(whoami)
read -p "Введите имя пользователя для смены пароля (по умолчанию: $CURRENT_USER): " USERNAME
USERNAME=${USERNAME:-$CURRENT_USER}

# Запрос нового пароля (скрытый ввод)
while true; do
    read -s -p "Введите новый сложный пароль: " PASSWORD
    echo
    read -s -p "Подтвердите пароль: " PASSWORD_CONFIRM
    echo

    if [ "$PASSWORD" == "$PASSWORD_CONFIRM" ]; then
        break
    else
        echo "Пароли не совпадают. Попробуйте заново."
    fi
done

# Применение смены пароля
echo "$USERNAME:$PASSWORD" | chpasswd
if [ $? -eq 0 ]; then
    echo "Пароль для пользователя $USERNAME успешно изменён."
else
    echo "Ошибка при смене пароля. Проверьте логи."
    exit 1  # Можно убрать exit, если не хочешь прерывать скрипт
fi

# Функция для создания/обновления пользователя с паролем и добавлением в sudo
create_user() {
    local USER=$1

    if id -u "$USER" > /dev/null 2>&1; then
        echo "Пользователь $USER уже существует."
        read -p "Обновить пароль для $USER? (y/n): " UPDATE_PASSWORD
        if [ "$UPDATE_PASSWORD" != "y" ]; then
            echo "Пропуск обновления пароля для $USER."
        else
            # Запрос пароля
            while true; do
                read -s -p "Введите новый пароль для $USER: " PASS
                echo
                read -s -p "Подтвердите пароль: " PASS_CONFIRM
                echo

                if [ "$PASS" == "$PASS_CONFIRM" ]; then
                    break
                else
                    echo "Пароли не совпадают. Попробуйте заново."
                fi
            done
            echo "$USER:$PASS" | chpasswd
            echo "Пароль для $USER обновлён."
        fi
    else
        echo "Создание пользователя $USER..."
        adduser --gecos "" --disabled-password "$USER"
        
        # Запрос пароля
        while true; do
            read -s -p "Введите пароль для $USER: " PASS
            echo
            read -s -p "Подтвердите пароль: " PASS_CONFIRM
            echo

            if [ "$PASS" == "$PASS_CONFIRM" ]; then
                break
            else
                echo "Пароли не совпадают. Попробуйте заново."
            fi
        done
        echo "$USER:$PASS" | chpasswd
        echo "Пользователь $USER создан и пароль установлен."
    fi

    # Добавление в группу sudo (если ещё не в ней)
    if ! groups "$USER" | grep -q sudo; then
        usermod -aG sudo "$USER"
        echo "$USER добавлен в группу sudo."
    else
        echo "$USER уже в группе sudo."
    fi
}

# Создание пользователей
create_user "putopelatudo"
create_user "reserveme"

# Функция для смены порта SSH
change_ssh_port() {
    echo "Смена порта SSH с 22 на 4422..."
    
    # Создаем резервную копию конфигурации SSH
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d%H%M%S)
    
    # Редактируем конфигурацию SSH
    echo "Редактирование /etc/ssh/sshd_config..."
    
    # Комментируем старый порт если он есть и добавляем новый
    sudo sed -i 's/^Port .*/#Port 22/' /etc/ssh/sshd_config
    
    # Добавляем новый порт
    if grep -q "^Port 4422" /etc/ssh/sshd_config; then
        echo "Порт 4422 уже настроен"
    else
        echo "Port 4422" | sudo tee -a /etc/ssh/sshd_config
    fi
    
    # Разрешаем новый порт в UFW
    echo "Добавление правила UFW для порта 4422..."
    sudo ufw allow 4422/tcp comment "SSH custom port"
    
    # Перезапускаем SSH службу
    echo "Перезапуск службы SSH..."
    sudo systemctl restart ssh
    
    echo "Порт SSH успешно изменен на 4422"
    echo "ВАЖНО: Не закрывайте это соединение! Проверьте подключение через новый порт в другом окне."
    echo "Для подключения используйте: ssh -p 4422 username@server_ip"
}

# Здесь будут добавляться следующие задачи

echo "Установка завершена!"
