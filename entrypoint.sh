#!/bin/bash
set -e

PORT="${PORT:-10000}"

sed -i "s/__PORT__/$PORT/g" /etc/nginx/nginx.conf
sed -i "s/__PORT__/$PORT/g" /etc/tor/torrc

DATA_DIR="/data"
if [ ! -d "/data" ]; then
    echo "/data directory not found, using ephemeral storage /var/lib"
    DATA_DIR="/var/lib"
fi

sed -i "s|__DATA_DIR__|$DATA_DIR|g" /etc/tor/torrc

TOR_DIR="$DATA_DIR/tor/hidden_service"
mkdir -p "$TOR_DIR"
chown -R debian-tor:debian-tor "$DATA_DIR/tor"
chmod 700 "$TOR_DIR"

CONDUIT_DB="$DATA_DIR/conduit"
mkdir -p "$CONDUIT_DB"

echo "Starting tor to generate hidden service keys..."
# Run tor in the background natively, not daemonized by itself
su -s /bin/bash -c "exec tor -f /etc/tor/torrc" debian-tor &
TOR_PID=$!

for i in {1..15}; do
    if [ -f "$TOR_DIR/hostname" ]; then
        break
    fi
    sleep 1
done

if [ ! -f "$TOR_DIR/hostname" ]; then
    echo "Failed to generate Tor hidden service hostname"
    exit 1
fi

ONION_ADDRESS=$(cat "$TOR_DIR/hostname")

if [ ! -f "$DATA_DIR/conduit_token" ]; then
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1 > "$DATA_DIR/conduit_token"
fi
REG_TOKEN=$(cat "$DATA_DIR/conduit_token")

echo "========================================================="
echo "Tor Hidden Service Address: $ONION_ADDRESS"
echo "Registration Token (KEEP SECRET): $REG_TOKEN"
echo "========================================================="

# Stop the temporary tor instance by directly killing the bash exec pid
kill $TOR_PID || true
sleep 1
# Extra cleanup just in case
pkill -9 tor || true
killall -9 tor || true

echo "Configuring Element web interface..."
CONFIG_PATH="/var/www/element/config.json"
if [ -f "$CONFIG_PATH" ]; then
    jq --arg onion "$ONION_ADDRESS" '
      .default_server_config."m.homeserver".base_url = "http://\($onion)" | 
      .default_server_config."m.homeserver".server_name = $onion |
      .disable_custom_urls = true |
      .disable_guests = true |
      .disable_3pid_login = true |
      .bug_report_endpoint_url = "" |
      .piwik = false |
      .integrations_ui_url = "" |
      .integrations_rest_url = "" |
      .integrations_widgets_urls = [] |
      .room_directory.servers = [$onion] |
      .features.feature_video_rooms = false |
      .features.feature_voice_rooms = false
    ' "$CONFIG_PATH" > /tmp/config.json
    mv /tmp/config.json "$CONFIG_PATH"
fi

echo "Configuring Conduit..."
mkdir -p /etc/matrix-conduit
cat <<EOF > /etc/matrix-conduit/conduit.toml
[global]
server_name = "${ONION_ADDRESS}"
database_path = "${CONDUIT_DB}"
database_backend = "sqlite"
port = 6167
address = "127.0.0.1"
allow_registration = false
allow_federation = false
registration_token = "${REG_TOKEN}"
max_request_size = 20_000_000
trusted_servers = ["matrix.org"]
EOF

chown -R www-data:www-data /etc/matrix-conduit
export CONDUIT_CONFIG="/etc/matrix-conduit/conduit.toml"

chown -R www-data:www-data "$CONDUIT_DB"

echo "Starting Nginx, Tor, and Conduit via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
