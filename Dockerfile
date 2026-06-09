# ============================================================
# Stage 1: Build Conduit from source with default features
# ============================================================
FROM docker.io/rust:alpine AS builder

# Build deps: musl, clang for rocksdb, git
RUN apk add --no-cache musl-dev git clang llvm-dev pkgconfig openssl-dev openssl-libs-static cmake g++ lz4-dev zstd-dev

# Clone specific stable release
RUN git clone --depth 1 --branch v0.10.12 \
    https://gitlab.com/famedly/conduit.git /build

WORKDIR /build

# Cache bust to force recompile (change this value to rebuild)
ARG CACHEBUST=3

# Build with DEFAULT features (includes backend_rocksdb + backend_sqlite + conduit_bin)
# This ensures all backends are compiled in
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
ENV LIBCLANG_PATH=/usr/lib/llvm19/lib
RUN cargo build --release \
    --features="conduit_bin,backend_rocksdb,backend_sqlite"

# ============================================================
# Stage 2: Final Image — nginx:alpine + Conduit binary
# ============================================================
FROM docker.io/nginx:alpine

# Install runtime dependencies
RUN apk add --no-cache supervisor sed ca-certificates lz4-libs zstd-libs

# Copy the compiled Conduit binary from builder
COPY --from=builder /build/target/release/conduit /usr/local/bin/conduit
RUN chmod +x /usr/local/bin/conduit

# Remove default nginx config
RUN rm -f /etc/nginx/conf.d/default.conf

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

CMD ["/start.sh"]
