FROM php:8.1-apache

RUN apt-get update && apt-get install -y \
    git curl libpng-dev libonig-dev libxml2-dev libzip-dev unzip \
    mariadb-server mariadb-client \
    && docker-php-ext-install pdo_mysql bcmath zip gd mysqli mbstring \
    && a2enmod rewrite headers \
    && curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www/html

# Clone OpenCart 4.1.0.4 and install dependencies
RUN git clone --depth 1 --branch 4.1.0.4 https://github.com/opencart/opencart.git /tmp/opencart \
    && cp -r /tmp/opencart/upload/* /var/www/html/ \
    && cp /tmp/opencart/composer.json /tmp/opencart/composer.lock /var/www/html/ \
    && composer install --no-dev --prefer-dist --no-interaction \
    && ls -la install/cli_install.php \
    && touch /var/www/html/config.php /var/www/html/admin/config.php \
    && chown -R www-data:www-data /var/www/html \
    && rm -rf /tmp/opencart

COPY apache-opencart.conf /etc/apache2/sites-available/000-default.conf
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
    && mkdir -p /var/run/mysqld && chown mysql:mysql /var/run/mysqld

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=5 \
    CMD curl -f http://localhost/ || exit 1

EXPOSE 80

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]
