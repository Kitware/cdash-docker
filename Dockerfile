FROM php:7.0-apache

LABEL maintainer="Omar Padron <omar.padron@kitware.com>"

RUN apt-get update && apt-get install -y gnupg1

RUN curl -sL https://deb.nodesource.com/setup_6.x | bash                       \
 && apt-get update && apt-get install -y git libbz2-dev libfreetype6-dev       \
  libjpeg62-turbo-dev libmcrypt-dev libpng-dev libpq-dev libxslt-dev libxss1   \
  nodejs unzip wget zip                                                        \
 && docker-php-ext-configure pgsql --with-pgsql=/usr/local/pgsql               \
 && docker-php-ext-configure gd --with-freetype-dir=/usr/include/              \
                                --with-jpeg-dir=/usr/include/                  \
 && docker-php-ext-install -j$(nproc) bcmath bz2 gd pdo_mysql pdo_pgsql xsl    \
 && pecl install xdebug-2.5.5                                                  \
 && docker-php-ext-enable xdebug                                               \
 && curl -o composer-setup.php.sha384sum                                       \
        https://composer.github.io/installer.sha384sum                         \
 && curl -o composer-setup.php --location https://getcomposer.org/installer    \
 && sha384sum -c composer-setup.php.sha384sum                                  \
 && rm composer-setup.php.sha384sum                                            \
 || ( rm -f checksum composer-setup.php && false )                             \
 && php composer-setup.php --install-dir=/usr/local/bin --filename=composer    \
 && php -r "unlink('composer-setup.php');"                                     \
 && composer self-update --no-interaction

RUN mkdir -p /var/www                                             \
 && git clone git://github.com/kitware/cdash /var/www/cdash       \
 && rm -rf /var/www/cdash/.git                                    \
 && cd /var/www/cdash                                             \
 && composer install --no-interaction --no-progress --prefer-dist \
 && npm install                                                   \
 && node_modules/.bin/gulp                                        \
 && chmod 777 backup log public/rss public/upload                 \
 && rm -rf /var/www/html                                          \
 && ln -s /var/www/cdash/public /var/www/html

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

WORKDIR /var/www/cdash
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5m \
  CMD ["curl", "-f", "http://localhost/viewProjects.php"]

ENTRYPOINT ["/bin/bash", "/docker-entrypoint.sh"]
