#!/bin/bash
# WireGuard VPN Key Generation Script for CA4
# Generates public/private key pairs for cloud and edge sites

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/keys"

echo "════════════════════════════════════════════════════════"
echo "  WireGuard VPN Key Generation for CA4"
echo "════════════════════════════════════════════════════════"
echo ""

# Check if WireGuard is installed
if ! command -v wg &> /dev/null; then
    echo "❌ ERROR: WireGuard not installed"
    echo ""
    echo "Install WireGuard:"
    echo "  Ubuntu/Debian: sudo apt install wireguard"
    echo "  macOS:         brew install wireguard-tools"
    exit 1
fi

echo "✅ WireGuard tools found"
echo ""

# Create keys directory
mkdir -p "${KEYS_DIR}"
chmod 700 "${KEYS_DIR}"

echo "Generating keys in: ${KEYS_DIR}"
echo ""

# Generate Cloud (AWS Manager) keys
echo "1. Generating Cloud VPN Gateway keys..."
wg genkey | tee "${KEYS_DIR}/cloud-private.key" | wg pubkey > "${KEYS_DIR}/cloud-public.key"
chmod 600 "${KEYS_DIR}/cloud-private.key"
chmod 644 "${KEYS_DIR}/cloud-public.key"
echo "   ✅ Cloud keys generated"

# Generate Edge (Local) keys
echo "2. Generating Edge VPN Client keys..."
wg genkey | tee "${KEYS_DIR}/edge-private.key" | wg pubkey > "${KEYS_DIR}/edge-public.key"
chmod 600 "${KEYS_DIR}/edge-private.key"
chmod 644 "${KEYS_DIR}/edge-public.key"
echo "   ✅ Edge keys generated"

echo ""
echo "════════════════════════════════════════════════════════"
echo "  Keys Generated Successfully"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Cloud (AWS Manager) Keys:"
echo "  Private: ${KEYS_DIR}/cloud-private.key"
echo "  Public:  ${KEYS_DIR}/cloud-public.key"
echo ""
echo "Edge (Local) Keys:"
echo "  Private: ${KEYS_DIR}/edge-private.key"
echo "  Public:  ${KEYS_DIR}/edge-public.key"
echo ""
echo "📝 Key Contents:"
echo "────────────────────────────────────────────────────────"
echo ""
echo "Cloud Public Key (share with edge):"
cat "${KEYS_DIR}/cloud-public.key"
echo ""
echo "Edge Public Key (share with cloud):"
cat "${KEYS_DIR}/edge-public.key"
echo ""
echo "════════════════════════════════════════════════════════"
echo ""
echo "⚠️  SECURITY NOTICE:"
echo "  - Private keys are sensitive! Keep them secure."
echo "  - Added to .gitignore (keys/ directory)"
echo "  - Share only PUBLIC keys between sites"
echo ""
echo "Next Steps:"
echo "  1. Note the public keys above"
echo "  2. Run: ./setup-vpn.sh <AWS_MANAGER_IP>"
echo "  3. This will generate config files with these keys"
echo ""
