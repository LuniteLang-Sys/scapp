# Single stage: nginx:alpine as base, download conduit binary from GitHub releases
FROM docker.io/nginx:alpine

# Install dependencies: curl (to download conduit), ca-certificates, and supervisor
RUN apk add --no-cache curl ca-certificates supervisor sed

# Download the conduit binary directly from GitHub releases (pre-compiled for musl/alpine)
RUN curl -fSL \
    "https://gitlab.com/famedly/conduit/-/releases/permalink/latest/downloads/conduit-x86_64-unknown-linux-musl" \
    -o /usr/local/bin/conduit && \
    chmod +x /usr/local/bin/conduit

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our custom nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy Element static web client into Nginx web root
COPY element /var/www/element

# Set proper permissions
RUN chown -R nginx:nginx /var/www/element

# Copy supervisord config
COPY supervisord.conf /etc/supervisord.conf

# Copy startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose the port Nginx is listening on
EXPOSE 10000

# Start everything
CMD ["/start.sh"]
