#!/bin/bash
# setup-freeradius-mysql.sh
# Installs and configures FreeRADIUS with MySQL on Ubuntu 24.04

set -e  # Exit on any error

echo "=== Updating system packages ==="
sudo apt update && sudo apt upgrade -y

echo "=== Installing required packages ==="
sudo apt install -y mysql-server python3 python3-pip python3-venv nginx git freeradius freeradius-mysql freeradius-utils

MYSQL_ROOT_PASSWORD="0YAdunfecoker1#"
RADIUS_DB_PASSWORD="radpass"


echo "=== Securing MySQL installation ==="
sudo mysql -u root <<EOF
-- Set the root password (replace 'your_root_password' with a secure password)
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$MYSQL_ROOT_PASSWORD';

-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Disallow root login remotely
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');

-- Remove test database and access to it
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';

-- Apply changes
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
echo "=== Checking if the FreeRADIUS MySQL schema file exists"
if [ -f /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql ]; then
    sudo mysql -u root -p radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql
else
    echo "Error: FreeRADIUS MySQL schema file not found!"
    exit 1
fi

#sudo mysql -u root -p radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql

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

echo "=== Enabling and Configuring sqlippool ==="
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

echo "=== Restarting FreeRADIUS service ==="
sudo systemctl restart freeradius

echo "=== FreeRADIUS service status ==="
sudo systemctl status freeradius --no-pager

echo "Setup complete! Run 'sudo freeradius -X' to debug."
