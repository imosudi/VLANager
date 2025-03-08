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
sudo mysql -u radius -pradpass radius < /etc/freeradius/3.0/mods-config/sql/main/mysql/schema.sql

# Add switches and NAS tables to track switch and VLAN mappings
sudo mysql -u radius -pradpass radius <<EOF
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

# Create a Flask application directory
mkdir -p ~/radius-manager
cd ~/radius-manager

# Create Python virtual environment
python3 -m venv venv
source venv/bin/activate

# Install required Python packages
pip install flask flask-sqlalchemy flask-login flask-wtf pymysql cryptography

# Create the Flask application
mkdir -p app/{static,templates}
mkdir -p app/static/{css,js}

# Create application structure
cat > app/__init__.py << 'EOF'
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
import os

# Initialize Flask extensions
db = SQLAlchemy()
login_manager = LoginManager()

def create_app():
    app = Flask(__name__)
    app.config['SECRET_KEY'] = os.urandom(24)
    app.config['SQLALCHEMY_DATABASE_URI'] = 'mysql+pymysql://radius:radpass@localhost/radius'
    app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

    # Initialize extensions
    db.init_app(app)
    login_manager.init_app(app)
    login_manager.login_view = 'auth.login'

    # Register blueprints
    from app.auth import bp as auth_bp
    app.register_blueprint(auth_bp)

    from app.main import bp as main_bp
    app.register_blueprint(main_bp)

    from app.api import bp as api_bp
    app.register_blueprint(api_bp, url_prefix='/api')

    return app
EOF

# Create models.py
cat > app/models.py << 'EOF'
from app import db, login_manager
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash
from datetime import datetime

class User(UserMixin, db.Model):
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), unique=True, nullable=False)
    email = db.Column(db.String(120), unique=True, nullable=False)
    password_hash = db.Column(db.String(128))
    is_admin = db.Column(db.Boolean, default=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    def set_password(self, password):
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        return check_password_hash(self.password_hash, password)

@login_manager.user_loader
def load_user(id):
    return User.query.get(int(id))

class Switch(db.Model):
    __tablename__ = 'switches'
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(64), nullable=False)
    ip_address = db.Column(db.String(15), unique=True, nullable=False)
    secret = db.Column(db.String(64), nullable=False)
    description = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    vlans = db.relationship('Vlan', backref='switch', lazy='dynamic', cascade='all, delete-orphan')
    mac_mappings = db.relationship('MacVlanMapping', backref='switch', lazy='dynamic', cascade='all, delete-orphan')

class Vlan(db.Model):
    __tablename__ = 'vlans'
    id = db.Column(db.Integer, primary_key=True)
    switch_id = db.Column(db.Integer, db.ForeignKey('switches.id'), nullable=False)
    vlan_id = db.Column(db.Integer, nullable=False)
    name = db.Column(db.String(64), nullable=False)
    description = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    mac_mappings = db.relationship('MacVlanMapping', backref='vlan', lazy='dynamic', cascade='all, delete-orphan')
    
    __table_args__ = (db.UniqueConstraint('switch_id', 'vlan_id'),)

class MacVlanMapping(db.Model):
    __tablename__ = 'mac_vlan_mapping'
    id = db.Column(db.Integer, primary_key=True)
    mac_address = db.Column(db.String(17), nullable=False)
    vlan_id = db.Column(db.Integer, db.ForeignKey('vlans.id'), nullable=False)
    switch_id = db.Column(db.Integer, db.ForeignKey('switches.id'), nullable=False)
    description = db.Column(db.Text)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    updated_at = db.Column(db.DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    
    __table_args__ = (db.UniqueConstraint('mac_address', 'switch_id'),)

# FreeRADIUS model classes
class RadCheck(db.Model):
    __tablename__ = 'radcheck'
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), nullable=False)
    attribute = db.Column(db.String(64), nullable=False)
    op = db.Column(db.String(2), nullable=False)
    value = db.Column(db.String(253), nullable=False)

