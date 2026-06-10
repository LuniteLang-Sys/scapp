#!/bin/bash
set -e

# Configuration
PORT="${PORT:-10000}"
CONDUIT_DATA_DIR="/var/lib/conduit"
TOR_DATA_DIR="/var/lib/tor"
mkdir -p "$CONDUIT_DATA_DIR" "$TOR_DATA_DIR"

# ---------------------------------------------------------
# TOR DISCOVERY (Use a temporary path to avoid lock issues)
# ---------------------------------------------------------
echo "Configuring Tor Discovery..."
TEMP_TOR_DIR="/tmp/tor_discovery"
mkdir -p "$TEMP_TOR_DIR"
chown -R debian-tor:debian-tor "$TEMP_TOR_DIR"
chmod 700 "$TEMP_TOR_DIR"

cat > /etc/tor/torrc.discovery << EOF
DataDirectory $TEMP_TOR_DIR
HiddenServiceDir $TEMP_TOR_DIR/hs
HiddenServicePort 80 127.0.0.1:$PORT
SocksPort 0
EOF

echo "Starting Tor Discovery to generate address..."
su -s /bin/sh debian-tor -c "tor -f /etc/tor/torrc.discovery --RunAsDaemon 1 --PidFile /tmp/tor_discovery.pid"

echo "Waiting for .onion address..."
for i in {1..60}; do
    if [ -f "$TEMP_TOR_DIR/hs/hostname" ]; then
        FINAL_DOMAIN=$(cat "$TEMP_TOR_DIR/hs/hostname")
        break
    fi
    sleep 2
done

if [ -z "$FINAL_DOMAIN" ]; then
    echo "ERROR: Tor discovery failed."
    exit 1
fi

echo "========================================================="
echo "Tor Hidden Service Address: $FINAL_DOMAIN"
echo "========================================================="

# Stop discovery Tor immediately and cleanup
if [ -f /tmp/tor_discovery.pid ]; then
    kill -9 $(cat /tmp/tor_discovery.pid) || true
    rm -f /tmp/tor_discovery.pid
fi
rm -rf "$TEMP_TOR_DIR"

# ---------------------------------------------------------
# PERMANENT CONFIGURATION
# ---------------------------------------------------------
# 1. Tor (Main)
echo "Configuring Permanent Tor..."
mkdir -p "$TOR_DATA_DIR/hidden_service"
chown -R debian-tor:debian-tor "$TOR_DATA_DIR"
chmod 700 "$TOR_DATA_DIR/hidden_service"

cat > /etc/tor/torrc << EOF
DataDirectory $TOR_DATA_DIR
HiddenServiceDir $TOR_DATA_DIR/hidden_service
HiddenServicePort 80 127.0.0.1:$PORT
SocksPort 9050
# Performance tweaks for Tor
FastFirstHopPK 1
LongLivedPorts 80,443,6167
EOF

# 2. Nginx
echo "Patching Nginx port..."
sed -i "s/__PORT__/$PORT/g" /etc/nginx/nginx.conf

# 3. Element
CONFIG_JSON="/var/www/element/config.json"
if [ -f "$CONFIG_JSON" ]; then
  echo "Patching Element..."
  sed -i "s|matrix.example.com|$FINAL_DOMAIN|g" "$CONFIG_JSON"
  sed -i "s|https://$FINAL_DOMAIN|http://$FINAL_DOMAIN|g" "$CONFIG_JSON"
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
EOF

echo "================================================================="
echo "ADMIN MASTER KEY: $MASTER_TOKEN"
echo "================================================================="

sleep 1
echo "Starting all services via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
