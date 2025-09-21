#!/bin/bash

# Make deployment scripts executable
echo "Making deployment scripts executable..."
chmod +x deploy.sh
chmod +x check_health.sh

echo "✅ Scripts are now executable!"
echo ""
echo "🚀 Ready for deployment! Run one of these commands:"
echo "   ./deploy.sh           # Complete infrastructure + applications"
echo "   ./check_health.sh     # Health check only"
echo ""
echo "📖 See README.md for detailed instructions and troubleshooting."