FROM node:18-alpine

WORKDIR /usr/src/app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application source
COPY . .

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs && \
    adduser -S sensor -u 1001 -G nodejs

# Change ownership to non-root user
RUN chown -R sensor:nodejs /usr/src/app
USER sensor

CMD ["npm", "start"]