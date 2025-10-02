#!/bin/bash
set -e

REPO_URL="https://github.com/redbarn-dev/odoo18-multitenant-deployer"
CLONE_DIR="/tmp/odoo19-deployer"

echo "📥 Cloning deployer repo..."
rm -rf "$CLONE_DIR"
git clone --branch 19.0 "$REPO_URL" "$CLONE_DIR"

echo "🚀 Installing odoo19-multitenant-deployer..."

# 1. Install main instance creation script
sudo install -m 755 "$CLONE_DIR/scripts/create-odoo19-instance.sh" /usr/local/bin/create-odoo19-instance

# 2. Install instance manager
sudo install -m 755 "$CLONE_DIR/scripts/odoo19-manager.sh" /usr/local/bin/odoo19-manager

# 3. Install deletion script
sudo install -m 755 "$CLONE_DIR/scripts/delete-odoo19-instance.sh" /usr/local/bin/delete-odoo19-instance
echo "🗑️  Delete script installed"

# 4. Install config, systemd templates, and maintenance template
sudo mkdir -p /usr/local/share/odoo19-templates/
sudo cp "$CLONE_DIR/templates/"*.conf /usr/local/share/odoo19-templates/
sudo cp "$CLONE_DIR/templates/"*.service /usr/local/share/odoo19-templates/
sudo cp "$CLONE_DIR/templates/maintenance.html" /usr/local/share/odoo19-templates/
echo "✅ Templates installed"

# 5. Ensure maintenance page is available for Caddy
sudo mkdir -p /var/www/maintenance
sudo cp "$CLONE_DIR/templates/maintenance.html" /var/www/maintenance/index.html
sudo chmod 644 /var/www/maintenance/index.html
echo "✅ Maintenance page deployed at /var/www/maintenance/index.html"

# 6. Caddy setup
sudo mkdir -p /etc/caddy/sites/
if [ ! -f /etc/caddy/Caddyfile ]; then
    sudo cp "$CLONE_DIR/caddy/Caddyfile" /etc/caddy/Caddyfile
    echo "✅ Default Caddyfile installed"
fi

IMPORT_LINE="import sites/*.caddy"
if ! grep -qF "$IMPORT_LINE" /etc/caddy/Caddyfile; then
    echo "$IMPORT_LINE" | sudo tee -a /etc/caddy/Caddyfile > /dev/null
    echo "✅ Added 'import sites/*.caddy' to Caddyfile"
fi

echo ""
echo "🎉 Setup complete! Now you can run:"
echo "   sudo create-odoo19-instance <yourdbname>"
echo "   odoo19-manager status"
echo ""
