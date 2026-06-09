<<<<<<< Updated upstream
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
    procps \
    && rm -rf /var/lib/apt/lists/*

# Download and install pre-built Conduit (x86_64 linux)
RUN curl -L -o /usr/local/bin/conduit "https://gitlab.com/api/v4/projects/famedly%2Fconduit/jobs/artifacts/next/raw/x86_64-unknown-linux-musl?job=artifacts" \
    && chmod +x /usr/local/bin/conduit

# Setup Element Web
COPY element/ /var/www/element/
RUN chown -R www-data:www-data /var/www/element

# Copy configurations
COPY nginx.conf /etc/nginx/nginx.conf
COPY torrc /etc/tor/torrc
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Copy entrypoint and start scripts
COPY entrypoint.sh /entrypoint.sh
COPY start-conduit.sh /start-conduit.sh
RUN chmod +x /entrypoint.sh /start-conduit.sh

# Default environment variables
ENV PORT=10000

# Start via entrypoint
ENTRYPOINT ["/entrypoint.sh"]
=======
# Stage 1: Extract Conduit Binary
FROM docker.io/matrixconduit/matrix-conduit:latest AS conduit-builder
# The official conduit image has the binary at /conduit or /usr/local/bin/conduit depending on version.
# Usually it's at /

# Stage 2: Final Image with Nginx + Conduit + Element
FROM docker.io/nginx:alpine

# Copy Conduit binary
# The latest conduit image uses /conduit as the binary path
COPY --from=conduit-builder /conduit /usr/local/bin/conduit

# Install dependencies if needed (nginx:alpine has basic tools)
RUN apk add --no-cache curl sed

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our custom nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy Element static web client into Nginx web root
COPY element /var/www/element

# Set proper permissions
RUN chown -R nginx:nginx /var/www/element && \
    chmod +x /usr/local/bin/conduit

# Copy startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose the port Nginx is listening on
EXPOSE 10000

# Start everything
CMD ["/start.sh"]
>>>>>>> Stashed changes
