# App factory: initializes Flask, SQLAlchemy, Flask-Login, and registers blueprints
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
import os

# Instantiate the Flask app directly
app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)
app.config['SQLALCHEMY_DATABASE_URI'] = 'mysql+pymysql://radius:radpass@localhost/radius'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# Initialize extensions with the app instance
db = SQLAlchemy(app)
login_manager = LoginManager(app)
login_manager.login_view = 'auth.login'

# Register blueprints
from app.auth import bp as auth_bp
app.register_blueprint(auth_bp)

from app.main import bp as main_bp
app.register_blueprint(main_bp)

from app.api import bp as api_bp
app.register_blueprint(api_bp, url_prefix='/api')
