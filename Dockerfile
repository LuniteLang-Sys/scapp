# ============================================================
# Stage 1: Build Conduit from source - RocksDB backend
# RocksDB is the default & most stable backend for Conduit
# NOTE: Using Debian (bookworm) instead of Alpine because Alpine's
# musl libc does NOT support dynamic loading (dlopen), which causes
# bindgen/libclang to fail with "Dynamic loading not supported".
# ============================================================
FROM docker.io/rust:slim-bookworm AS builder

# Install build dependencies — Debian/glibc supports dynamic loading properly
RUN apt-get update && apt-get install -y --no-install-recommends \
    git pkg-config \
    clang libclang-dev llvm-dev \
    libssl-dev \
    libzstd-dev \
    cmake g++ make ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Clone specific stable release
RUN git clone --depth 1 --branch v0.10.12 \
    https://gitlab.com/famedly/conduit.git /build

WORKDIR /build

# Cache bust to force recompile
ARG CACHEBUST=6

ENV CARGO_NET_GIT_FETCH_WITH_CLI=true

# Locate libclang — Debian ships it under /usr/lib/llvm-*/lib/
RUN LIBCLANG_PATH=$(dirname $(find /usr/lib/llvm-* -name 'libclang.so*' -print -quit 2>/dev/null)) \
    && echo "Found libclang at: $LIBCLANG_PATH" \
    && export LIBCLANG_PATH \
    && cargo build --release \
        --no-default-features \
        --features="conduit_bin,backend_rocksdb"

# ============================================================
# Stage 2: Final Image — nginx:bookworm-slim + Conduit binary
# NOTE: Must use Debian here too — binary is compiled against glibc
# (from rust:bookworm-slim builder), it will NOT run on Alpine/musl.
# ============================================================
FROM docker.io/nginx:bookworm

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor sed ca-certificates libgcc-s1 libstdc++6 \
    tor jq procps psmisc \
    && rm -rf /var/lib/apt/lists/*

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
RUN chown -R www-data:www-data /var/www/element

# Copy startup script
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose the port Nginx is listening on
EXPOSE 10000

CMD ["/start.sh"]
