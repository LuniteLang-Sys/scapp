#!/bin/bash
set -e

# Default port to 10000 if not set by Render
PORT="${PORT:-10000}"

# Substitute PORT in nginx.conf and torrc
sed -i "s/__PORT__/$PORT/g" /etc/nginx/nginx.conf
sed -i "s/__PORT__/$PORT/g" /etc/tor/torrc

# Render might provide a persistent disk at /data.
# If /data does not exist or we are not using a disk, we fallback to /var/lib.
DATA_DIR="/data"
if [ ! -d "/data" ]; then
    echo "/data directory not found, using ephemeral storage /var/lib"
    DATA_DIR="/var/lib"
fi

# Substitute DATA_DIR in torrc
sed -i "s|__DATA_DIR__|$DATA_DIR|g" /etc/tor/torrc

# Setup Tor Hidden Service directory
TOR_DIR="$DATA_DIR/tor/hidden_service"
mkdir -p "$TOR_DIR"
chown -R debian-tor:debian-tor "$DATA_DIR/tor"
chmod 700 "$TOR_DIR"

# Setup Conduit Database directory
CONDUIT_DB="$DATA_DIR/conduit"
mkdir -p "$CONDUIT_DB"

# Generate Tor Hidden Service if it doesn't exist yet by starting tor temporarily
echo "Starting tor to generate hidden service keys..."
tor -f /etc/tor/torrc --RunAsDaemon 1

# Wait for hostname to be generated
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

# Sinh mã đăng ký ngẫu nhiên nếu chưa có
if [ ! -f "$DATA_DIR/conduit_token" ]; then
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1 > "$DATA_DIR/conduit_token"
fi
REG_TOKEN=$(cat "$DATA_DIR/conduit_token")

echo "========================================================="
echo "Tor Hidden Service Address: $ONION_ADDRESS"
echo "Registration Token (GIỮ BÍ MẬT): $REG_TOKEN"
echo "========================================================="

# Stop the temporary tor instance
pkill tor || true
sleep 1

# Update Element config.json dynamically
echo "Configuring Element web interface..."
CONFIG_PATH="/var/www/element/config.json"
if [ -f "$CONFIG_PATH" ]; then
    # Xoá toàn bộ link rò rỉ ra ngoài clearnet
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

# Configure Conduit
export CONDUIT_SERVER_NAME="$ONION_ADDRESS"
export CONDUIT_DATABASE_PATH="$CONDUIT_DB"
export CONDUIT_DATABASE_BACKEND="sqlite"
export CONDUIT_PORT=6167
export CONDUIT_ADDRESS="127.0.0.1"
export CONDUIT_ALLOW_REGISTRATION="false"
export CONDUIT_ALLOW_FEDERATION="false"
export CONDUIT_REGISTRATION_TOKEN="$REG_TOKEN"

# Chuyển quyền thư mục DB cho www-data để chạy dưới quyền tối thiểu
chown -R www-data:www-data "$CONDUIT_DB"

# Start supervisord to launch everything
echo "Starting Nginx, Tor, and Conduit..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
