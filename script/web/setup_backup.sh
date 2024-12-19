#!/bin/bash

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Vui lòng chạy với quyền root."
  exit 1
fi

# Nhận tham số từ dòng lệnh
DOMAIN="$1"               # Tên miền được truyền vào như tham số đầu tiên
BACKUP_DIR="$2"           # Đường dẫn thư mục backup
START_TIME="$3"           # Thời gian bắt đầu backup (HH:MM)
BACKUP_INTERVAL_DAYS="$4" # Tần suất backup (số ngày)

LOG_FILE="/var/log/backup_script.log"

log() {
  echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

if [ -z "$DOMAIN" ] || [ -z "$BACKUP_DIR" ] || [ -z "$START_TIME" ] || [ -z "$BACKUP_INTERVAL_DAYS" ]; then
  log "ERROR: Vui lòng cung cấp tên miền (domain), đường dẫn thư mục backup, thời gian bắt đầu (HH:MM) và tần suất backup (số ngày) như tham số."
  exit 1
fi

# Kiểm tra và cài đặt zip
if ! command -v zip &>/dev/null; then
  log "zip chưa được cài đặt. Đang cài đặt..."
  sudo apt-get update && sudo apt-get install -y zip
fi

# Kiểm tra và cài đặt mysqldump
if ! command -v mysqldump &>/dev/null; then
  log "mysqldump chưa được cài đặt. Đang cài đặt..."
  sudo apt-get update && sudo apt-get install -y mysql-client
fi

# Cài đặt
WWW_DIR="/var/www/$DOMAIN" # Thư mục chứa mã nguồn web
DB_NAME="${DOMAIN//./_}"   # Tên cơ sở dữ liệu, thay thế dấu chấm bằng dấu gạch dưới

# Đọc thông tin đăng nhập từ wp-config.php
WP_CONFIG="$WWW_DIR/wp-config.php"
DB_USER=$(grep "DB_USER" "$WP_CONFIG" | sed -E "s/define\('DB_USER',\s*'([^']+)'.*/\1/")
DB_PASS=$(grep "DB_PASS" "$WP_CONFIG" | sed -E "s/define\('DB_PASS',\s*'([^']+)'.*/\1/")

MAX_BACKUPS=7 # Số lượng file backup tối đa được giữ lại

# Thời gian hiện tại
CURRENT_TIME=$(date +"%d%m%Y%H%M%S")

# Tạo thư mục backup nếu chưa tồn tại
mkdir -p "$BACKUP_DIR"

# Tên file backup
BACKUP_FILE="$BACKUP_DIR/${DOMAIN}_${CURRENT_TIME}.zip"

log "Bắt đầu backup cho $DOMAIN..."

# Backup source code
log "Backup source code từ $WWW_DIR..."
zip -r "$BACKUP_FILE" "$WWW_DIR" >/dev/null 2>&1
if [ $? -eq 0 ]; then
  log "Backup source code hoàn tất."
else
  log "ERROR: Lỗi khi backup source code."
fi

# Backup database
log "Backup database $DB_NAME..."
SQL_BACKUP_FILE="/tmp/${DB_NAME}.sql"
mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$SQL_BACKUP_FILE"
log "Backup database hoàn tất."

# Thêm file backup database vào file zip
zip -j "$BACKUP_FILE" "$SQL_BACKUP_FILE" >/dev/null 2>&1
rm "$SQL_BACKUP_FILE"

log "Backup hoàn tất: $BACKUP_FILE"

# Giới hạn số lượng file backup
BACKUP_COUNT=$(ls -1t "$BACKUP_DIR" | grep "${DOMAIN}_" | wc -l)

if [ "$BACKUP_COUNT" -gt "$MAX_BACKUPS" ]; then
  log "Xóa các backup cũ..."
  ls -1t "$BACKUP_DIR" | grep "${DOMAIN}_" | tail -n +$(($MAX_BACKUPS + 1)) | while read OLD_BACKUP; do
    rm "$BACKUP_DIR/$OLD_BACKUP"
    log "Đã xóa backup cũ: $OLD_BACKUP"
  done
fi

# Tự động hoá backup
BACKUP_INTERVAL_MINUTES=$((BACKUP_INTERVAL_DAYS * 24 * 60))

(
  crontab -l 2>/dev/null
  echo "$START_TIME */$BACKUP_INTERVAL_MINUTES * * * /bin/bash $(realpath $0) $DOMAIN $BACKUP_DIR $START_TIME $BACKUP_INTERVAL_DAYS"
) | crontab -

log "Thiết lập backup tự động cho $DOMAIN tại $BACKUP_DIR"
