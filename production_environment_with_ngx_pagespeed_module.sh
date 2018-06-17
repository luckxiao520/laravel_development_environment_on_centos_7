#!/usr/bin/env bash

#
# INSTRUCTIONS FOR USE:
# 1. Copy this shell script to your home directory.
# 2. Make it executable with the following command:
#      chmod a+x filename.sh
#      bash filename.sh
# 3. Execute the script as a sudo user:
#      sudo ./filename.sh
#
#


# color constants

RED='\033[0;31m'
GREEN='\033[0;32m'
LIGHTGREEN='\033[1;32m'
ORANGE='\033[0;33m'
NC='\033[0m' # No Color

#Checking OS version

OSVERSION=`cat /etc/redhat-release`
OS=`echo $OSVERSION|cut -c1-22`
if [ "$OS" == "CentOS Linux release 7" ]
then
echo -e "${RED} Starting setup! ${NC}"
echo ""

#Updating System

echo -e "${ORANGE} Updating packages ${NC}"
sudo yum -y update
echo -e "${GREEN} Updated packages ${NC}"

#Git

echo -e "${ORANGE} Installing git ${NC}"
sudo yum install -y git
echo -e "${GREEN} git Installed ${NC}"


#Wget

echo -e "${ORANGE} Installing wget ${NC}"
sudo yum install -y wget
echo -e "${GREEN} wget Installed ${NC}"


#Nginx

RELEASEVER='$releasever'
BASEARCH='$basearch'
echo -e "[nginx]
name=nginx repo
baseurl=http://nginx.org/packages/centos/${RELEASEVER}/${BASEARCH}/
gpgcheck=0
enabled=1" > /etc/yum.repos.d/nginx.repo

echo -e "${ORANGE} Installing nginx ${NC}"
sudo yum -y install nginx-1.14.0
echo -e "${GREEN} nginx Installed ${NC}"

#Starting Nginx

echo -e "${ORANGE} Starting nginx ${LIGHTGREEN}"
sudo systemctl start nginx
sudo systemctl enable nginx
echo -e "${GREEN} nginx Started ${NC}"

#Setting Up Firewall

echo -e "${ORANGE} Adding Firewall Rule ${LIGHTGREEN}"
sudo firewall-cmd --zone=public --add-service=http --permanent

#for SSL Uncomment Below line
#sudo firewall-cmd --zone=public --add-service=https --permanent

sudo service firewalld reload
echo -e "${GREEN} Firewall Configured ${NC}"

#Setting repo ius for PHP-fpm & eple
#To Run php application with nginx no special configuration is required
# Url for Repo https://dl.iuscommunity.org/pub/ius/stable/CentOS/7/x86_64/


#Upadating packages with ius repo

echo -e "${ORANGE} Updating packages ${NC}"
sudo yum install -y http://dl.iuscommunity.org/pub/ius/stable/CentOS/7/x86_64/ius-release-1.0-15.ius.centos7.noarch.rpm
sudo yum -y update
echo -e "${GREEN} Updated packages ${NC}"

#MySQL

echo -e "${ORANGE} Installing MySQL server ${NC}"
wget http://dev.mysql.com/get/mysql80-community-release-el7-1.noarch.rpm
sudo yum -y localinstall mysql80-community-release-el7-1.noarch.rpm
sudo yum repolist enabled | grep "mysql.*-community.*"
sudo yum install -y mysql-community-server
echo -e "${GREEN} MySQL Installed ${NC}"

#Starting MySQL

echo -e "${ORANGE} Starting MySQL ${LIGHTGREEN}"
sudo systemctl start mysqld
sudo systemctl enable mysqld
echo -e "${GREEN} MySQL Started ${NC}"

#Setting Up MySQL

echo -e "${ORANGE} Setting Up MySQL ${LIGHTGREEN}"
grep 'temporary password' /var/log/mysqld.log
sudo mysql_secure_installation
echo "${NC} "
echo ""


#PHP
echo -e "${ORANGE} Installing PHP ${NC}"
sudo yum -y install php72u php72u-cli php72u-gd php72u-devel php72u-pecl-memcached php72u-imap php72u-mysql php72u-mbstring php72u-pdo php72u-mysqlnd php72u-opcache php72u-xml php72u-mcrypt php72u-intl php72u-bcmath php72u-json php72u-iconv php72u-soap php72u-fpm php72u-pecl-imagick php72u-pecl-redis

# Changing Php.ini value
sudo sed -i "s/error_reporting = .*/error_reporting = E_ALL/" /etc/php.ini
sudo sed -i "s/display_errors = .*/display_errors = Off/" /etc/php.ini
sudo sed -i "s/memory_limit = .*/memory_limit = 512M/" /etc/php.ini
sudo sed -i "s/;date.timezone.*/date.timezone = UTC/" /etc/php.ini
sudo sed -i "s/;error_log = php_errors.log/error_log = php_errors.log/" /etc/php.ini

