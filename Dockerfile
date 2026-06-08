FROM debian:bullseye-slim

# Install necessary packages: Tor, Nginx, Supervisor, Curl, and certificates
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    tor \
    nginx \
    supervisor \
    curl \
    ca-certificates \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Download and install pre-built Conduit (x86_64 linux)
RUN curl -L -o /usr/local/bin/conduit https://gitlab.com/famedly/conduit/-/releases/v0.11.0-alpha/downloads/x86_64-unknown-linux-musl \
    && chmod +x /usr/local/bin/conduit

# Setup Element Web
COPY element/ /var/www/element/
RUN chown -R www-data:www-data /var/www/element

# Copy configurations
COPY nginx.conf /etc/nginx/nginx.conf
COPY torrc /etc/tor/torrc
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Default environment variables
ENV PORT=10000

# Start via entrypoint
ENTRYPOINT ["/entrypoint.sh"]
