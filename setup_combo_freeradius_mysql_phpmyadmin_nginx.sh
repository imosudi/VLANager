#!/bin/bash
# setup-freeradius-mysql.sh
# Installs and configures FreeRADIUS with MySQL on Ubuntu 24.04,
# and installs/configures phpMyAdmin to be served by Nginx using PHP 8.2-FPM.
# The script automatically retrieves the device's current connectivity IP address and uses it for the MySQL root password
# as well as the phpMyAdmin password.

set -e  # Exit on any error

# Get the primary IP address of the device (the first IP from hostname -I)
SERVER_IP=$(hostname -I | awk '{print $1}')
echo "Detected primary IP: $SERVER_IP"

# Use the detected IP as the MySQL root and phpMyAdmin password.
MYSQL_ROOT_PASSWORD="0YAdunfecoker1#"
RADIUS_DB_PASSWORD="radpass"
PHPMYADMIN_PASSWORD="$MYSQL_ROOT_PASSWORD"


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
;
USE radius;
CREATE TABLE IF NOT EXISTS switches (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    ip_address VARCHAR(15) NOT NULL UNIQUE,
    secret VARCHAR(64) NOT NULL,
    description TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
);
;
CREATE TABLE IF NOT EXISTS vlans (
    id INT AUTO_INCREMENT PRIMARY KEY,
    switch_id INT NOT NULL,
    vlan_id INT NOT NULL,
    name VARCHAR(64) NOT NULL,
    description TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE (switch_id, vlan_id),
    FOREIGN KEY (switch_id) REFERENCES switches(id) ON DELETE CASCADE
);
;
CREATE TABLE IF NOT EXISTS user (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL UNIQUE,
    email VARCHAR(120) NOT NULL UNIQUE,
    password_hash VARCHAR(255),
    is_admin BOOLEAN DEFAULT FALSE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
;
CREATE TABLE IF NOT EXISTS mac_vlan_mapping (
    id INT AUTO_INCREMENT PRIMARY KEY,
    mac_address VARCHAR(17) NOT NULL,
    vlan_id INT NOT NULL,
    switch_id INT NOT NULL,
    description TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE (mac_address, switch_id),
    FOREIGN KEY (vlan_id) REFERENCES vlans(id) ON DELETE CASCADE,
    FOREIGN KEY (switch_id) REFERENCES switches(id) ON DELETE CASCADE
);
;
CREATE TABLE IF NOT EXISTS radcheck (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    attribute VARCHAR(64) NOT NULL,
    op VARCHAR(2) NOT NULL,
    value VARCHAR(253) NOT NULL
);
;
CREATE TABLE IF NOT EXISTS radreply (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    attribute VARCHAR(64) NOT NULL,
    op VARCHAR(2) NOT NULL,
    value VARCHAR(253) NOT NULL
);
;
CREATE TABLE IF NOT EXISTS radusergroup (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(64) NOT NULL,
    groupname VARCHAR(64) NOT NULL,
    priority INT NOT NULL
);
;
CREATE TABLE IF NOT EXISTS nas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nasname VARCHAR(128) NOT NULL,
    shortname VARCHAR(32),
    type VARCHAR(30) DEFAULT 'other',
    ports INT,
    secret VARCHAR(60) NOT NULL,
    server VARCHAR(64),
    community VARCHAR(50),
    description VARCHAR(200)
);
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
phpmyadmin phpmyadmin/app-password-confirm password $PHPMYADMIN_PASSWORD
phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_ROOT_PASSWORD
phpmyadmin phpmyadmin/mysql/app-pass password $PHPMYADMIN_PASSWORD
phpmyadmin phpmyadmin/reconfigure-webserver multiselect none
EOF
sudo apt install -y phpmyadmin

echo "=== Configuring Nginx for phpMyAdmin ==="
sudo tee /etc/nginx/sites-available/phpmyadmin > /dev/null <<EOF
server {
    listen 80;
    server_name $SERVER_IP;

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
CREATE USER IF NOT EXISTS 'phpmyadmin'@'localhost' IDENTIFIED BY '$PHPMYADMIN_PASSWORD';
GRANT ALL PRIVILEGES ON *.* TO 'phpmyadmin'@'localhost' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

echo "=== phpMyAdmin installation and configuration completed for Nginx! ==="

echo "=== Restarting FreeRADIUS service ==="
sudo systemctl restart freeradius

echo "=== FreeRADIUS service status ==="
sudo systemctl status freeradius --no-pager

echo "Setup complete! Run 'sudo freeradius -X' to debug."


# Create a Flask web application for management
echo "Creating Flask web application for RADIUS management..."
cd ~
mkdir -p ~/VLANAGER #/radius-manager
cd ~/VLANAGER

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install required Python packages
pip install flask flask-sqlalchemy flask-login flask-wtf mysql-connector-python gunicorn pymysql flask-Migrate email-validator flask_moment cryptography pysnmp
