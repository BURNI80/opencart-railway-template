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

    # Initialize data dir if needed
    if [ ! -d "/var/lib/mysql/mysql" ]; then
        mysql_install_db --user=mysql --datadir=/var/lib/mysql >/dev/null 2>&1
    fi

    # Start MariaDB in background
    mysqld_safe --datadir=/var/lib/mysql &

    # Wait for it
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

    # Create database and user
    mysql -u root <<-EOSQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
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

    # Root config.php (catalog)
    cat > /var/www/html/config.php <<CONF
<?php
// APPLICATION
define('APPLICATION', 'Catalog');

// HTTP
define('HTTP_SERVER', '${HTTP_SERVER}/');

// DIR
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

// DB
define('DB_DRIVER', 'mysqli');
define('DB_HOSTNAME', 'localhost');
define('DB_USERNAME', '${DB_USER}');
define('DB_PASSWORD', '${DB_PASS}');
define('DB_DATABASE', '${DB_NAME}');
define('DB_PREFIX', '${DB_PREFIX}');
define('DB_PORT', '3306');
define('DB_SSL_KEY', '');
define('DB_SSL_CERT', '');
define('DB_SSL_CA', '');

// Cache
define('CACHE_ENGINE', 'file');
CONF

    # Admin config.php
    cat > /var/www/html/admin/config.php <<CONF
<?php
// APPLICATION
define('APPLICATION', 'Admin');

// HTTP
define('HTTP_SERVER', '${HTTP_SERVER}/admin/');
define('HTTP_CATALOG', '${HTTP_SERVER}/');

// DIR
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

// DB
define('DB_DRIVER', 'mysqli');
define('DB_HOSTNAME', 'localhost');
define('DB_USERNAME', '${DB_USER}');
define('DB_PASSWORD', '${DB_PASS}');
define('DB_DATABASE', '${DB_NAME}');
define('DB_PREFIX', '${DB_PREFIX}');
define('DB_PORT', '3306');
define('DB_SSL_KEY', '');
define('DB_SSL_CERT', '');
define('DB_SSL_CA', '');

// Cache
define('CACHE_ENGINE', 'file');

// OpenCart API
define('OPENCART_SERVER', 'https://www.opencart.com/');
CONF

    chown www-data:www-data /var/www/html/config.php /var/www/html/admin/config.php
}

install_opencart() {
    log "Running custom installer..."

    php /var/www/html/install/custom_install.php \
        --username    "$ADMIN_USER" \
        --email       "$ADMIN_EMAIL" \
        --password    "$ADMIN_PASS" \
        --http_server "$HTTP_SERVER/" \
        --db_driver   mysqli \
        --db_hostname localhost \
        --db_port     3306 \
        --db_username "$DB_USER" \
        --db_password "$DB_PASS" \
        --db_database "$DB_NAME" \
        --db_prefix   "$DB_PREFIX" \
        --language    en-gb

    log "Removing install directory..."
    rm -rf /var/www/html/install

    log "OpenCart installed successfully!"
}

# ─── Main ──────────────────────────────────────────────────

log "=== OpenCart Entry Point ==="
log "HTTP server: $HTTP_SERVER"

# Start embedded MariaDB
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

# Keep MariaDB running in background by starting Apache in foreground
log "Starting Apache..."
exec "$@"
