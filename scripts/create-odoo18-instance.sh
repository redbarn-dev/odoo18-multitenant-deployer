#!/bin/bash
if [[ "$1" == "--help" || -z "$1" ]]; then
  echo ""
  echo "🛠️  Odoo18 Instance Setup Script"
  echo ""
  echo "Usage:"
  echo "  ./create-odoo18-instance.sh <dbname>"
  echo ""
  echo "What it does:"
  echo "  ✔ Creates an Odoo config file from a template"
  echo "  ✔ Assigns a unique port and random admin password"
  echo "  ✔ Sets up a systemd service"
  echo "  ✔ Generates a new Caddy site config"
  echo "  ✔ Starts the service and reloads Caddy"
  echo ""
  exit 0
fi

BASE_PORT=8070
ODOO_CONF_TEMPLATE="/usr/local/share/odoo18-templates/odoo18-template.conf"
ODOO_SYSTEMD_TEMPLATE="/usr/local/share/odoo18-templates/odoo18-template.service"
SYSTEMD_DIR="/etc/systemd/system"
ODOO_CONF_DIR="/etc"
CADDY_SITE_DIR="/etc/caddy/sites"
DOMAIN_SUFFIX=".redbarn.club"

DBNAME="$1"
SERVICE_NAME="odoo18-$DBNAME"
ODOO_CONF_FILE="$ODOO_CONF_DIR/odoo18-$DBNAME.conf"
SYSTEMD_FILE="$SYSTEMD_DIR/$SERVICE_NAME.service"
CADDY_FILE="$CADDY_SITE_DIR/$DBNAME.caddy"
DOMAIN="${DBNAME}${DOMAIN_SUFFIX}"

if [[ -f "$ODOO_CONF_FILE" || -f "$SYSTEMD_FILE" || -f "$CADDY_FILE" ]]; then
  echo "❌ Instance '$DBNAME' already exists."
  exit 1
fi

ADMIN_PASSWD=$(openssl rand -base64 16)
# Start at base port 8070
BASE_PORT=8070

# Count current odoo18-* services to determine offset
INSTANCE_COUNT=$(systemctl list-units --type=service --no-legend "odoo18-*.service" | wc -l)
NEXT_PORT=$((BASE_PORT + INSTANCE_COUNT))

# Ensure the port isn't already used (paranoia check)
EXISTING_PORTS=$(grep -rh 'xmlrpc_port' /etc/odoo18-*.conf 2>/dev/null | awk '{print $3}' | sort -n)
while echo "$EXISTING_PORTS" | grep -q "^$NEXT_PORT$"; do
  ((NEXT_PORT++))
done

cp "$ODOO_CONF_TEMPLATE" "$ODOO_CONF_FILE"
sed -i "s|admin_passwd *=.*|admin_passwd = $ADMIN_PASSWD|" "$ODOO_CONF_FILE"
sed -i "s|odoo18-dbname.log|odoo18-$DBNAME.log|" "$ODOO_CONF_FILE"
sed -i "s|db_name *=.*|db_name = $DBNAME|" "$ODOO_CONF_FILE"
sed -i "s|xmlrpc_port *=.*|xmlrpc_port = $NEXT_PORT|" "$ODOO_CONF_FILE"
sed -i "s|^dbfilter *=.*|dbfilter = ^$DBNAME\$|" "$ODOO_CONF_FILE"

cp "$ODOO_SYSTEMD_TEMPLATE" "$SYSTEMD_FILE"
sed -i "s|odoo18-dbname|$SERVICE_NAME|g" "$SYSTEMD_FILE"
# sed -i "s|\*dbname\*|$DBNAME|g" "$SYSTEMD_FILE"
sed -i "s|/etc/odoo18-dbname.conf|$ODOO_CONF_FILE|" "$SYSTEMD_FILE"


# Set config file permissions for odoo18
chown odoo18:odoo18 "$ODOO_CONF_FILE"
chmod 640 "$ODOO_CONF_FILE"

# Initialize the database and install website module
# echo "📦 Creating database '$DBNAME' and installing website module..."
# sudo -u odoo18 /opt/odoo18/odoo18-venv/bin/python3 /opt/odoo18/odoo18/odoo-bin \
#   -c "$ODOO_CONF_FILE" -d "$DBNAME" -i website --without-demo=all --stop-after-init \
#   --log-level=debug

# if [ $? -ne 0 ]; then
#   echo "❌ Failed to initialize database '$DBNAME'."
#   exit 1
# fi


systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl start "$SERVICE_NAME"

mkdir -p "$CADDY_SITE_DIR"
cat <<EOF > "$CADDY_FILE"
$DOMAIN {
    handle_errors {
        @odoo_down expression `{http.error.status_code} == 502`
        rewrite @odoo_down /index.html
        file_server
        root * /var/www/maintenance
    }

    reverse_proxy localhost:$NEXT_PORT {
        header_up Connection {>Connection}
        header_up Upgrade {>Upgrade}
    }

    encode gzip
}
EOF

caddy reload

echo ""
echo "🎉 Instance '$DBNAME' created successfully!"
echo "🔗 Access it at: https://$DOMAIN"
echo "🛠 Service: $SERVICE_NAME"
echo "📦 Port: $NEXT_PORT"
echo "🔐 Admin password: $ADMIN_PASSWD"
