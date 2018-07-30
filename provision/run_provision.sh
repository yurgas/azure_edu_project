#!/usr/bin/env bash
set -x
set -o errexit

CONFIG_FILE=$1
DB_NAME=$2
DB_USER=$3
DB_PASSWORD=$4
DB_HOST=$5

AZ_SHARE_USER=$6
AZ_SHARE_PASS=$7
AZ_SHARE=$8

#Install required packages and WordPress
until apt-get -y update && apt-get -y install cifs-utils apache2 php libapache2-mod-php php-mcrypt php-mysql php-curl php-gd php-mbstring php-mcrypt php-xml php-xmlrpc
do
  echo "Try again"
  sleep 5
done

cd /tmp
curl -O https://wordpress.org/latest.tar.gz
tar xzvf latest.tar.gz
touch /tmp/wordpress/.htaccess
chmod 660 /tmp/wordpress/.htaccess
rm -rf /var/www/html/*
cp -a /tmp/wordpress/. /var/www/html
chown -R root:www-data /var/www/html
chmod g+w /var/www/html/wp-content
chmod -R g+w /var/www/html/wp-content/themes
chmod -R g+w /var/www/html/wp-content/plugins
systemctl restart apache2

#Mount file storage

mount -t cifs //${AZ_SHARE_USER}.file.core.windows.net/${AZ_SHARE} /var/www/html/wp-content -o vers=3.0,username=${AZ_SHARE_USER},password=${AZ_SHARE_PASS},gid=`id -g www-data`,dir_mode=0775,file_mode=0664
# if no static files, then copy from distribution
if [[ `ls /var/www/html/wp-content | wc -l` == "0" ]]; then
  echo 'Copying static resources ...'
  cp -a /tmp/wordpress/wp-content/. /var/www/html/wp-content
fi

#Generate wordpress configuration file

exec 1>$CONFIG_FILE

echo "<?php"
echo
echo "define('FORCE_SSL_ADMIN', true);"
echo "if (strpos(\$_SERVER['HTTP_X_FORWARDED_PROTO'], 'https') !== false)"
echo "  \$_SERVER['HTTPS']='on';"
echo
echo "define('DB_NAME', '$DB_NAME');"
echo "define('DB_USER', '$DB_USER');"
echo "define('DB_PASSWORD', '$DB_PASSWORD');"
echo "define('DB_HOST', '$DB_HOST');"
echo "define('DB_CHARSET', 'utf8');"
echo "define('DB_COLLATE', '');"
echo

curl -s https://api.wordpress.org/secret-key/1.1/salt/

echo
echo "\$table_prefix  = 'wp_';"
echo
echo "define('WP_DEBUG', false);"
echo
echo "if ( !defined('ABSPATH') )"
echo "	define('ABSPATH', dirname(__FILE__) . '/');"
echo
echo "require_once(ABSPATH . 'wp-settings.php');"
