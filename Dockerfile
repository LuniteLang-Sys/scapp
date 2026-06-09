# Stage 1: Get Conduit binary from official image
FROM docker.io/matrixconduit/matrix-conduit:latest AS conduit-builder

# Stage 2: Final Image with Nginx + Conduit + Element
FROM docker.io/nginx:alpine

# Install dependencies
RUN apk add --no-cache supervisor sed

# Copy Conduit binary from official image
# Binary is at /srv/conduit/conduit per official Dockerfile
COPY --from=conduit-builder /srv/conduit/conduit /usr/local/bin/conduit
RUN chmod +x /usr/local/bin/conduit

# Remove default nginx config
RUN rm /etc/nginx/conf.d/default.conf

# Copy our custom nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy Element static web client into Nginx web root
COPY element /var/www/element

# Set proper permissions
RUN chown -R nginx:nginx /var/www/element

# Copy startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose the port Nginx is listening on
EXPOSE 10000

# Start everything
CMD ["/start.sh"]
