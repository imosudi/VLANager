# API routes (to be implemented as needed)
from flask import jsonify, request
from app import db
from app.api import bp
from app.models import Switch

@bp.route('/switches', methods=['GET'])
def get_switches():
    switches = Switch.query.all()
    data = []
    for s in switches:
        data.append({
            'id': s.id,
            'name': s.name,
            'ip_address': s.ip_address,
            'description': s.description
        })
    return jsonify(data)
