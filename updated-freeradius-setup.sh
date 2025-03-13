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
print_message "Adjusting MySQL password policy settings..."
sudo mysql --user=root <<EOF
SET GLOBAL validate_password.policy = LOW;
SET GLOBAL validate_password.length = 8;
EOF

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

# Create a Flask web application for management
print_message "Creating Flask web application for RADIUS management..."
mkdir -p ~/radius-manager
cd ~/radius-manager

# Create a Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install required Python packages
pip install flask flask-sqlalchemy flask-login flask-wtf mysql-connector-python gunicorn

# Create Flask application files
cat > app.py <<EOF
from flask import Flask, render_template, request, redirect, url_for, flash
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager, UserMixin, login_user, logout_user, login_required, current_user
from werkzeug.security import generate_password_hash, check_password_hash
import os
from datetime import datetime

app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24).hex()
app.config['SQLALCHEMY_DATABASE_URI'] = f"mysql+mysqlconnector://radius:${RADIUS_PASS}@localhost/radius"
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)
login_manager = LoginManager(app)
login_manager.login_view = 'login'

# Models
class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(80), unique=True, nullable=False)
    password_hash = db.Column(db.String(256), nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    
    def set_password(self, password):
        self.password_hash = generate_password_hash(password)
        
    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

class Switch(db.Model):
    __tablename__ = 'switches'
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(64), nullable=False)
    ip_address = db.Column(db.String(15), unique=True, nullable=False)
    secret = db.Column(db.String(64), nullable=False)
    description = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    vlans = db.relationship('Vlan', backref='switch', lazy=True, cascade="all, delete-orphan")

class Vlan(db.Model):
    __tablename__ = 'vlans'
    id = db.Column(db.Integer, primary_key=True)
    switch_id = db.Column(db.Integer, db.ForeignKey('switches.id'), nullable=False)
    vlan_id = db.Column(db.Integer, nullable=False)
    name = db.Column(db.String(64), nullable=False)
    description = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    mac_mappings = db.relationship('MacVlanMapping', backref='vlan', lazy=True, cascade="all, delete-orphan")

class MacVlanMapping(db.Model):
    __tablename__ = 'mac_vlan_mapping'
    id = db.Column(db.Integer, primary_key=True)
    mac_address = db.Column(db.String(17), nullable=False)
    vlan_id = db.Column(db.Integer, db.ForeignKey('vlans.id'), nullable=False)
    switch_id = db.Column(db.Integer, db.ForeignKey('switches.id'), nullable=False)
    description = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    switch = db.relationship('Switch')

# Create tables for Flask user management
with app.app_context():
    db.create_all()
    # Create initial admin user if not exists
    if not User.query.filter_by(username='admin').first():
        admin = User(username='admin', email='admin@example.com')
        admin.set_password('adminpassword')
        db.session.add(admin)
        db.session.commit()

@login_manager.user_loader
def load_user(user_id):
    return User.query.get(int(user_id))

# Routes
@app.route('/')
@login_required
def index():
    switches = Switch.query.all()
    return render_template('index.html', switches=switches)

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form.get('username')
        password = request.form.get('password')
        
        user = User.query.filter_by(username=username).first()
        if user and user.check_password(password):
            login_user(user)
            return redirect(url_for('index'))
        
        flash('Invalid username or password')
    
    return render_template('login.html')

@app.route('/logout')
@login_required
def logout():
    logout_user()
    return redirect(url_for('login'))

# More routes for managing switches, VLANs, and MAC mappings to be added here

if __name__ == '__main__':
    app.run(debug=True)
EOF

# Create templates directory
mkdir -p templates

# Create a simple login template
cat > templates/layout.html <<EOF
<!DOCTYPE html>
<html>
<head>
    <title>RADIUS Manager</title>
    <link rel="stylesheet" href="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/css/bootstrap.min.css">
