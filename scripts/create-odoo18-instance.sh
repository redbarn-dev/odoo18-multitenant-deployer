#!/bin/bash

# Help section
if [[ "$1" == "--help" || -z "$1" ]]; then
  echo ""
  echo "🛠️  Odoo18 Instance Setup Script with Logging"
  echo ""
  echo "Usage:"
  echo "  ./create-odoo18-instance.sh <dbname>"
  echo ""
  exit 0
fi

# Constants
BASE_PORT=8070
DBNAME="$1"
SERVICE_NAME="odoo18-$DBNAME"
ODOO_CONF_TEMPLATE="/usr/local/share/odoo18-templates/odoo18-template.conf"
ODOO_SYSTEMD_TEMPLATE="/usr/local/share/odoo18-templates/odoo18-template.service"
ODOO_CONF_FILE="/etc/odoo18-$DBNAME.conf"
SYSTEMD_FILE="/etc/systemd/system/$SERVICE_NAME.service"
CADDY_FILE="/etc/caddy/sites/$DBNAME.caddy"
DOMAIN_SUFFIX=".redbarn.club"
DOMAIN="${DBNAME}${DOMAIN_SUFFIX}"
LOG_DIR="/var/log/odoo18"
LOG_FILE="$LOG_DIR/create-odoo18-instance-$DBNAME.log"

# Setup logging
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
chmod 644 "$LOG_FILE"
echo "⏱️ $(date) - Starting creation of instance '$DBNAME'" > "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

# Cleanup log on success
cleanup_log_on_exit() {
  if [[ $? -eq 0 ]]; then
    echo "🧹 Cleaning up log file..."
    rm -f "$LOG_FILE"
  fi
}
trap cleanup_log_on_exit EXIT

# Check if instance already exists
if [[ -f "$ODOO_CONF_FILE" || -f "$SYSTEMD_FILE" || -f "$CADDY_FILE" ]]; then
  echo "❌ Instance '$DBNAME' already exists."
  exit 1
fi

# Generate credentials and assign a port
ADMIN_PASSWD=$(openssl rand -base64 16)

# Find next available port by checking both configs AND actual port binding
echo "🔎 Scanning for available port..."
NEXT_PORT=$BASE_PORT
while true; do
  # Check if port is in any config file
  if grep -rq "xmlrpc_port[[:space:]]*=[[:space:]]*$NEXT_PORT" /etc/odoo18-*.conf 2>/dev/null; then
    ((NEXT_PORT++))
    continue
  fi
  
  # Check if port is actually in use on the system
  if ss -tuln | grep -q ":$NEXT_PORT "; then
    ((NEXT_PORT++))
    continue
  fi
  
  # Port is free
  break
done

echo "📦 Assigned port $NEXT_PORT to new instance"


# Create config file
echo "⚙️ Creating config file..."
cp "$ODOO_CONF_TEMPLATE" "$ODOO_CONF_FILE" || exit 1
sed -i "s|admin_passwd *=.*|admin_passwd = $ADMIN_PASSWD|" "$ODOO_CONF_FILE"
sed -i "s|odoo18-dbname.log|odoo18-$DBNAME.log|" "$ODOO_CONF_FILE"
sed -i "s|db_name *=.*|db_name = $DBNAME|" "$ODOO_CONF_FILE"
sed -i "s|xmlrpc_port *=.*|xmlrpc_port = $NEXT_PORT|" "$ODOO_CONF_FILE"
sed -i "s|^dbfilter *=.*|dbfilter = ^$DBNAME\$|" "$ODOO_CONF_FILE"
chown odoo18:odoo18 "$ODOO_CONF_FILE"
chmod 640 "$ODOO_CONF_FILE"

# Create systemd service
echo "📜 Setting up systemd service..."
cp "$ODOO_SYSTEMD_TEMPLATE" "$SYSTEMD_FILE" || exit 1
sed -i "s|odoo18-dbname|$SERVICE_NAME|g" "$SYSTEMD_FILE"
sed -i "s|/etc/odoo18-dbname.conf|$ODOO_CONF_FILE|" "$SYSTEMD_FILE"

# Initialize DB
echo "📦 Creating database '$DBNAME'..."

# Build the init command
# DB_INIT_CMD="sudo -u odoo18 /opt/odoo18/odoo18-venv/bin/python3 /opt/odoo18/odoo18/odoo-bin \
#   -c \"$ODOO_CONF_FILE\" \
#   -d \"$DBNAME\" \
#   -i base,website \
#   --without-demo=all \
#   --stop-after-init \
#   --log-level=debug"

# Optional: Show live spinner during DB init
# spin() {
#   local -a marks=( '-' '\' '|' '/' )
#   while :; do
#     for m in "${marks[@]}"; do
#       echo -ne "\r⏳ Initializing DB... $m"
#       sleep 0.1
#     done
#   done
# }

# spin & SPIN_PID=$!

# Run command and capture result
# eval $DB_INIT_CMD
# EXIT_CODE=$?

# Kill spinner
# kill $SPIN_PID &>/dev/null
# wait $SPIN_PID 2>/dev/null
# echo ""

# Check success
# if [ $EXIT_CODE -ne 0 ]; then
#   echo -e "\n❌ \e[31mDatabase initialization FAILED for '$DBNAME'.\e[0m"
#   echo "👉 Review the full log at: $LOG_FILE"
#   exit $EXIT_CODE
# fi



# Start service
echo "🔧 Enabling and starting service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME" || exit 1

# Create Caddy config
echo "🌐 Setting up Caddy config..."
mkdir -p "$(dirname "$CADDY_FILE")"
cat <<EOF > "$CADDY_FILE"
$DOMAIN {
    handle_errors 5xx {
        root * /var/www/maintenance
        rewrite * /index.html
        file_server
    }

    reverse_proxy localhost:$NEXT_PORT {
        header_up Connection {>Connection}
        header_up Upgrade {>Upgrade}
        header_down -Server
    }
    encode gzip
}
EOF

# Restart Caddy
echo "🔁 Reloading Caddy..."
systemctl restart caddy || exit 1

# Final Output
echo ""
echo "✅ Instance '$DBNAME' created successfully!"
echo "🔗 URL: https://$DOMAIN"
echo "🛠 Service: $SERVICE_NAME"
echo "📦 Port: $NEXT_PORT"
echo "🔐 Admin Password: $ADMIN_PASSWD"
