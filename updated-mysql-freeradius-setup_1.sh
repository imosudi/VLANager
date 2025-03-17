#!/bin/bash
# updated-mysql-freeradius-setup.sh
# This script installs and configures FreeRADIUS with MySQL on Ubuntu 24.04.
# It sets up the FreeRADIUS MySQL database, imports the schema, creates extra
# tables for switch/VLAN mappings, configures the SQL module, installs a MAC-based VLAN policy,
# and creates a minimal policy module so that policy.d/mac_policy is valid.

set -e

echo "=== Updating system packages ==="
sudo apt update && sudo apt upgrade -y

echo "=== Installing required packages ==="
sudo apt install -y mysql-server python3 python3-pip python3-venv nginx git freeradius freeradius-mysql freeradius-utils

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

echo "=== Creating additional tables for switches, VLANs, and MAC-to-VLAN mapping ==="
sudo mysql -u root -p radius <<EOF
CREATE TABLE IF NOT EXISTS switches (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(64) NOT NULL,
    ip_address VARCHAR(15) NOT NULL,
    secret VARCHAR(64) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY (ip_address)
);
CREATE TABLE IF NOT EXISTS vlans (
    id INT AUTO_INCREMENT PRIMARY KEY,
    switch_id INT NOT NULL,
    vlan_id INT NOT NULL,
    name VARCHAR(64) NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (switch_id) REFERENCES switches(id) ON DELETE CASCADE,
    UNIQUE KEY (switch_id, vlan_id)
);
CREATE TABLE IF NOT EXISTS mac_vlan_mapping (
    id INT AUTO_INCREMENT PRIMARY KEY,
    mac_address VARCHAR(17) NOT NULL,
    vlan_id INT NOT NULL,
    switch_id INT NOT NULL,
    description TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (vlan_id) REFERENCES vlans(id) ON DELETE CASCADE,
    FOREIGN KEY (switch_id) REFERENCES switches(id) ON DELETE CASCADE,
    UNIQUE KEY (mac_address, switch_id)
);
EOF

echo "=== Enabling the SQL module ==="
sudo ln -sf /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql

echo "=== Removing duplicate backup files from mods-enabled ==="
sudo rm -f /etc/freeradius/3.0/mods-enabled/*.bak*

echo "=== Configuring SQL module for MySQL ==="
sudo sed -i 's/dialect = "sqlite"/dialect = "mysql"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*server = "localhost"/server = "localhost"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*port = 3306/port = 3306/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*login = "radius"/login = "radius"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*password = "radpass"/password = "radpass"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/radius_db = "radius"/radius_db = "radius"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/\${..generic_failure_query}/null/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/\${..generic_success_query}/null/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/read_clients = no/read_clients = yes/' /etc/freeradius/3.0/mods-enabled/sql

echo "=== Updating sites-enabled/default to enable SQL in relevant sections ==="
sudo sed -i '/^#[[:space:]]*sql/s/^#[[:space:]]*//g' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/authenticate {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/accounting {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/session {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/post-auth {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default

echo "=== Creating dynamic clients.conf configuration ==="
sudo tee /etc/freeradius/3.0/clients.conf > /dev/null <<EOF
client localhost {
    ipaddr = 127.0.0.1
    secret = testing123
    require_message_authenticator = no
    nas_type = other
}

client default {
    ipaddr = 0.0.0.0/0
    secret = testing123
}
EOF

echo "=== Creating MAC-based VLAN assignment policy file ==="
sudo tee /etc/freeradius/3.0/policy.d/mac_policy > /dev/null <<'EOF'
policy mac_auth {
    if (&User-Name =~ /^([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})$/i) {
        update request {
            &User-Name := "%{tolower:%{1}%{2}%{3}%{4}%{5}%{6}}"
            &User-Password := "%{User-Name}"
        }
    }
}
EOF

echo "=== Inserting mac_auth into the authorize section in sites-enabled/default ==="
sudo sed -i '/authorize {/a \    mac_auth' /etc/freeradius/3.0/sites-enabled/default

echo "=== Ensuring the 'policy' module is enabled ==="
# Create a minimal policy module file that defines a 'policy' block.
if [ ! -f /etc/freeradius/3.0/mods-available/policy ]; then
    sudo tee /etc/freeradius/3.0/mods-available/policy > /dev/null <<'EOF'
policy policy {
    # Minimal policy configuration for FreeRADIUS.
    # This module acts as a placeholder to allow policy files in policy.d (like mac_policy) to reference "policy".
}
EOF
fi
if [ ! -f /etc/freeradius/3.0/mods-enabled/policy ]; then
    sudo ln -s /etc/freeradius/3.0/mods-available/policy /etc/freeradius/3.0/mods-enabled/policy
fi

echo "=== Setting proper ownership and permissions ==="
sudo chown -R freerad:freerad /etc/freeradius/3.0/
sudo chmod -R 755 /etc/freeradius/3.0/

echo "=== Restarting FreeRADIUS service ==="
sudo systemctl restart freeradius

echo "=== FreeRADIUS service status ==="
sudo systemctl status freeradius --no-pager

echo "Setup complete. For detailed debugging, run 'sudo freeradius -X'."
