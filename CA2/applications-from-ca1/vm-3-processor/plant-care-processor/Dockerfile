FROM node:18-alpine

WORKDIR /usr/src/app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --omit=dev

# Copy application source
COPY . .

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S processor -u 1001 -G nodejs

# Change ownership to non-root user
RUN chown -R processor:nodejs /usr/src/app
USER processor

EXPOSE 8080

CMD ["npm", "start"]