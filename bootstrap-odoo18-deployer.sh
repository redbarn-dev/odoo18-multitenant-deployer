#!/bin/bash
set -e

REPO_URL="https://github.com/yourname/odoo18-multitenant-deployer"
CLONE_DIR="/tmp/odoo18-deployer"

echo "📥 Cloning deployer repo..."
rm -rf "$CLONE_DIR"
git clone "$REPO_URL" "$CLONE_DIR"

echo "🚀 Installing odoo18-multitenant-deployer..."

# 1. Install the instance creation script
sudo install -m 755 "$CLONE_DIR/create-odoo18-instance.sh" /usr/local/bin/create-odoo18-instance

# 2. Install templates
sudo mkdir -p /usr/local/share/odoo18-templates/
sudo cp "$CLONE_DIR/templates/"*.conf /usr/local/share/odoo18-templates/
sudo cp "$CLONE_DIR/templates/"*.service /usr/local/share/odoo18-templates/

# 3. Caddy setup
sudo mkdir -p /etc/caddy/sites/
if [ ! -f /etc/caddy/Caddyfile ]; then
    sudo cp "$CLONE_DIR/caddy/Caddyfile" /etc/caddy/Caddyfile
fi

IMPORT_LINE="import sites/*.caddy"
if ! grep -qF "$IMPORT_LINE" /etc/caddy/Caddyfile; then
    echo "$IMPORT_LINE" | sudo tee -a /etc/caddy/Caddyfile > /dev/null
fi

echo "✅ Setup complete! You can now run:"
echo "   sudo create-odoo18-instance <dbname>"
