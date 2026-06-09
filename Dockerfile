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
