# Trading Engine Service
FROM node:18-alpine

LABEL maintainer="Energrid DevOps <devops@energrid.com>"
LABEL service="trading-engine"
LABEL version="1.0.0"

# Create app directory
WORKDIR /app

# Install system dependencies
RUN apk add --no-cache \
    curl \
    git \
    python3 \
    make \
    g++ \
    && rm -rf /var/cache/apk/*

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy application code
COPY src/ ./src/
COPY config/ ./config/

# Create non-root user
RUN addgroup -g 1001 -S energrid && \
    adduser -S energrid -u 1001 -G energrid

# Change ownership
RUN chown -R energrid:energrid /app
USER energrid

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1

# Expose port
EXPOSE 8080

# Start the application
CMD ["node", "src/index.js"]
