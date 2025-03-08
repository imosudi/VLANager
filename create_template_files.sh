#!/bin/bash
# Script to create all Flask template files

# Base template directory (adjust if your project structure is different)
TEMPLATE_DIR="radius-manager/app/templates"

# Create necessary directories
mkdir -p "${TEMPLATE_DIR}/auth"
mkdir -p "${TEMPLATE_DIR}/main"

##############################
# Create auth templates
##############################

# auth/login.html
cat > "${TEMPLATE_DIR}/auth/login.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Login</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>
    <h1>Login</h1>
    <form method="post">
        {{ form.hidden_tag() }}
        <div>
            {{ form.username.label }}<br>
            {{ form.username(size=32) }}
        </div>
        <div>
            {{ form.password.label }}<br>
            {{ form.password(size=32) }}
        </div>
        <div>
            {{ form.remember_me() }} {{ form.remember_me.label }}
        </div>
        <div>
            {{ form.submit() }}
        </div>
    </form>
    <p>Don't have an account? <a href="{{ url_for('auth.register') }}">Register here</a></p>
    {% with messages = get_flashed_messages() %}
        {% if messages %}
            <ul>
            {% for message in messages %}
                <li>{{ message }}</li>
            {% endfor %}
            </ul>
        {% endif %}
    {% endwith %}
</body>
</html>
EOF

# auth/register.html
cat > "${TEMPLATE_DIR}/auth/register.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Register</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>
    <h1>Register</h1>
    <form method="post">
        {{ form.hidden_tag() }}
        <div>
            {{ form.username.label }}<br>
            {{ form.username(size=32) }}
        </div>
        <div>
            {{ form.email.label }}<br>
            {{ form.email(size=32) }}
        </div>
        <div>
            {{ form.password.label }}<br>
            {{ form.password(size=32) }}
        </div>
        <div>
            {{ form.password2.label }}<br>
            {{ form.password2(size=32) }}
        </div>
        <div>
            {{ form.submit() }}
        </div>
    </form>
    <p>Already have an account? <a href="{{ url_for('auth.login') }}">Login here</a></p>
    {% with messages = get_flashed_messages() %}
        {% if messages %}
            <ul>
            {% for message in messages %}
                <li>{{ message }}</li>
            {% endfor %}
            </ul>
        {% endif %}
    {% endwith %}
</body>
</html>
EOF

##############################
# Create main templates
##############################

# main/index.html
cat > "${TEMPLATE_DIR}/main/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Dashboard</title>
    <link rel="stylesheet" href="{{ url_for('static', filename='css/style.css') }}">
</head>
<body>
    <h1>Dashboard</h1>
    <p>Welcome, {{ current_user.username }}!</p>
    <nav>
        <a href="{{ url_for('main.switches') }}">Manage Switches</a> |
        <a href="{{ url_for('auth.logout') }}">Logout</a>
    </nav>
    {% block content %}{% endblock %}
</body>
</html>
EOF

# main/switches.html
cat > "${TEMPLATE_DIR}/main/switches.html" << 'EOF'
{% extends "main/index.html" %}
{% block content %}
<h2>Switches</h2>
<ul>
    {% for switch in switches %}
    <li>
        {{ switch.name }} ({{ switch.ip_address }})
        <a href="{{ url_for('main.edit_switch', id=switch.id) }}">Edit</a>
        <form action="{{ url_for('main.delete_switch', id=switch.id) }}" method="post" style="display:inline;">
            <button type="submit">Delete</button>
        </form>
        <a href="{{ url_for('main.switch_vlans', id=switch.id) }}">VLANs</a>
        <a href="{{ url_for('main.switch_macs', id=switch.id) }}">MAC Addresses</a>
    </li>
    {% endfor %}
</ul>
<a href="{{ url_for('main.add_switch') }}">Add New Switch</a>
{% endblock %}
EOF

