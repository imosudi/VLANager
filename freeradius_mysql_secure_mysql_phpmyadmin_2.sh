#!/bin/bash
# setup-freeradius-mysql.sh
# Installs and configures FreeRADIUS with MySQL on Ubuntu 24.04,
# and installs/configures phpMyAdmin to be served by Nginx using PHP 8.2-FPM.

set -e  # Exit on any error

echo "=== Updating system packages ==="
sudo apt update && sudo apt upgrade -y

echo "=== Installing required packages for FreeRADIUS, MySQL, etc. ==="
sudo apt install -y mysql-server python3 python3-pip python3-venv nginx git freeradius freeradius-mysql freeradius-utils

# --- Install PHP 8.2 and required modules ---
echo "=== Adding Ondrej PHP PPA ==="
sudo add-apt-repository ppa:ondrej/php -y

echo "=== Updating package list after adding PHP PPA ==="
sudo apt update

echo "=== Installing PHP 8.2 and required modules ==="
sudo apt install -y php8.2 php8.2-fpm php8.2-mysql

echo "=== Enabling and Restarting PHP 8.2-FPM service ==="
sudo systemctl enable php8.2-fpm
sudo systemctl restart php8.2-fpm

# Define credentials
MYSQL_ROOT_PASSWORD="0YAdunfecoker1#"
RADIUS_DB_PASSWORD="radpass"

echo "=== Securing MySQL installation ==="
sudo mysql -u root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

echo "=== Stopping FreeRADIUS service ==="
sudo systemctl stop freeradius

echo "=== Creating MySQL database and user for FreeRADIUS ==="
sudo mysql -u root -p <<EOF
CREATE DATABASE IF NOT EXISTS radius;
CREATE USER IF NOT EXISTS 'radius'@'localhost' IDENTIFIED BY '$RADIUS_DB_PASSWORD';
GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'localhost';
FLUSH PRIVILEGES;
EOF

echo "=== Importing FreeRADIUS MySQL schema ==="
if [ -f /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql ]; then
    sudo mysql -u root -p radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql
else
    echo "Error: FreeRADIUS MySQL schema file not found!"
    exit 1
fi

echo "=== Enabling the SQL module for FreeRADIUS ==="
sudo ln -sf /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql

echo "=== Configuring SQL module for MySQL in FreeRADIUS ==="
sudo sed -i 's/dialect = "sqlite"/dialect = "mysql"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*server = "localhost"/server = "localhost"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*port = 3306/port = 3306/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*login = "radius"/login = "radius"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*password = "radpass"/password = "radpass"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/radius_db = "radius"/radius_db = "radius"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/read_clients = no/read_clients = yes/' /etc/freeradius/3.0/mods-enabled/sql

echo "=== Enabling and Configuring sqlippool (if available) ==="
if [ -f /etc/freeradius/3.0/mods-available/sqlippool ]; then
    sudo ln -sf /etc/freeradius/3.0/mods-available/sqlippool /etc/freeradius/3.0/mods-enabled/sqlippool
    sudo sed -i 's/dialect = "sqlite"/dialect = "mysql"/' /etc/freeradius/3.0/mods-enabled/sqlippool
    sudo sed -i 's/#\s*server = "localhost"/server = "localhost"/' /etc/freeradius/3.0/mods-enabled/sqlippool
    sudo sed -i 's/#\s*port = 3306/port = 3306/' /etc/freeradius/3.0/mods-enabled/sqlippool
    sudo sed -i 's/#\s*login = "radius"/login = "radius"/' /etc/freeradius/3.0/mods-enabled/sqlippool
    sudo sed -i 's/#\s*password = "radpass"/password = "radpass"/' /etc/freeradius/3.0/mods-enabled/sqlippool
    sudo sed -i 's/radius_db = "radius"/radius_db = "radius"/' /etc/freeradius/3.0/mods-enabled/sqlippool
else
    echo "Warning: sqlippool module not found. Skipping..."
fi

echo "=== Configuring sites-enabled/default to enable SQL in FreeRADIUS ==="
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

echo "=== Disabling unnecessary modules in FreeRADIUS ==="
sudo rm -f /etc/freeradius/3.0/mods-enabled/policy

echo "=== Setting proper ownership and permissions for FreeRADIUS ==="
sudo chown -R freerad:freerad /etc/freeradius/3.0/
sudo chmod -R 755 /etc/freeradius/3.0/

echo "=== Installing phpMyAdmin with automated setup for Nginx ==="
export DEBIAN_FRONTEND=noninteractive
sudo debconf-set-selections <<EOF
phpmyadmin phpmyadmin/dbconfig-install boolean true
phpmyadmin phpmyadmin/app-password-confirm password yourpassword
phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_ROOT_PASSWORD
phpmyadmin phpmyadmin/mysql/app-pass password yourpassword
phpmyadmin phpmyadmin/reconfigure-webserver multiselect none
EOF
sudo apt install -y phpmyadmin

echo "=== Configuring Nginx for phpMyAdmin ==="
sudo tee /etc/nginx/sites-available/phpmyadmin > /dev/null <<EOF
server {
    listen 80;
    server_name your_domain_or_ip;

    root /usr/share/phpmyadmin;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ ^/(doc|sql|setup)/ {
        deny all;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.2-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location /phpmyadmin {
        alias /usr/share/phpmyadmin/;
        index index.php;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

# Enable the phpMyAdmin Nginx configuration
sudo ln -s /etc/nginx/sites-available/phpmyadmin /etc/nginx/sites-enabled/

echo "=== Restarting Nginx ==="
sudo systemctl restart nginx

echo "=== Securing phpMyAdmin with Basic Authentication ==="
sudo apt install -y apache2-utils
sudo mkdir -p /etc/nginx/.htpasswd
sudo htpasswd -cb /etc/nginx/.htpasswd/phpmyadmin admin securepassword

# Enforce HTTP Basic Authentication in the phpMyAdmin Nginx config
sudo sed -i '/location \/phpmyadmin {/a\
    auth_basic "Restricted Access";\
    auth_basic_user_file /etc/nginx/.htpasswd/phpmyadmin;' /etc/nginx/sites-available/phpmyadmin

sudo systemctl reload nginx

echo "=== Granting MySQL privileges to phpMyAdmin user ==="
sudo mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOF
CREATE USER IF NOT EXISTS 'phpmyadmin'@'localhost' IDENTIFIED BY 'yourpassword';
GRANT ALL PRIVILEGES ON *.* TO 'phpmyadmin'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

echo "=== phpMyAdmin installation and configuration completed for Nginx! ==="

echo "=== Restarting FreeRADIUS service ==="
sudo systemctl restart freeradius

echo "=== FreeRADIUS service status ==="
sudo systemctl status freeradius --no-pager

echo "Setup complete! Run 'sudo freeradius -X' to debug."
