FROM php:8.1-apache

# Install system deps + MariaDB server
RUN apt-get update && apt-get install -y \
    git curl libpng-dev libonig-dev libxml2-dev libzip-dev unzip \
    mariadb-server mariadb-client \
    && docker-php-ext-install pdo_mysql bcmath zip gd mysqli mbstring \
    && a2enmod rewrite headers \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

# Clone OpenCart 4.1.0.4
RUN git clone --depth 1 --branch 4.1.0.4 https://github.com/opencart/opencart.git /tmp/opencart \
    && cp -r /tmp/opencart/upload/* /var/www/html/ \
    && rm -rf /tmp/opencart \
    && touch /var/www/html/config.php /var/www/html/admin/config.php \
    && chown -R www-data:www-data /var/www/html

# Apache vhost
COPY apache-opencart.conf /etc/apache2/sites-available/000-default.conf

# Startup script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Create dirs for MariaDB
RUN mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

HEALTHCHECK --interval=30s --timeout=5s --start-period=90s --retries=3 \
    CMD curl -f http://localhost/ || exit 1

EXPOSE 80

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
