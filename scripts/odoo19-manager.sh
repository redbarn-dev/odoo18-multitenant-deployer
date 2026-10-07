#!/bin/bash

ACTION=$1

show_help() {
  echo ""
  echo "🛠️  Usage: odoo19-manager {start|stop|restart|status|list|install-module|update-addons|help}"
  echo ""
  echo "Commands:"
  echo "  start            - Start all odoo19-* services"
  echo "  stop             - Stop all odoo19-* services"
  echo "  restart          - Restart all odoo19-* services"
  echo "  status           - Show detailed status of each odoo19-* service"
  echo "  list             - List all odoo19-* services with ✅ running or ❌ not running"
  echo "  install-module   - Interactively install or upgrade a module on one or all databases"
  echo "  update-addons    - Add any missing template addons_path entries to every /etc/odoo19-*.conf"
  echo "                     (use 'update-addons --dry-run' to preview changes)"
  echo "  help             - Show this help message"
  echo ""
}

# Show help if no action or help is requested
if [[ -z "$ACTION" || "$ACTION" == "help" ]]; then
  show_help
  exit 0
fi

# Validate allowed commands - Better approach with direct array matching
VALID_COMMANDS=("start" "stop" "restart" "status" "list" "install-module" "update-addons" "help")
VALID=0
for cmd in "${VALID_COMMANDS[@]}"; do
  if [[ "$ACTION" == "$cmd" ]]; then
    VALID=1
    break
  fi
done

if [[ $VALID -eq 0 ]]; then
  echo "❌ Unknown command: '$ACTION'"
  echo "Run 'odoo19-manager help' to see available commands."
  exit 1
fi

SERVICES=$(systemctl list-unit-files | grep '^odoo19-.*\.service' | awk '{print $1}')

# Handle list command
if [[ "$ACTION" == "list" ]]; then
  echo "🔍 Listing Odoo instances:"
  for svc in $SERVICES; do
    if systemctl is-active --quiet "$svc"; then
      echo "✅ $svc is running"
    else
      echo "❌ $svc is not running"
    fi
  done
  exit 0
fi

# Handle install-module command
if [[ "$ACTION" == "install-module" ]]; then
  read -p "🔧 Enter module name to deploy: " MODULE
  if [[ -z "$MODULE" ]]; then
    echo "❌ Module name cannot be blank."
    exit 1
  fi

  MODULE_PATH="/opt/odoo19/custom-addons/$MODULE"
  if [[ ! -d "$MODULE_PATH" ]]; then
    echo "❌ Module '$MODULE' not found in /opt/odoo19/custom-addons/"
    exit 2
  fi

  read -p "🎯 Target specific DB? Leave blank to run on ALL: " TARGET_DB
  read -p "⚙️ [i]nstall or [u]pgrade? " MODE_INPUT

  case "$MODE_INPUT" in
    i|I)
      MODE="install"
      ;;
    u|U)
      MODE="upgrade"
      ;;
    *)
      echo "❌ Invalid choice. Enter 'i' or 'u'."
      exit 3
      ;;
  esac

  ODOO_BIN="/opt/odoo19/odoo19/odoo-bin"
  PYTHON="/opt/odoo19/odoo19-venv/bin/python3"

  for CONF in /etc/odoo19-*.conf; do
    DBNAME=$(grep '^db_name' "$CONF" | awk '{print $3}')
    BASENAME=$(basename "$CONF" .conf)
    SERVICE_NAME="$BASENAME.service"

    if [[ -n "$TARGET_DB" && "$DBNAME" != "$TARGET_DB" ]]; then
      continue
    fi

    echo "🛑 Stopping $SERVICE_NAME..."
    systemctl stop "$SERVICE_NAME"

    echo "📦 Deploying '$MODULE' to $DBNAME ($MODE)..."
    if [[ "$MODE" == "install" ]]; then
      CMD="$PYTHON $ODOO_BIN -c $CONF -d $DBNAME -i $MODULE --without-demo=all --stop-after-init"
    else
      CMD="$PYTHON $ODOO_BIN -c $CONF -d $DBNAME -u $MODULE --without-demo=all --stop-after-init"
    fi

    sudo -u odoo19 bash -c "$CMD"
    if [[ $? -eq 0 ]]; then
      echo "✅ Success for $DBNAME"
    else
      echo "❌ Failed for $DBNAME"
    fi

    echo "🚀 Restarting $SERVICE_NAME..."
    systemctl start "$SERVICE_NAME"
    echo "-----------------------------------------"
  done

  echo "🎉 Finished '$MODE' for module '$MODULE'"
  exit 0
