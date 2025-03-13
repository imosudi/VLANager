#!/bin/bash
# FreeRADIUS with MySQL, phpMyAdmin and Flask Web Application Setup
# For Ubuntu 24.04 - Supporting Multiple Switches and VLANs

# Exit script immediately if a command exits with a non-zero status
set -e

# Function to print colored messages
print_message() {
    GREEN='\033[0;32m'
    NC='\033[0m' # No Color
    echo -e "${GREEN}[INFO] $1${NC}"
}

# Function to print error messages and exit
print_error() {
    RED='\033[0;31m'
    NC='\033[0m' # No Color
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

# Prompt for MySQL root password
read -sp "Enter a secure password for MySQL root user: " MYSQL_ROOT_PASS
echo
read -sp "Enter a password for RADIUS database user: " RADIUS_PASS
echo
read -sp "Enter a password for phpMyAdmin setup: " PHPMYADMIN_PASS
echo

print_message "Updating package lists and installing dependencies..."
# Update package lists
sudo apt update && sudo apt upgrade -y || print_error "Failed to update packages"

# Install MySQL Server and required dependencies
sudo apt install -y mysql-server python3 python3-pip python3-venv nginx git || print_error "Failed to install core packages"

# Configure MySQL to start at boot
sudo systemctl enable mysql
sudo systemctl start mysql

# Set more relaxed password policy before securing MySQL
#print_message "Adjusting MySQL password policy settings..."
#sudo mysql --user=root <<EOF
#SET GLOBAL validate_password.policy = LOW;
#SET GLOBAL validate_password.length = 8;
#EOF

# Skip interactive prompts for MySQL secure installation
print_message "Securing MySQL installation..."
sudo mysql --user=root <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASS}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\_%';
FLUSH PRIVILEGES;
EOF

# Install FreeRADIUS and MySQL module
print_message "Installing FreeRADIUS and required modules..."
sudo apt install -y freeradius freeradius-mysql freeradius-utils || print_error "Failed to install FreeRADIUS"

# Rest of the script remains unchanged...

# Install phpMyAdmin with non-interactive setup
print_message "Installing phpMyAdmin..."
# Set debconf selections to avoid interactive prompt
echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | sudo debconf-set-selections
echo "phpmyadmin phpmyadmin/app-password-confirm password ${PHPMYADMIN_PASS}" | sudo debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/admin-pass password ${MYSQL_ROOT_PASS}" | sudo debconf-set-selections
echo "phpmyadmin phpmyadmin/mysql/app-pass password ${PHPMYADMIN_PASS}" | sudo debconf-set-selections
echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect apache2" | sudo debconf-set-selections

# Install phpMyAdmin
sudo apt install -y phpmyadmin || print_error "Failed to install phpMyAdmin"

# Ensure phpMyAdmin is configured with Nginx if Apache2 wasn't installed
if ! command -v apache2 &> /dev/null; then
    print_message "Configuring phpMyAdmin with Nginx..."
    # Create Nginx configuration for phpMyAdmin
    cat << EOF | sudo tee /etc/nginx/conf.d/phpmyadmin.conf > /dev/null
server {
    listen 80;
    server_name localhost;
    
    location /phpmyadmin {
        root /usr/share/;
        index index.php index.html index.htm;
        location ~ ^/phpmyadmin/(.+\.php)$ {
            try_files \$uri =404;
            root /usr/share/;
            fastcgi_pass unix:/run/php/php8.1-fpm.sock;
            fastcgi_index index.php;
            fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
            include fastcgi_params;
        }
        
        location ~* ^/phpmyadmin/(.+\.(jpg|jpeg|gif|css|png|js|ico|html|xml|txt))$ {
            root /usr/share/;
        }
    }
}
EOF
    # Install PHP-FPM if not already installed
    sudo apt install -y php-fpm php-mysql || print_error "Failed to install PHP-FPM"
    sudo systemctl restart nginx
fi

# Stop FreeRADIUS service for configuration
print_message "Stopping FreeRADIUS service for configuration..."
sudo systemctl stop freeradius

