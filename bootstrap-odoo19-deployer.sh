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

# 3. Install config and systemd templates
sudo mkdir -p /usr/local/share/odoo19-templates/
sudo cp "$CLONE_DIR/templates/"*.conf /usr/local/share/odoo19-templates/
sudo cp "$CLONE_DIR/templates/"*.service /usr/local/share/odoo19-templates/
echo "✅ Templates installed"

# 4. Caddy setup
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

#5. Install Delete Script 

# 3. Install deletion script
sudo install -m 755 "$CLONE_DIR/scripts/delete-odoo19-instance.sh" /usr/local/bin/delete-odoo19-instance
echo "🗑️  Delete script installed"


echo ""
echo "🎉 Setup complete! Now you can run:"
echo "   sudo create-odoo19-instance <yourdbname>"
echo "   odoo19-manager status"
echo ""
