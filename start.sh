#!/bin/sh

# If we are running on Render, RENDER_EXTERNAL_HOSTNAME will be populated automatically
if [ -n "$RENDER_EXTERNAL_HOSTNAME" ]; then
  echo "Detected Render environment. Setting domain to $RENDER_EXTERNAL_HOSTNAME"
  export CONDUIT_SERVER_NAME="$RENDER_EXTERNAL_HOSTNAME"

  # Dynamically patch Element's config.json with the actual domain
  sed -i "s|https://matrix.example.com|https://$RENDER_EXTERNAL_HOSTNAME|g" /var/www/element/config.json
  sed -i "s|matrix.example.com|$RENDER_EXTERNAL_HOSTNAME|g" /var/www/element/config.json

  # Dynamically generate .well-known discovery files (Removed Identity Server for Privacy)
  mkdir -p /var/www/element/.well-known/matrix
  echo "{\"m.homeserver\": {\"base_url\": \"https://$RENDER_EXTERNAL_HOSTNAME\"}}" > /var/www/element/.well-known/matrix/client
  echo "{\"m.server\": \"$RENDER_EXTERNAL_HOSTNAME:443\"}" > /var/www/element/.well-known/matrix/server
else
  export CONDUIT_SERVER_NAME="localhost"
fi

# Ensure database directory exists
mkdir -p /var/lib/matrix-conduit/

# Configure Conduit to listen only on localhost for security
export CONDUIT_ADDRESS="127.0.0.1"
export CONDUIT_PORT=6167
export CONDUIT_DATABASE_PATH="/var/lib/matrix-conduit/"

# ---------------------------------------------------------
# ULTRA SECRET ADMIN MASTER KEY GENERATION
# ---------------------------------------------------------
if [ ! -f /var/lib/matrix-conduit/master_token.txt ]; then
  # Generate a 32-character random alphanumeric string
  cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1 > /var/lib/matrix-conduit/master_token.txt
fi

MASTER_TOKEN=$(cat /var/lib/matrix-conduit/master_token.txt)

echo "================================================================="
echo "🚨 BÍ MẬT QUỐC GIA - ADMIN MASTER KEY CỦA BẠN 🚨"
echo "Chỉ có người ấn nút Deploy trên Render mới được thấy dòng này!"
echo "Master Key: $MASTER_TOKEN"
echo "Hãy dùng Key này dán vào ô 'Registration Token' khi đăng ký."
echo "Tài khoản đầu tiên đăng ký thành công sẽ trở thành ADMIN."
echo "================================================================="

export CONDUIT_REGISTRATION_TOKEN="$MASTER_TOKEN"
export CONDUIT_ALLOW_REGISTRATION="false" 
export CONDUIT_ALLOW_FEDERATION="false"

echo "Starting Conduit Server..."
# Run conduit in background
/usr/local/bin/conduit &

echo "Starting Nginx Proxy & Web Client..."
# Run Nginx in foreground
nginx -g "daemon off;"
