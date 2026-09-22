#!/bin/bash
# Скрипт управления Git-сервером для локального сервера (Intel Atom 330, 4GB RAM, Debian Server)

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Управление Git-сервером (Intel Atom 330) ===${NC}"
echo "1) Полная установка и настройка Git-сервера"
echo "2) ПОЛНОЕ УДАЛЕНИЕ всех компонентов (очистка)"
read -p "Выберите действие (1 или 2): " main_choice

# Функция для валидации портов
validate_port() {
    local port=$1
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    else
        return 1
    fi
}

# ==========================================
# РЕЖИМ 2: ПОЛНОЕ УДАЛЕНИЕ СЕРВЕРА
# ==========================================
if [[ "$main_choice" == "2" ]]; then
    echo -e "\n${RED}!!! ВНИМАНИЕ !!! ВЫ ВЫБРАЛИ ПОЛНОЕ УДАЛЕНИЕ СЕРВЕРА !!!${NC}"
    echo -e "${RED}Все репозитории, базы данных, бэкапы и пользователи будут стерты БЕЗВОЗВРАТНО.${NC}"
    read -p "Вы уверены, что хотите продолжить? Введите 'yes' для подтверждения: " confirm_delete
    
    if [[ "$confirm_delete" != "yes" ]]; then
        echo "Удаление отменено."
        exit 0
    fi

    while true; do
        read -p "Укажите порт Forgejo, который использовался (по умолчанию 3000): " del_web_port
        del_web_port=${del_web_port:-3000}
        if validate_port "$del_web_port"; then break; else echo -e "${YELLOW}Некорректный порт.${NC}"; fi
    done

    echo -e "\n${BLUE}=== Шаг 1: Остановка и удаление службы Forgejo ===${NC}"
    # Проверяем, существует ли файл службы в системе
    if [ -f /etc/systemd/system/forgejo.service ]; then
        echo "Служба Forgejo найдена. Деактивация..."
        sudo systemctl stop forgejo || true
        sudo systemctl disable forgejo || true
        sudo rm -f /etc/systemd/system/forgejo.service
        sudo systemctl daemon-reload
        echo -e "${GREEN}[УСПЕШНО] Служба удалена.${NC}"
    else
        echo "Служба Forgejo не была установлена. Пропускаем."
    fi

    echo -e "\n${BLUE}=== Шаг 2: Удаление конфигурации и файлов Forgejo ===${NC}"
    sudo rm -f /usr/local/bin/forgejo
    sudo rm -rf /var/lib/forgejo
    sudo rm -rf /etc/forgejo
    echo "Компоненты веб-панели очищены."

    echo -e "\n${BLUE}=== Шаг 3: Удаление пользователя git и репозиториев ===${NC}"
    if id "git" &>/dev/null; then
        echo "Пользователь git найден. Удаление репозиториев и профиля..."
        sudo deluser --remove-home git || true
        sudo rm -rf /home/git
        echo -e "${GREEN}[УСПЕШНО] Данные пользователя git стерты.${NC}"
    else
        echo "Пользователь git отсутствует. Пропускаем."
    fi

    echo -e "\n${BLUE}=== Шаг 4: Удаление бэкапов и скриптов ===${NC}"
    sudo rm -rf /var/backups/forgejo
    sudo rm -f /usr/local/bin/forgejo-backup.sh

       echo -e "\n${BLUE}=== Шаг 5: Умная очистка правил UFW ===${NC}"
    if command -v ufw &>/dev/null; then
        echo "Удаляем созданные правила из брандмауэра..."
        
        # Переопределяем подсеть, чтобы понять, какое именно правило удалять
        LOCAL_SUBNET=$(ip route show | grep -E 'proto kernel.*scope link' | awk '{print $1}' | head -n 1)
        
        if [ -n "$LOCAL_SUBNET" ]; then
            # Если подсеть есть — удаляем именно локальное правило, строго повторяя его синтаксис
            sudo ufw delete allow from "$LOCAL_SUBNET" to any port "$del_web_port" proto tcp || true
            echo "Локальное правило для порта $del_web_port удалено."
        else
            # Если подсети не было и пользователь открывал порт глобально — удаляем глобальное правило
            sudo ufw delete allow "$del_web_port"/tcp || true
            echo "Глобальное правило для порта $del_web_port удалено."
        fi
        
        sudo ufw reload
        echo -e "${GREEN}[УСПЕШНО] Очистка портов завершена. Доступ по SSH полностью сохранен!${NC}"
    fi

    echo -e "\n${BLUE}=== Шаг 6: Очистка системы ===${NC}"
    sudo apt autoremove -y

    echo -e "\n${GREEN}=== Все компоненты сервера успешно удалены! ===${NC}"
    exit 0

