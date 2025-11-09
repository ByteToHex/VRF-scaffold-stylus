#!/bin/bash

# Script to export ABIs from compiled contracts
# This extracts ABIs from the out/ directory and saves them to deployments/abis/

set -e

ABI_DIR="deployments/abis"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_DIR"

# Create ABI directory
mkdir -p $ABI_DIR

echo "=========================================="
echo "Exporting Contract ABIs"
echo "=========================================="
echo ""

# Check if contracts are compiled
if [ ! -d "out" ]; then
  echo "❌ Contracts not compiled. Running forge build..."
  forge build
fi

# Export ERC20Example ABI
if [ -f "out/ERC20Example.sol/ERC20Example.json" ]; then
  echo "📄 Exporting ERC20Example ABI..."
  forge inspect contracts/ERC20Example.sol:ERC20Example abi > $ABI_DIR/ERC20Example.json
  echo "✅ Exported to $ABI_DIR/ERC20Example.json"
else
  echo "⚠️  ERC20Example not found in out/ directory"
fi

# Export VrfConsumer ABI
if [ -f "out/VrfConsumer.sol/VrfConsumer.json" ]; then
  echo "📄 Exporting VrfConsumer ABI..."
  forge inspect contracts/VrfConsumer.sol:VrfConsumer abi > $ABI_DIR/VrfConsumer.json
  echo "✅ Exported to $ABI_DIR/VrfConsumer.json"
else
  echo "⚠️  VrfConsumer not found in out/ directory"
fi

# Export MockVRFV2PlusWrapper ABI
if [ -f "out/MockVRFV2PlusWrapper.sol/MockVRFV2PlusWrapper.json" ]; then
  echo "📄 Exporting MockVRFV2PlusWrapper ABI..."
  forge inspect test/mocks/MockVRFV2PlusWrapper.sol:MockVRFV2PlusWrapper abi > $ABI_DIR/MockVRFV2PlusWrapper.json
  echo "✅ Exported to $ABI_DIR/MockVRFV2PlusWrapper.json"
else
  echo "⚠️  MockVRFV2PlusWrapper not found in out/ directory"
fi

echo ""
echo "=========================================="
echo "✅ ABI Export Complete!"
echo "=========================================="
echo "ABIs saved to: $ABI_DIR/"
echo ""