# Create MySQL database and user for FreeRADIUS with more secure password
print_message "Creating MySQL database and user for FreeRADIUS..."
sudo mysql -u root -p${MYSQL_ROOT_PASS} <<EOF
CREATE DATABASE IF NOT EXISTS radius;
CREATE USER IF NOT EXISTS 'radius'@'localhost' IDENTIFIED BY '${RADIUS_PASS}';
GRANT ALL PRIVILEGES ON radius.* TO 'radius'@'localhost';
FLUSH PRIVILEGES;
EOF

# Import FreeRADIUS schema into MySQL
print_message "Importing FreeRADIUS schema into MySQL..."
sudo mysql -u radius -p${RADIUS_PASS} radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql

# Add switches and NAS tables to track switch and VLAN mappings
print_message "Creating additional tables for switch and VLAN management..."
sudo mysql -u radius -p${RADIUS_PASS} radius <<EOF
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

-- Add SQL view for easier management
CREATE OR REPLACE VIEW vw_mac_vlan_details AS
SELECT 
    m.id, 
    m.mac_address, 
    v.vlan_id, 
    v.name as vlan_name, 
    s.name as switch_name, 
    s.ip_address as switch_ip,
    m.description
FROM 
    mac_vlan_mapping m
JOIN 
    vlans v ON m.vlan_id = v.id
JOIN 
    switches s ON m.switch_id = s.id;
EOF

# Enable SQL module in FreeRADIUS
print_message "Configuring FreeRADIUS SQL module..."
sudo ln -sf /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/

# Create a backup of the original SQL module configuration
sudo cp /etc/freeradius/3.0/mods-enabled/sql /etc/freeradius/3.0/mods-enabled/sql.bak

# Configure SQL module
cat << EOF | sudo tee /etc/freeradius/3.0/mods-enabled/sql > /dev/null
sql {
    dialect = "mysql"
    
    driver = "rlm_sql_\${dialect}"
    
    server = "localhost"
    port = 3306
    login = "radius"
    password = "${RADIUS_PASS}"
    
    radius_db = "radius"
    
    acct_table1 = "radacct"
    acct_table2 = "radacct"
    postauth_table = "radpostauth"
    authcheck_table = "radcheck"
    authreply_table = "radreply"
    groupcheck_table = "radgroupcheck"
    groupreply_table = "radgroupreply"
    usergroup_table = "radusergroup"
    read_groups = yes
    read_clients = yes
    client_table = "nas"
    
    group_attribute = "SQL-Group"
    
    \$INCLUDE \${modconfdir}/\${dialect}/main/queries.conf
    
    pool {
        start = 5
        min = 4
        max = 10
        spare = 3
        uses = 0
        lifetime = 0
        idle_timeout = 60
    }
    
    read_clients = yes
    client_table = "nas"
    
    accounting {
        reference = "%{tolower:type.%{Acct-Status-Type}.query}"
        logfile = \${logdir}/accounting.log
    }
    
    authorize_check_query = "SELECT id, username, attribute, value, op FROM \${authcheck_table} WHERE username = '%{SQL-User-Name}' ORDER BY id"
    authorize_reply_query = "SELECT id, username, attribute, value, op FROM \${authreply_table} WHERE username = '%{SQL-User-Name}' ORDER BY id"
    
    # Use MAC address to assign VLAN
    authorize_group_check_query = "SELECT id, username, attribute, value, op FROM \${groupcheck_table} WHERE groupname = '%{SQL-Group}' ORDER BY id"
    authorize_group_reply_query = "SELECT id, groupname, attribute, value, op FROM \${groupreply_table} WHERE groupname = '%{SQL-Group}' ORDER BY id"
}
EOF

# Create a custom query to fetch VLAN information based on MAC address
cat << EOF | sudo tee /etc/freeradius/3.0/policy.d/mac_vlan_query > /dev/null
sql mac_vlan_query {
    query = "SELECT v.vlan_id AS Reply-Items FROM mac_vlan_mapping m JOIN vlans v ON m.vlan_id = v.id WHERE m.mac_address = '%{tolower:%{User-Name}}' AND m.switch_id = (SELECT id FROM switches WHERE ip_address = '%{NAS-IP-Address}')"
}
EOF

