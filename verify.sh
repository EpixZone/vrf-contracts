#!/bin/bash
# Verify a deployed contract on Blockscout (Epix Testnet)
#
# Usage:
#   ./verify.sh <contract_address> <contract_name>
#
# Examples:
#   ./verify.sh 0xD0793a2a11Fa3600Ec941115937FB8E259cfdbf1 VRFCoinFlip
#   ./verify.sh 0x1234...abcd MyContract
#
# Requires: forge, curl, jq (optional, for pretty output)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Load .env if present
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

# Args
CONTRACT_ADDR="${1:-}"
CONTRACT_NAME="${2:-}"

if [[ -z "$CONTRACT_ADDR" || -z "$CONTRACT_NAME" ]]; then
    echo "Usage: $0 <contract_address> <contract_name>"
    echo "Example: $0 0xD0793a2a11Fa3600Ec941115937FB8E259cfdbf1 VRFCoinFlip"
    exit 1
fi

# Explorer URL — strip trailing slash, ensure https
EXPLORER="${EXPLORER_URL:-https://scan.epix.zone}"
EXPLORER="${EXPLORER%/}"
EXPLORER="${EXPLORER/http:/https:}"

echo "==> Building standard JSON input for $CONTRACT_NAME..."

# Build the project first to ensure artifacts are fresh
cd "$SCRIPT_DIR"
forge build --force --silent

# Generate standard JSON input
TMPFILE=$(mktemp /tmp/verify_input_XXXXXX.json)
forge verify-contract "$CONTRACT_ADDR" "src/${CONTRACT_NAME}.sol:${CONTRACT_NAME}" \
    --show-standard-json-input > "$TMPFILE" 2>/dev/null

echo "==> Submitting to Blockscout at $EXPLORER..."
echo "    Contract: $CONTRACT_ADDR"
echo "    Name: $CONTRACT_NAME"
echo ""

# Submit via Blockscout v2 API
RESPONSE=$(curl -s -X POST \
    "${EXPLORER}/api/v2/smart-contracts/${CONTRACT_ADDR}/verification/via/standard-input" \
    -F "compiler_version=v0.8.24+commit.e11b9ed9" \
    -F "license_type=mit" \
    -F "files[0]=@${TMPFILE};type=application/json")

rm -f "$TMPFILE"

# Check result
if command -v jq &>/dev/null; then
    VERIFIED=$(echo "$RESPONSE" | jq -r '.is_verified // empty' 2>/dev/null)
    if [[ "$VERIFIED" == "true" ]]; then
        echo "==> Verified successfully!"
        echo "$RESPONSE" | jq '{is_verified, is_fully_verified, name, compiler_version, verified_at}'
    else
        echo "==> Verification response:"
        echo "$RESPONSE" | jq . 2>/dev/null || echo "$RESPONSE"
    fi
else
    echo "==> Response (install jq for prettier output):"
    echo "$RESPONSE"
fi

echo ""
echo "    View: ${EXPLORER}/address/${CONTRACT_ADDR}"
