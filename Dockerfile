# ============================================================
# Stage 1: Build Conduit from source - SQLITE ONLY (no rocksdb)
# sqlite uses bundled rusqlite (pure C, no libclang needed)
# ============================================================
FROM docker.io/rust:alpine AS builder

# Only need basic C compiler (for sqlite bundled build), no libclang/llvm
RUN apk add --no-cache musl-dev git pkgconfig openssl-dev openssl-libs-static

# Clone specific stable release
RUN git clone --depth 1 --branch v0.10.12 \
    https://gitlab.com/famedly/conduit.git /build

WORKDIR /build

# Cache bust to force recompile
ARG CACHEBUST=4

# Build with ONLY sqlite backend (no rocksdb = no libclang dependency)
# backend_sqlite -> sqlite -> rusqlite (bundled, compiles from C source)
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
RUN cargo build --release \
    --no-default-features \
    --features="conduit_bin,backend_sqlite"

# ============================================================
# Stage 2: Final Image — nginx:alpine + Conduit binary
# ============================================================
FROM docker.io/nginx:alpine

# Install runtime dependencies
RUN apk add --no-cache supervisor sed ca-certificates

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
