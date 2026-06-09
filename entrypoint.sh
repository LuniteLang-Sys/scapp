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
chown -R www-data:www-data "$CONDUIT_DB"

if [ ! -f "$DATA_DIR/conduit_token" ]; then
    cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1 > "$DATA_DIR/conduit_token"
fi

mkdir -p /etc/matrix-conduit
chown -R www-data:www-data /etc/matrix-conduit

echo "Starting Nginx, Tor, and Conduit via supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
