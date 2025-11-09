# Deployment script for Solidity contracts (PowerShell)
# This script deploys MockVRFV2PlusWrapper, ERC20Example, and VrfConsumer contracts
# and configures them for integration.

$ErrorActionPreference = "Stop"

# Configuration
$RPC_URL = if ($env:RPC_URL) { $env:RPC_URL } else { "http://127.0.0.1:8547" }
$PRIVATE_KEY = if ($env:PRIVATE_KEY) { $env:PRIVATE_KEY } else { "0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659" }
$OWNER_ADDRESS = (cast wallet address $PRIVATE_KEY).Trim()

# Token parameters
$TOKEN_NAME = "LotteryToken"
$TOKEN_SYMBOL = "LUK"
$TOKEN_CAP = "1000000000000000000000000"  # 1M tokens with 10 decimals

# VRF Mock parameters
$VRF_REQUEST_PRICE = "1000000000000000"  # 0.001 ether

# Directories
$ABI_DIR = "deployments/abis"
$DEPLOYMENT_DIR = "deployments"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deploying Solidity Contracts" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "RPC URL: $RPC_URL"
Write-Host "Owner: $OWNER_ADDRESS"
Write-Host ""

# Navigate to solidity directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $scriptPath "..")

# Build contracts
Write-Host "📦 Building contracts..." -ForegroundColor Yellow
forge build
Write-Host "✅ Build complete" -ForegroundColor Green
Write-Host ""

# Create deployment directories
New-Item -ItemType Directory -Force -Path $ABI_DIR | Out-Null
New-Item -ItemType Directory -Force -Path $DEPLOYMENT_DIR | Out-Null

# Deploy Mock VRF Wrapper
Write-Host "🚀 Deploying MockVRFV2PlusWrapper..." -ForegroundColor Yellow
$mockVrfOutput = forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY `
  --broadcast `
  test/mocks/MockVRFV2PlusWrapper.sol:MockVRFV2PlusWrapper `
  --constructor-args $VRF_REQUEST_PRICE

$MOCK_VRF = ($mockVrfOutput | Select-String "Deployed to:" | ForEach-Object { $_.Line -split '\s+' | Select-Object -Last 1 })

if (-not $MOCK_VRF) {
  Write-Host "❌ Failed to deploy MockVRFV2PlusWrapper" -ForegroundColor Red
  Write-Host $mockVrfOutput
  exit 1
}

Write-Host "✅ MockVRFV2PlusWrapper deployed at: $MOCK_VRF" -ForegroundColor Green

# Export Mock VRF ABI
forge inspect test/mocks/MockVRFV2PlusWrapper.sol:MockVRFV2PlusWrapper abi | Out-File -FilePath "$ABI_DIR/MockVRFV2PlusWrapper.json" -Encoding utf8
Write-Host "✅ Exported MockVRFV2PlusWrapper ABI" -ForegroundColor Green
Write-Host ""

# Deploy ERC20Example
Write-Host "🚀 Deploying ERC20Example..." -ForegroundColor Yellow
$erc20Output = forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY `
  --broadcast `
  contracts/ERC20Example.sol:ERC20Example `
  --constructor-args $TOKEN_NAME $TOKEN_SYMBOL $TOKEN_CAP $OWNER_ADDRESS

$ERC20 = ($erc20Output | Select-String "Deployed to:" | ForEach-Object { $_.Line -split '\s+' | Select-Object -Last 1 })

if (-not $ERC20) {
  Write-Host "❌ Failed to deploy ERC20Example" -ForegroundColor Red
  Write-Host $erc20Output
  exit 1
}

Write-Host "✅ ERC20Example deployed at: $ERC20" -ForegroundColor Green

# Export ERC20 ABI
forge inspect contracts/ERC20Example.sol:ERC20Example abi | Out-File -FilePath "$ABI_DIR/ERC20Example.json" -Encoding utf8
Write-Host "✅ Exported ERC20Example ABI" -ForegroundColor Green
Write-Host ""

# Deploy VrfConsumer
Write-Host "🚀 Deploying VrfConsumer..." -ForegroundColor Yellow
$vrfOutput = forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY `
  --broadcast `
  contracts/VrfConsumer.sol:VrfConsumer `
  --constructor-args $MOCK_VRF $OWNER_ADDRESS

$VRF = ($vrfOutput | Select-String "Deployed to:" | ForEach-Object { $_.Line -split '\s+' | Select-Object -Last 1 })

if (-not $VRF) {
  Write-Host "❌ Failed to deploy VrfConsumer" -ForegroundColor Red
  Write-Host $vrfOutput
  exit 1
}

Write-Host "✅ VrfConsumer deployed at: $VRF" -ForegroundColor Green

# Export VrfConsumer ABI
forge inspect contracts/VrfConsumer.sol:VrfConsumer abi | Out-File -FilePath "$ABI_DIR/VrfConsumer.json" -Encoding utf8
Write-Host "✅ Exported VrfConsumer ABI" -ForegroundColor Green
Write-Host ""

# Configure contracts
Write-Host "⚙️  Configuring contracts..." -ForegroundColor Yellow

# Set VrfConsumer as authorized minter in ERC20
Write-Host "  Setting VrfConsumer as authorized minter..." -ForegroundColor Gray
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY `
  $ERC20 "setAuthorizedMinter(address)" $VRF | Out-Null
Write-Host "  ✅ Authorized minter set" -ForegroundColor Green

# Set ERC20 token address in VrfConsumer
Write-Host "  Setting ERC20 token address in VrfConsumer..." -ForegroundColor Gray
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY `
  $VRF "setErc20Token(address)" $ERC20 | Out-Null
Write-Host "  ✅ ERC20 token address set" -ForegroundColor Green
Write-Host ""

# Save deployment info
$DEPLOYMENT_INFO = "$DEPLOYMENT_DIR/deployment_info.json"
$deploymentJson = @{
  chainId = "local"
  rpcUrl = $RPC_URL
  deployer = $OWNER_ADDRESS
  deployedAt = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ")
  contracts = @{
    MockVRFV2PlusWrapper = @{
      address = $MOCK_VRF
      abi = "$ABI_DIR/MockVRFV2PlusWrapper.json"
    }
    ERC20Example = @{
      address = $ERC20
      abi = "$ABI_DIR/ERC20Example.json"
      name = $TOKEN_NAME
      symbol = $TOKEN_SYMBOL
      cap = $TOKEN_CAP
    }
    VrfConsumer = @{
      address = $VRF
      abi = "$ABI_DIR/VrfConsumer.json"
    }
  }
} | ConvertTo-Json -Depth 10

$deploymentJson | Out-File -FilePath $DEPLOYMENT_INFO -Encoding utf8

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "✅ Deployment Complete!" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Contract Addresses:"
Write-Host "  MockVRFV2PlusWrapper: $MOCK_VRF"
Write-Host "  ERC20Example:          $ERC20"
Write-Host "  VrfConsumer:          $VRF"
Write-Host ""
Write-Host "Files:"
Write-Host "  Deployment info: $DEPLOYMENT_INFO"
Write-Host "  ABIs:           $ABI_DIR/"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Use the addresses above to interact with contracts"
Write-Host "  2. See scripts/test.sh for testing examples"
Write-Host "  3. ABIs are available in $ABI_DIR/"
Write-Host ""