sudo systemctl start php-fpm
sudo systemctl enable php-fpm


#Setting Nginx for PHP-FPM & google pagespeed

wget https://extras.getpagespeed.com/redhat/7/x86_64/RPMS/nginx-module-nps-1.14.0.1.13.35.2-1.el7_4.gps.x86_64.rpm
rpm -Uvh nginx-*

rm -f /etc/nginx/nginx.conf
rm -f /etc/nginx/conf.d/default.conf
mkdir -p /var/www/html


cat > /etc/nginx/nginx.conf <<EOF

            user  nginx;

            worker_processes  auto;

            worker_rlimit_nofile 1192;

            error_log  /var/log/nginx/error.log warn;
            pid        /var/run/nginx.pid;

            load_module modules/ngx_pagespeed.so;

            events {
                worker_connections  1024;
            }

            http {
                # Hide Nginx version
                 server_tokens off;

                # PageSpeed
                pagespeed on;
                # needs to exist and be writable by nginx
                pagespeed FileCachePath /var/ngx_pagespeed_cache;
                # Filter settings
                pagespeed RewriteLevel CoreFilters;
                pagespeed EnableFilters collapse_whitespace,remove_comments;
                pagespeed XHeaderValue "Powered By ngx_pagespeed";
                include       /etc/nginx/mime.types;
                default_type  application/octet-stream;

                charset_types
                    text/css
                    text/plain
                    text/vnd.wap.wml
                    application/javascript
                    application/json
                    application/rss+xml
                    application/xml;

                log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                                  '\$status \$body_bytes_sent "\$http_referer" '
                                  '"\$http_user_agent" "\$http_x_forwarded_for"';

                # access log
                access_log  /var/log/nginx/access.log  main;

                sendfile       on;
                tcp_nopush     on;

                keepalive_timeout  65;

                include /etc/nginx/conf.d/*.conf;
            }
EOF

cat > /etc/nginx/conf.d/default.conf <<EOF

            server {
                    #port to listen on
                    listen 80;
                    listen [::]:80 ipv6only=on;

                    # server name
                    server_name _;

                    # root location
                    root   /var/www/html;

                    index  index.php index.html index.htm;

                    location / {
                        try_files \$uri \$uri/ /index.php?\$query_string;
                    }

                    # Ensure requests for pagespeed optimized resources go to the pagespeed handler
                    # and no extraneous headers get set.
                    location ~ "\.pagespeed\.([a-z]\.)?[a-z]{2}\.[^.]{10}\.[^.]+" {
                        add_header "" "";
                      }

                    location ~ "^/pagespeed_static/" { }
                    location ~ "^/ngx_pagespeed_beacon$" { }

                    location ~ [^/]\.php(/|\$) {
                    fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
                    if (!-f \$document_root\$fastcgi_script_name) {
                        return 404;
                    }
                    fastcgi_param HTTP_PROXY "";
                        fastcgi_pass   127.0.0.1:9000;
                        fastcgi_index  index.php;
                        include        fastcgi_params;
                        fastcgi_param  SCRIPT_FILENAME   \$document_root\$fastcgi_script_name;
                    }
            }
EOF


sudo systemctl restart php-fpm
sudo systemctl restart nginx
echo -e "${GREEN} PHP Installed with following Version ${NC}"
php -v
echo""

#composer

echo -e "${ORANGE} Installing Composer ${NC}"
sudo curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/bin --filename=composer
echo -e "${GREEN} Composer installed ${NC}"

#NodeJS

echo -e "${ORANGE} Installing NodeJS ${NC}"
sudo curl --silent --location https://rpm.nodesource.com/setup_9.x | sudo bash -
sudo yum -y install nodejs
echo -e "${GREEN} NodeJS installed ${NC}"

#Dependencies or Libraries

sudo yum -y install jpegoptim optipng pngquant
sudo yum -y install libpng-devel
sudo yum -y install autoconf nasm libtool
sudo npm install -g svgo
sudo yum -y install gifsicle

#Fast memory for storing cache files.
mount -t tmpfs -o size=200M,mode=0755 tmpfs /var/ngx_pagespeed_cache
sudo setsebool -P httpd_execmem on
chown -R nginx:root /var/www/html
chown -R nginx:nginx /var/ngx_pagespeed_cache
sudo systemctl restart php-fpm
sudo systemctl restart nginx


#Redis
sudo yum -y install redis


#Supervisor for Queue
sudo yum -y install python-setuptools python-pip
easy_install supervisor


echo -e " ${GREEN} All Done ${NC}"
echo ""

else
echo ""
echo -e "${RED} Unsupported OS Version ${NC}"
echo ""
fi
