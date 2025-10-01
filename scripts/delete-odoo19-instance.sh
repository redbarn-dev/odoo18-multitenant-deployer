#!/bin/bash

DBNAME="$1"
SERVICE_NAME="odoo19-$DBNAME"
ODOO_CONF_FILE="/etc/odoo19-$DBNAME.conf"
SYSTEMD_FILE="/etc/systemd/system/$SERVICE_NAME.service"
CADDY_FILE="/etc/caddy/sites/$DBNAME.caddy"
LOG_FILE="/var/log/odoo19/odoo19-$DBNAME.log"

# Safety check
if [[ -z "$DBNAME" ]]; then
  echo "❌ Please specify an instance name to delete."
  echo "Usage: sudo delete-odoo19-instance myclient"
  exit 1
fi

echo "⚠️  Are you sure you want to delete instance '$DBNAME'? This will remove files and drop the database."
read -p "Type YES to confirm: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo "❌ Deletion cancelled."
  exit 0
fi

# Stop and disable service
echo "🛑 Stopping systemd service..."
systemctl stop "$SERVICE_NAME"
systemctl disable "$SERVICE_NAME"
rm -f "$SYSTEMD_FILE"

# Remove Odoo config
echo "🧹 Removing Odoo config..."
rm -f "$ODOO_CONF_FILE"

# Remove log file
echo "🧹 Removing log file..."
rm -f "$LOG_FILE"

# Remove Caddy config
echo "🧹 Removing Caddy config..."
rm -f "$CADDY_FILE"

# Reload daemons
echo "🔁 Reloading systemd and restarting Caddy..."
systemctl daemon-reload
systemctl restart caddy

# Drop the PostgreSQL database
echo "🗑️ Dropping PostgreSQL database '$DBNAME'..."
sudo -u odoo19 dropdb "$DBNAME"

echo "✅ Instance '$DBNAME' deleted successfully."
