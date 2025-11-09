#!/bin/bash

# Deployment script for Solidity contracts
# This script deploys MockVRFV2PlusWrapper, ERC20Example, and VrfConsumer contracts
# and configures them for integration.

set -e  # Exit on error

# Configuration
RPC_URL=${RPC_URL:-http://127.0.0.1:8547}
PRIVATE_KEY=${PRIVATE_KEY:-0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659}
OWNER_ADDRESS=$(cast wallet address $PRIVATE_KEY)
ABI_DIR="deployments/abis"
DEPLOYMENT_DIR="deployments"

# Token parameters
TOKEN_NAME="LotteryToken"
TOKEN_SYMBOL="LUK"
TOKEN_CAP="1000000000000000000000000"  # 1M tokens with 10 decimals

# VRF Mock parameters
VRF_REQUEST_PRICE="1000000000000000"  # 0.001 ether

echo "=========================================="
echo "Deploying Solidity Contracts"
echo "=========================================="
echo "RPC URL: $RPC_URL"
echo "Owner: $OWNER_ADDRESS"
echo ""

# Navigate to solidity directory
cd "$(dirname "$0")/.."

# Build contracts
echo "📦 Building contracts..."
forge build
echo "✅ Build complete"
echo ""

# Create deployment directories
mkdir -p $ABI_DIR
mkdir -p $DEPLOYMENT_DIR

# Deploy Mock VRF Wrapper
echo "🚀 Deploying MockVRFV2PlusWrapper..."
MOCK_VRF_OUTPUT=$(forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --broadcast \
  test/mocks/MockVRFV2PlusWrapper.sol:MockVRFV2PlusWrapper \
  --constructor-args $VRF_REQUEST_PRICE)

MOCK_VRF=$(echo "$MOCK_VRF_OUTPUT" | grep "Deployed to:" | awk '{print $3}')

if [ -z "$MOCK_VRF" ]; then
  echo "❌ Failed to deploy MockVRFV2PlusWrapper"
  echo "$MOCK_VRF_OUTPUT"
  exit 1
fi

echo "✅ MockVRFV2PlusWrapper deployed at: $MOCK_VRF"

# Export Mock VRF ABI
forge inspect test/mocks/MockVRFV2PlusWrapper.sol:MockVRFV2PlusWrapper abi > $ABI_DIR/MockVRFV2PlusWrapper.json
echo "✅ Exported MockVRFV2PlusWrapper ABI"
echo ""

# Deploy ERC20Example
echo "🚀 Deploying ERC20Example..."
ERC20_OUTPUT=$(forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --broadcast \
  contracts/ERC20Example.sol:ERC20Example \
  --constructor-args "$TOKEN_NAME" "$TOKEN_SYMBOL" $TOKEN_CAP $OWNER_ADDRESS)

ERC20=$(echo "$ERC20_OUTPUT" | grep "Deployed to:" | awk '{print $3}')

if [ -z "$ERC20" ]; then
  echo "❌ Failed to deploy ERC20Example"
  echo "$ERC20_OUTPUT"
  exit 1
fi

echo "✅ ERC20Example deployed at: $ERC20"

# Export ERC20 ABI
forge inspect contracts/ERC20Example.sol:ERC20Example abi > $ABI_DIR/ERC20Example.json
echo "✅ Exported ERC20Example ABI"
echo ""

# Deploy VrfConsumer
echo "🚀 Deploying VrfConsumer..."
VRF_OUTPUT=$(forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --broadcast \
  contracts/VrfConsumer.sol:VrfConsumer \
  --constructor-args $MOCK_VRF $OWNER_ADDRESS)

VRF=$(echo "$VRF_OUTPUT" | grep "Deployed to:" | awk '{print $3}')

if [ -z "$VRF" ]; then
  echo "❌ Failed to deploy VrfConsumer"
  echo "$VRF_OUTPUT"
  exit 1
fi

echo "✅ VrfConsumer deployed at: $VRF"

# Export VrfConsumer ABI
forge inspect contracts/VrfConsumer.sol:VrfConsumer abi > $ABI_DIR/VrfConsumer.json
echo "✅ Exported VrfConsumer ABI"
echo ""

# Configure contracts
echo "⚙️  Configuring contracts..."

# Set VrfConsumer as authorized minter in ERC20
echo "  Setting VrfConsumer as authorized minter..."
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $ERC20 "setAuthorizedMinter(address)" $VRF > /dev/null
echo "  ✅ Authorized minter set"

# Set ERC20 token address in VrfConsumer
echo "  Setting ERC20 token address in VrfConsumer..."
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $VRF "setErc20Token(address)" $ERC20 > /dev/null
echo "  ✅ ERC20 token address set"
echo ""

# Save deployment info
DEPLOYMENT_INFO="$DEPLOYMENT_DIR/deployment_info.json"
cat > $DEPLOYMENT_INFO <<EOF
{
  "chainId": "local",
  "rpcUrl": "$RPC_URL",
  "deployer": "$OWNER_ADDRESS",
  "deployedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "contracts": {
    "MockVRFV2PlusWrapper": {
      "address": "$MOCK_VRF",
      "abi": "$ABI_DIR/MockVRFV2PlusWrapper.json"
    },
    "ERC20Example": {
      "address": "$ERC20",
      "abi": "$ABI_DIR/ERC20Example.json",
      "name": "$TOKEN_NAME",
      "symbol": "$TOKEN_SYMBOL",
      "cap": "$TOKEN_CAP"
    },
    "VrfConsumer": {
      "address": "$VRF",
      "abi": "$ABI_DIR/VrfConsumer.json"
    }
  }
}
EOF

echo "=========================================="
echo "✅ Deployment Complete!"
echo "=========================================="
echo ""
echo "Contract Addresses:"
echo "  MockVRFV2PlusWrapper: $MOCK_VRF"
echo "  ERC20Example:          $ERC20"
echo "  VrfConsumer:          $VRF"
echo ""
echo "Files:"
echo "  Deployment info: $DEPLOYMENT_INFO"
echo "  ABIs:           $ABI_DIR/"
echo ""
echo "Next steps:"
echo "  1. Use the addresses above to interact with contracts"
echo "  2. See scripts/test.sh for testing examples"
echo "  3. ABIs are available in $ABI_DIR/"
echo ""

