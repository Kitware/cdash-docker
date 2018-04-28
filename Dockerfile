FROM php:7.0-apache

LABEL maintainer="Omar Padron <omar.padron@kitware.com>"

RUN curl -sL https://deb.nodesource.com/setup_6.x | bash                       \
 && apt-get install -y git libbz2-dev libfreetype6-dev libjpeg62-turbo-dev     \
    libmcrypt-dev libpng12-dev libpq-dev libxslt-dev libxss1 nodejs unzip wget \
    zip                                                                        \
 && docker-php-ext-configure pgsql --with-pgsql=/usr/local/pgsql               \
 && docker-php-ext-configure gd --with-freetype-dir=/usr/include/              \
                                --with-jpeg-dir=/usr/include/                  \
 && docker-php-ext-install -j$(nproc) bcmath bz2 gd pdo_mysql pdo_pgsql xsl    \
 && pecl install xdebug-2.5.5                                                  \
 && docker-php-ext-enable xdebug                                               \
 && (                                                                          \
      echo '544e09ee 996cdf60 ece3804a bc52599c'                               \
    ; echo '22b1f40f 4323403c 44d44fdf dd586475'                               \
    ; echo 'ca9813a8 58088ffb c1f233e9 b180f061'                               \
    ) | tr -d "\\n " | sed 's/$/  -/g' > checksum                              \
 && curl -o - 'https://getcomposer.org/installer'                              \
 |  tee composer-setup.php                                                     \
 |  sha384sum -c checksum                                                      \
 && rm checksum                                                                \
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
COPY docker-lib.sh /docker-lib.sh
RUN chmod +x /docker-entrypoint.sh

WORKDIR /var/www/cdash
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=5m \
  CMD ["curl", "-f", "http://localhost/viewProjects.php"]

ENTRYPOINT ["/bin/bash", "/docker-entrypoint.sh"]
