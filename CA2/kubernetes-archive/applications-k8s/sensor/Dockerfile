# Use official Node.js runtime as parent image
FROM node:18-alpine

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Copy application code
COPY sensor.js .

# Create non-root user for security
RUN addgroup -g 1001 -S sensor && \
    adduser -S sensor -u 1001

# Change ownership to sensor user
RUN chown -R sensor:sensor /app
USER sensor

# Expose health check port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Command to run the application
CMD ["npm", "start"]