#!/bin/bash

# Verification script for Solidity contracts on Arbiscan
# This script verifies deployed contracts on block explorers (Arbiscan, Etherscan, etc.)

# Don't exit on error - we want to continue verifying other contracts even if one fails

# Configuration
RPC_URL=${RPC_URL:-http://127.0.0.1:8547}
CHAIN_ID=${CHAIN_ID:-}
ARBISCAN_API_KEY=${ARBISCAN_API_KEY:-}
ETHERSCAN_API_KEY=${ETHERSCAN_API_KEY:-}
VERIFY_SKIP=${VERIFY_SKIP:-false}

# Get chain ID if not set
if [ -z "$CHAIN_ID" ]; then
  CHAIN_ID=$(cast chain-id --rpc-url $RPC_URL 2>/dev/null || echo "")
  if [ -z "$CHAIN_ID" ]; then
    echo "⚠️  Could not determine chain ID, skipping verification"
    exit 0
  fi
fi

# Navigate to solidity directory
cd "$(dirname "$0")/.."

# Determine API key and explorer based on chain ID
case "$CHAIN_ID" in
  "421614"|"42161")
    # Arbitrum Sepolia or Arbitrum One
    if [ -z "$ARBISCAN_API_KEY" ]; then
      echo "⚠️  ARBISCAN_API_KEY not set, skipping verification"
      echo "   Set ARBISCAN_API_KEY environment variable to enable verification"
      exit 0
    fi
    API_KEY="$ARBISCAN_API_KEY"
    EXPLORER="arbiscan"
    ;;
  "1"|"11155111")
    # Ethereum Mainnet or Sepolia
    if [ -z "$ETHERSCAN_API_KEY" ]; then
      echo "⚠️  ETHERSCAN_API_KEY not set, skipping verification"
      echo "   Set ETHERSCAN_API_KEY environment variable to enable verification"
      exit 0
    fi
    API_KEY="$ETHERSCAN_API_KEY"
    EXPLORER="etherscan"
    ;;
  *)
    # Local or unsupported network
    if [[ "$RPC_URL" == *"127.0.0.1"* ]] || [[ "$RPC_URL" == *"localhost"* ]]; then
      echo "⏭️  Skipping verification (local network)"
      exit 0
    fi
    echo "⚠️  Chain ID $CHAIN_ID not configured for verification"
    echo "   Supported chains: Arbitrum (421614, 42161), Ethereum (1, 11155111)"
    exit 0
    ;;
esac

# Check if verification should be skipped
if [ "$VERIFY_SKIP" = "true" ]; then
  echo "⏭️  Verification skipped (VERIFY_SKIP=true)"
  exit 0
fi

echo "=========================================="
echo "Verifying Contracts on $EXPLORER"
echo "=========================================="
echo "Chain ID: $CHAIN_ID"
echo "RPC URL: $RPC_URL"
echo ""

# Function to verify a contract
verify_contract() {
  local contract_address=$1
  local contract_name=$2
  local constructor_args=$3
  
  if [ -z "$contract_address" ] || [ -z "$contract_name" ]; then
    echo "⚠️  Skipping verification: missing address or contract name"
    return 1
  fi
  
  echo "🔍 Verifying $contract_name at $contract_address..."
  
  # Build verify command
  local verify_cmd="forge verify-contract"
  verify_cmd="$verify_cmd --chain-id $CHAIN_ID"
  verify_cmd="$verify_cmd --num-of-optimizations 200"
  verify_cmd="$verify_cmd --watch"
  
  # Add constructor args if provided
  if [ -n "$constructor_args" ] && [ "$constructor_args" != "" ]; then
    verify_cmd="$verify_cmd --constructor-args $constructor_args"
  fi
  
  # Add API key based on explorer
  if [ "$EXPLORER" = "arbiscan" ]; then
    verify_cmd="$verify_cmd --etherscan-api-key $API_KEY"
  else
    verify_cmd="$verify_cmd --etherscan-api-key $API_KEY"
  fi
  
  verify_cmd="$verify_cmd $contract_address $contract_name"
  
  # Execute verification
  if eval "$verify_cmd" 2>&1; then
    echo "✅ $contract_name verified successfully"
    return 0
  else
    echo "❌ Failed to verify $contract_name (this may be normal if already verified)"
    return 1
  fi
}

