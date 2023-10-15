FROM debian:12-slim
ARG S6_OVERLAY_VERSION=3.1.5.0
ENV NODE_MAJOR=20
ENV KBIN_GURL https://github.com/ernestwisniewski/kbin
ENV NGINX_CONF /etc/nginx/nginx.conf
ENV WWW_CONF /etc/nginx/conf.d/www.conf
ENV PHP_CONF /etc/php/8.2/fpm/php.ini
ENV FPM_CONF /etc/php/8.2/fpm/php-fpm.conf
ENV FPM_POOL /etc/php/8.2/fpm/pool.d/www.conf
ENV PATH "$PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/go/bin:/usr/lib/postgresql/15/bin"
ENV USER http

# create user
RUN adduser ${USER}

# install requirements
RUN apt-get update -y && \
	apt-get upgrade -y && \
	apt-get install --no-install-recommends -y vim xz-utils wget ca-certificates curl gnupg git nginx php8.2-common php8.2-fpm php8.2-cli php8.2-amqp php8.2-pgsql php8.2-gd php8.2-curl php8.2-simplexml php8.2-dom php8.2-xml php8.2-redis php8.2-mbstring php8.2-intl unzip

# install composer
RUN wget https://getcomposer.org/installer -O /tmp/composer-setup.php && \
	php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer

# config nginx
COPY conf/nginx/kbin.conf ${WWW_CONF}
RUN openssl dhparam -dsaparam -out /etc/nginx/dhparam.pem 4096 && \
	chmod 644 /etc/nginx/dhparam.pem && \
	echo "daemon off;" >> ${NGINX_CONF} && \
	sed -i -e "s/user www-data;/user ${USER};/g" ${NGINX_CONF} && \
	rm /etc/nginx/sites-enabled/default

# config php
RUN sed -i -e "s/;daemonize = yes/daemonize = no/g" ${FPM_CONF} && \
	sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" ${PHP_CONF} && \
	sed -i -e "s/upload_max_filesize = 2M/upload_max_filesize = 8M/g" ${PHP_CONF} && \
	sed -i -e "s/memory_limit = 128M/memory_limit = 256M/g" ${PHP_CONF} && \
	sed -i -e "s/;opcache.enable=1/opcache.enable=1/g" ${PHP_CONF} && \
	sed -i -e "s/;opcache.enable_cli=0/opcache.enable_cli=1/g" ${PHP_CONF} && \
	sed -i -e "s/;opcache.memory_consumption=128/opcache.memory_consumption=512/g" ${PHP_CONF} && \
	sed -i -e "s/;opcache.interned_strings_buffer=8/opcache.interned_strings_buffer=128/g" ${PHP_CONF} && \
	sed -i -e "s/;opcache.max_accelerated_files=10000/opcache.max_accelerated_files=100000/g" ${PHP_CONF} && \
	sed -i -e "s/listen.owner = www-data/listen.owner = ${USER}/g" ${FPM_POOL} && \
	sed -i -e "s/listen.group = www-data/listen.group = ${USER}/g" ${FPM_POOL} && \
	sed -i -e "s/;listen.mode = 0660/listen.mode = 0660/g" ${FPM_POOL} && \
	sed -i -e "s/user = www-data/user = ${USER}/g" ${FPM_POOL} && \
	sed -i -e "s/group = www-data/group = ${USER}/g" ${FPM_POOL} && \
	sed -i -e "s/pm = dynamic/pm = dynamic/g" ${FPM_POOL} && \
	sed -i -e "s/pm.max_children = 5/pm.max_children = 60/g" ${FPM_POOL} && \
	sed -i -e "s/pm.start_servers = 2/pm.start_servers = 10/g" ${FPM_POOL} && \
	sed -i -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 5/g" ${FPM_POOL} && \
	sed -i -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 10/g" ${FPM_POOL} && \
	sed -i -e "s/listen = \/run\/php\/php8.2-fpm.sock/listen = \/run\/php\/php-fpm.sock/g" ${FPM_POOL} && \
	mkdir -p /run/php && \
	chown -R ${USER}:${USER} /run/php && \
	touch /var/log/php8.2-fpm.log && \
	chown ${USER}:${USER} /var/log/php8.2-fpm.log

# install nodejs and yarn
RUN mkdir -p /etc/apt/keyrings && \
	curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
	echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_$NODE_MAJOR.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list &&\
	curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg | apt-key add - && \
	echo "deb https://dl.yarnpkg.com/debian/ stable main" | tee /etc/apt/sources.list.d/yarn.list && \
	apt-get update && \
	apt-get install nodejs yarn --no-install-recommends -y

# install kbin
RUN mkdir -p /var/www/kbin && \
	cd /var/www/kbin && \
	git clone ${KBIN_GURL} . && \
	mkdir public/media && \
	chmod -R 777 public/media && \
	mkdir var && \
	cp .env.example .env && \
	chown -R ${USER}:${USER} /var/www/kbin

# enable services
RUN mkdir -p /etc/s6-overlay/s6-rc.d/user/contents.d && \
	mkdir -p /etc/s6-overlay/s6-rc.d/php && \
	touch /etc/s6-overlay/s6-rc.d/php/run && \
	echo "#!/bin/sh" >> /etc/s6-overlay/s6-rc.d/php/run && \
	echo "exec s6-setuidgid ${USER} /usr/sbin/php-fpm8.2 --fpm-config /etc/php/8.2/fpm/php-fpm.conf" >> /etc/s6-overlay/s6-rc.d/php/run && \
	chmod +x /etc/s6-overlay/s6-rc.d/php/run && \
	touch /etc/s6-overlay/s6-rc.d/php/type && \
	echo "longrun" >> /etc/s6-overlay/s6-rc.d/php/type && \
	touch /etc/s6-overlay/s6-rc.d/user/contents.d/php && \ 
	mkdir -p /etc/s6-overlay/s6-rc.d/nginx && \
	touch /etc/s6-overlay/s6-rc.d/nginx/run && \
	echo "#!/command/execlineb -P" >> /etc/s6-overlay/s6-rc.d/nginx/run && \
	echo "/usr/sbin/nginx" >> /etc/s6-overlay/s6-rc.d/nginx/run && \
	chmod +x /etc/s6-overlay/s6-rc.d/nginx/run && \
	touch /etc/s6-overlay/s6-rc.d/nginx/type && \
	echo "longrun" >> /etc/s6-overlay/s6-rc.d/nginx/type && \
	touch /etc/s6-overlay/s6-rc.d/user/contents.d/nginx

EXPOSE 80

ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-noarch.tar.xz
ADD https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-x86_64.tar.xz /tmp
RUN tar -C / -Jxpf /tmp/s6-overlay-x86_64.tar.xz

# clear tmp
RUN apt-get clean -y && \
	rm -r /tmp/*

ENTRYPOINT ["/init"]
