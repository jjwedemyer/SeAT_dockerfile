FROM ubuntu:14.04

MAINTAINER schmorrison <schmorrison@gmail.com>

ARG DEBIAN_FRONTEND=noninteractive

#apt-cache line for fast local building
#install language-pack-en-base because ppa-pubkey is odd character set
#install software-properties-common to use add-apt-repository
#"export LC_ALL=en_US.UTF-8 && export LANG=en_US.UTF-8" to set up the UTF-8 language sets
#add-apt-repository php5-5.6 ppa
#install ppa:ondrej packages
#RUN echo 'Acquire::http { Proxy "http://172.17.0.2:3142"; };' >> /etc/apt/apt.conf.d/01proxy && \
RUN apt-get update && apt-get install -y \
	curl \
	expect \ 
	git \
	language-pack-en-base \
	mysql-server \
	redis-server \
	screen \
	supervisor \
	software-properties-common \
	wget && \ 
	export LC_ALL=en_US.UTF-8 && \  
	export LANG=en_US.UTF-8 && \
	add-apt-repository ppa:ondrej/php5-5.6 -y && \ 
	apt-get update && apt-get install -y \
	apache2 \
	php5 \
	php5-cli \
	php5-mcrypt \
	php5-intl \
	php5-mysql \
	php5-curl \
	php5-gd
	
RUN MYSQL_ROOT_PASS=$(echo -e `date` | md5sum | awk '{ print $1 }') && \
	sleep 1 && \
	SEAT_DB_PASS=$(echo -e `date` | md5sum | awk '{ print $1 }') && \
	echo "MySQL $MYSQL_ROOT_PASS" > /root/seat-install-creds && \
	echo "User $SEAT_DB_PASS" >> /root/seat-install-creds && \
	/etc/init.d/mysql start && \
	mysqladmin -u root password "$MYSQL_ROOT_PASS" && \
	mysql -u root -p$MYSQL_ROOT_PASS -e "CREATE DATABASE seat;" && \
	mysql -u root -p$MYSQL_ROOT_PASS -e "GRANT ALL ON seat.* to seat@localhost IDENTIFIED BY '$SEAT_DB_PASS';" && \
	cd /var/www && \
	curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer && \
	hash -r && \
	composer create-project eveseat/seat seat --keep-vcs --prefer-source --no-dev && \
	chown -R www-data:www-data /var/www/seat && \
	chmod -R guo+w /var/www/seat/storage/ && \
	cd /var/www/seat && \
	sed -i -r "s/DB_DATABASE=homestead/DB_DATABASE=seat/" /var/www/seat/.env && \
	sed -i -r "s/DB_USERNAME=homestead/DB_USERNAME=seat/" /var/www/seat/.env && \
	sed -i -r "s/DB_PASSWORD=secret/DB_PASSWORD=$SEAT_DB_PASS/" /var/www/seat/.env && \
	sed -i -r "s/CACHE_DRIVER=file/CACHE_DRIVER=redis/" /var/www/seat/.env && \
	sed -i -r "s/QUEUE_DRIVER=sync/QUEUE_DRIVER=redis/" /var/www/seat/.env && \
	sed -i -r "s/Options Indexes FollowSymLinks/Options FollowSymLinks/" /etc/apache2/apache2.conf && \
	sed -i -r "s/ServerTokens OS/ServerTokens Prod/" /etc/apache2/conf-enabled/security.conf && \
	sed -i -r "s/ServerSignature On/ServerSignature Off/" /etc/apache2/conf-enabled/security.conf && \
	unlink /etc/apache2/sites-enabled/000-default.conf && \
	ln -s /etc/apache2/sites-available/100-seat.local.conf /etc/apache2/sites-enabled/100-seat.local.conf && \
	php artisan vendor:publish && \
	php artisan migrate && \
	php artisan db:seed --class=Seat\\Services\\database\\seeds\\NotificationTypesSeeder && \
	php artisan db:seed --class=Seat\\Services\\database\\seeds\\ScheduleSeeder && \
	php artisan eve:update-sde -n
	
ADD /static/seat.conf /etc/supervisor/conf.d/seat.conf
ADD /static/100-seat.local.conf /etc/apache2/sites-available/100-seat.local.conf
ADD /static/crontab /app/crontab

RUN /etc/init.d/mysql start && \
	service supervisor start && \
	supervisorctl reload && \
	crontab /app/crontab && \
	a2enmod rewrite && \
	service apache2 restart && \
	apachectl restart && \
	apachectl -t -D DUMP_VHOSTS