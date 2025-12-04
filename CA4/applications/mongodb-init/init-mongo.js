// MongoDB initialization script
// Creates application user for plant monitoring system

print('========================================');
print('Starting MongoDB initialization...');
print('========================================');

// Switch to the admin database to create user (required for authSource=admin)
db = db.getSiblingDB('admin');

// Read credentials from environment variables set by Docker secrets
// MongoDB's docker-entrypoint.sh sets env vars for _FILE secrets
const appUsername = 'plant_app';  // Fixed username matching the secret
const appPassword = process.env.MONGO_APP_PASSWORD || 'changeme';  // Will be set from secret file

// Read from secret files using Node.js fs module (available in mongosh)
try {
  const fs = require('fs');
  const appUsernameFromFile = fs.readFileSync('/run/secrets/mongo_app_username', 'utf8').trim();
  const appPasswordFromFile = fs.readFileSync('/run/secrets/mongo_app_password', 'utf8').trim();
  
  print('Creating application user: ' + appUsernameFromFile);

  // Create the application user with read/write permissions on plant_monitoring database
  db.createUser({
    user: appUsernameFromFile,
    pwd: appPasswordFromFile,
    roles: [
      {
        role: 'readWrite',
        db: 'plant_monitoring'
      }
    ]
  });

  print('✅ Application user created successfully');
} catch (e) {
  print('❌ Error creating user: ' + e.message);
  print('Stack: ' + e.stack);
}

print('========================================');
print('MongoDB initialization complete');
print('========================================');
