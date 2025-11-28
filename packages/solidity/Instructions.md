# Solidity Contracts Setup Instructions

This directory contains Solidity versions of the Stylus Rust contracts. The contracts use OpenZeppelin libraries which need to be installed using Foundry.

## Prerequisites

1. **Foundry** must be installed. If you don't have it installed:
   ```bash
   curl -L https://foundry.paradigm.xyz | bash
   foundryup
   ```

   For more details, see: https://book.getfoundry.sh/getting-started/installation

## Installation Steps

1. **Navigate to the solidity package directory:**
   ```bash
   cd packages/solidity
   ```

2. **Install OpenZeppelin Contracts using Foundry:**
   ```bash
   forge install OpenZeppelin/openzeppelin-contracts
   ```

   This will clone the OpenZeppelin contracts into the `lib/openzeppelin-contracts` directory.

3. **Verify the installation:**
   ```bash
   forge build
   ```

   This should compile both contracts without errors.

## Project Structure

```
packages/solidity/
├── contracts/
│   ├── ERC20Example.sol      # ERC20 token with capped supply and authorized minter
│   └── VrfConsumer.sol       # VRF consumer lottery contract
├── scripts/
│   ├── deploy.sh             # Deployment script (Linux/Mac)
│   ├── deploy.ps1            # Deployment script (Windows)
│   ├── test.sh               # Testing script with cast examples
│   └── export_abis.sh       # ABI export script
├── deployments/
│   ├── abis/                 # Exported ABIs (created after deployment)
│   └── deployment_info.json  # Deployment addresses and info
├── foundry.toml              # Foundry configuration
├── remappings.txt            # Import path remappings
└── lib/                      # Dependencies (created after forge install)
    └── openzeppelin-contracts/
```

## Compiling Contracts

After installing dependencies, compile the contracts:

```bash
forge build
```

The compiled artifacts will be in the `out/` directory.

## Testing

To run tests (if you add them):

```bash
forge test
```

## Deployment

### Quick Deployment (Recommended)

Use the provided deployment scripts for easy deployment:

**Linux/Mac:**
```bash
cd packages/solidity
chmod +x scripts/deploy.sh
./scripts/deploy.sh
```

**Windows (PowerShell):**
```powershell
cd packages/solidity
.\scripts\deploy.ps1
```

The scripts will:
- Build the contracts
- Deploy MockVRFV2PlusWrapper, ERC20Example, and VrfConsumer
- Configure the contracts for integration
- Export ABIs to `deployments/abis/`
- Save deployment info to `deployments/deployment_info.json`

### Manual Deployment with Cast

If you prefer manual deployment, follow these steps:

#### Prerequisites

1. Start your test node (e.g., Nitro dev node):
   ```bash
   cd nitro-devnode
   ./run-dev-node.sh
   ```

2. Set environment variables:
   ```bash
   export RPC_URL=http://127.0.0.1:8547
   export PRIVATE_KEY=0xb6b15c8cb491557369f3c7d2c287b053eb229daa9c22138887752191c9520659
   export OWNER_ADDRESS=$(cast wallet address $PRIVATE_KEY)
   ```

#### Step 1: Deploy MockVRFV2PlusWrapper

```bash
cd packages/solidity
forge build

# Deploy Mock VRF Wrapper (for testing)
MOCK_VRF=$(forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --broadcast \
  test/mocks/MockVRFV2PlusWrapper.sol:MockVRFV2PlusWrapper \
  --constructor-args 1000000000000000 | grep "Deployed to:" | awk '{print $3}')

echo "MockVRFV2PlusWrapper: $MOCK_VRF"
```

#### Step 2: Deploy ERC20Example

```bash
ERC20=$(forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --broadcast \
  contracts/ERC20Example.sol:ERC20Example \
  --constructor-args "LotteryToken" "LUK" 1000000000000000000000000 $OWNER_ADDRESS \
  | grep "Deployed to:" | awk '{print $3}')

echo "ERC20Example: $ERC20"
```

#### Step 3: Deploy VrfConsumer

```bash
VRF=$(forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --broadcast \
  contracts/VrfConsumer.sol:VrfConsumer \
  --constructor-args $MOCK_VRF $OWNER_ADDRESS \
  | grep "Deployed to:" | awk '{print $3}')

echo "VrfConsumer: $VRF"
```

#### Step 4: Configure Contracts

```bash
# Set VrfConsumer as authorized minter in ERC20
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $ERC20 "setAuthorizedMinter(address)" $VRF

# Set ERC20 token address in VrfConsumer
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $VRF "setErc20Token(address)" $ERC20
```

#### Step 5: Export ABIs

```bash
# Export ABIs using forge inspect
mkdir -p deployments/abis
forge inspect contracts/ERC20Example.sol:ERC20Example abi > deployments/abis/ERC20Example.json
forge inspect contracts/VrfConsumer.sol:VrfConsumer abi > deployments/abis/VrfConsumer.json
forge inspect test/mocks/MockVRFV2PlusWrapper.sol:MockVRFV2PlusWrapper abi > deployments/abis/MockVRFV2PlusWrapper.json
```

Or use the export script:
```bash
chmod +x scripts/export_abis.sh
./scripts/export_abis.sh
```

## Troubleshooting

### Import errors

If you see import errors like "file import callback not supported":

1. Make sure you've run `forge install OpenZeppelin/openzeppelin-contracts`
2. Verify that `lib/openzeppelin-contracts` directory exists
3. Check that `remappings.txt` is in the root of `packages/solidity/`
4. Try running `forge remappings` to verify the remappings are correct

### Solidity version mismatch

The contracts use Solidity `^0.8.20`. If you encounter version issues:

1. Check `foundry.toml` has `solc_version = "0.8.20"`
2. Update Foundry: `foundryup`

