#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[opencart]${NC} $*"; }
warn() { echo -e "${YELLOW}[opencart]${NC} $*"; }
err()  { echo -e "${RED}[opencart]${NC} $*" >&2; }

DB_USER="${DB_USER:-opencart}"
DB_PASS="${DB_PASSWORD:-opencart}"
DB_NAME="${DB_NAME:-opencart}"
DB_PREFIX="${DB_PREFIX:-oc_}"

ADMIN_USER="${ADMIN_USERNAME:-admin}"
ADMIN_PASS="${ADMIN_PASSWORD:-opencart}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"

if [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
    HTTP_SERVER="https://${RAILWAY_PUBLIC_DOMAIN}"
else
    HTTP_SERVER="${HTTP_SERVER:-http://localhost:8080}"
fi

# ─── MariaDB (embedded) ───────────────────────────────────

start_mariadb() {
    log "Starting embedded MariaDB..."

    if [ ! -d "/var/lib/mysql/mysql" ]; then
        mysql_install_db --user=mysql --datadir=/var/lib/mysql >/dev/null 2>&1
    fi

    mysqld_safe --datadir=/var/lib/mysql &

    local retries=30
    while [ $retries -gt 0 ]; do
        if mysqladmin ping -u root --silent 2>/dev/null; then
            log "MariaDB is ready!"
            return 0
        fi
        retries=$((retries - 1))
        echo -n "."
        sleep 2
    done
    err "MariaDB not reachable after 60s"
    return 1
}

setup_database() {
    log "Setting up database..."

    mysql -u root <<-EOSQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL
}

# ─── Helpers ───────────────────────────────────────────────

db_has_tables() {
    local count
    count=$(mysql -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" \
        -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_NAME}' AND table_name LIKE '${DB_PREFIX}%'" \
        2>/dev/null || echo "0")
    [ "$count" -gt 0 ]
}

generate_config() {
    log "Writing config.php files..."

    # Catalog config.php
    cat > /var/www/html/config.php <<CATCONF
<?php
define('APPLICATION', 'Catalog');
define('HTTP_SERVER', '${HTTP_SERVER}/');
define('DIR_OPENCART', '/var/www/html/');
define('DIR_APPLICATION', DIR_OPENCART . 'catalog/');
define('DIR_SYSTEM', DIR_OPENCART . 'system/');
define('DIR_EXTENSION', DIR_OPENCART . 'extension/');
define('DIR_IMAGE', DIR_OPENCART . 'image/');
define('DIR_STORAGE', DIR_SYSTEM . 'storage/');
define('DIR_LANGUAGE', DIR_APPLICATION . 'language/');
define('DIR_TEMPLATE', DIR_APPLICATION . 'view/template/');
define('DIR_CONFIG', DIR_SYSTEM . 'config/');
define('DIR_CACHE', DIR_STORAGE . 'cache/');
define('DIR_DOWNLOAD', DIR_STORAGE . 'download/');
define('DIR_LOGS', DIR_STORAGE . 'logs/');
define('DIR_SESSION', DIR_STORAGE . 'session/');
define('DIR_UPLOAD', DIR_STORAGE . 'upload/');
define('DB_DRIVER', 'mysqli');
define('DB_HOSTNAME', '127.0.0.1');
define('DB_USERNAME', '${DB_USER}');
define('DB_PASSWORD', '${DB_PASS}');
define('DB_DATABASE', '${DB_NAME}');
define('DB_PREFIX', '${DB_PREFIX}');
define('DB_PORT', '3306');
define('DB_SSL_KEY', '');
define('DB_SSL_CERT', '');
define('DB_SSL_CA', '');
CATCONF

    # Admin config.php
    cat > /var/www/html/admin/config.php <<ADMCONF
<?php
define('APPLICATION', 'Admin');
define('HTTP_SERVER', '${HTTP_SERVER}/admin/');
define('HTTP_CATALOG', '${HTTP_SERVER}/');
define('DIR_OPENCART', '/var/www/html/');
define('DIR_APPLICATION', DIR_OPENCART . 'admin/');
define('DIR_SYSTEM', DIR_OPENCART . 'system/');
define('DIR_EXTENSION', DIR_OPENCART . 'extension/');
define('DIR_IMAGE', DIR_OPENCART . 'image/');
define('DIR_STORAGE', DIR_SYSTEM . 'storage/');
define('DIR_CATALOG', DIR_OPENCART . 'catalog/');
define('DIR_LANGUAGE', DIR_APPLICATION . 'language/');
define('DIR_TEMPLATE', DIR_APPLICATION . 'view/template/');
define('DIR_CONFIG', DIR_SYSTEM . 'config/');
define('DIR_CACHE', DIR_STORAGE . 'cache/');
define('DIR_DOWNLOAD', DIR_STORAGE . 'download/');
define('DIR_LOGS', DIR_STORAGE . 'logs/');
define('DIR_SESSION', DIR_STORAGE . 'session/');
define('DIR_UPLOAD', DIR_STORAGE . 'upload/');
define('DB_DRIVER', 'mysqli');
define('DB_HOSTNAME', '127.0.0.1');
define('DB_USERNAME', '${DB_USER}');
define('DB_PASSWORD', '${DB_PASS}');
define('DB_DATABASE', '${DB_NAME}');
define('DB_PREFIX', '${DB_PREFIX}');
define('DB_PORT', '3306');
define('DB_SSL_KEY', '');
define('DB_SSL_CERT', '');
define('DB_SSL_CA', '');
define('OPENCART_SERVER', 'https://www.opencart.com/');
ADMCONF

    chown www-data:www-data /var/www/html/config.php /var/www/html/admin/config.php
}

install_opencart() {
    log "Importing OpenCart SQL schema..."

    # Import schema using mysql CLI (proper multi-statement handling)
    if [ -f "/root/opencart-en-gb.sql" ]; then
        mysql -u root "$DB_NAME" < /root/opencart-en-gb.sql 2>&1 | tail -5 || true
        log "SQL schema imported"
    else
        warn "SQL schema not found at /root/opencart-en-gb.sql"
    fi

    log "Creating admin user..."
    local admin_hash
    admin_hash=$(php -r "echo password_hash('${ADMIN_PASS}', PASSWORD_DEFAULT);")

    mysql -u root "$DB_NAME" <<-EOSQL
INSERT IGNORE INTO \`${DB_PREFIX}user\` SET
    user_group_id = 1,
    username = '${ADMIN_USER}',
    password = '${admin_hash}',
    salt = '',
    firstname = 'Admin',
    lastname = 'User',
    email = '${ADMIN_EMAIL}',
    code = '',
    ip = '127.0.0.1',
    status = 1,
    date_added = NOW();
EOSQL
    log "Admin user created: $ADMIN_USER"

    generate_config
    log "OpenCart installed successfully!"
}

# ─── Main ──────────────────────────────────────────────────

log "=== OpenCart Entry Point ==="
log "HTTP server: $HTTP_SERVER"

start_mariadb
setup_database

if db_has_tables; then
    log "Database already populated — generating config.php..."
    generate_config
else
    log "Fresh database — running full installation..."
    install_opencart
fi

# Ensure storage dirs exist and are writable
mkdir -p /var/www/html/system/storage/{cache,logs,session,upload,download,modification,sass}
chown -R www-data:www-data /var/www/html/system/storage

log "Starting Apache..."
exec "$@"
