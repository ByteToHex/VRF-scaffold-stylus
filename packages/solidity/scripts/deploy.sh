#!/bin/bash

# Deployment script for Solidity contracts
# This script deploys MockVRFV2PlusWrapper, ERC20Example, and VrfConsumer contracts
# and configures them for integration.

set -e  # Exit on error

# Function to load .env file
load_env_file() {
  local env_file="$1"
  if [ -f "$env_file" ]; then
    echo "📋 Loading environment variables from .env file..."
    # Export variables from .env file, ignoring comments and empty lines
    while IFS= read -r line || [ -n "$line" ]; do
      # Skip comments and empty lines
      [[ "$line" =~ ^[[:space:]]*# ]] && continue
      [[ -z "${line// }" ]] && continue
      # Export the variable if it's in KEY=VALUE format
      if [[ "$line" =~ ^[[:space:]]*([^#=]+)=(.*)$ ]]; then
        local key="${line%%=*}"
        local value="${line#*=}"
        # Remove leading/trailing whitespace from key
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        # Remove quotes from value if present
        value="${value#\"}"
        value="${value%\"}"
        value="${value#\'}"
        value="${value%\'}"
        # Only export if key is not empty
        if [ -n "$key" ]; then
          export "$key"="$value"
        fi
      fi
    done < "$env_file"
    echo "✅ Environment variables loaded"
  fi
}

# Check if we're explicitly on a local node (check RPC_URL from environment)
# If RPC_URL is explicitly set to localhost, skip .env loading
# Otherwise, we'll try to load .env and check again
IS_LOCAL_NODE=false
CURRENT_RPC_URL="${RPC_URL:-}"
if [[ -n "$CURRENT_RPC_URL" ]] && \
   ([[ "$CURRENT_RPC_URL" == *"127.0.0.1:8547"* ]] || \
    [[ "$CURRENT_RPC_URL" == *"localhost"* ]]); then
  IS_LOCAL_NODE=true
fi

# Load .env file ONLY if not explicitly on local node
if [ "$IS_LOCAL_NODE" = false ]; then
  # Navigate to script directory first to establish base path
  SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
  
  # Try to find .env file in multiple locations
  ENV_FILE=""
  
  # 1. Check in project root (workspace root)
  if [ -f "$SCRIPT_DIR/../../.env" ]; then
    ENV_FILE="$SCRIPT_DIR/../../.env"
  # 2. Check in packages/solidity directory
  elif [ -f "$SCRIPT_DIR/.env" ]; then
    ENV_FILE="$SCRIPT_DIR/.env"
  # 3. Check in current directory
  elif [ -f ".env" ]; then
    ENV_FILE=".env"
  fi
  
  # Load .env if found
  if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
    load_env_file "$ENV_FILE"
    echo ""
  else
    echo "ℹ️  No .env file found, using environment variables and defaults"
    echo ""
  fi
else
  echo "ℹ️  Local node detected, skipping .env file loading"
  echo ""
fi

# Configuration (after .env loading so env vars can override defaults)
# Check again if RPC_URL is now pointing to localhost (might have been set in .env)
if [[ -n "${RPC_URL:-}" ]] && \
   ([[ "$RPC_URL" == *"127.0.0.1:8547"* ]] || [[ "$RPC_URL" == *"localhost"* ]]); then
  echo "ℹ️  RPC_URL points to localhost, using local node configuration"
fi

RPC_URL=${RPC_URL:-http://127.0.0.1:8547}
PRIVATE_KEY=${PRIVATE_KEY:-0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659}
OWNER_ADDRESS=$(cast wallet address $PRIVATE_KEY)
ABI_DIR="../stylus/deployments/abis"
DEPLOYMENT_DIR="../stylus/deployments"

# Get chain ID (use CHAIN_ID env var if set, otherwise query from RPC)
# For local network, use 412346 (Arbitrum Nitro DevNode)
if [ -z "$CHAIN_ID" ]; then
  if [[ "$RPC_URL" == *"127.0.0.1:8547"* ]] || [[ "$RPC_URL" == *"localhost"* ]]; then
    CHAIN_ID="412346"
    echo "ℹ️  Using chain ID 412346 for local network"
  else
    CHAIN_ID=$(cast chain-id --rpc-url $RPC_URL 2>/dev/null || echo "421614")
    if [ -z "$CHAIN_ID" ]; then
      echo "⚠️  Could not determine chain ID, defaulting to 421614 (Arbitrum Sepolia)"
      CHAIN_ID="421614"
    fi
  fi
fi

# Path to update script
UPDATE_SCRIPT="scripts/update_deployed_contracts.js"

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

# Determine VRF wrapper address based on network
if [[ "$RPC_URL" == *"127.0.0.1:8547"* ]]; then
  # Local node: Deploy MockVRFV2PlusWrapper
  echo "🚀 Deploying MockVRFV2PlusWrapper..."
  MOCK_VRF_OUTPUT=$(forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
    --broadcast \
    test/mocks/MockVRFV2PlusWrapper.sol:MockVRFV2PlusWrapper \
    --constructor-args $VRF_REQUEST_PRICE)

  MOCK_VRF=$(echo "$MOCK_VRF_OUTPUT" | grep "Deployed to:" | awk '{print $3}')
  MOCK_VRF_TX=$(echo "$MOCK_VRF_OUTPUT" | grep -iE "(Transaction hash|tx hash|txHash|transactionHash|Deployment transaction):" | grep -oE "0x[a-fA-F0-9]{64}" | head -1)
  if [ -z "$MOCK_VRF_TX" ]; then
    MOCK_VRF_TX=$(echo "$MOCK_VRF_OUTPUT" | grep -oE "0x[a-fA-F0-9]{64}" | grep -v "$MOCK_VRF" | head -1)
  fi

  if [ -z "$MOCK_VRF" ]; then
    echo "❌ Failed to deploy MockVRFV2PlusWrapper"
    echo "$MOCK_VRF_OUTPUT"
    exit 1
  fi

  if [ -z "$MOCK_VRF_TX" ]; then
    echo "⚠️  Could not extract transaction hash for MockVRFV2PlusWrapper, using empty string"
    MOCK_VRF_TX=""
  fi

  echo "✅ MockVRFV2PlusWrapper deployed at: $MOCK_VRF"
  echo "   Transaction hash: $MOCK_VRF_TX"

  # Export Mock VRF ABI
  if [ -f "out/MockVRFV2PlusWrapper.sol/MockVRFV2PlusWrapper.json" ]; then
    jq '.abi' out/MockVRFV2PlusWrapper.sol/MockVRFV2PlusWrapper.json > $ABI_DIR/MockVRFV2PlusWrapper.json 2>/dev/null || \
    python3 -c "import json; print(json.dumps(json.load(open('out/MockVRFV2PlusWrapper.sol/MockVRFV2PlusWrapper.json'))['abi']))" > $ABI_DIR/MockVRFV2PlusWrapper.json 2>/dev/null || \
    node -e "console.log(JSON.stringify(require('./out/MockVRFV2PlusWrapper.sol/MockVRFV2PlusWrapper.json').abi, null, 2))" > $ABI_DIR/MockVRFV2PlusWrapper.json 2>/dev/null || \
    echo "⚠️  Could not extract ABI automatically. Please extract manually from out/MockVRFV2PlusWrapper.sol/MockVRFV2PlusWrapper.json"
  fi
  echo "✅ Exported MockVRFV2PlusWrapper ABI"

  # Update deployedContracts.ts
  if [ -f "$ABI_DIR/MockVRFV2PlusWrapper.json" ]; then
    echo "📝 Updating deployedContracts.ts for MockVRFV2PlusWrapper..."
    node $UPDATE_SCRIPT "$CHAIN_ID" "mock-vrf-v2-plus-wrapper-solidity" "$MOCK_VRF" "$MOCK_VRF_TX" "$ABI_DIR/MockVRFV2PlusWrapper.json" || \
    echo "⚠️  Failed to update deployedContracts.ts for MockVRFV2PlusWrapper"
  fi
  echo ""
elif [ "$CHAIN_ID" = "421614" ]; then
  # Arbitrum Sepolia: Use real VRF wrapper
  MOCK_VRF="0x29576aB8152A09b9DC634804e4aDE73dA1f3a3CC"
  echo "⏭️  Skipping MockVRFV2PlusWrapper deployment (using real VRF wrapper on Arbitrum Sepolia)"
  echo "   Using Arbitrum Sepolia VRF V2+ Wrapper: $MOCK_VRF"
  echo ""
else
  # Other networks: Use MOCK_VRF_ADDRESS env var
  if [ -n "$MOCK_VRF_ADDRESS" ]; then
    MOCK_VRF="$MOCK_VRF_ADDRESS"
    echo "⏭️  Skipping MockVRFV2PlusWrapper deployment"
    echo "   Using provided VRF wrapper address: $MOCK_VRF"
  else
    echo "⏭️  Skipping MockVRFV2PlusWrapper deployment"
    echo "⚠️  MOCK_VRF_ADDRESS not set. VrfConsumer deployment may fail if it requires a VRF wrapper."
    echo "   Set MOCK_VRF_ADDRESS environment variable with the VRF wrapper address."
    MOCK_VRF=""
  fi
  echo ""
fi

# Deploy ERC20Example
echo "🚀 Deploying ERC20Example..."
ERC20_OUTPUT=$(forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --broadcast \
  contracts/ERC20Example.sol:ERC20Example \
  --constructor-args "$TOKEN_NAME" "$TOKEN_SYMBOL" $TOKEN_CAP $OWNER_ADDRESS)

ERC20=$(echo "$ERC20_OUTPUT" | grep "Deployed to:" | awk '{print $3}')
# Extract transaction hash from forge output
ERC20_TX=$(echo "$ERC20_OUTPUT" | grep -iE "(Transaction hash|tx hash|txHash|transactionHash|Deployment transaction):" | grep -oE "0x[a-fA-F0-9]{64}" | head -1)
# If not found, try to extract from broadcast logs or any hex string that looks like a tx hash
if [ -z "$ERC20_TX" ]; then
  ERC20_TX=$(echo "$ERC20_OUTPUT" | grep -oE "0x[a-fA-F0-9]{64}" | grep -v "$ERC20" | head -1)
fi

if [ -z "$ERC20" ]; then
  echo "❌ Failed to deploy ERC20Example"
  echo "$ERC20_OUTPUT"
  exit 1
fi

if [ -z "$ERC20_TX" ]; then
  echo "⚠️  Could not extract transaction hash for ERC20Example, using empty string"
  ERC20_TX=""
fi

echo "✅ ERC20Example deployed at: $ERC20"
echo "   Transaction hash: $ERC20_TX"

# Export ERC20 ABI (extract from compiled JSON)
if [ -f "out/ERC20Example.sol/ERC20Example.json" ]; then
  jq '.abi' out/ERC20Example.sol/ERC20Example.json > $ABI_DIR/ERC20Example.json 2>/dev/null || \
  python3 -c "import json; print(json.dumps(json.load(open('out/ERC20Example.sol/ERC20Example.json'))['abi']))" > $ABI_DIR/ERC20Example.json 2>/dev/null || \
  node -e "console.log(JSON.stringify(require('./out/ERC20Example.sol/ERC20Example.json').abi, null, 2))" > $ABI_DIR/ERC20Example.json 2>/dev/null || \
  echo "⚠️  Could not extract ABI automatically. Please extract manually from out/ERC20Example.sol/ERC20Example.json"
fi
echo "✅ Exported ERC20Example ABI"

# Update deployedContracts.ts
if [ -f "$ABI_DIR/ERC20Example.json" ]; then
  echo "📝 Updating deployedContracts.ts for ERC20Example..."
  node $UPDATE_SCRIPT "$CHAIN_ID" "erc20-example-solidity" "$ERC20" "$ERC20_TX" "$ABI_DIR/ERC20Example.json" || \
  echo "⚠️  Failed to update deployedContracts.ts for ERC20Example"
fi
echo ""

# Deploy VrfConsumer
echo "🚀 Deploying VrfConsumer..."
if [ -z "$MOCK_VRF" ]; then
  echo "❌ Cannot deploy VrfConsumer: MockVRFV2PlusWrapper address is required"
  echo "   Set MOCK_VRF_ADDRESS environment variable or deploy on test chain (http://127.0.0.1:8547)"
  exit 1
fi

VRF_OUTPUT=$(forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --broadcast \
  contracts/VrfConsumer.sol:VrfConsumer \
  --constructor-args $MOCK_VRF $OWNER_ADDRESS)

VRF=$(echo "$VRF_OUTPUT" | grep "Deployed to:" | awk '{print $3}')
# Extract transaction hash from forge output
VRF_TX=$(echo "$VRF_OUTPUT" | grep -iE "(Transaction hash|tx hash|txHash|transactionHash|Deployment transaction):" | grep -oE "0x[a-fA-F0-9]{64}" | head -1)
# If not found, try to extract from broadcast logs or any hex string that looks like a tx hash
if [ -z "$VRF_TX" ]; then
  VRF_TX=$(echo "$VRF_OUTPUT" | grep -oE "0x[a-fA-F0-9]{64}" | grep -v "$VRF" | head -1)
fi

if [ -z "$VRF" ]; then
  echo "❌ Failed to deploy VrfConsumer"
  echo "$VRF_OUTPUT"
  exit 1
fi

if [ -z "$VRF_TX" ]; then
  echo "⚠️  Could not extract transaction hash for VrfConsumer, using empty string"
  VRF_TX=""
fi

echo "✅ VrfConsumer deployed at: $VRF"
echo "   Transaction hash: $VRF_TX"

# Export VrfConsumer ABI (extract from compiled JSON)
if [ -f "out/VrfConsumer.sol/VrfConsumer.json" ]; then
  jq '.abi' out/VrfConsumer.sol/VrfConsumer.json > $ABI_DIR/VrfConsumer.json 2>/dev/null || \
  python3 -c "import json; print(json.dumps(json.load(open('out/VrfConsumer.sol/VrfConsumer.json'))['abi']))" > $ABI_DIR/VrfConsumer.json 2>/dev/null || \
  node -e "console.log(JSON.stringify(require('./out/VrfConsumer.sol/VrfConsumer.json').abi, null, 2))" > $ABI_DIR/VrfConsumer.json 2>/dev/null || \
  echo "⚠️  Could not extract ABI automatically. Please extract manually from out/VrfConsumer.sol/VrfConsumer.json"
fi
echo "✅ Exported VrfConsumer ABI"

# Update deployedContracts.ts
if [ -f "$ABI_DIR/VrfConsumer.json" ]; then
  echo "📝 Updating deployedContracts.ts for VrfConsumer..."
  node $UPDATE_SCRIPT "$CHAIN_ID" "vrf-consumer-solidity" "$VRF" "$VRF_TX" "$ABI_DIR/VrfConsumer.json" || \
  echo "⚠️  Failed to update deployedContracts.ts for VrfConsumer"
fi
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
      "abi": "abis/MockVRFV2PlusWrapper.json"
    },
    "ERC20Example": {
      "address": "$ERC20",
      "abi": "abis/ERC20Example.json",
      "name": "$TOKEN_NAME",
      "symbol": "$TOKEN_SYMBOL",
      "cap": "$TOKEN_CAP"
    },
    "VrfConsumer": {
      "address": "$VRF",
      "abi": "abis/VrfConsumer.json"
    }
  }
}
EOF

# Function to create chainId_latest.json file (Stylus format)
create_chain_deployment_file() {
  local contract_name="$1"
  local address="$2"
  local tx_hash="$3"
  local contract_folder="$4"
  local chain_id="$5"
  
  local chain_file="$DEPLOYMENT_DIR/${chain_id}_latest.json"
  
  # Read existing deployments or start fresh
  local deployments_json="{}"
  if [ -f "$chain_file" ]; then
    deployments_json=$(cat "$chain_file" 2>/dev/null || echo "{}")
  fi
  
  # Update with new contract (using jq if available, otherwise node/python)
  if command -v jq &> /dev/null; then
    deployments_json=$(echo "$deployments_json" | jq --arg name "$contract_name" \
      --arg addr "$address" \
      --arg tx "$tx_hash" \
      --arg folder "$contract_folder" \
      '. + {($name): {address: $addr, txHash: $tx, contract: $folder}}')
  elif command -v node &> /dev/null; then
    # Use node.js for JSON manipulation (write to temp file to avoid shell escaping issues)
    local temp_file=$(mktemp)
    echo "$deployments_json" > "$temp_file"
    deployments_json=$(node -e "
      const fs = require('fs');
      const data = JSON.parse(fs.readFileSync('$temp_file', 'utf8') || '{}');
      data['$contract_name'] = {
        address: '$address',
        txHash: '$tx_hash',
        contract: '$contract_folder'
      };
      console.log(JSON.stringify(data, null, 2));
    ")
    rm -f "$temp_file"
  elif command -v python3 &> /dev/null; then
    # Use python3 for JSON manipulation (write to temp file to avoid shell escaping issues)
    local temp_file=$(mktemp)
    echo "$deployments_json" > "$temp_file"
    deployments_json=$(python3 -c "
import json
with open('$temp_file', 'r') as f:
    content = f.read()
    data = json.loads(content) if content.strip() else {}
data['$contract_name'] = {
    'address': '$address',
    'txHash': '$tx_hash',
    'contract': '$contract_folder'
}
print(json.dumps(data, indent=2))
")
    rm -f "$temp_file"
  else
    echo "⚠️  Warning: jq, node, or python3 not found. Cannot update ${chain_id}_latest.json properly."
    echo "   Please install jq for proper JSON handling: https://stedolan.github.io/jq/download/"
    return 1
  fi
  
  echo "$deployments_json" > "$chain_file"
  echo "💾 Updated ${chain_id}_latest.json with $contract_name"
}

# Function to create contract folder with abi.json
create_contract_folder() {
  local contract_name="$1"
  local abi_file="$2"
  
  local contract_dir="$DEPLOYMENT_DIR/$contract_name"
  mkdir -p "$contract_dir"
  
  if [ -f "$abi_file" ]; then
    cp "$abi_file" "$contract_dir/abi.json"
    echo "📁 Created $contract_name/abi.json"
  fi
}

# Function to create contract-name file (Stylus ABI export format)
create_contract_name_file() {
  local contract_name_lower="$1"
  local abi_file="$2"
  local interface_name="$3"
  
  local output_file="$DEPLOYMENT_DIR/$contract_name_lower"
  
  if [ -f "$abi_file" ]; then
    # Read ABI JSON
    local abi_content
    if command -v jq &> /dev/null; then
      abi_content=$(cat "$abi_file" | jq -c '.')
    else
      abi_content=$(cat "$abi_file")
    fi
    
    # Create file in Stylus export format
    cat > "$output_file" <<EOF

======= <stdin>:$interface_name =======
Contract JSON ABI
$abi_content
EOF
    echo "📄 Created $contract_name_lower file"
  fi
}

# Create chainId_latest.json files for each contract
echo "📝 Creating chain-specific deployment files..."
if [ -n "$MOCK_VRF" ]; then
  create_chain_deployment_file "MockVRFV2PlusWrapper" "$MOCK_VRF" "$MOCK_VRF_TX" "MockVRFV2PlusWrapper" "$CHAIN_ID"
  create_contract_folder "MockVRFV2PlusWrapper" "$ABI_DIR/MockVRFV2PlusWrapper.json"
  create_contract_name_file "mock-vrf-v2-plus-wrapper" "$ABI_DIR/MockVRFV2PlusWrapper.json" "IMockVRFV2PlusWrapper"
fi

create_chain_deployment_file "ERC20Example" "$ERC20" "$ERC20_TX" "ERC20Example" "$CHAIN_ID"
create_contract_folder "ERC20Example" "$ABI_DIR/ERC20Example.json"
create_contract_name_file "erc20-example" "$ABI_DIR/ERC20Example.json" "IERC20Example"

create_chain_deployment_file "VrfConsumer" "$VRF" "$VRF_TX" "VrfConsumer" "$CHAIN_ID"
create_contract_folder "VrfConsumer" "$ABI_DIR/VrfConsumer.json"
create_contract_name_file "vrf-consumer" "$ABI_DIR/VrfConsumer.json" "IVrfConsumer"
echo ""

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

# Run verification script if not on local network
if [[ "$RPC_URL" != *"127.0.0.1:8547"* ]] && [[ "$RPC_URL" != *"localhost"* ]]; then
  echo "=========================================="
  echo "Verifying Contracts"
  echo "=========================================="
  echo ""
  
  # Export variables for verification script
  export MOCK_VRF_ADDRESS=$MOCK_VRF
  export ERC20_ADDRESS=$ERC20
  export VRF_ADDRESS=$VRF
  export OWNER_ADDRESS=$OWNER_ADDRESS
  export VRF_REQUEST_PRICE=$VRF_REQUEST_PRICE
  export TOKEN_NAME=$TOKEN_NAME
  export TOKEN_SYMBOL=$TOKEN_SYMBOL
  export TOKEN_CAP=$TOKEN_CAP
  export CHAIN_ID=$CHAIN_ID
  export RPC_URL=$RPC_URL
  
  # Call verification script
  if [ -f "scripts/verify.sh" ]; then
    bash scripts/verify.sh || echo "⚠️  Verification failed or skipped. You can verify manually later using scripts/verify.sh"
  else
    echo "⚠️  Verification script not found at scripts/verify.sh"
  fi
  echo ""
fi

echo "Next steps:"
echo "  1. Use the addresses above to interact with contracts"
echo "  2. See scripts/test.sh for testing examples"
echo "  3. ABIs are available in $ABI_DIR/"
if [[ "$RPC_URL" != *"127.0.0.1:8547"* ]] && [[ "$RPC_URL" != *"localhost"* ]]; then
  echo "  4. Verify contracts on block explorer: scripts/verify.sh"
fi
echo ""
