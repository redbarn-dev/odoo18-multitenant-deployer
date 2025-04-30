#!/bin/bash

ACTION=$1

show_help() {
  echo ""
  echo "🛠️  Usage: odoo17-manager {start|stop|restart|status|list|help}"
  echo ""
  echo "Commands:"
  echo "  start     - Start all odoo17-* services"
  echo "  stop      - Stop all odoo17-* services"
  echo "  restart   - Restart all odoo17-* services"
  echo "  status    - Show detailed status of each odoo17-* service"
  echo "  list      - List all odoo17-* services with ✅ running or ❌ not running"
  echo "  help      - Show this help message"
  echo ""
}

# Show help if no action or help is requested
if [[ -z "$ACTION" || "$ACTION" == "help" ]]; then
  show_help
  exit 0
fi

SERVICES=$(systemctl list-unit-files | grep '^odoo17-.*\.service' | awk '{print $1}')

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

# Handle other commands
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