class RadReply(db.Model):
    __tablename__ = 'radreply'
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), nullable=False)
    attribute = db.Column(db.String(64), nullable=False)
    op = db.Column(db.String(2), nullable=False)
    value = db.Column(db.String(253), nullable=False)

class RadUserGroup(db.Model):
    __tablename__ = 'radusergroup'
    id = db.Column(db.Integer, primary_key=True)
    username = db.Column(db.String(64), nullable=False)
    groupname = db.Column(db.String(64), nullable=False)
    priority = db.Column(db.Integer, nullable=False)

class NasClient(db.Model):
    __tablename__ = 'nas'
    id = db.Column(db.Integer, primary_key=True)
    nasname = db.Column(db.String(128), nullable=False)
    shortname = db.Column(db.String(32), nullable=True)
    type = db.Column(db.String(30), default='other')
    ports = db.Column(db.Integer)
    secret = db.Column(db.String(60), nullable=False)
    server = db.Column(db.String(64))
    community = db.Column(db.String(50))
    description = db.Column(db.String(200))
EOF

# Create auth blueprint
mkdir -p app/auth
cat > app/auth/__init__.py << 'EOF'
from flask import Blueprint

bp = Blueprint('auth', __name__)

from app.auth import routes
EOF

cat > app/auth/routes.py << 'EOF'
from flask import render_template, redirect, url_for, flash, request
from flask_login import login_user, logout_user, current_user, login_required
from app import db
from app.auth import bp
from app.models import User
from app.auth.forms import LoginForm, RegistrationForm

@bp.route('/login', methods=['GET', 'POST'])
def login():
    if current_user.is_authenticated:
        return redirect(url_for('main.index'))
    form = LoginForm()
    if form.validate_on_submit():
        user = User.query.filter_by(username=form.username.data).first()
        if user is None or not user.check_password(form.password.data):
            flash('Invalid username or password')
            return redirect(url_for('auth.login'))
        login_user(user, remember=form.remember_me.data)
        next_page = request.args.get('next')
        if not next_page or not next_page.startswith('/'):
            next_page = url_for('main.index')
        return redirect(next_page)
    return render_template('auth/login.html', title='Sign In', form=form)

@bp.route('/logout')
def logout():
    logout_user()
    return redirect(url_for('main.index'))

@bp.route('/register', methods=['GET', 'POST'])
def register():
    if current_user.is_authenticated:
        return redirect(url_for('main.index'))
    form = RegistrationForm()
    if form.validate_on_submit():
        user = User(username=form.username.data, email=form.email.data)
        user.set_password(form.password.data)
        # Make the first user an admin
        if User.query.count() == 0:
            user.is_admin = True
        db.session.add(user)
        db.session.commit()
        flash('Congratulations, you are now a registered user!')
        return redirect(url_for('auth.login'))
    return render_template('auth/register.html', title='Register', form=form)
EOF

cat > app/auth/forms.py << 'EOF'
from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, BooleanField, SubmitField
from wtforms.validators import DataRequired, Email, EqualTo, ValidationError
from app.models import User

class LoginForm(FlaskForm):
    username = StringField('Username', validators=[DataRequired()])
    password = PasswordField('Password', validators=[DataRequired()])
    remember_me = BooleanField('Remember Me')
    submit = SubmitField('Sign In')

class RegistrationForm(FlaskForm):
    username = StringField('Username', validators=[DataRequired()])
    email = StringField('Email', validators=[DataRequired(), Email()])
    password = PasswordField('Password', validators=[DataRequired()])
    password2 = PasswordField(
        'Repeat Password', validators=[DataRequired(), EqualTo('password')])
    submit = SubmitField('Register')

    def validate_username(self, username):
        user = User.query.filter_by(username=username.data).first()
        if user is not None:
            raise ValidationError('Please use a different username.')

    def validate_email(self, email):
        user = User.query.filter_by(email=email.data).first()
        if user is not None:
            raise ValidationError('Please use a different email address.')
EOF

