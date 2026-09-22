#!/bin/bash
# Скрипт деплоя Git-сервера для локального сервера (Intel Atom 330, 4GB RAM, Debian Server)

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Шаг 1: Обновление Debian и установка зависимостей ===${NC}"
sudo apt update && sudo apt upgrade -y
sudo apt install git curl -y

echo -e "\n${BLUE}=== Шаг 2: Создание изолированного пользователя git ===${NC}"
if id "git" &>/dev/null; then
    echo "Пользователь git уже существует."
else
    # Создаем системного пользователя без пароля для безопасности
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
    # Доустанавливаем sqlite3
    echo "Установка дополнительных зависимостей (sqlite3)..."
    sudo apt install sqlite3 -y

    echo "Скачивание Forgejo..."
    cd /tmp
    # Загружаем стабильную версию
    curl -# -LO https://code.forgejo.org/forgejo/forgejo/releases/download/v16.0.5/forgejo-16.0.5-linux-amd64
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
ExecStart=/usr/local/bin/forgejo web --config /etc/forgejo/app.ini
Restart=always
Environment=USER=git HOME=$GIT_HOME GITEA_WORK_DIR=/var/lib/forgejo

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now forgejo
    
    SERVER_IP=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}[УСПЕШНО] Forgejo запущен! Доступ в локальной сети: http://$SERVER_IP:3000${NC}"

    echo -e "\n${BLUE}=== Шаг 5: Настройка бэкапа SQLite3 (Cron) ===${NC}"
    read -p "Хотите настроить автоматический ежедневный бэкап базы данных Forgejo? (y/n): " setup_backup
    if [[ $setup_backup == "y" || $setup_backup == "Y" ]]; then
        
        # ИНТЕРАКТИВНЫЙ ЗАПРОС ВРЕМЕНИ
        while true; do
            read -p "Введите время для ежедневного бэкапа в формате ЧЧ:ММ (например, 03:30): " backup_time
            if [[ $backup_time =~ ^([0-1][0-9]|2[0-3]):[0-5][0-9]$ ]]; then
                CRON_MIN=$(echo $backup_time | cut -d: -f2)
                CRON_HOUR=$(echo $backup_time | cut -d: -f1)
                break
            else
                echo -e "\033[0;33m[ОШИБКА] Некорректный формат времени. Используйте ЧЧ:ММ (от 00:00 до 23:59).\033[0m"
            fi
        done

        sudo mkdir -p /var/backups/forgejo
        sudo chown git:git /var/backups/forgejo

        cat << 'EOF' | sudo tee /usr/local/bin/forgejo-backup.sh > /dev/null
#!/bin/bash
BACKUP_DIR="/var/backups/forgejo"
DB_PATH="/var/lib/forgejo/data/gitea.db"
DATE=$(date +%Y-%m-%d_%H-%M-%S)

# Проверяем, существует ли база (она появится только после первого запуска в браузере)
if [ -f "$DB_PATH" ]; then
    sqlite3 "$DB_PATH" ".backup '$BACKUP_DIR/forgejo_db_$DATE.sqlite'"
    chown git:git "$BACKUP_DIR/forgejo_db_$DATE.sqlite"
fi

# Удаляем бэкапы старше 30 дней
find "$BACKUP_DIR" -type f -name "*.sqlite" -mtime +30 -delete
EOF

        sudo chmod +x /usr/local/bin/forgejo-backup.sh
        
        # Подставляем выбранные пользователем переменные времени в cron
        (sudo -u git crontab -l 2>/dev/null; echo "$CRON_MIN $CRON_HOUR * * * /usr/local/bin/forgejo-backup.sh") | sudo -u git crontab -
        echo -e "${GREEN}[УСПЕШНО] Ежедневный бэкап настроен на $backup_time. Копии хранятся в /var/backups/forgejo/${NC}"
    fi

else
    # Этот блок сработает, если пользователь на Шаге 4 ответил "n"
    echo -e "${GREEN}Установка веб-панели пропущена. Сервер работает как чистый Git-сервер через SSH.${NC}"
fi

echo -e "\n${GREEN}=== Развертывание на домашнем сервере завершено! ===${NC}"
