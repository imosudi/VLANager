# Routes for managing switches, VLANs, and MAC address mappings
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
        mac = normalize_mac(form.mac_address.data)
        mac_radius = mac.replace(':', '').lower()
        existing = MacVlanMapping.query.filter_by(mac_address=mac, switch_id=switch.id).first()
        if existing:
            flash(f'MAC address {mac} already exists for this switch.')
            return redirect(url_for('main.switch_macs', id=switch.id))
        vlan = Vlan.query.get(form.vlan_id.data)
        mapping = MacVlanMapping(
            mac_address=mac,
            vlan_id=vlan.id,
            switch_id=switch.id,
            description=form.description.data
        )
        radcheck = RadCheck(
            username=mac_radius,
            attribute='Auth-Type',
            op=':=',
            value='Accept'
        )
        vlan_type = RadReply(
            username=mac_radius,
            attribute='Tunnel-Type',
            op=':=',
            value='13'
        )
        vlan_medium = RadReply(
            username=mac_radius,
            attribute='Tunnel-Medium-Type',
            op=':=',
            value='6'
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
        mac = normalize_mac(form.mac_address.data)
        mac_radius = mac.replace(':', '').lower()
        old_mac_radius = mapping.mac_address.replace(':', '').lower()
        vlan = Vlan.query.get(form.vlan_id.data)
        mapping.mac_address = mac
        mapping.vlan_id = vlan.id
        mapping.description = form.description.data
        if mac_radius != old_mac_radius:
            RadCheck.query.filter_by(username=old_mac_radius).delete()
            RadReply.query.filter_by(username=old_mac_radius).delete()
            radcheck = RadCheck(
                username=mac_radius,
                attribute='Auth-Type',
                op=':=',
                value='Accept'
            )
            db.session.add(radcheck)
        vlan_id_reply = RadReply.query.filter_by(
            username=mac_radius, 
            attribute='Tunnel-Private-Group-ID'
        ).first()
        if vlan_id_reply:
            vlan_id_reply.value = str(vlan.vlan_id)
        else:
            vlan_type = RadReply(
                username=mac_radius,
                attribute='Tunnel-Type',
                op=':=',
                value='13'
            )
            vlan_medium = RadReply(
                username=mac_radius,
                attribute='Tunnel-Medium-Type',
                op=':=',
                value='6'
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
    mac_radius = mapping.mac_address.replace(':', '').lower()
    RadCheck.query.filter_by(username=mac_radius).delete()
    RadReply.query.filter_by(username=mac_radius).delete()
    db.session.delete(mapping)
    db.session.commit()
    flash(f'MAC address {mapping.mac_address} has been deleted.')
    return redirect(url_for('main.switch_macs', id=switch_id))

def normalize_mac(mac):
    mac = mac.lower()
    mac = re.sub(r'[^0-9a-f]', '', mac)
    if len(mac) != 12:
        raise ValueError("Invalid MAC address format")
    return ':'.join(mac[i:i+2] for i in range(0, 12, 2))
