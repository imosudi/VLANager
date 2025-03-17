from flask_wtf import FlaskForm
from wtforms import StringField, IntegerField, TextAreaField, SubmitField, SelectField, PasswordField, BooleanField
from wtforms.validators import DataRequired, IPAddress, NumberRange, DataRequired, Email, EqualTo


class RegistrationForm(FlaskForm):
    username = StringField('Username', validators=[DataRequired()])
    email = StringField('Email', validators=[DataRequired(), Email()])
    password = PasswordField('Password', validators=[DataRequired()])
    password2 = PasswordField('Repeat Password', validators=[DataRequired(), EqualTo('password')])
    is_admin = BooleanField('Make Admin')
    submit = SubmitField('Register')

class SwitchForm(FlaskForm):
    name = StringField('Switch Name', validators=[DataRequired()])
    ip_address = StringField('IP Address', validators=[DataRequired(), IPAddress()])
    secret = StringField('Secret', validators=[DataRequired()])
    description = TextAreaField('Description')
    submit = SubmitField('Submit')

class VlanForm(FlaskForm):
    vlan_id = IntegerField('VLAN ID', validators=[DataRequired(), NumberRange(min=1, max=4094)])
    name = StringField('VLAN Name', validators=[DataRequired()])
    description = TextAreaField('Description')
    submit = SubmitField('Submit')

class MacAddressForm(FlaskForm):
    mac_address = StringField('MAC Address', validators=[DataRequired()])
    vlan_id = SelectField('VLAN', coerce=int, validators=[DataRequired()])
    description = TextAreaField('Description')
    submit = SubmitField('Submit')
