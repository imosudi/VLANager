#!/bin/bash
# setup-freeradius-mysql.sh
# Installs FreeRADIUS with MySQL and phpMyAdmin on Ubuntu 24.04 with Nginx

set -e  # Exit on any error

echo "=== Updating system packages ==="
sudo apt update && sudo apt upgrade -y

echo "=== Installing required packages ==="
sudo apt install -y mysql-server python3 python3-pip python3-venv nginx git freeradius freeradius-mysql freeradius-utils php-fpm php-cli php-mbstring php-zip php-gd php-json php-curl php-common unzip

echo "=== Securing MySQL installation ==="
echo "If you haven't already, run 'sudo mysql_secure_installation' now."
read -p "Press Enter to continue after securing MySQL..."

echo "=== Stopping FreeRADIUS service ==="
sudo systemctl stop freeradius

echo "=== Creating MySQL database and user for FreeRADIUS ==="
sudo mysql -u root -p <<EOF
CREATE DATABASE IF NOT EXISTS radius;
CREATE USER IF NOT EXISTS 'radius'@'localhost' IDENTIFIED BY 'radpass';
GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "=== Importing FreeRADIUS MySQL schema ==="
sudo mysql -u root -p radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql

echo "=== Enabling the SQL module ==="
sudo ln -sf /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql

echo "=== Configuring SQL module for MySQL ==="
sudo sed -i 's/dialect = "sqlite"/dialect = "mysql"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*server = "localhost"/server = "localhost"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*port = 3306/port = 3306/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*login = "radius"/login = "radius"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*password = "radpass"/password = "radpass"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/radius_db = "radius"/radius_db = "radius"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/read_clients = no/read_clients = yes/' /etc/freeradius/3.0/mods-enabled/sql

echo "=== Installing and Configuring phpMyAdmin for Nginx ==="
sudo mkdir -p /usr/share/phpmyadmin
cd /usr/share/phpmyadmin
sudo wget -q https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.zip
sudo unzip phpMyAdmin-latest-all-languages.zip
sudo mv phpMyAdmin-*-all-languages/* .
sudo rm -rf phpMyAdmin-*-all-languages phpMyAdmin-latest-all-languages.zip
sudo chown -R www-data:www-data /usr/share/phpmyadmin
sudo chmod -R 755 /usr/share/phpmyadmin

echo "=== Creating phpMyAdmin configuration file ==="
sudo tee /etc/nginx/sites-available/phpmyadmin > /dev/null <<EOF
server {
    listen 80;
    server_name phpmyadmin.local;
    root /usr/share/phpmyadmin;

    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

echo "=== Enabling phpMyAdmin in Nginx ==="
sudo ln -s /etc/nginx/sites-available/phpmyadmin /etc/nginx/sites-enabled/
sudo systemctl reload nginx

echo "=== Creating phpMyAdmin root user ==="
sudo mysql -u root -p <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'rootpassword';
FLUSH PRIVILEGES;
EOF

echo "=== Configuring sites-enabled/default to enable SQL ==="
sudo sed -i '/^#[[:space:]]*sql/s/^#[[:space:]]*//g' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/authenticate {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/accounting {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/session {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/post-auth {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default

echo "=== Creating FreeRADIUS clients.conf ==="
sudo tee /etc/freeradius/3.0/clients.conf > /dev/null <<EOF
client localhost {
    ipaddr = 127.0.0.1
    secret = testing123
    require_message_authenticator = no
    nas_type = other
}
EOF

echo "=== Disabling unnecessary modules ==="
sudo rm -f /etc/freeradius/3.0/mods-enabled/policy  # `policy` is not needed and causes errors

echo "=== Setting proper ownership and permissions ==="
sudo chown -R freerad:freerad /etc/freeradius/3.0/
sudo chmod -R 755 /etc/freeradius/3.0/

echo "=== Restarting MySQL, Nginx, PHP-FPM, and FreeRADIUS ==="
sudo systemctl restart mysql
sudo systemctl restart nginx
sudo systemctl restart php-fpm
sudo systemctl restart freeradius

echo "=== Setup complete! ==="
echo "Access phpMyAdmin at: http://phpmyadmin.local"
echo "Run 'sudo freeradius -X' to debug FreeRADIUS."
