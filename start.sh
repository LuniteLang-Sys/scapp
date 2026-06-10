#!/bin/bash
set -e

# Configuration
PORT="${PORT:-10000}"
DATA_DIR="/var/lib/matrix-conduit"
mkdir -p "$DATA_DIR"

# ---------------------------------------------------------
# TOR CONFIGURATION
# ---------------------------------------------------------
echo "Configuring Tor..."
TOR_DATA_DIR="$DATA_DIR/tor"
TOR_HS_DIR="$TOR_DATA_DIR/hidden_service"

# Clear old config to avoid conflicts
rm -f /etc/tor/torrc

# Create fresh torrc
cat > /etc/tor/torrc << EOF
DataDirectory $TOR_DATA_DIR
HiddenServiceDir $TOR_HS_DIR
HiddenServicePort 80 127.0.0.1:$PORT
EOF

# Ensure directories exist and have correct permissions
mkdir -p "$TOR_HS_DIR"
chown -R debian-tor:debian-tor "$TOR_DATA_DIR"
chmod 700 "$TOR_HS_DIR"

# Start Tor in background to generate hostname
echo "Starting Tor to generate .onion address..."
# Start tor as debian-tor user to satisfy security checks
su -s /bin/sh debian-tor -c "tor -f /etc/tor/torrc --RunAsDaemon 1"

echo "Waiting for Tor to generate hidden service keys..."
# We wait for the hostname file to appear
MAX_RETRIES=60
RETRY_COUNT=0
while [ ! -f "$TOR_HS_DIR/hostname" ] && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    # Check if Tor is still running
    if ! pgrep -x tor > /dev/null; then
        echo "ERROR: Tor process died. Printing Tor system logs (if available):"
        # On Debian, check tail of system log if possible, or just fail
        exit 1
    fi
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $((RETRY_COUNT % 5)) -eq 0 ]; then
        echo "Still waiting for Tor... ($((RETRY_COUNT * 2))s)"
    fi
done

if [ -f "$TOR_HS_DIR/hostname" ]; then
    FINAL_DOMAIN=$(cat "$TOR_HS_DIR/hostname")
else
    echo "ERROR: Tor failed to generate a hostname in time."
    exit 1
fi

echo "========================================================="
echo "Tor Hidden Service Address: $FINAL_DOMAIN"
echo "========================================================="

# ---------------------------------------------------------
# CONFIGURE ELEMENT WEB
# ---------------------------------------------------------
CONFIG_JSON="/var/www/element/config.json"
if [ -f "$CONFIG_JSON" ]; then
  echo "Patching Element config.json..."
  # Use http for .onion addresses
  sed -i "s|matrix.example.com|$FINAL_DOMAIN|g" "$CONFIG_JSON"
  sed -i "s|https://$FINAL_DOMAIN|http://$FINAL_DOMAIN|g" "$CONFIG_JSON"
  
  if grep -q "permalink_prefix" "$CONFIG_JSON"; then
    sed -i "s|\"permalink_prefix\": \".*\"|\"permalink_prefix\": \"http://$FINAL_DOMAIN\"|g" "$CONFIG_JSON"
  else
    sed -i "s|}$|, \"permalink_prefix\": \"http://$FINAL_DOMAIN\"}|" "$CONFIG_JSON"
  fi
fi

# ---------------------------------------------------------
# CONFIGURE WELL-KNOWN DISCOVERY
# ---------------------------------------------------------
echo "Generating .well-known files..."
mkdir -p /var/www/element/.well-known/matrix
echo "{\"m.homeserver\": {\"base_url\": \"http://$FINAL_DOMAIN\"}}" > /var/www/element/.well-known/matrix/client
echo "{\"m.server\": \"$FINAL_DOMAIN:80\"}" > /var/www/element/.well-known/matrix/server

# ---------------------------------------------------------
# ADMIN MASTER KEY
# ---------------------------------------------------------
if [ ! -f "$DATA_DIR/master_token.txt" ]; then
  tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32 > "$DATA_DIR/master_token.txt"
fi
MASTER_TOKEN=$(cat "$DATA_DIR/master_token.txt")

# ---------------------------------------------------------
# CONDUIT CONFIGURATION
# ---------------------------------------------------------
echo "Configuring Conduit..."
mkdir -p /etc/conduit
cat > /etc/conduit/conduit.toml << EOF
[global]
server_name = "${FINAL_DOMAIN}"
database_path = "$DATA_DIR"
database_backend = "${CONDUIT_DATABASE_BACKEND:-rocksdb}"
port = 6167
address = "127.0.0.1"
allow_registration = true
registration_token = "${MASTER_TOKEN}"
allow_federation = false
max_request_size = 20000000
trusted_servers = []
EOF

echo "================================================================="
echo "ADMIN MASTER KEY: $MASTER_TOKEN"
echo "================================================================="

# Kill the background Tor process before starting supervisord
pkill tor || true
sleep 1

echo "Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
