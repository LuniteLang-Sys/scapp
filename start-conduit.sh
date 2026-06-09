#!/bin/bash
set -e

TOR_DIR="/data/tor/hidden_service"
if [ ! -d "/data" ]; then
    TOR_DIR="/var/lib/tor/hidden_service"
fi

echo "Waiting for Tor to generate hidden service keys..."
for i in {1..30}; do
    if [ -f "$TOR_DIR/hostname" ]; then
        break
    fi
    sleep 1
done

if [ ! -f "$TOR_DIR/hostname" ]; then
    echo "Failed to find Tor hidden service hostname"
    exit 1
fi

ONION_ADDRESS=$(cat "$TOR_DIR/hostname")

DATA_DIR="/data"
if [ ! -d "/data" ]; then
    DATA_DIR="/var/lib"
fi
CONDUIT_DB="$DATA_DIR/conduit"
REG_TOKEN=$(cat "$DATA_DIR/conduit_token")

echo "========================================================="
echo "Tor Hidden Service Address: $ONION_ADDRESS"
echo "Registration Token (KEEP SECRET): $REG_TOKEN"
echo "========================================================="

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

export CONDUIT_CONFIG="/etc/matrix-conduit/conduit.toml"

echo "Starting Conduit..."
exec /usr/local/bin/conduit