## Contract Details

### ERC20Example.sol
- ERC20 token with metadata, capped supply, and burnable functionality
- Supports authorized minter (in addition to owner)
- Decimals: 10
- Uses OpenZeppelin's ERC20, ERC20Capped, ERC20Burnable, and Ownable

### VrfConsumer.sol
- VRF consumer contract for Chainlink VRF V2+ wrapper
- Implements a lottery system with participant entry fees
- Integrates with ERC20Example to mint tokens to winners
- Uses OpenZeppelin's Ownable for access control

## Integration

To use these contracts together:

1. Deploy `ERC20Example` first
2. Deploy `VrfConsumer` with the VRF wrapper address
3. Set the ERC20 token address in VrfConsumer: `vrfConsumer.setErc20Token(erc20Address)`
4. Set VrfConsumer as authorized minter in ERC20: `erc20.setAuthorizedMinter(vrfConsumerAddress)`

# Forge Test Setup Instructions

## Test Coverage
The test suite verifies:
✅ Interdependent minting functionality between contracts
✅ Full lottery workflow from participation to winner selection
✅ Token distribution to winners
✅ Access control and authorization
✅ Edge cases and error conditions
✅ Multiple lottery rounds

## Running Tests

Run all:

```
cd packages/solidity
forge test
```

Run specific:

```
forge test --match-path test/VrfConsumerIntegration.t.sol
forge test --match-path test/VrfConsumerE2E.t.sol
```

All tests use Forge's cheatcodes (vm.warp(), vm.prank(), vm.expectRevert(), etc.) to simulate the full lottery flow and verify the interdependent functionality between VrfConsumer and ERC20Example.

## Testing Deployed Contracts with Cast

After deploying contracts, you can test them using `cast` commands. The `scripts/test.sh` script provides automated testing examples.

### Quick Testing

Run the test script:
```bash
chmod +x scripts/test.sh
./scripts/test.sh
```

### Manual Testing Examples

#### 1. Check Contract State

```bash
# ERC20 Token Info
cast call --rpc-url $RPC_URL $ERC20 "name()(string)"
cast call --rpc-url $RPC_URL $ERC20 "symbol()(string)"
cast call --rpc-url $RPC_URL $ERC20 "decimals()(uint8)"
cast call --rpc-url $RPC_URL $ERC20 "cap()(uint256)"
cast call --rpc-url $RPC_URL $ERC20 "totalSupply()(uint256)"

# VrfConsumer Info
cast call --rpc-url $RPC_URL $VRF "lotteryEntryFee()(uint256)"
cast call --rpc-url $RPC_URL $VRF "lotteryIntervalHours()(uint256)"
cast call --rpc-url $RPC_URL $VRF "erc20TokenAddress()(address)"
cast call --rpc-url $RPC_URL $VRF "acceptingParticipants()(bool)"
cast call --rpc-url $RPC_URL $VRF "getParticipantCount()(uint256)"
```

#### 2. Participate in Lottery

```bash
# Get entry fee
ENTRY_FEE=$(cast call --rpc-url $RPC_URL $VRF "lotteryEntryFee()(uint256)")

# Participate (send exact entry fee)
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --value $ENTRY_FEE \
  $VRF "participateInLottery()"

# Check participant count
cast call --rpc-url $RPC_URL $VRF "getParticipantCount()(uint256)"
```

#### 3. Request Random Words

```bash
# Calculate VRF request price
CALLBACK_GAS=$(cast call --rpc-url $RPC_URL $VRF "callbackGasLimit()(uint256)")
NUM_WORDS=$(cast call --rpc-url $RPC_URL $VRF "numWords()(uint256)")

REQUEST_PRICE=$(cast call --rpc-url $RPC_URL $MOCK_VRF \
  "calculateRequestPriceNative(uint32,uint32)" \
  $(cast --to-uint256 $CALLBACK_GAS) $(cast --to-uint256 $NUM_WORDS))

# Fund VRF consumer
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  --value $REQUEST_PRICE \
  $VRF

# Request random words (after interval has passed)
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $VRF "requestRandomWords()(uint256)"

# Fulfill request using mock wrapper
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $MOCK_VRF "fulfillRandomWords(uint256,uint256[])" \
  <REQUEST_ID> "[42]"
```

#### 4. Owner Functions

```bash
# Set lottery entry fee
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $VRF "setLotteryEntryFee(uint256)" 1000000

# Set lottery interval hours
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $VRF "setLotteryIntervalHours(uint256)" 2

# Mint tokens directly (as owner)
cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
  $ERC20 "mint(address,uint256)" $OWNER_ADDRESS 1000000000000000000000

# Check balance
cast call --rpc-url $RPC_URL $ERC20 "balanceOf(address)(uint256)" $OWNER_ADDRESS
```

#### 5. Check Winner and Token Distribution

```bash
# Get last fulfilled request
cast call --rpc-url $RPC_URL $VRF "getLastFulfilledId()(uint256)"
cast call --rpc-url $RPC_URL $VRF "getLastFulfilledValue()(uint256)"

# Check token balance of participants
cast call --rpc-url $RPC_URL $ERC20 "balanceOf(address)(uint256)" <PARTICIPANT_ADDRESS>
```

### Notes

- **Time Advancement**: For `requestRandomWords()`, you may need to wait for the lottery interval to pass. On a local node, you can mine blocks or wait.
- **Mock VRF Wrapper**: The mock wrapper allows manual fulfillment for testing. In production, use a real Chainlink VRF wrapper.
- **Gas Estimation**: Use `--gas-limit` if needed:
  ```bash
  cast send --rpc-url $RPC_URL --private-key $PRIVATE_KEY \
    --gas-limit 500000 \
    $CONTRACT_ADDRESS "functionName()"
  ```