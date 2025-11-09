#!/bin/bash

# Script to fix build issues for yarn install

set -e

echo "🔧 Fixing build issues..."

# 1. Check if build tools are installed
echo "📦 Checking for build tools..."
if ! command -v python3 &> /dev/null; then
    echo "❌ python3 not found. Installing build tools..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y python3 make g++ nodejs npm
    elif command -v dnf &> /dev/null; then
        sudo dnf install -y python3 make gcc-c++ nodejs npm
    else
        echo "⚠️  Please install python3, make, and g++ manually"
    fi
else
    echo "✅ Build tools found"
fi

# 2. Set npm registry environment variable for Next.js
export npm_config_registry=https://registry.npmjs.org/
echo "✅ Set npm registry environment variable"

# 3. Clean node_modules and cache
echo "🧹 Cleaning node_modules and cache..."
rm -rf node_modules packages/*/node_modules .yarn/cache

# 4. Reinstall
echo "📥 Running yarn install..."
yarn install

echo "✅ Done! Try running 'yarn start' now."

