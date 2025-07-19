# Blockchain Node Service
FROM node:18-alpine

LABEL maintainer="Energrid DevOps <devops@energrid.com>"
LABEL service="blockchain-node"
LABEL version="1.0.0"

# Create app directory
WORKDIR /app

# Install system dependencies for blockchain operations
RUN apk add --no-cache \
    curl \
    git \
    python3 \
    make \
    g++ \
    openssl \
    ca-certificates \
    && rm -rf /var/cache/apk/*

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy application code
COPY src/ ./src/
COPY config/ ./config/
COPY contracts/ ./contracts/

# Create non-root user
RUN addgroup -g 1001 -S energrid && \
    adduser -S energrid -u 1001 -G energrid

# Create data directory for blockchain data
RUN mkdir -p /app/data && chown -R energrid:energrid /app
USER energrid

# Health check for blockchain connectivity
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Expose ports
EXPOSE 8080 8545

# Start the blockchain node service
CMD ["node", "src/blockchain-node.js"]