fi

# Handle update-addons command
if [[ "$ACTION" == "update-addons" ]]; then
  DRY_RUN=0
  [[ "$2" == "--dry-run" ]] && DRY_RUN=1

  TEMPLATE="/usr/local/share/odoo19-templates/odoo19-template.conf"
  if [[ ! -f "$TEMPLATE" ]]; then
    echo "❌ Template not found: $TEMPLATE"
    exit 1
  fi

  # Required paths come from the installed template's addons_path
  REQUIRED=$(grep -E '^[[:space:]]*addons_path[[:space:]]*=' "$TEMPLATE" | head -1 | cut -d= -f2- | tr -d '[:space:]')
  if [[ -z "$REQUIRED" ]]; then
    echo "❌ No addons_path found in $TEMPLATE"
    exit 1
  fi
  IFS=',' read -ra REQUIRED_PATHS <<< "$REQUIRED"

  # Odoo refuses to start if an addons_path entry doesn't exist, so verify all dirs before touching any config
  VALID_PATHS=()
  MISSING_PATHS=()
  for P in "${REQUIRED_PATHS[@]}"; do
    if [[ -d "$P" ]]; then
      VALID_PATHS+=("${P%/}")
    else
      MISSING_PATHS+=("$P")
    fi
  done

  if [[ ${#MISSING_PATHS[@]} -gt 0 ]]; then
    echo "❌ The following addons directories do not exist on this server:"
    for P in "${MISSING_PATHS[@]}"; do
      echo "   - $P"
    done
    echo "Create or clone them first, then re-run. No configs were changed."
    exit 1
  fi

  CHANGED_SERVICES=()
  for CONF in /etc/odoo19-*.conf; do
    [[ -f "$CONF" ]] || continue

    CURRENT=$(grep -E '^[[:space:]]*addons_path[[:space:]]*=' "$CONF" | head -1 | cut -d= -f2- | tr -d '[:space:]')
    NEW="$CURRENT"

    # Append each required path not already present (ignoring trailing slashes)
    NORMALIZED=",$(echo "$CURRENT" | sed 's|/,|,|g; s|/$||'),"
    for P in "${VALID_PATHS[@]}"; do
      if [[ "$NORMALIZED" != *",$P,"* ]]; then
        NEW="${NEW:+$NEW,}$P"
        NORMALIZED="$NORMALIZED$P,"
      fi
    done

    if [[ "$NEW" == "$CURRENT" ]]; then
      echo "✅ $CONF is up to date"
      continue
    fi

    echo "🔧 $CONF"
    echo "   old: ${CURRENT:-<none>}"
    echo "   new: $NEW"

    if [[ $DRY_RUN -eq 1 ]]; then
      continue
    fi

    cp -p "$CONF" "$CONF.bak.$(date +%Y%m%d%H%M%S)"
    if grep -qE '^[[:space:]]*addons_path[[:space:]]*=' "$CONF"; then
      sed -i "s|^[[:space:]]*addons_path[[:space:]]*=.*|addons_path = $NEW|" "$CONF"
    else
      sed -i "/^\[options\]/a addons_path = $NEW" "$CONF"
    fi
    CHANGED_SERVICES+=("$(basename "$CONF" .conf).service")
  done

  if [[ $DRY_RUN -eq 1 ]]; then
    echo "ℹ️  Dry run — no files were changed."
    exit 0
  fi

  if [[ ${#CHANGED_SERVICES[@]} -eq 0 ]]; then
    echo "🎉 All configs already include the required addons paths."
    exit 0
  fi

  echo ""
  echo "📝 Updated ${#CHANGED_SERVICES[@]} config(s). Backups saved alongside as *.conf.bak.<timestamp>"
  read -p "🔁 Restart the affected services now? [y/N] " RESTART
  if [[ "$RESTART" =~ ^[yY]$ ]]; then
    for svc in "${CHANGED_SERVICES[@]}"; do
      if systemctl restart "$svc"; then
        echo "✅ $svc restarted"
      else
        echo "❌ $svc restart failed"
      fi
    done
  else
    echo "ℹ️  Changes take effect on next restart (odoo19-manager restart)."
  fi
  exit 0
fi

# Default start/stop/restart/status command handling
for svc in $SERVICES; do
  echo "$ACTION $svc"

  if [[ "$ACTION" == "status" ]]; then
    systemctl status --no-pager "$svc"
    echo "-----------------------------------------"
  else
    if systemctl "$ACTION" "$svc"; then
      echo "✅ $svc $ACTION succeeded"
    else
      echo "❌ $svc $ACTION failed"
    fi
  fi
done
