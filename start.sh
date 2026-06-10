#!/bin/sh

# Determine the domain to use
# 1. Use DOMAIN if provided (user override)
# 2. Use RENDER_EXTERNAL_HOSTNAME if on Render
# 3. Fallback to localhost
if [ -n "$DOMAIN" ]; then
  FINAL_DOMAIN="$DOMAIN"
elif [ -n "$RENDER_EXTERNAL_HOSTNAME" ]; then
  FINAL_DOMAIN="$RENDER_EXTERNAL_HOSTNAME"
else
  FINAL_DOMAIN="localhost"
fi

echo "Detected Domain: $FINAL_DOMAIN"
export CONDUIT_SERVER_NAME="$FINAL_DOMAIN"

# ---------------------------------------------------------
# CONFIGURE ELEMENT WEB
# ---------------------------------------------------------
CONFIG_JSON="/var/www/element/config.json"
if [ -f "$CONFIG_JSON" ]; then
  echo "Patching Element config.json..."
  # Replace all occurrences of matrix.example.com with the actual domain
  # This handles https://matrix.example.com and the raw domain
  sed -i "s|matrix.example.com|$FINAL_DOMAIN|g" "$CONFIG_JSON"
fi

# ---------------------------------------------------------
# CONFIGURE WELL-KNOWN DISCOVERY
# ---------------------------------------------------------
echo "Generating .well-known files..."
mkdir -p /var/www/element/.well-known/matrix
echo "{\"m.homeserver\": {\"base_url\": \"https://$FINAL_DOMAIN\"}}" > /var/www/element/.well-known/matrix/client
echo "{\"m.server\": \"$FINAL_DOMAIN:443\"}" > /var/www/element/.well-known/matrix/server

# Ensure database directory exists
mkdir -p /var/lib/matrix-conduit/

# ---------------------------------------------------------
# ADMIN MASTER KEY GENERATION
# ---------------------------------------------------------
if [ ! -f /var/lib/matrix-conduit/master_token.txt ]; then
  tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32 > /var/lib/matrix-conduit/master_token.txt
fi

MASTER_TOKEN=$(cat /var/lib/matrix-conduit/master_token.txt)

echo "================================================================="
echo "ADMIN MASTER KEY (Registration Token)"
echo "Master Key: $MASTER_TOKEN"
echo "================================================================="

# Create conduit config file
mkdir -p /etc/conduit
cat > /etc/conduit/conduit.toml << EOF
[global]
server_name = "${CONDUIT_SERVER_NAME}"
database_path = "/var/lib/matrix-conduit/"
database_backend = "${CONDUIT_DATABASE_BACKEND:-rocksdb}"
port = 6167
address = "127.0.0.1"
allow_registration = true
registration_token = "${MASTER_TOKEN}"
allow_federation = false
max_request_size = 20000000
trusted_servers = ["matrix.org"]
EOF


export CONDUIT_CONFIG="/etc/conduit/conduit.toml"

# Run conduit in background
/usr/local/bin/conduit &
CONDUIT_PID=$!

# Wait a moment for conduit to start
sleep 2

# Check if conduit is still running
if ! kill -0 $CONDUIT_PID 2>/dev/null; then
  echo "ERROR: Conduit failed to start!"
  exit 1
fi

echo "Conduit is running (PID: $CONDUIT_PID)"
echo "Starting Nginx Proxy..."
nginx -g "daemon off;"
