#!/bin/bash

# Testing script for deployed contracts using cast
# This script demonstrates how to interact with deployed contracts

set -e

# Load deployment info if available
DEPLOYMENT_INFO="../stylus/deployments/deployment_info.json"
RPC_URL=${RPC_URL:-http://127.0.0.1:8547}
PRIVATE_KEY=${PRIVATE_KEY:-0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659}
OWNER_ADDRESS=$(cast wallet address $PRIVATE_KEY)

# Check if deployment info exists
if [ ! -f "$DEPLOYMENT_INFO" ]; then
  echo "❌ Deployment info not found. Please run deploy.sh first."
  exit 1
fi

# Extract addresses from deployment info (requires jq)
if command -v jq &> /dev/null; then
  ERC20=$(jq -r '.contracts.ERC20Example.address' $DEPLOYMENT_INFO)
  VRF=$(jq -r '.contracts.VrfConsumer.address' $DEPLOYMENT_INFO)
  MOCK_VRF=$(jq -r '.contracts.MockVRFV2PlusWrapper.address' $DEPLOYMENT_INFO)
else
  echo "⚠️  jq not found. Please set ERC20, VRF, and MOCK_VRF environment variables."
  echo "   Or install jq: https://stedolan.github.io/jq/download/"
  exit 1
fi

echo "=========================================="
echo "Testing Deployed Contracts"
echo "=========================================="
echo "RPC URL: $RPC_URL"
echo "ERC20Example: $ERC20"
echo "VrfConsumer: $VRF"
echo "MockVRFV2PlusWrapper: $MOCK_VRF"
echo ""

# Navigate to solidity directory
cd "$(dirname "$0")/.."

# Test 1: Check contract state
echo "📋 Test 1: Checking contract state..."
echo ""

echo "ERC20 Token Info:"
echo "  Name: $(cast call --rpc-url $RPC_URL $ERC20 "name()(string)")"
echo "  Symbol: $(cast call --rpc-url $RPC_URL $ERC20 "symbol()(string)")"
echo "  Decimals: $(cast call --rpc-url $RPC_URL $ERC20 "decimals()(uint8)")"
echo "  Cap: $(cast call --rpc-url $RPC_URL $ERC20 "cap()(uint256)")"
echo "  Total Supply: $(cast call --rpc-url $RPC_URL $ERC20 "totalSupply()(uint256)")"
echo "  Authorized Minter: $(cast call --rpc-url $RPC_URL $ERC20 "getAuthorizedMinter()(address)")"
echo ""

echo "VrfConsumer Info:"
echo "  Entry Fee: $(cast call --rpc-url $RPC_URL $VRF "lotteryEntryFee()(uint256)")"
echo "  Interval Hours: $(cast call --rpc-url $RPC_URL $VRF "lotteryIntervalHours()(uint256)")"
echo "  ERC20 Token: $(cast call --rpc-url $RPC_URL $VRF "erc20TokenAddress()(address)")"
echo "  Accepting Participants: $(cast call --rpc-url $RPC_URL $VRF "acceptingParticipants()(bool)")"
echo "  Participant Count: $(cast call --rpc-url $RPC_URL $VRF "getParticipantCount()(uint256)")"
echo ""

# Test 2: Participate in lottery
echo "📋 Test 2: Participating in lottery..."
ENTRY_FEE=$(cast call --rpc-url $RPC_URL $VRF "lotteryEntryFee()(uint256)")

# Create a test user (using a different private key for demonstration)
# In real testing, you'd use a different account
TEST_USER=$OWNER_ADDRESS

echo "  Entry fee: $ENTRY_FEE wei"
echo "  Participating as: $TEST_USER"

cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --value $ENTRY_FEE \
  $VRF "participateInLottery()" > /dev/null

echo "  ✅ Participation successful"
PARTICIPANT_COUNT=$(cast call --rpc-url $RPC_URL $VRF "getParticipantCount()(uint256)")
echo "  Current participants: $PARTICIPANT_COUNT"
echo ""

# Test 3: Request random words (if enough time has passed)
echo "📋 Test 3: Requesting random words..."
echo "  Note: This requires the lottery interval to have passed"
echo "  Current interval: $(cast call --rpc-url $RPC_URL $VRF "lotteryIntervalHours()(uint256)") hours"

# Calculate required payment for VRF request
CALLBACK_GAS=$(cast call --rpc-url $RPC_URL $VRF "callbackGasLimit()(uint256)")
NUM_WORDS=$(cast call --rpc-url $RPC_URL $VRF "numWords()(uint256)")

REQUEST_PRICE=$(cast call --rpc-url $RPC_URL $MOCK_VRF \
  "calculateRequestPriceNative(uint32,uint32)" \
  $(cast --to-uint256 $CALLBACK_GAS) $(cast --to-uint256 $NUM_WORDS))

echo "  Request price: $REQUEST_PRICE wei"

# Fund VRF consumer for request
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --value $REQUEST_PRICE \
  $VRF > /dev/null

echo "  ✅ VRF consumer funded"

# Try to request (may fail if interval hasn't passed)
if cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $VRF "requestRandomWords()(uint256)" 2>&1 | grep -q "Too soon"; then
  echo "  ⚠️  Too soon to request (interval hasn't passed)"
else
  echo "  ✅ Random words requested"
fi
echo ""

# Test 4: Owner functions
echo "📋 Test 4: Testing owner functions..."

# Get current entry fee
CURRENT_FEE=$(cast call --rpc-url $RPC_URL $VRF "lotteryEntryFee()(uint256)")
echo "  Current entry fee: $CURRENT_FEE"

# Set new entry fee
NEW_FEE="1000000"
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $VRF "setLotteryEntryFee(uint256)" $NEW_FEE > /dev/null

UPDATED_FEE=$(cast call --rpc-url $RPC_URL $VRF "lotteryEntryFee()(uint256)")
echo "  Updated entry fee: $UPDATED_FEE"
echo "  ✅ Entry fee updated"

# Restore original fee
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $VRF "setLotteryEntryFee(uint256)" $CURRENT_FEE > /dev/null
echo "  ✅ Entry fee restored"
echo ""

# Test 5: Mint tokens directly (as owner)
echo "📋 Test 5: Minting tokens directly..."
MINT_AMOUNT="1000000000000000000000"  # 1000 tokens with 10 decimals

cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $ERC20 "mint(address,uint256)" $OWNER_ADDRESS $MINT_AMOUNT > /dev/null

BALANCE=$(cast call --rpc-url $RPC_URL $ERC20 "balanceOf(address)(uint256)" $OWNER_ADDRESS)
echo "  Minted $MINT_AMOUNT tokens to $OWNER_ADDRESS"
echo "  Balance: $BALANCE"
echo "  ✅ Mint successful"
echo ""

echo "=========================================="
echo "✅ Testing Complete!"
echo "=========================================="
echo ""
echo "For more advanced testing:"
echo "  1. Use cast send/call to interact with contracts"
echo "  2. Check deployment_info.json for contract addresses"
echo "  3. Use ABIs in ../stylus/deployments/abis/ for frontend integration"
echo ""

