#!/bin/bash
# Script to create the Flask app structure

# Base project directory
PROJECT_DIR="radius-manager"

# Create base directory and subdirectories
mkdir -p "${PROJECT_DIR}/app"

# Create application directories
mkdir -p "${PROJECT_DIR}/app/auth"
mkdir -p "${PROJECT_DIR}/app/main"
mkdir -p "${PROJECT_DIR}/app/api"
mkdir -p "${PROJECT_DIR}/app/static/css"
mkdir -p "${PROJECT_DIR}/app/static/js"
mkdir -p "${PROJECT_DIR}/app/templates/auth"
mkdir -p "${PROJECT_DIR}/app/templates/main"

# Create empty files with placeholder comments

# App factory and models
cat > "${PROJECT_DIR}/app/__init__.py" << 'EOF'
# App factory: initializes Flask, SQLAlchemy, Flask-Login, and registers blueprints
EOF

cat > "${PROJECT_DIR}/app/models.py" << 'EOF'
# SQLAlchemy models: User, Switch, Vlan, MacVlanMapping, plus FreeRADIUS tables
EOF

# Auth blueprint files
cat > "${PROJECT_DIR}/app/auth/__init__.py" << 'EOF'
from flask import Blueprint
bp = Blueprint('auth', __name__)
from app.auth import routes
EOF

cat > "${PROJECT_DIR}/app/auth/routes.py" << 'EOF'
# Routes for login, logout, and registration
EOF

cat > "${PROJECT_DIR}/app/auth/forms.py" << 'EOF'
# WTForms for login and registration
EOF

# Main blueprint files
cat > "${PROJECT_DIR}/app/main/__init__.py" << 'EOF'
from flask import Blueprint
bp = Blueprint('main', __name__)
from app.main import routes
EOF

cat > "${PROJECT_DIR}/app/main/routes.py" << 'EOF'
# Routes for managing switches, VLANs, and MAC address mappings
EOF

# API blueprint files (optional)
cat > "${PROJECT_DIR}/app/api/__init__.py" << 'EOF'
from flask import Blueprint
bp = Blueprint('api', __name__)
from app.api import routes
EOF

cat > "${PROJECT_DIR}/app/api/routes.py" << 'EOF'
# API routes (to be implemented as needed)
EOF

# Templates for auth blueprint
cat > "${PROJECT_DIR}/app/templates/auth/login.html" << 'EOF'
<!-- HTML template for login page -->
EOF

cat > "${PROJECT_DIR}/app/templates/auth/register.html" << 'EOF'
<!-- HTML template for registration page -->
EOF

# Templates for main blueprint
cat > "${PROJECT_DIR}/app/templates/main/index.html" << 'EOF'
<!-- HTML template for the home/dashboard view -->
EOF

cat > "${PROJECT_DIR}/app/templates/main/switches.html" << 'EOF'
<!-- HTML template for listing switches -->
EOF

cat > "${PROJECT_DIR}/app/templates/main/switch_form.html" << 'EOF'
<!-- HTML template for adding/editing a switch -->
EOF

cat > "${PROJECT_DIR}/app/templates/main/vlans.html" << 'EOF'
<!-- HTML template for listing VLANs for a switch -->
EOF

cat > "${PROJECT_DIR}/app/templates/main/vlan_form.html" << 'EOF'
<!-- HTML template for adding/editing a VLAN -->
EOF

cat > "${PROJECT_DIR}/app/templates/main/macs.html" << 'EOF'
<!-- HTML template for listing MAC address mappings for a switch -->
EOF

cat > "${PROJECT_DIR}/app/templates/main/mac_form.html" << 'EOF'
<!-- HTML template for adding/editing a MAC address -->
EOF

echo "Flask app structure created successfully in '${PROJECT_DIR}'!"

# Create a Flask application directory
#mkdir -p ~/radius-manager
cd ~/radius-manager

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install required Python packages
pip install flask flask-sqlalchemy flask-login flask-wtf pymysql cryptography