# Create main blueprint
mkdir -p app/main
cat > app/main/__init__.py << 'EOF'
from flask import Blueprint

bp = Blueprint('main', __name__)

from app.main import routes
EOF

cat > app/main/routes.py << 'EOF'
from flask import render_template, redirect, url_for, flash, request, jsonify
from flask_login import login_required, current_user
from app import db
from app.main import bp
from app.models import Switch, Vlan, MacVlanMapping, RadCheck, RadReply, NasClient
from app.main.forms import SwitchForm, VlanForm, MacAddressForm
import re

@bp.route('/')
@bp.route('/index')
@login_required
def index():
    switches = Switch.query.all()
    return render_template('main/index.html', title='Home', switches=switches)

@bp.route('/switches')
@login_required
def switches():
    switches = Switch.query.all()
    return render_template('main/switches.html', title='Switches', switches=switches)

@bp.route('/switch/add', methods=['GET', 'POST'])
@login_required
def add_switch():
    form = SwitchForm()
    if form.validate_on_submit():
        switch = Switch(
            name=form.name.data,
            ip_address=form.ip_address.data,
            secret=form.secret.data,
            description=form.description.data
        )
        
        # Also add to the NAS table for FreeRADIUS
        nas = NasClient(
            nasname=form.ip_address.data,
            shortname=form.name.data,
            type='cisco',
            secret=form.secret.data,
            description=form.description.data
        )
        
        db.session.add(switch)
        db.session.add(nas)
        db.session.commit()
        
        flash(f'Switch {form.name.data} has been added.')
        return redirect(url_for('main.switches'))
    
    return render_template('main/switch_form.html', title='Add Switch', form=form)

@bp.route('/switch/<int:id>/edit', methods=['GET', 'POST'])
@login_required
def edit_switch(id):
    switch = Switch.query.get_or_404(id)
    form = SwitchForm(obj=switch)
    
    if form.validate_on_submit():
        # Update switch
        switch.name = form.name.data
        switch.ip_address = form.ip_address.data
        switch.secret = form.secret.data
        switch.description = form.description.data
        
        # Update NAS entry
        nas = NasClient.query.filter_by(nasname=switch.ip_address).first()
        if nas:
            nas.nasname = form.ip_address.data
            nas.shortname = form.name.data
            nas.secret = form.secret.data
            nas.description = form.description.data
        
        db.session.commit()
        flash(f'Switch {switch.name} has been updated.')
        return redirect(url_for('main.switches'))
    
    return render_template('main/switch_form.html', title='Edit Switch', form=form)

@bp.route('/switch/<int:id>/delete', methods=['POST'])
@login_required
def delete_switch(id):
    switch = Switch.query.get_or_404(id)
    
    # Delete associated NAS entry
    nas = NasClient.query.filter_by(nasname=switch.ip_address).first()
    if nas:
        db.session.delete(nas)
    
    db.session.delete(switch)
    db.session.commit()
    
    flash(f'Switch {switch.name} has been deleted.')
    return redirect(url_for('main.switches'))

@bp.route('/switch/<int:id>/vlans')
@login_required
def switch_vlans(id):
    switch = Switch.query.get_or_404(id)
    vlans = Vlan.query.filter_by(switch_id=id).all()
    return render_template('main/vlans.html', title=f'VLANs for {switch.name}', switch=switch, vlans=vlans)

@bp.route('/switch/<int:id>/vlan/add', methods=['GET', 'POST'])
@login_required
def add_vlan(id):
    switch = Switch.query.get_or_404(id)
    form = VlanForm()
    
    if form.validate_on_submit():
        vlan = Vlan(
            switch_id=switch.id,
            vlan_id=form.vlan_id.data,
            name=form.name.data,
            description=form.description.data
        )
        
        db.session.add(vlan)
        db.session.commit()
        
        flash(f'VLAN {form.vlan_id.data} has been added to {switch.name}.')
        return redirect(url_for('main.switch_vlans', id=switch.id))
    
    return render_template('main/vlan_form.html', title=f'Add VLAN to {switch.name}', form=form, switch=switch)

