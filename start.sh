#!/bin/sh

# If we are running on Render, RENDER_EXTERNAL_HOSTNAME will be populated automatically
if [ -n "$RENDER_EXTERNAL_HOSTNAME" ]; then
  echo "Detected Render environment. Setting domain to $RENDER_EXTERNAL_HOSTNAME"
  export CONDUIT_SERVER_NAME="$RENDER_EXTERNAL_HOSTNAME"

  # Dynamically patch Element's config.json with the actual domain
  sed -i "s|https://matrix.example.com|https://$RENDER_EXTERNAL_HOSTNAME|g" /var/www/element/config.json
  sed -i "s|matrix.example.com|$RENDER_EXTERNAL_HOSTNAME|g" /var/www/element/config.json

  # Dynamically generate .well-known discovery files
  mkdir -p /var/www/element/.well-known/matrix
  echo "{\"m.homeserver\": {\"base_url\": \"https://$RENDER_EXTERNAL_HOSTNAME\"}}" > /var/www/element/.well-known/matrix/client
  echo "{\"m.server\": \"$RENDER_EXTERNAL_HOSTNAME:443\"}" > /var/www/element/.well-known/matrix/server
else
  export CONDUIT_SERVER_NAME="localhost"
fi

# Ensure database directory exists
mkdir -p /var/lib/matrix-conduit/

# ---------------------------------------------------------
# ADMIN MASTER KEY GENERATION
# Use /dev/urandom with tr + head -c (busybox compatible)
# ---------------------------------------------------------
if [ ! -f /var/lib/matrix-conduit/master_token.txt ]; then
  # Generate a 32-character random alphanumeric string (busybox compatible)
  tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c 32 > /var/lib/matrix-conduit/master_token.txt
fi

MASTER_TOKEN=$(cat /var/lib/matrix-conduit/master_token.txt)

echo "================================================================="
echo "ADMIN MASTER KEY (Registration Token)"
echo "Master Key: $MASTER_TOKEN"
echo "Use this token in the 'Registration Token' field when signing up."
echo "================================================================="

echo "Starting Conduit Server..."

# Create conduit config file (required by v0.10.12+)
mkdir -p /etc/conduit
cat > /etc/conduit/conduit.toml << EOF
[global]
server_name = "${CONDUIT_SERVER_NAME}"
database_path = "/var/lib/matrix-conduit/"
database_backend = "sqlite"
port = 6167
address = "127.0.0.1"
allow_registration = true
registration_token = "${MASTER_TOKEN}"
allow_federation = false
max_request_size = 20000000
trusted_servers = ["matrix.org"]
EOF

export CONDUIT_CONFIG="/etc/conduit/conduit.toml"

# Run conduit in background, redirect stderr to stdout for logging
/usr/local/bin/conduit &
CONDUIT_PID=$!

# Wait a moment for conduit to start
sleep 2

# Check if conduit is still running
if ! kill -0 $CONDUIT_PID 2>/dev/null; then
  echo "ERROR: Conduit failed to start! Check logs above."
  exit 1
fi

echo "Conduit is running (PID: $CONDUIT_PID)"
echo "Starting Nginx Proxy & Web Client..."
# Run Nginx in foreground
nginx -g "daemon off;"
