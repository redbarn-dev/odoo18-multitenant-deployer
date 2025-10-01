#!/bin/bash

# Help section
if [[ "$1" == "--help" || -z "$1" ]]; then
  echo ""
  echo "🛠️  odoo19 Instance Setup Script with Logging"
  echo ""
  echo "Usage:"
  echo "  ./create-odoo19-instance.sh <dbname>"
  echo ""
  exit 0
fi

# Constants
BASE_PORT=8070
DBNAME="$1"
SERVICE_NAME="odoo19-$DBNAME"
ODOO_CONF_TEMPLATE="/usr/local/share/odoo19-templates/odoo19-template.conf"
ODOO_SYSTEMD_TEMPLATE="/usr/local/share/odoo19-templates/odoo19-template.service"
ODOO_CONF_FILE="/etc/odoo19-$DBNAME.conf"
SYSTEMD_FILE="/etc/systemd/system/$SERVICE_NAME.service"
CADDY_FILE="/etc/caddy/sites/$DBNAME.caddy"
DOMAIN_SUFFIX=".redbarn.club"
DOMAIN="${DBNAME}${DOMAIN_SUFFIX}"
LOG_DIR="/var/log/odoo19"
LOG_FILE="$LOG_DIR/create-odoo19-instance-$DBNAME.log"

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

# Determine next available XML-RPC port scoped only to Odoo configs
echo "🔎 Scanning used Odoo ports..."
USED_PORTS=$(grep -rh 'xmlrpc_port' /etc/odoo19-*.conf 2>/dev/null | awk '{print $3}' | sort -n)

NEXT_PORT=$BASE_PORT

# Keep incrementing from 8070 until we find a free one
while echo "$USED_PORTS" | grep -q "^$NEXT_PORT$"; do
  ((NEXT_PORT++))
done

echo "📦 Assigned port $NEXT_PORT to new instance"


# Create config file
echo "⚙️ Creating config file..."
cp "$ODOO_CONF_TEMPLATE" "$ODOO_CONF_FILE" || exit 1
sed -i "s|admin_passwd *=.*|admin_passwd = $ADMIN_PASSWD|" "$ODOO_CONF_FILE"
sed -i "s|odoo19-dbname.log|odoo19-$DBNAME.log|" "$ODOO_CONF_FILE"
sed -i "s|db_name *=.*|db_name = $DBNAME|" "$ODOO_CONF_FILE"
sed -i "s|xmlrpc_port *=.*|xmlrpc_port = $NEXT_PORT|" "$ODOO_CONF_FILE"
sed -i "s|^dbfilter *=.*|dbfilter = ^$DBNAME\$|" "$ODOO_CONF_FILE"
chown odoo19:odoo19 "$ODOO_CONF_FILE"
chmod 640 "$ODOO_CONF_FILE"

# Create systemd service
echo "📜 Setting up systemd service..."
cp "$ODOO_SYSTEMD_TEMPLATE" "$SYSTEMD_FILE" || exit 1
sed -i "s|odoo19-dbname|$SERVICE_NAME|g" "$SYSTEMD_FILE"
sed -i "s|/etc/odoo19-dbname.conf|$ODOO_CONF_FILE|" "$SYSTEMD_FILE"

# Initialize DB
echo "📦 Creating database '$DBNAME'..."

# Build the init command
# DB_INIT_CMD="sudo -u odoo19 /opt/odoo19/odoo19-venv/bin/python3 /opt/odoo19/odoo19/odoo-bin \
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