@bp.route('/vlan/<int:id>/edit', methods=['GET', 'POST'])
@login_required
def edit_vlan(id):
    vlan = Vlan.query.get_or_404(id)
    form = VlanForm(obj=vlan)
    
    if form.validate_on_submit():
        vlan.vlan_id = form.vlan_id.data
        vlan.name = form.name.data
        vlan.description = form.description.data
        
        db.session.commit()
        flash(f'VLAN {vlan.vlan_id} has been updated.')
        return redirect(url_for('main.switch_vlans', id=vlan.switch_id))
    
    return render_template('main/vlan_form.html', title=f'Edit VLAN', form=form, switch=vlan.switch)

@bp.route('/vlan/<int:id>/delete', methods=['POST'])
@login_required
def delete_vlan(id):
    vlan = Vlan.query.get_or_404(id)
    switch_id = vlan.switch_id
    
    db.session.delete(vlan)
    db.session.commit()
    
    flash(f'VLAN {vlan.vlan_id} has been deleted.')
    return redirect(url_for('main.switch_vlans', id=switch_id))

@bp.route('/switch/<int:id>/macs')
@login_required
def switch_macs(id):
    switch = Switch.query.get_or_404(id)
    mac_mappings = MacVlanMapping.query.filter_by(switch_id=id).all()
    return render_template('main/macs.html', title=f'MAC Addresses for {switch.name}', switch=switch, mac_mappings=mac_mappings)

@bp.route('/switch/<int:id>/mac/add', methods=['GET', 'POST'])
@login_required
def add_mac(id):
    switch = Switch.query.get_or_404(id)
    form = MacAddressForm()
    
    # Populate VLAN choices
    form.vlan_id.choices = [(v.id, f'{v.vlan_id} - {v.name}') for v in Vlan.query.filter_by(switch_id=id).order_by(Vlan.vlan_id).all()]
    
    if form.validate_on_submit():
        # Normalize MAC address format (lowercase, with colons)
        mac = normalize_mac(form.mac_address.data)
        
        # Format for FreeRADIUS (lowercase, no separators)
        mac_radius = mac.replace(':', '').lower()
        
        # Check if MAC already exists
        existing = MacVlanMapping.query.filter_by(mac_address=mac, switch_id=switch.id).first()
        if existing:
            flash(f'MAC address {mac} already exists for this switch.')
            return redirect(url_for('main.switch_macs', id=switch.id))
        
        # Get VLAN object
        vlan = Vlan.query.get(form.vlan_id.data)
        
        # Add to MAC-VLAN mapping
        mapping = MacVlanMapping(
            mac_address=mac,
            vlan_id=vlan.id,
            switch_id=switch.id,
            description=form.description.data
        )
        
        # Add to FreeRADIUS tables
        radcheck = RadCheck(
            username=mac_radius,
            attribute='Auth-Type',
            op=':=',
            value='Accept'
        )
        
        # Add VLAN assignment
        vlan_type = RadReply(
            username=mac_radius,
            attribute='Tunnel-Type',
            op=':=',
            value='13'  # VLAN
        )
        
        vlan_medium = RadReply(
            username=mac_radius,
            attribute='Tunnel-Medium-Type',
            op=':=',
            value='6'  # IEEE-802
        )
        
        vlan_id = RadReply(
            username=mac_radius,
            attribute='Tunnel-Private-Group-ID',
            op=':=',
            value=str(vlan.vlan_id)
        )
        
        db.session.add_all([mapping, radcheck, vlan_type, vlan_medium, vlan_id])
        db.session.commit()
        
        flash(f'MAC address {mac} has been added to VLAN {vlan.vlan_id}.')
        return redirect(url_for('main.switch_macs', id=switch.id))
    
    return render_template('main/mac_form.html', title=f'Add MAC Address to {switch.name}', form=form, switch=switch)

