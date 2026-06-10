# ============================================================
# Stage 1: Build Conduit from source - RocksDB backend
# RocksDB is the default & most stable backend for Conduit
# ============================================================
FROM docker.io/rust:alpine AS builder

# Need clang/llvm for RocksDB bindgen, plus standard build tools
RUN apk add --no-cache \
    musl-dev git pkgconfig \
    openssl-dev openssl-libs-static \
    clang-dev llvm-dev \
    cmake g++ make

# Clone specific stable release
RUN git clone --depth 1 --branch v0.10.12 \
    https://gitlab.com/famedly/conduit.git /build

WORKDIR /build

# Cache bust to force recompile
ARG CACHEBUST=5

# Build with RocksDB backend (default, stable, no runtime config issues)
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
ENV LIBCLANG_PATH=/usr/lib/llvm17/lib
RUN cargo build --release \
    --no-default-features \
    --features="conduit_bin,backend_rocksdb"

# ============================================================
# Stage 2: Final Image — nginx:alpine + Conduit binary
# ============================================================
FROM docker.io/nginx:alpine

# Install runtime dependencies (libgcc/libstdc++ needed for RocksDB at runtime)
RUN apk add --no-cache supervisor sed ca-certificates libgcc libstdc++

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