# ==========================================
# РЕЖИМ 1: УСТАНОВКА СЕРВЕРА
# ==========================================
elif [[ "$main_choice" == "1" ]]; then

    while true; do
        read -p "Введите текущий порт SSH вашего сервера (по умолчанию 22): " ssh_port
        ssh_port=${ssh_port:-22}
        if validate_port "$ssh_port"; then break; else echo -e "${YELLOW}[ОШИБКА] Некорректный порт (1-65535).${NC}"; fi
    done

    while true; do
        read -p "Выберите порт для веб-панели Forgejo (по умолчанию 3000): " web_port
        web_port=${web_port:-3000}
        if validate_port "$web_port"; then break; else echo -e "${YELLOW}[ОШИБКА] Некорректный порт (1-65535).${NC}"; fi
    done

    echo -e "\n${BLUE}=== Шаг 1: Обновление Debian и установка базовых утилит ===${NC}"
    sudo apt update && sudo apt upgrade -y
    sudo apt install git wget ufw -y

    echo -e "\n${BLUE}=== Шаг 2: Создание изолированного пользователя git ===${NC}"
    if id "git" &>/dev/null; then
        echo "Пользователь git уже существует."
    else
        sudo adduser --shell /bin/bash --disabled-password --gecos "" git
    fi

    GIT_HOME="/home/git"
    sudo mkdir -p "$GIT_HOME/projects"
    sudo chown -R git:git "$GIT_HOME/projects"

    echo -e "\n${BLUE}=== Шаг 3: Настройка SSH-доступа для локальной сети ===${NC}"
    read -p "Подготовить сервер для авторизации по SSH-ключу? (y/n): " setup_ssh
    if [[ $setup_ssh == "y" || $setup_ssh == "Y" ]]; then
        sudo -u git mkdir -p "$GIT_HOME/.ssh"
        sudo -u git touch "$GIT_HOME/.ssh/authorized_keys"
        sudo -u git chmod 700 "$GIT_HOME/.ssh"
        sudo -u git chmod 600 "$GIT_HOME/.ssh/authorized_keys"
        echo -e "${GREEN}[УСПЕШНО] Папки для SSH-ключей готовы.${NC}"
    fi

    echo -e "\n${BLUE}=== Шаг 4: Установка веб-панели Forgejo ===${NC}"
    read -p "Хотите установить легковесную веб-панель Forgejo? (y/n): " setup_web
    if [[ $setup_web == "y" || $setup_web == "Y" ]]; then
        echo "Установка дополнительных зависимостей (sqlite3)..."
        sudo apt install sqlite3 -y

        echo "Скачивание Forgejo..."
        cd /tmp
        wget --show-progress -q https://code.forgejo.org/forgejo/forgejo/releases/download/v16.0.5/forgejo-16.0.5-linux-amd64
        sudo mv forgejo-16.0.5-linux-amd64 /usr/local/bin/forgejo
        sudo chmod +x /usr/local/bin/forgejo

        # Создание структуры папок
        sudo mkdir -p /var/lib/forgejo/{custom,data,log}
        sudo chown -R git:git /var/lib/forgejo/
        sudo chmod -R 750 /var/lib/forgejo/
        
        sudo mkdir -p /etc/forgejo
        sudo chown -R root:git /etc/forgejo
        sudo chmod -R 770 /etc/forgejo

        # Создание Systemd службы
        cat <<EOF | sudo tee /etc/systemd/system/forgejo.service > /dev/null
[Unit]
Description=Forgejo (Git Server for Intel Atom)
After=network.target

[Service]
Type=simple
User=git
Group=git
WorkingDirectory=/var/lib/forgejo/
RuntimeDirectory=forgejo
ExecStart=/usr/local/bin/forgejo web --port $web_port --config /etc/forgejo/app.ini
Restart=always
Environment=USER=git HOME=$GIT_HOME GITEA_WORK_DIR=/var/lib/forgejo