@bp.route('/mac/<int:id>/edit', methods=['GET', 'POST'])
@login_required
def edit_mac(id):
    mapping = MacVlanMapping.query.get_or_404(id)
    form = MacAddressForm(obj=mapping)
    
    # Populate VLAN choices
    form.vlan_id.choices = [(v.id, f'{v.vlan_id} - {v.name}') for v in Vlan.query.filter_by(switch_id=mapping.switch_id).order_by(Vlan.vlan_id).all()]
    
    if form.validate_on_submit():
        # Normalize MAC address format
        mac = normalize_mac(form.mac_address.data)
        
        # Format for FreeRADIUS (lowercase, no separators)
        mac_radius = mac.replace(':', '').lower()
        old_mac_radius = mapping.mac_address.replace(':', '').lower()
        
        # Get new VLAN
        vlan = Vlan.query.get(form.vlan_id.data)
        
        # Update mapping
        mapping.mac_address = mac
        mapping.vlan_id = vlan.id
        mapping.description = form.description.data
        
        # Update or create FreeRADIUS entries
        if mac_radius != old_mac_radius:
            # MAC address changed, delete old entries
            RadCheck.query.filter_by(username=old_mac_radius).delete()
            RadReply.query.filter_by(username=old_mac_radius).delete()
            
            # Create new entries
            radcheck = RadCheck(
                username=mac_radius,
                attribute='Auth-Type',
                op=':=',
                value='Accept'
            )
            db.session.add(radcheck)
        
        # Update VLAN assignment
        vlan_id_reply = RadReply.query.filter_by(
            username=mac_radius, 
            attribute='Tunnel-Private-Group-ID'
        ).first()
        
        if vlan_id_reply:
            vlan_id_reply.value = str(vlan.vlan_id)
        else:
            # Create VLAN assignment entries
            vlan_type = RadReply(
                username=mac_radius,
                attribute='Tunnel-Type',
                op=':=',
                value='13'  # VLAN
            )
            
            vlan_medium = RadReply(
                username=mac_radius,
                attribute='Tunnel-Medium-Type',
                op=':=',
                value='6'  # IEEE-802
            )
            
            vlan_id = RadReply(
                username=mac_radius,
                attribute='Tunnel-Private-Group-ID',
                op=':=',
                value=str(vlan.vlan_id)
            )
            
            db.session.add_all([vlan_type, vlan_medium, vlan_id])
        
        db.session.commit()
        
        flash(f'MAC address {mac} has been updated to VLAN {vlan.vlan_id}.')
        return redirect(url_for('main.switch_macs', id=mapping.switch_id))
    
    return render_template('main/mac_form.html', title='Edit MAC Address', form=form, switch=mapping.switch)

@bp.route('/mac/<int:id>/delete', methods=['POST'])
@login_required
def delete_mac(id):
    mapping = MacVlanMapping.query.get_or_404(id)
    switch_id = mapping.switch_id
    
    # Format for FreeRADIUS (lowercase, no separators)
    mac_radius = mapping.mac_address.replace(':', '').lower()
    
    # Delete from FreeRADIUS tables
    RadCheck.query.filter_by(username=mac_radius).delete()
    RadReply.query.filter_by(username=mac_radius).delete()
    
    db.session.delete(mapping)
    db.session.commit()
    
    flash(f'MAC address {mapping.mac_address} has been deleted.')
    return redirect(url_for('main.switch_macs', id=switch_id))

def normalize_mac(mac):
    """
    Normalizes a MAC address by converting it to lowercase and using colons as separators.
    Accepts various formats (e.g., AA:BB:CC:DD:EE:FF, AA-BB-CC-DD-EE-FF, AABBCCDDEEFF) and
    returns a standardized format (aa:bb:cc:dd:ee:ff).
    """
    mac = mac.lower()
    mac = re.sub(r'[^0-9a-f]', '', mac)  # Remove non-hex characters
    if len(mac) != 12:
        raise ValueError("Invalid MAC address format")
    return ':'.join(mac[i:i+2] for i in range(0, 12, 2))

