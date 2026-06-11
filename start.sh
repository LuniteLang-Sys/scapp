#!/bin/bash
set -e

# Configuration
PORT="${PORT:-10000}"
CONDUIT_DATA_DIR="/var/lib/conduit"
TOR_DATA_DIR="/var/lib/tor"
TOR_HS_DIR="$TOR_DATA_DIR/hidden_service"
mkdir -p "$CONDUIT_DATA_DIR" "$TOR_HS_DIR"

# ---------------------------------------------------------
# TOR INITIALIZATION (Generate keys in the permanent location)
# ---------------------------------------------------------
echo "Configuring Tor..."
chown -R debian-tor:debian-tor "$TOR_DATA_DIR"
chmod 700 "$TOR_HS_DIR"

cat > /etc/tor/torrc << EOF
DataDirectory $TOR_DATA_DIR
HiddenServiceDir $TOR_HS_DIR
HiddenServicePort 80 127.0.0.1:$PORT
SocksPort 9050
# Performance tweaks for Tor
LongLivedPorts 80,443,6167
EOF

echo "Starting Tor to generate/verify .onion address..."
# Start tor as debian-tor
su -s /bin/sh debian-tor -c "tor -f /etc/tor/torrc --RunAsDaemon 1 --PidFile /tmp/tor.pid"

echo "Waiting for .onion address..."
for i in {1..60}; do
    if [ -f "$TOR_HS_DIR/hostname" ]; then
        FINAL_DOMAIN=$(cat "$TOR_HS_DIR/hostname")
        break
    fi
    sleep 2
done

if [ -z "$FINAL_DOMAIN" ]; then
    echo "ERROR: Tor failed to initialize."
    exit 1
fi

echo "========================================================="
echo "FINAL Tor Hidden Service Address: $FINAL_DOMAIN"
echo "========================================================="

# Stop Tor using the PID file to release the lock
if [ -f /tmp/tor.pid ]; then
    TOR_PID=$(cat /tmp/tor.pid)
    echo "Stopping discovery Tor (PID: $TOR_PID)..."
    kill -9 "$TOR_PID" || su -s /bin/sh debian-tor -c "kill -9 $TOR_PID" || true
    rm -f /tmp/tor.pid
fi
# Clean up lock file just in case
rm -f "$TOR_DATA_DIR/lock"

# ---------------------------------------------------------
# PERMANENT CONFIGURATION
# ---------------------------------------------------------
# 1. Nginx
echo "Patching Nginx port..."
sed -i "s/__PORT__/$PORT/g" /etc/nginx/nginx.conf

# 2. Element
CONFIG_JSON="/var/www/element/config.json"
if [ -f "$CONFIG_JSON" ]; then
  echo "Patching Element..."
  # Replace both the example and any previous onion address
  sed -i "s|matrix.example.com|$FINAL_DOMAIN|g" "$CONFIG_JSON"
  # This regex is more broad to catch any existing .onion links
  sed -i "s|https://[^ ]*\.onion|http://$FINAL_DOMAIN|g" "$CONFIG_JSON"
  sed -i "s|http://[^ ]*\.onion|http://$FINAL_DOMAIN|g" "$CONFIG_JSON"
  
  if grep -q "permalink_prefix" "$CONFIG_JSON"; then
    sed -i "s|\"permalink_prefix\": \".*\"|\"permalink_prefix\": \"http://$FINAL_DOMAIN\"|g" "$CONFIG_JSON"
  else
    sed -i "s|}$|, \"permalink_prefix\": \"http://$FINAL_DOMAIN\"}|" "$CONFIG_JSON"
  fi
fi

# 3. Discovery Files
mkdir -p /var/www/element/.well-known/matrix
echo "{\"m.homeserver\": {\"base_url\": \"http://$FINAL_DOMAIN\"}}" > /var/www/element/.well-known/matrix/client
echo "{\"m.server\": \"$FINAL_DOMAIN:80\"}" > /var/www/element/.well-known/matrix/server

# 4. Conduit
echo "Configuring Conduit..."
chown -R www-data:www-data "$CONDUIT_DATA_DIR"
if [ ! -f "$CONDUIT_DATA_DIR/master_token.txt" ]; then
  tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32 > "$CONDUIT_DATA_DIR/master_token.txt"
fi
MASTER_TOKEN=$(cat "$CONDUIT_DATA_DIR/master_token.txt")
chown www-data:www-data "$CONDUIT_DATA_DIR/master_token.txt"

mkdir -p /etc/conduit
cat > /etc/conduit/conduit.toml << EOF
[global]
server_name = "${FINAL_DOMAIN}"
database_path = "$CONDUIT_DATA_DIR"
database_backend = "${CONDUIT_DATABASE_BACKEND:-rocksdb}"
port = 6167
address = "127.0.0.1"
allow_registration = true
registration_token = "${MASTER_TOKEN}"
allow_federation = false
max_request_size = 20000000
trusted_servers = []

[media]
backend = "s3"
s3_bucket = "${S3_BUCKET}"
s3_endpoint = "${S3_ENDPOINT}"
s3_region = "${S3_REGION:-us-east-1}"
s3_access_key = "${S3_ACCESS_KEY}"
s3_secret_key = "${S3_SECRET_KEY}"
EOF

echo "================================================================="
echo "ADMIN MASTER KEY: $MASTER_TOKEN"
echo "================================================================="

sleep 1
echo "Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
