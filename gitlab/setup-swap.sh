
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Пожалуйста, запустите скрипт с правами root (sudo)${NC}"
    exit 1
fi

echo -e "${GREEN}=== Настройка SWAP для GitLab ===${NC}\n"


SWAP_SIZE_GB=10

echo -e "${YELLOW}Шаг 1: Проверка текущей конфигурации памяти${NC}"
free -h
echo ""

if swapon --show | grep -q '/swapfile'; then
    echo -e "${YELLOW}SWAP файл уже существует. Удаляем старый...${NC}"
    swapoff /swapfile
    rm -f /swapfile
fi

echo -e "${YELLOW}Шаг 2: Создание swap файла размером ${SWAP_SIZE_GB}GB${NC}"
echo "Это может занять несколько минут..."


if fallocate -l ${SWAP_SIZE_GB}G /swapfile 2>/dev/null; then
    echo -e "${GREEN}Swap файл создан с помощью fallocate${NC}"
else
    echo -e "${YELLOW}fallocate не сработал, используем dd (это займет больше времени)${NC}"
    dd if=/dev/zero of=/swapfile bs=1G count=${SWAP_SIZE_GB} status=progress
fi

echo -e "${YELLOW}Шаг 3: Установка прав доступа${NC}"
chmod 600 /swapfile

echo -e "${YELLOW}Шаг 4: Создание swap области${NC}"
mkswap /swapfile

echo -e "${YELLOW}Шаг 5: Включение swap${NC}"
swapon /swapfile

echo -e "${YELLOW}Шаг 6: Настройка автоматического монтирования при загрузке${NC}"
# Проверяем, есть ли уже запись в fstab
if ! grep -q '/swapfile' /etc/fstab; then
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo -e "${GREEN}Запись добавлена в /etc/fstab${NC}"
else
    echo -e "${GREEN}Запись уже существует в /etc/fstab${NC}"
fi

echo -e "${YELLOW}Шаг 7: Настройка swappiness${NC}"

# Установка для текущей сессии
sysctl vm.swappiness=10

# Постоянная установка
if ! grep -q 'vm.swappiness' /etc/sysctl.conf; then
    echo 'vm.swappiness=10' >> /etc/sysctl.conf
    echo -e "${GREEN}vm.swappiness=10 добавлено в /etc/sysctl.conf${NC}"
else
    sed -i 's/vm.swappiness=.*/vm.swappiness=10/' /etc/sysctl.conf
    echo -e "${GREEN}vm.swappiness обновлено в /etc/sysctl.conf${NC}"
fi

# Настройка vfs_cache_pressure
# Это влияет на то, как ядро освобождает память, занятую кешем inode/dentry
# Значение 50 - хороший компромисс для GitLab
if ! grep -q 'vm.vfs_cache_pressure' /etc/sysctl.conf; then
    echo 'vm.vfs_cache_pressure=50' >> /etc/sysctl.conf
    echo -e "${GREEN}vm.vfs_cache_pressure=50 добавлено в /etc/sysctl.conf${NC}"
fi
sysctl vm.vfs_cache_pressure=50

echo -e "\n${GREEN}=== SWAP успешно настроен ===${NC}\n"

echo -e "${YELLOW}Текущее состояние памяти:${NC}"
free -h

echo -e "\n${YELLOW}SWAP информация:${NC}"
swapon --show

echo -e "\n${YELLOW}Параметры ядра:${NC}"
echo "vm.swappiness = $(sysctl vm.swappiness | awk '{print $3}')"
echo "vm.vfs_cache_pressure = $(sysctl vm.vfs_cache_pressure | awk '{print $3}')"

echo -e "\n${GREEN}✓ Настройка завершена!${NC}"
echo -e "${YELLOW}Теперь вы можете запустить GitLab с помощью:${NC}"
echo -e "  cd $(dirname $(readlink -f $0))"
echo -e "  docker-compose up -d"
echo -e "\n${YELLOW}Для мониторинга использования памяти используйте:${NC}"
echo -e "  watch -n 5 free -h"
