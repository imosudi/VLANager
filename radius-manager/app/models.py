# SQLAlchemy models: User, Switch, Vlan, MacVlanMapping, plus FreeRADIUS tables
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
