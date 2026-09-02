<?php
/**
 * OpenCart Installer for Railway (embedded MariaDB)
 *
 * Uses oc_db_schema() to create tables, then imports INSERT data.
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);

$args = getopt('', [
    'username:', 'email:', 'password:', 'http_server:',
    'db_hostname:', 'db_port:', 'db_username:', 'db_password:',
    'db_database:', 'db_prefix:', 'db_driver:',
    'language:'
]);

$username  = $args['username']    ?? 'admin';
$email     = $args['email']       ?? 'admin@example.com';
$password  = $args['password']    ?? 'admin';
$server    = $args['http_server'] ?? 'http://localhost/';
$db_host   = $args['db_hostname'] ?? '127.0.0.1';
$db_port   = $args['db_port']     ?? '3306';
$db_user   = $args['db_username'] ?? 'opencart';
$db_pass   = $args['db_password'] ?? 'opencart';
$db_name   = $args['db_database'] ?? 'opencart';
$db_prefix = $args['db_prefix']   ?? 'oc_';
$language  = $args['language']     ?? 'en-gb';

echo "=== OpenCart Installer (db_schema) ===\n";
echo "Database: $db_name @ $db_host:$db_port\n";
echo "Admin: $username ($email)\n\n";

// Load OpenCart DB schema helper (pure function, no dependencies)
require_once '/var/www/html/system/helper/db_schema.php';

// Connect via PDO
try {
    $pdo = new PDO(
        "mysql:host=$db_host;port=$db_port;dbname=$db_name;charset=utf8mb4",
        $db_user,
        $db_pass,
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4",
        ]
    );
    echo "[OK] Connected to database\n";
} catch (PDOException $e) {
    die("[FAIL] Connection: " . $e->getMessage() . "\n");
}

// Check if already installed
$stmt = $pdo->query("SHOW TABLES LIKE '{$db_prefix}setting'");
if ($stmt->fetch()) {
    echo "[SKIP] Tables already exist\n";
} else {
    echo "[INFO] Creating database tables from oc_db_schema()...\n";

    $tables = oc_db_schema();
    $created = 0;

    foreach ($tables as $table) {
        $tbl_name = $db_prefix . $table['name'];

        // Drop if exists
        $pdo->exec("DROP TABLE IF EXISTS `$tbl_name`");

        // Build CREATE TABLE
        $sql = "CREATE TABLE `$tbl_name` (\n";

        foreach ($table['field'] as $field) {
            $sql .= "  `" . $field['name'] . "` " . $field['type'];
            if (!empty($field['not_null'])) {
                $sql .= " NOT NULL";
            }
            if (isset($field['default'])) {
                $sql .= " DEFAULT '" . addslashes($field['default']) . "'";
            }
            if (!empty($field['auto_increment'])) {
                $sql .= " AUTO_INCREMENT";
            }
            $sql .= ",\n";
        }

        if (isset($table['primary'])) {
            $cols = array_map(function ($c) { return "`$c`"; }, $table['primary']);
            $sql .= "  PRIMARY KEY (" . implode(',', $cols) . "),\n";
        }

        if (isset($table['index'])) {
            foreach ($table['index'] as $index) {
                $cols = array_map(function ($c) { return "`$c`"; }, $index['key']);
                $sql .= "  KEY `" . $index['name'] . "` (" . implode(',', $cols) . "),\n";
            }
        }

        $sql = rtrim($sql, ",\n") . "\n";
        $sql .= ") ENGINE=" . $table['engine']
              . " CHARSET=" . $table['charset']
              . " ROW_FORMAT=DYNAMIC COLLATE=" . $table['collate'] . ";\n";

        try {
            $pdo->exec($sql);
            $created++;
        } catch (PDOException $e) {
            echo "[ERROR] Table $tbl_name: " . $e->getMessage() . "\n";
        }
    }
    echo "[OK] Created $created tables\n";

    // Import INSERT data from SQL file
    $sqlFile = '/root/opencart-en-gb.sql';
    if (!file_exists($sqlFile)) {
        die("[FAIL] SQL file not found: $sqlFile\n");
    }

    echo "[INFO] Importing INSERT data...\n";
    $lines = file($sqlFile, FILE_IGNORE_NEW_LINES);
    $imported = 0;

    if ($lines) {
        $sql  = '';
        $start = false;

        foreach ($lines as $line) {
            if (substr($line, 0, 12) === 'INSERT INTO ') {
                $sql   = '';
                $start = true;
            }
            if ($start) {
                $sql .= $line;
            }
            if (substr($line, -2) === ');') {
                $sql = str_replace("INSERT INTO `oc_", "INSERT INTO `$db_prefix", $sql);
                try {
                    $pdo->exec($sql);
                    $imported++;
                } catch (PDOException $e) {
                    echo "[WARN] " . substr($e->getMessage(), 0, 120) . "\n";
                }
                $start = false;
            }
        }
    }
    echo "[OK] Imported $imported INSERT statements\n";

    // Create admin user
    $enc = password_hash($password, PASSWORD_DEFAULT);
    $pdo->exec("SET CHARACTER SET utf8mb4");
    $pdo->exec("SET @@session.sql_mode = ''");

    $pdo->exec("DELETE FROM `{$db_prefix}user` WHERE `user_id` = '1'");
    $stmt = $pdo->prepare("INSERT INTO `{$db_prefix}user` SET
        `user_id` = '1', `user_group_id` = '1',
        `username` = ?, `password` = ?,
        `firstname` = 'Admin', `lastname` = 'User',
        `email` = ?, `status` = '1', `date_added` = NOW()");
    $stmt->execute([$username, $enc, $email]);
    echo "[OK] Created admin user: $username\n";

    // Update settings
    $pdo->exec("DELETE FROM `{$db_prefix}setting` WHERE `key` = 'config_email'");
    $stmt = $pdo->prepare("INSERT INTO `{$db_prefix}setting` SET `code` = 'config', `key` = 'config_email', `value` = ?");
    $stmt->execute([$email]);

    $pdo->exec("DELETE FROM `{$db_prefix}setting` WHERE `key` = 'config_encryption'");
    $enc_key = bin2hex(random_bytes(512));
    $stmt = $pdo->prepare("INSERT INTO `{$db_prefix}setting` SET `code` = 'config', `key` = 'config_encryption', `value` = ?");
    $stmt->execute([$enc_key]);

    $pdo->exec("INSERT INTO `{$db_prefix}api` SET `username` = 'Default', `key` = '" . bin2hex(random_bytes(128)) . "', `status` = 1, `date_added` = NOW(), `date_modified` = NOW()");
    $api_id = $pdo->lastInsertId();

    $pdo->exec("DELETE FROM `{$db_prefix}setting` WHERE `key` = 'config_api_id'");
    $stmt = $pdo->prepare("INSERT INTO `{$db_prefix}setting` SET `code` = 'config', `key` = 'config_api_id', `value` = ?");
    $stmt->execute([(string)$api_id]);

    $pdo->exec("UPDATE `{$db_prefix}setting` SET `value` = 'INV-" . date('Y') . "-00' WHERE `key` = 'config_invoice_prefix'");
    echo "[OK] Settings configured\n";
}

// Write config.php files
$dir_opencart = '/var/www/html/';
$dir_storage  = $dir_opencart . 'system/storage/';

// Catalog config.php
$catalog = "<?php\n"
    . "define('APPLICATION', 'Catalog');\n\n"
    . "define('HTTP_SERVER', '" . addslashes($server) . "/');\n\n"
    . "define('DIR_OPENCART', '" . $dir_opencart . "');\n"
    . "define('DIR_APPLICATION', DIR_OPENCART . 'catalog/');\n"
    . "define('DIR_SYSTEM', DIR_OPENCART . 'system/');\n"
    . "define('DIR_EXTENSION', DIR_OPENCART . 'extension/');\n"
    . "define('DIR_IMAGE', DIR_OPENCART . 'image/');\n"
    . "define('DIR_STORAGE', DIR_SYSTEM . 'storage/');\n"
    . "define('DIR_LANGUAGE', DIR_APPLICATION . 'language/');\n"
    . "define('DIR_TEMPLATE', DIR_APPLICATION . 'view/template/');\n"
    . "define('DIR_CONFIG', DIR_SYSTEM . 'config/');\n"
    . "define('DIR_CACHE', DIR_STORAGE . 'cache/');\n"
    . "define('DIR_DOWNLOAD', DIR_STORAGE . 'download/');\n"
    . "define('DIR_LOGS', DIR_STORAGE . 'logs/');\n"
    . "define('DIR_SESSION', DIR_STORAGE . 'session/');\n"
    . "define('DIR_UPLOAD', DIR_STORAGE . 'upload/');\n\n"
    . "define('DB_DRIVER', 'mysqli');\n"
    . "define('DB_HOSTNAME', '" . addslashes($db_host) . "');\n"
    . "define('DB_USERNAME', '" . addslashes($db_user) . "');\n"
    . "define('DB_PASSWORD', '" . addslashes($db_pass) . "');\n"
    . "define('DB_DATABASE', '" . addslashes($db_name) . "');\n"
    . "define('DB_PREFIX', '" . addslashes($db_prefix) . "');\n"
    . "define('DB_PORT', '" . addslashes($db_port) . "');\n"
    . "define('DB_SSL_KEY', '');\n"
    . "define('DB_SSL_CERT', '');\n"
    . "define('DB_SSL_CA', '');\n\n"
    . "define('CACHE_ENGINE', 'file');\n";

file_put_contents('/var/www/html/config.php', $catalog);

// Admin config.php
$admin = "<?php\n"
    . "define('APPLICATION', 'Admin');\n\n"
    . "define('HTTP_SERVER', '" . addslashes($server) . "/admin/');\n"
    . "define('HTTP_CATALOG', '" . addslashes($server) . "/');\n\n"
    . "define('DIR_OPENCART', '" . $dir_opencart . "');\n"
    . "define('DIR_APPLICATION', DIR_OPENCART . 'admin/');\n"
    . "define('DIR_SYSTEM', DIR_OPENCART . 'system/');\n"
    . "define('DIR_EXTENSION', DIR_OPENCART . 'extension/');\n"
    . "define('DIR_IMAGE', DIR_OPENCART . 'image/');\n"
    . "define('DIR_STORAGE', DIR_SYSTEM . 'storage/');\n"
    . "define('DIR_CATALOG', DIR_OPENCART . 'catalog/');\n"
    . "define('DIR_LANGUAGE', DIR_APPLICATION . 'language/');\n"
    . "define('DIR_TEMPLATE', DIR_APPLICATION . 'view/template/');\n"
    . "define('DIR_CONFIG', DIR_SYSTEM . 'config/');\n"
    . "define('DIR_CACHE', DIR_STORAGE . 'cache/');\n"
    . "define('DIR_DOWNLOAD', DIR_STORAGE . 'download/');\n"
    . "define('DIR_LOGS', DIR_STORAGE . 'logs/');\n"
    . "define('DIR_SESSION', DIR_STORAGE . 'session/');\n"
    . "define('DIR_UPLOAD', DIR_STORAGE . 'upload/');\n\n"
    . "define('DB_DRIVER', 'mysqli');\n"
    . "define('DB_HOSTNAME', '" . addslashes($db_host) . "');\n"
    . "define('DB_USERNAME', '" . addslashes($db_user) . "');\n"
    . "define('DB_PASSWORD', '" . addslashes($db_pass) . "');\n"
    . "define('DB_DATABASE', '" . addslashes($db_name) . "');\n"
    . "define('DB_PREFIX', '" . addslashes($db_prefix) . "');\n"
    . "define('DB_PORT', '" . addslashes($db_port) . "');\n"
    . "define('DB_SSL_KEY', '');\n"
    . "define('DB_SSL_CERT', '');\n"
    . "define('DB_SSL_CA', '');\n\n"
    . "define('CACHE_ENGINE', 'file');\n\n"
    . "define('OPENCART_SERVER', 'https://www.opencart.com/');\n";

file_put_contents('/var/www/html/admin/config.php', $admin);
echo "[OK] Wrote admin/config.php\n";

echo "\n=== Installation Complete ===\n";