[Install]
WantedBy=multi-user.target
EOF

        sudo systemctl daemon-reload
        sudo systemctl enable --now forgejo

        # Настройка брандмауэра UFW
        echo "Настройка правил безопасности UFW..."
        
        # Определяем локальную подсеть роутера (например, 192.168.1.0/24)
        LOCAL_SUBNET=$(ip route show | grep -E 'proto kernel.*scope link' | awk '{print $1}' | head -n 1)

        if [ -n "$LOCAL_SUBNET" ]; then
            # Доступ к SSH доступен ТОЛЬКО из локальной сети
            sudo ufw allow from "$LOCAL_SUBNET" to any port "$ssh_port" proto tcp
            # Доступ к Forgejo доступен ТОЛЬКО из локальной сети
            sudo ufw allow from "$LOCAL_SUBNET" to any port "$web_port" proto tcp
            echo "y" | sudo ufw enable
            echo -e "${GREEN}[УСПЕШНО] UFW настроен. SSH ($ssh_port) и Forgejo ($web_port) доступны ТОЛЬКО из локальной сети ($LOCAL_SUBNET).${NC}"
        else
            echo -e "${YELLOW}[ВНИМАНИЕ] Не удалось автоматически определить локальную подсеть.${NC}"
            echo "Если этот сервер находится за роутером (NAT), открытие портов глобально безопасно."
            echo "Если сервер подключен к интернету напрямую, открытие портов сделает их доступными всему миру."
            
            read -p "Хотите открыть порты SSH ($ssh_port) и Forgejo ($web_port) глобально для всех подключений? (y/n): " allow_global
            
            if [[ $allow_global == "y" || $allow_global == "Y" ]]; then
                sudo ufw allow "$ssh_port"/tcp
                sudo ufw allow "$web_port"/tcp
                echo "y" | sudo ufw enable
                echo -e "${GREEN}[УСПЕШНО] Порты $ssh_port и $web_port открыты глобально в UFW.${NC}"
            else
                echo -e "${YELLOW}Настройка UFW пропущена. Вам потребуется открыть порты $ssh_port и $web_port вручную.${NC}"
            fi
        fi
        
        SERVER_IP=$(hostname -I | awk '{print $1}')
        echo -e "${GREEN}[УСПЕШНО] Forgejo запущен! Доступ: http://$SERVER_IP:$web_port${NC}"

        # Настройка бэкапа SQLite3
        echo -e "\n${BLUE}=== Шаг 5: Настройка бэкапа SQLite3 (Cron) ===${NC}"
        read -p "Хотите настроить автоматический ежедневный бэкап базы данных Forgejo? (y/n): " setup_backup
        if [[ $setup_backup == "y" || $setup_backup == "Y" ]]; then
            
            while true; do
                read -p "Введите время для ежедневного бэкапа в формате ЧЧ:ММ (например, 03:30): " backup_time
                if [[ $backup_time =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                    CRON_MIN=$(echo $backup_time | cut -d: -f2)
                    CRON_HOUR=$(echo $backup_time | cut -d: -f1)
                    break
                else
                    echo -e "${YELLOW}[ОШИБКА] Некорректный формат времени. Используйте ЧЧ:ММ (от 00:00 до 23:59).${NC}"
                fi
            done

            while true; do
                read -p "Сколько дней хранить резервные копии? (например, 14 или 30): " backup_days
                if [[ $backup_days =~ ^[0-9]+$ ]] && [ "$backup_days" -gt 0 ]; then
                    break
                else
                    echo -e "${YELLOW}[ОШИБКА] Пожалуйста, введите корректное число дней (больше 0).${NC}"
                fi
            done

            sudo mkdir -p /var/backups/forgejo
            sudo chown git:git /var/backups/forgejo

            # Генерация скрипта бэкапа
            cat << EOF | sudo tee /usr/local/bin/forgejo-backup.sh > /dev/null
#!/bin/bash
BACKUP_DIR="/var/backups/forgejo"
DB_PATH="/var/lib/forgejo/data/gitea.db"
DATE=\$(date +%Y-%m-%d_%H-%M-%S)

if [ -f "\$DB_PATH" ]; then
    sqlite3 "\$DB_PATH" ".backup '\$BACKUP_DIR/forgejo_db_\$DATE.sqlite'"
    chown git:git "\$BACKUP_DIR/forgejo_db_\$DATE.sqlite"
fi

find "\$BACKUP_DIR" -type f -name "*.sqlite" -mtime +$backup_days -delete
EOF

            sudo chmod +x /usr/local/bin/forgejo-backup.sh
            
            (sudo -u git crontab -l 2>/dev/null; echo "$CRON_MIN $CRON_HOUR * * * /usr/local/bin/forgejo-backup.sh") | sudo -u git crontab -
            echo -e "${GREEN}[УСПЕШНО] Ежедневный бэкап настроен на $backup_time. Срок хранения: $backup_days дн. Копии: /var/backups/forgejo/${NC}"
        fi

    else
        echo -e "${GREEN}Установка веб-панели пропущена. Сервер работает как чистый Git-сервер через SSH.${NC}"
    fi

    echo -e "\n${GREEN}=== Развертывание на домашнем сервере завершено! ===${NC}"

else
    echo -e "${YELLOW}Некорректный выбор. Пожалуйста, перезапустите скрипт и выберите 1 или 2.${NC}"
    exit 1
fi
