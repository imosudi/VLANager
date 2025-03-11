#!/bin/bash
# FreeRADIUS with MySQL and Flask Web Application Setup
# For Ubuntu 24.04 - Supporting Multiple Switches and VLANs

# Update package lists
sudo apt update
sudo apt upgrade -y

# Install MySQL Server and required dependencies
sudo apt install -y mysql-server python3 python3-pip python3-venv nginx git

# Secure MySQL installation
sudo mysql_secure_installation

# Install FreeRADIUS and MySQL module
sudo apt install -y freeradius freeradius-mysql freeradius-utils

# Stop FreeRADIUS service for configuration
sudo systemctl stop freeradius

# Create MySQL database and user for FreeRADIUS
sudo mysql -u root -p <<EOF
CREATE DATABASE radius;
CREATE USER 'radius'@'localhost' IDENTIFIED BY 'radpass';
GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'localhost';
FLUSH PRIVILEGES;
EOF

# Import FreeRADIUS schema into MySQL
#sudo mysql -u radius -pradpass radius  <
#sudo mysql -u root -p radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql
sudo cat /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql | sudo mysql -u root -p radius

# Add switches and NAS tables to track switch and VLAN mappings
#sudo mysql -u radius -pradpass radius <<EOF
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

# Enable SQL module in FreeRADIUS
sudo cp /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/

# Configure SQL module
sudo sed -i 's/dialect = "sqlite"/dialect = "mysql"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*server = "localhost"/server = "localhost"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*port = 3306/port = 3306/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*login = "radius"/login = "radius"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/#\s*password = "radpass"/password = "radpass"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/radius_db = "radius"/radius_db = "radius"/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/\${..generic_failure_query}/null/' /etc/freeradius/3.0/mods-enabled/sql
sudo sed -i 's/\${..generic_success_query}/null/' /etc/freeradius/3.0/mods-enabled/sql

# Enable read/write access to the SQL module
sudo sed -i 's/read_clients = no/read_clients = yes/' /etc/freeradius/3.0/mods-enabled/sql

# Edit sites-enabled/default to use SQL
sudo sed -i '/^#[[:space:]]*sql/s/^#[[:space:]]*//g' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/authenticate {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/accounting {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/session {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/post-auth {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default

# Create a dynamic clients.conf configuration that reads from the database
sudo cat > /etc/freeradius/3.0/clients.conf << 'EOF'
client localhost {
    ipaddr = 127.0.0.1
    secret = testing123
    require_message_authenticator = no
    nas_type = other
}

# Other clients will be loaded from SQL
client default {
    ipaddr = 0.0.0.0/0
    secret = testing123
}
EOF
sudo vi /etc/freeradius/3.0/clients.confv
#client localhost {
#    ipaddr = 127.0.0.1
#    secret = testing123
#    require_message_authenticator = no
#    nas_type = other
#}

# Other clients will be loaded from SQL
#client default {
#    ipaddr = 0.0.0.0/0
#    secret = testing123
#}

# Configure the policy to handle VLAN assignment
sudo cat > /etc/freeradius/3.0/policy.d/mac_policy << 'EOF'
policy mac_auth {
    if (&User-Name =~ /^([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})$/i) {
        update request {
            &User-Name := "%{tolower:%{1}%{2}%{3}%{4}%{5}%{6}}"
            &User-Password := "%{User-Name}"
        }
    }
}
EOF

# Update the authorize section to use our new policy
sudo sed -i '/authorize {/a \    mac_auth' /etc/freeradius/3.0/sites-enabled/default

# Set ownership and permissions
sudo chown -R freerad:freerad /etc/freeradius/3.0/mods-enabled/sql
sudo chown -R freerad:freerad /etc/freeradius/3.0/policy.d/mac_policy