# Configure the policy to handle VLAN assignment
cat << EOF | sudo tee /etc/freeradius/3.0/policy.d/mac_policy > /dev/null
policy mac_auth {
    if (&User-Name =~ /^([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})[-:]?([0-9a-f]{2})$/i) {
        update request {
            &User-Name := "%{tolower:%{1}:%{2}:%{3}:%{4}:%{5}:%{6}}"
            &User-Password := "%{User-Name}"
        }
        
        # Log the MAC authentication attempt
        update request {
            &Module-Failure-Message := "MAC Authentication: %{User-Name} from switch %{NAS-IP-Address}"
        }
        
        # Execute SQL query to find VLAN assignment
        mac_vlan_query
    }
}
EOF

# Update the authorize section to use our new policy
print_message "Updating FreeRADIUS configuration to use MAC-based VLAN assignment..."
sudo cp /etc/freeradius/3.0/sites-enabled/default /etc/freeradius/3.0/sites-enabled/default.bak
sudo sed -i '/authorize {/a \    mac_auth' /etc/freeradius/3.0/sites-enabled/default

# Enable SQL in different sections
sudo sed -i '/^#[[:space:]]*sql/s/^#[[:space:]]*//g' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/authenticate {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/accounting {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/session {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default
sudo sed -i '/post-auth {/,/}/s/^#[[:space:]]*sql/sql/' /etc/freeradius/3.0/sites-enabled/default

# Create a dynamic clients.conf configuration that reads from the database
print_message "Configuring FreeRADIUS clients..."
cat << EOF | sudo tee /etc/freeradius/3.0/clients.conf > /dev/null
client localhost {
    ipaddr = 127.0.0.1
    secret = testing123
    require_message_authenticator = no
    nas_type = other
}

# SQL clients will be loaded from the nas table in the database
\$INCLUDE \${modconfdir}/sql/main/naslist.conf
EOF

# Set ownership and permissions
print_message "Setting correct permissions..."
sudo chown -R freerad:freerad /etc/freeradius/3.0/mods-enabled/sql
sudo chown -R freerad:freerad /etc/freeradius/3.0/policy.d/mac_policy
sudo chown -R freerad:freerad /etc/freeradius/3.0/policy.d/mac_vlan_query

sudo mkdir -p /etc/freeradius/3.0/mods-config/sql/main/
sudo touch /etc/freeradius/3.0/mods-config/sql/main/naslist.conf

# Create the proper MySQL directory structure
print_message "Creating MySQL configuration directory structure..."
sudo mkdir -p /etc/freeradius/3.0/mods-config/mysql/main/

# Copy the queries.conf file to the correct location
print_message "Copying MySQL queries configuration..."
sudo cp /etc/freeradius/3.0/mods-config/sql/main/mysql/queries.conf /etc/freeradius/3.0/mods-config/mysql/main/

# Set proper permissions
sudo chown -R freerad:freerad /etc/freeradius/3.0/mods-config/mysql/
sudo chown freerad:freerad /etc/freeradius/3.0/mods-config/sql/main/naslist.conf
sudo chmod 640 /etc/freeradius/3.0/mods-config/sql/main/naslist.conf
sudo chmod -R 640 /etc/freeradius/3.0/mods-config/mysql/
sudo chmod 750 /etc/freeradius/3.0/mods-config/mysql/main/

# Fix permissions for naslist.conf


# Enable and start the services
print_message "Starting services..."
sudo systemctl daemon-reload
#sudo systemctl enable radius-manager
#sudo systemctl start radius-manager
sudo systemctl restart nginx
sudo systemctl restart freeradius

print_message "FreeRADIUS with MySQL, phpMyAdmin and Flask Web Application Setup Complete!"
print_message "Access the web management interface at http://your-server-ip/"
print_message "Access phpMyAdmin at http://your-server-ip/phpmyadmin/"
#print_message "Default Flask admin username: admin, password: adminpassword"
#print_message "IMPORTANT: Please change the default password after login!"
