#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log()  { echo -e "${GREEN}[opencart]${NC} $*"; }
warn() { echo -e "${YELLOW}[opencart]${NC} $*"; }
err()  { echo -e "${RED}[opencart]${NC} $*" >&2; }

# A single self-contained container. By default it runs an embedded MariaDB
# inside this same container (simple, zero-config deploy). If a real external
# MySQL host is provided via MYSQLHOST, it connects to that instead.
DB_HOST="${MYSQLHOST:-127.0.0.1}"
DB_PORT="${MYSQLPORT:-3306}"
DB_USER="${MYSQLUSER:-opencart}"
DB_PASS="${MYSQLPASSWORD:-opencart}"
DB_NAME="${MYSQLDATABASE:-opencart}"
DB_PREFIX="${DB_PREFIX:-oc_}"

ADMIN_USER="${ADMIN_USERNAME:-admin}"
ADMIN_PASS="${ADMIN_PASSWORD:-opencart}"
ADMIN_EMAIL="${ADMIN_EMAIL:-admin@example.com}"

if [ -n "$RAILWAY_PUBLIC_DOMAIN" ]; then
    HTTP_SERVER="https://${RAILWAY_PUBLIC_DOMAIN}"
else
    HTTP_SERVER="${HTTP_SERVER:-http://localhost:8080}"
fi

is_local_db() {
    [ "$DB_HOST" = "127.0.0.1" ] || [ "$DB_HOST" = "localhost" ]
}

# ─── Embedded MariaDB (only when no external DB is configured) ──

start_mariadb() {
    log "Starting embedded MariaDB..."

    if [ ! -d "/var/lib/mysql/mysql" ]; then
        mysql_install_db --user=mysql --datadir=/var/lib/mysql >/dev/null 2>&1
    fi

    mysqld_safe --datadir=/var/lib/mysql --bind-address=127.0.0.1 &

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

setup_embedded_db() {
    log "Creating database and user on embedded MariaDB..."
    mysql -u root <<-EOSQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`;
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;
EOSQL
}

# ─── Main ──────────────────────────────────────────────────

log "=== OpenCart Entry Point ==="
log "HTTP server: $HTTP_SERVER"

INSTALLER=/usr/local/bin/opencart_install.php

if [ ! -f "$INSTALLER" ]; then
    err "Installer not found at $INSTALLER — cannot provision database"
    exit 1
fi

if is_local_db; then
    start_mariadb
    setup_embedded_db
    DB_HOSTNAME=127.0.0.1
else
    log "Using external database at $DB_HOST:$DB_PORT"
    DB_HOSTNAME="$DB_HOST"
fi

# Provision schema + data + admin idempotently via the PHP installer.
# It uses oc_db_schema() to CREATE the tables and then imports the demo data.
log "Running OpenCart installer..."
php "$INSTALLER" \
    --username="$ADMIN_USER" \
    --email="$ADMIN_EMAIL" \
    --password="$ADMIN_PASS" \
    --http_server="$HTTP_SERVER" \
    --db_hostname="$DB_HOSTNAME" \
    --db_port="$DB_PORT" \
    --db_username="$DB_USER" \
    --db_password="$DB_PASS" \
    --db_database="$DB_NAME" \
    --db_prefix="$DB_PREFIX" \
    --language=en-gb

# Ensure storage dirs exist and are writable
mkdir -p /var/www/html/system/storage/{cache,logs,session,upload,download,modification,sass}
chown -R www-data:www-data /var/www/html/system/storage

log "Starting Apache..."
exec "$@"
