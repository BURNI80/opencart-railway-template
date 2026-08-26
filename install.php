<?php
/**
 * Custom OpenCart Installer for Railway
 * Replaces cli_install.php which may not be available at runtime.
 * Imports the SQL schema directly and creates the admin user.
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);

$args = getopt('', [
    'username:', 'email:', 'password:', 'http_server:',
    'db_hostname:', 'db_port:', 'db_username:', 'db_password:',
    'db_database:', 'db_prefix:', 'db_driver:',
    'language:'
]);

$username  = $args['username']   ?? 'admin';
$email     = $args['email']      ?? 'admin@example.com';
$password  = $args['password']   ?? 'admin';
$server    = $args['http_server'] ?? 'http://localhost/';
$db_host   = $args['db_hostname'] ?? '127.0.0.1';
$db_port   = $args['db_port']     ?? '3306';
$db_user   = $args['db_username'] ?? 'opencart';
$db_pass   = $args['db_password'] ?? 'opencart';
$db_name   = $args['db_database'] ?? 'opencart';
$db_prefix = $args['db_prefix']   ?? 'oc_';
$language  = $args['language']     ?? 'en-gb';

echo "=== OpenCart Custom Installer ===\n";
echo "Database: $db_name @ $db_host:$db_port\n";
echo "Admin: $username ($email)\n";
echo "HTTP Server: $server\n\n";

// Connect to database (use 127.0.0.1 for TCP instead of socket)
try {
    $pdo = new PDO(
        "mysql:host=$db_host;port=$db_port;dbname=$db_name;charset=utf8mb4",
        $db_user,
        $db_pass,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::MYSQL_ATTR_INIT_COMMAND => "SET NAMES utf8mb4"
        ]
    );
    echo "[OK] Connected to database: $db_name\n";
} catch (PDOException $e) {
    die("[FAIL] Database connection: " . $e->getMessage() . "\n");
}

// Check if already installed
$stmt = $pdo->query("SHOW TABLES LIKE '{$db_prefix}setting'");
if ($stmt->fetch()) {
    echo "[SKIP] Tables already exist, generating config only\n";
} else {
    // Import SQL schema
    $sqlFile = '/root/opencart-en-gb.sql';
    if (!file_exists($sqlFile)) {
        die("[FAIL] SQL schema not found: $sqlFile\n");
    }

    echo "[INFO] Importing SQL schema...\n";
    $sql = file_get_contents($sqlFile);

    // Replace table prefix
    if ($db_prefix !== 'oc_') {
        $sql = str_replace('oc_', $db_prefix, $sql);
    }

    // Split by semicolons (naive but works for this schema)
    $statements = array_filter(array_map('trim', explode(';', $sql)));

    $imported = 0;
    foreach ($statements as $statement) {
        if (empty($statement) || substr($statement, 0, 2) === '--') {
            continue;
        }
        try {
            $pdo->exec($statement);
            $imported++;
        } catch (PDOException $e) {
            // Skip duplicate key errors and similar
            if (strpos($e->getMessage(), 'Duplicate') === false &&
                strpos($e->getMessage(), 'already exists') === false) {
                echo "[WARN] " . substr($e->getMessage(), 0, 120) . "\n";
            }
        }
    }
    echo "[OK] Imported $imported SQL statements\n";

    // Create admin user with proper password hash
    $encrypted = password_hash($password, PASSWORD_DEFAULT);
    $date_added = date('Y-m-d H:i:s');

    try {
        $pdo->exec("INSERT INTO `{$db_prefix}user` SET
            user_group_id = 1,
            username = " . $pdo->quote($username) . ",
            password = " . $pdo->quote($encrypted) . ",
            salt = '',
            firstname = 'Admin',
            lastname = 'User',
            email = " . $pdo->quote($email) . ",
            code = '',
            ip = '127.0.0.1',
            status = 1,
            date_added = " . $pdo->quote($date_added));
        echo "[OK] Created admin user: $username\n";
    } catch (PDOException $e) {
        echo "[WARN] Admin user: " . $e->getMessage() . "\n";
    }

    // Insert default settings
    $settings = [
        ['config_name'  => 'config_email',           'config_value' => $email],
        ['config_name'  => 'config_name',            'config_value' => 'OpenCart Store'],
        ['config_name'  => 'config_url',             'config_value' => $server],
        ['config_name'  => 'config_ssl',             'config_value' => $server],
        ['config_name'  => 'config_language',        'config_value' => $language],
        ['config_name'  => 'config_admin',           'config_value' => 'admin'],
        ['config_name'  => 'config_error_filename',  'config_value' => 'error_not_found'],
        ['config_name'  => 'config_error_login',     'config_value' => 'error_login'],
        ['config_name'  => 'config_error_permission', 'config_value' => 'error_permission'],
    ];

    foreach ($settings as $s) {
        try {
            $stmt = $pdo->prepare("INSERT IGNORE INTO `{$db_prefix}setting` SET `store_id` = 0, `group` = 'config', `key` = ?, `value` = ?");
            $stmt->execute([$s['config_name'], $s['config_value']]);
        } catch (PDOException $e) {
            // ignore
        }
    }
    echo "[OK] Default settings inserted\n";
}

// Generate config.php files
$dir_opencart = '/var/www/html/';
$dir_storage  = $dir_opencart . 'system/storage/';

// Catalog config.php
$catalog_config = "<?php\n// HTTP\n"
    . "define('HTTP_SERVER', '" . addslashes($server) . "');\n\n"
    . "// DIR\n"
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
    . "// DB\n"
    . "define('DB_DRIVER', 'mysqli');\n"
    . "define('DB_HOSTNAME', '127.0.0.1');\n"
    . "define('DB_USERNAME', '" . addslashes($db_user) . "');\n"
    . "define('DB_PASSWORD', '" . addslashes($db_pass) . "');\n"
    . "define('DB_DATABASE', '" . addslashes($db_name) . "');\n"
    . "define('DB_PREFIX', '" . addslashes($db_prefix) . "');\n"
    . "define('DB_PORT', '$db_port');\n"
    . "define('DB_SSL_KEY', '');\n"
    . "define('DB_SSL_CERT', '');\n"
    . "define('DB_SSL_CA', '');\n";

file_put_contents('/var/www/html/config.php', $catalog_config);
echo "[OK] Wrote config.php (catalog)\n";

// Admin config.php
$admin_config = "<?php\n// HTTP\n"
    . "define('HTTP_SERVER', '" . addslashes($server) . "admin/');\n"
    . "define('HTTP_CATALOG', '" . addslashes($server) . "');\n\n"
    . "// DIR\n"
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
    . "// DB\n"
    . "define('DB_DRIVER', 'mysqli');\n"
    . "define('DB_HOSTNAME', '127.0.0.1');\n"
    . "define('DB_USERNAME', '" . addslashes($db_user) . "');\n"
    . "define('DB_PASSWORD', '" . addslashes($db_pass) . "');\n"
    . "define('DB_DATABASE', '" . addslashes($db_name) . "');\n"
    . "define('DB_PREFIX', '" . addslashes($db_prefix) . "');\n"
    . "define('DB_PORT', '$db_port');\n"
    . "define('DB_SSL_KEY', '');\n"
    . "define('DB_SSL_CERT', '');\n"
    . "define('DB_SSL_CA', '');\n\n"
    . "// OpenCart API\n"
    . "define('OPENCART_SERVER', 'https://www.opencart.com/');\n";

file_put_contents('/var/www/html/admin/config.php', $admin_config);
echo "[OK] Wrote admin/config.php\n";

echo "\n=== Installation Complete ===\n";