# Show help if requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Usage: $0 [options] [address] [contract_name] [constructor_args]"
  echo ""
  echo "Verify Solidity contracts on block explorers (Arbiscan, Etherscan)"
  echo ""
  echo "Options:"
  echo "  -h, --help    Show this help message"
  echo ""
  echo "Usage modes:"
  echo "  1. Automatic (called from deploy.sh):"
  echo "     $0"
  echo "     Uses environment variables set by deploy.sh"
  echo ""
  echo "  2. Manual single contract:"
  echo "     $0 <address> <contract_name> [constructor_args]"
  echo ""
  echo "  3. Manual with constructor args:"
  echo "     $0 0x123... contracts/ERC20Example.sol:ERC20Example \"$(cast abi-encode 'constructor(string,string,uint256,address)' 'Token' 'TKN' 1000000 0xOwner)\""
  echo ""
  echo "Environment variables:"
  echo "  ARBISCAN_API_KEY    API key for Arbitrum networks (required for 421614, 42161)"
  echo "  ETHERSCAN_API_KEY   API key for Ethereum networks (required for 1, 11155111)"
  echo "  CHAIN_ID            Chain ID (auto-detected from RPC_URL if not set)"
  echo "  RPC_URL             RPC endpoint (default: http://127.0.0.1:8547)"
  echo "  VERIFY_SKIP          Set to 'true' to skip verification"
  echo ""
  exit 0
fi

# Parse command line arguments or use environment variables
if [ $# -ge 2 ]; then
  # Called with arguments: verify.sh <address> <contract_name> [constructor_args]
  CONTRACT_ADDRESS=$1
  CONTRACT_NAME=$2
  CONSTRUCTOR_ARGS=${3:-}
  
  verify_contract "$CONTRACT_ADDRESS" "$CONTRACT_NAME" "$CONSTRUCTOR_ARGS"
else
  # Called without arguments: verify all contracts from deployment info
  DEPLOYMENT_INFO="../stylus/deployments/deployment_info.json"
  
  if [ ! -f "$DEPLOYMENT_INFO" ]; then
    echo "⚠️  Deployment info not found: $DEPLOYMENT_INFO"
    echo "   Usage: $0 <address> <contract_name> [constructor_args]"
    echo "   Or set environment variables and run after deployment"
    exit 0
  fi
  
  echo "📋 Reading deployment info from $DEPLOYMENT_INFO..."
  
  # Extract contract addresses and verify them
  # Note: This is a simplified approach. For full automation, you'd need to
  # store constructor args in deployment_info.json as well
  
  # Try to verify MockVRFV2PlusWrapper if deployed
  if [ -n "$MOCK_VRF_ADDRESS" ] && [ "$MOCK_VRF_ADDRESS" != "" ]; then
    # Only verify if it's not the real Arbitrum Sepolia wrapper
    if [ "$CHAIN_ID" != "421614" ] || [ "$MOCK_VRF_ADDRESS" != "0x29576aB8152A09b9DC634804e4aDE73dA1f3a3CC" ]; then
      # MockVRFV2PlusWrapper constructor: uint256 _requestPrice
      REQUEST_PRICE=${VRF_REQUEST_PRICE:-1000000000000000}
      CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(uint256)" $REQUEST_PRICE)
      verify_contract "$MOCK_VRF_ADDRESS" "test/mocks/MockVRFV2PlusWrapper.sol:MockVRFV2PlusWrapper" "$CONSTRUCTOR_ARGS" || true
    fi
  fi
  
  # Verify ERC20Example if address is provided
  if [ -n "$ERC20_ADDRESS" ] && [ "$ERC20_ADDRESS" != "" ]; then
    # ERC20Example constructor: string name, string symbol, uint256 cap, address owner
    TOKEN_NAME=${TOKEN_NAME:-LotteryToken}
    TOKEN_SYMBOL=${TOKEN_SYMBOL:-LUK}
    TOKEN_CAP=${TOKEN_CAP:-1000000000000000000000000}
    OWNER_ADDRESS=${OWNER_ADDRESS:-}
    
    if [ -n "$OWNER_ADDRESS" ]; then
      CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(string,string,uint256,address)" "$TOKEN_NAME" "$TOKEN_SYMBOL" $TOKEN_CAP $OWNER_ADDRESS)
      verify_contract "$ERC20_ADDRESS" "contracts/ERC20Example.sol:ERC20Example" "$CONSTRUCTOR_ARGS" || true
    else
      echo "⚠️  OWNER_ADDRESS not set, skipping ERC20Example verification"
    fi
  fi
  
  # Verify VrfConsumer if address is provided
  if [ -n "$VRF_ADDRESS" ] && [ "$VRF_ADDRESS" != "" ]; then
    # VrfConsumer constructor: address _vrfV2PlusWrapper, address _owner
    VRF_WRAPPER=${MOCK_VRF_ADDRESS:-}
    OWNER_ADDRESS=${OWNER_ADDRESS:-}
    
    if [ -n "$VRF_WRAPPER" ] && [ -n "$OWNER_ADDRESS" ]; then
      CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,address)" $VRF_WRAPPER $OWNER_ADDRESS)
      verify_contract "$VRF_ADDRESS" "contracts/VrfConsumer.sol:VrfConsumer" "$CONSTRUCTOR_ARGS" || true
    else
      echo "⚠️  MOCK_VRF_ADDRESS or OWNER_ADDRESS not set, skipping VrfConsumer verification"
    fi
  fi
fi

echo ""
echo "=========================================="
echo "✅ Verification Complete"
echo "=========================================="

