# SCApp - Secure Chat App

A self-hosted, privacy-focused Matrix homeserver stack.

## Architecture

This project provides a Matrix communication stack comprising:
1. **Conduit:** A lightweight, high-performance Matrix homeserver written in Rust.
2. **Element:** A feature-rich Matrix web client.
3. **Infrastructure:** Orchestrated via `docker-compose` with Nginx as a reverse proxy, providing basic security and onion service support.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/)
- [Docker Compose](https://docs.docker.com/compose/install/)

## Quick Start (Recommended)

To run the entire stack:

```bash
# Clone the repository
git clone <your-repository-url>
cd scapp

# Start the services
docker-compose up -d
```

## Data Persistence

The stack uses Docker volumes to ensure data persists across container restarts:
- `./conduit_db`: Database storage for Conduit.
- `./config`: Configuration files for Conduit.

Ensure these directories exist and are writable by the container user.

## Security & Maintenance

- The server automatically generates a `.onion` address upon first startup if configured in `torrc`.
- Logs can be viewed via `docker-compose logs -f`.
- To update, pull the latest image and restart: `docker-compose pull && docker-compose up -d --build`.
- **SSL Certificates:** To initialize Let's Encrypt SSL certificates (once you have a domain), run:
  ```bash
  docker-compose run --rm certbot certonly --webroot --webroot-path=/var/www/certbot -d yourdomain.com
  ```
  Then, add the corresponding SSL configuration to your `nginx.conf` and restart Nginx.

---
*For manual development or specific configurations, refer to the individual service directories.*
