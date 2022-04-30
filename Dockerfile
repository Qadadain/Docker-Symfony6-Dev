FROM php:8.1.2-fpm-alpine AS base

ENV APP_ENV prod

RUN apk add --update --no-cache icu-dev \
 && docker-php-ext-install intl opcache pdo pdo_mysql \
 && rm -rf /var/www/html/

########################################################################################################################

FROM base AS composer

RUN apk add --no-cache --update curl git libzip-dev openssl unzip zip \
 && docker-php-ext-install zip \
 && mkdir /composer

COPY /app/composer.json /composer
COPY /app/composer.lock /composer
COPY /app/symfony.lock /composer

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN composer install --working-dir=/composer --no-dev --no-autoloader --no-progress --no-scripts --no-interaction

COPY /app /var/www/html/
RUN mv /composer/vendor /var/www/html/vendor \
 && composer dump-autoload --working-dir=/var/www/html/ --optimize --classmap-authoritative --no-interaction \
 && php /var/www/html/bin/console cache:clear

########################################################################################################################

FROM node:17-alpine3.14 AS npm

WORKDIR /code
ENV NODE_ENV development

COPY /app/package.json /code
COPY /app/package-lock.json /code
RUN npm ci

COPY /app/assets /code/assets
COPY /app/webpack.config.js /code
RUN npm run build

########################################################################################################################

FROM base AS final

RUN apk add --no-cache --update nginx \
 && docker-php-ext-enable opcache

COPY ./deploy/local.ini /usr/local/etc/php/conf.d/local.ini
COPY ./deploy/conf.d/nginx.conf /etc/nginx/http.d/default.conf

COPY --from=composer --chown=www-data /var/www/html /var/www/html
COPY --from=npm --chown=www-data /code/public/build /var/www/html/public/build

EXPOSE 8080
RUN nginx -t

COPY /post_deploy.sh /post_deploy.sh

RUN ["chmod", "+x", "/post_deploy.sh"]

CMD [ "sh", "/post_deploy.sh" ]

########################################################################################################################

FROM final as dev

ENV APP_ENV=dev

COPY --from=composer:2 /usr/bin/composer /usr/local/bin/composer

RUN apk add --no-cache --update npm
