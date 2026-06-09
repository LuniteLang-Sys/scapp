# Use the official Conduit image as base (it's Alpine-based)
# and add nginx + supervisor on top of it
FROM docker.io/matrixconduit/matrix-conduit:latest

USER root

# Install nginx and supervisor (conduit image is Alpine-based)
RUN apk add --no-cache nginx supervisor sed

# Create nginx directories
RUN mkdir -p /run/nginx /var/log/nginx /var/lib/nginx/tmp

# Remove default nginx config
RUN rm -f /etc/nginx/http.d/default.conf /etc/nginx/conf.d/default.conf

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

# Override conduit's default entrypoint
ENTRYPOINT []
CMD ["/start.sh"]
