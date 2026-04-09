# Stage 1: Build Rust binaries (ralph-api + ralph CLI)
FROM rust:1.83-slim AS rust-builder
RUN apt-get update && apt-get install -y \
    pkg-config libssl-dev git curl \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/mikeyobrien/ralph-orchestrator /app
WORKDIR /app
# Build both the API server and the CLI (api calls CLI to run loops)
RUN cargo build --release -p ralph-api -p ralph-cli

# Stage 2: Build React frontend (static files only)
FROM node:20-alpine AS frontend-builder
RUN apk add --no-cache git
RUN git clone --depth 1 https://github.com/mikeyobrien/ralph-orchestrator /app
WORKDIR /app
# Install all workspace deps (needed for @ralph-web/dashboard build)
RUN npm install
RUN npm run build:web

# Stage 3: Runtime image
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y \
    nginx supervisor git curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Rust binaries
COPY --from=rust-builder /app/target/release/ralph-api /usr/local/bin/ralph-api
COPY --from=rust-builder /app/target/release/ralph    /usr/local/bin/ralph

# React frontend static files
COPY --from=frontend-builder /app/frontend/ralph-web/dist /srv/ralph-web

# Configs
COPY nginx.conf /etc/nginx/sites-available/default
COPY supervisord.conf /etc/supervisor/conf.d/ralph.conf

# Persistent dirs: workspace (ralph loop files) and state (~/.ralph)
RUN mkdir -p /workspace /root/.ralph /var/log/supervisor

# Remove default nginx config
RUN rm -f /etc/nginx/sites-enabled/default && \
    ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default

WORKDIR /workspace
EXPOSE 80
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/conf.d/ralph.conf"]
