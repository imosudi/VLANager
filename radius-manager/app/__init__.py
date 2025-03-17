
# App factory: initializes Flask, SQLAlchemy, Flask-Login, and registers blueprints
from flask import Flask
from flask_sqlalchemy import SQLAlchemy
from flask_login import LoginManager
from flask_migrate import Migrate
from flask_moment import Moment
import os

# Instantiate the Flask app directly
app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)
app.config['SQLALCHEMY_DATABASE_URI'] = 'mysql+pymysql://radius:radpass@localhost/radius'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

# Initialize extensions with the app instance
db = SQLAlchemy(app)
migrate = Migrate(app, db)
login_manager = LoginManager(app)
login_manager.login_view = 'auth.login'


from app.models import db, User  # Ensure models are imported after db initialization

def create_default_admin():
    """Creates a default admin user if no users exist."""
    with app.app_context():  # Ensure execution inside an application context
        if User.query.count() == 0:
            admin = User(
                username='admin',
                email='imosudi@outlook.com',
                is_admin=True
            )
            admin.set_password('adminpassword')
            db.session.add(admin)
            db.session.commit()
            print("Default admin user created: admin / adminpassword")

# Register blueprints
from app.auth import bp as auth_bp
app.register_blueprint(auth_bp)

from app.main import bp as main_bp
app.register_blueprint(main_bp)

from app.api import bp as api_bp
app.register_blueprint(api_bp, url_prefix='/api')




# Run admin creation after the app is fully set up
create_default_admin()