</head>
<body>
    <nav class="navbar navbar-expand-lg navbar-dark bg-dark">
        <a class="navbar-brand" href="{{ url_for('index') }}">RADIUS Manager</a>
        <div class="collapse navbar-collapse">
            <ul class="navbar-nav ml-auto">
                {% if current_user.is_authenticated %}
                    <li class="nav-item">
                        <a class="nav-link" href="{{ url_for('logout') }}">Logout</a>
                    </li>
                {% endif %}
            </ul>
        </div>
    </nav>
    
    <div class="container mt-4">
        {% with messages = get_flashed_messages() %}
            {% if messages %}
                {% for message in messages %}
                    <div class="alert alert-info">{{ message }}</div>
                {% endfor %}
            {% endif %}
        {% endwith %}
        
        {% block content %}{% endblock %}
    </div>
    
    <script src="https://code.jquery.com/jquery-3.5.1.slim.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/@popperjs/core@2.5.3/dist/umd/popper.min.js"></script>
    <script src="https://stackpath.bootstrapcdn.com/bootstrap/4.5.2/js/bootstrap.min.js"></script>
</body>
</html>
EOF

cat > templates/login.html <<EOF
{% extends "layout.html" %}

{% block content %}
<div class="row justify-content-center">
    <div class="col-md-6">
        <div class="card">
            <div class="card-header">Login</div>
            <div class="card-body">
                <form method="POST">
                    <div class="form-group">
                        <label>Username</label>
                        <input type="text" name="username" class="form-control" required>
                    </div>
                    <div class="form-group">
                        <label>Password</label>
                        <input type="password" name="password" class="form-control" required>
                    </div>
                    <button type="submit" class="btn btn-primary">Login</button>
                </form>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

cat > templates/index.html <<EOF
{% extends "layout.html" %}

{% block content %}
<h1>RADIUS Manager Dashboard</h1>
<div class="row">
    <div class="col-md-12">
        <div class="card">
            <div class="card-header">
                Switches
                <a href="#" class="btn btn-sm btn-primary float-right">Add Switch</a>
            </div>
            <div class="card-body">
                <table class="table table-striped">
                    <thead>
                        <tr>
                            <th>Name</th>
                            <th>IP Address</th>
                            <th>Description</th>
                            <th>Actions</th>
                        </tr>
                    </thead>
                    <tbody>
                        {% for switch in switches %}
                        <tr>
                            <td>{{ switch.name }}</td>
                            <td>{{ switch.ip_address }}</td>
                            <td>{{ switch.description }}</td>
                            <td>
                                <a href="#" class="btn btn-sm btn-info">View VLANs</a>
                                <a href="#" class="btn btn-sm btn-warning">Edit</a>
                                <a href="#" class="btn btn-sm btn-danger">Delete</a>
                            </td>
                        </tr>
                        {% else %}
                        <tr>
                            <td colspan="4" class="text-center">No switches configured yet.</td>
                        </tr>
                        {% endfor %}
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</div>
{% endblock %}
EOF

# Create a systemd service for the Flask application
print_message "Creating systemd service for the Flask application..."
cat << EOF | sudo tee /etc/systemd/system/radius-manager.service > /dev/null
[Unit]
Description=Radius Manager Flask Application
After=network.target

[Service]
User=$(whoami)
WorkingDirectory=$(pwd)
ExecStart=$(pwd)/venv/bin/gunicorn -b 127.0.0.1:5000 app:app
Restart=always

[Install]
WantedBy=multi-user.target
EOF

# Configure Nginx to serve the Flask application
print_message "Configuring Nginx for the Flask application..."
cat << EOF | sudo tee /etc/nginx/sites-available/radius-manager > /dev/null
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://127.0.0.1:5000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/radius-manager /etc/nginx/sites-enabled/

# Enable and start the services
print_message "Starting services..."
sudo systemctl daemon-reload
sudo systemctl enable radius-manager
sudo systemctl start radius-manager
sudo systemctl restart nginx
sudo systemctl restart freeradius

print_message "FreeRADIUS with MySQL, phpMyAdmin and Flask Web Application Setup Complete!"
print_message "Access the web management interface at http://your-server-ip/"
print_message "Access phpMyAdmin at http://your-server-ip/phpmyadmin/"
print_message "Default Flask admin username: admin, password: adminpassword"
print_message "IMPORTANT: Please change the default password after login!"
