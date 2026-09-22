#!/bin/bash
# Скрипт деплоя Git-сервера для локального сервера (Intel Atom 330, 4GB RAM, Debian Server)

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Шаг 1: Обновление Debian и установка Git ===${NC}"
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
    sudo chmod 700 "$GIT_HOME/.ssh"
    sudo chmod 600 "$GIT_HOME/.ssh/authorized_keys"
    echo -e "${GREEN}[УСПЕШНО] Папки для SSH-ключей готовы.${NC}"
fi

echo -e "\n${BLUE}=== Шаг 4: Установка веб-панели Forgejo ===${NC}"
read -p "Хотите установить легковесную веб-панель Forgejo? (y/n): " setup_web
if [[ $setup_web == "y" || $setup_web == "Y" ]]; then
    echo "Скачивание Forgejo (архитектура amd64)..."
    cd /tmp
    # Загружаем стабильную версию
    curl -code -LO https://codeberg.org
    sudo mv forgejo-9.0.2-linux-amd64 /usr/local/bin/forgejo
    sudo chmod +x /usr/local/bin/forgejo

    # Создание структуры папок
    sudo mkdir -p /var/lib/forgejo/{custom,data,log}
    sudo chown -R git:git /var/lib/forgejo/
    sudo chmod -R 750 /var/lib/forgejo/
    
    sudo mkdir -p /etc/forgejo
    sudo chown -R root:git /etc/forgejo
    sudo chmod -R 770 /etc/forgejo

    # Создание Systemd службы (используем все 4 потока Atom 330)
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
else
    echo "Установка веб-панели пропущена. Сервер работает как чистый Git-сервер через SSH."
fi

echo -e "\n${GREEN}=== Развертывание на домашнем сервере завершено! ===${NC}"