# main/switch_form.html
cat > "${TEMPLATE_DIR}/main/switch_form.html" << 'EOF'
{% extends "main/index.html" %}
{% block content %}
<h2>{{ title }}</h2>
<form method="post">
    {{ form.hidden_tag() }}
    <div>
        {{ form.name.label }}<br>
        {{ form.name(size=32) }}
    </div>
    <div>
        {{ form.ip_address.label }}<br>
        {{ form.ip_address(size=32) }}
    </div>
    <div>
        {{ form.secret.label }}<br>
        {{ form.secret(size=32) }}
    </div>
    <div>
        {{ form.description.label }}<br>
        {{ form.description() }}
    </div>
    <div>
        {{ form.submit() }}
    </div>
</form>
<a href="{{ url_for('main.switches') }}">Back to Switches</a>
{% endblock %}
EOF

# main/vlans.html
cat > "${TEMPLATE_DIR}/main/vlans.html" << 'EOF'
{% extends "main/index.html" %}
{% block content %}
<h2>VLANs for {{ switch.name }}</h2>
<ul>
    {% for vlan in vlans %}
    <li>
        VLAN {{ vlan.vlan_id }} - {{ vlan.name }}
        <a href="{{ url_for('main.edit_vlan', id=vlan.id) }}">Edit</a>
        <form action="{{ url_for('main.delete_vlan', id=vlan.id) }}" method="post" style="display:inline;">
            <button type="submit">Delete</button>
        </form>
    </li>
    {% endfor %}
</ul>
<a href="{{ url_for('main.add_vlan', id=switch.id) }}">Add New VLAN</a>
<a href="{{ url_for('main.switches') }}">Back to Switches</a>
{% endblock %}
EOF

# main/vlan_form.html
cat > "${TEMPLATE_DIR}/main/vlan_form.html" << 'EOF'
{% extends "main/index.html" %}
{% block content %}
<h2>{{ title }}</h2>
<form method="post">
    {{ form.hidden_tag() }}
    <div>
        {{ form.vlan_id.label }}<br>
        {{ form.vlan_id(size=5) }}
    </div>
    <div>
        {{ form.name.label }}<br>
        {{ form.name(size=32) }}
    </div>
    <div>
        {{ form.description.label }}<br>
        {{ form.description() }}
    </div>
    <div>
        {{ form.submit() }}
    </div>
</form>
<a href="{{ url_for('main.switch_vlans', id=switch.id) }}">Back to VLANs</a>
{% endblock %}
EOF

# main/macs.html
cat > "${TEMPLATE_DIR}/main/macs.html" << 'EOF'
{% extends "main/index.html" %}
{% block content %}
<h2>MAC Addresses for {{ switch.name }}</h2>
<ul>
    {% for mapping in mac_mappings %}
    <li>
        {{ mapping.mac_address }} - VLAN: {{ mapping.vlan_id }}
        <a href="{{ url_for('main.edit_mac', id=mapping.id) }}">Edit</a>
        <form action="{{ url_for('main.delete_mac', id=mapping.id) }}" method="post" style="display:inline;">
            <button type="submit">Delete</button>
        </form>
    </li>
    {% endfor %}
</ul>
<a href="{{ url_for('main.add_mac', id=switch.id) }}">Add New MAC Address</a>
<a href="{{ url_for('main.switches') }}">Back to Switches</a>
{% endblock %}
EOF

# main/mac_form.html
cat > "${TEMPLATE_DIR}/main/mac_form.html" << 'EOF'
{% extends "main/index.html" %}
{% block content %}
<h2>{{ title }}</h2>
<form method="post">
    {{ form.hidden_tag() }}
    <div>
        {{ form.mac_address.label }}<br>
        {{ form.mac_address(size=20) }}
    </div>
    <div>
        {{ form.vlan_id.label }}<br>
        {{ form.vlan_id() }}
    </div>
    <div>
        {{ form.description.label }}<br>
        {{ form.description() }}
    </div>
    <div>
        {{ form.submit() }}
    </div>
</form>
<a href="{{ url_for('main.switch_macs', id=switch.id) }}">Back to MAC Addresses</a>
{% endblock %}
EOF

echo "Template files created successfully in '${TEMPLATE_DIR}'!"
