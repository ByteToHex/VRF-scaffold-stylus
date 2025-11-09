# Solidity Package Usage Instructions

This package contains Foundry-based Solidity contracts and deployment scripts that mirror the structure of the Stylus package. It includes two contracts: `ERC20Example` and `VrfConsumer`, with their interdependencies automatically configured during deployment.

## Prerequisites

### 1. Install Foundry

Foundry is required for compiling and deploying Solidity contracts. Install it using:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Or follow the official installation guide: https://book.getfoundry.sh/getting-started/installation

### 2. Install Foundry Dependencies

Navigate to the solidity package directory and install required dependencies:

```bash
cd packages/solidity
forge install OpenZeppelin/openzeppelin-contracts
forge install smartcontractkit/chainlink
```

This will install:
- OpenZeppelin Contracts (for ERC20, Ownable, etc.)
- Chainlink Contracts (for VRF interfaces)

### 3. Install Node Dependencies

From the project root, install all workspace dependencies:

```bash
yarn install
```

## Environment Setup

### Environment Variables

The Solidity package **automatically uses the `.env` file from `packages/stylus/`**. You don't need to create a separate `.env` file for the solidity package.

If you don't have a `.env` file yet, create one in `packages/stylus/` with the following variables:

#### For Local Development (Devnet)
```env
PRIVATE_KEY=your_private_key_here
ACCOUNT_ADDRESS=your_account_address_here
RPC_URL=http://localhost:8547
```

#### For Arbitrum Sepolia
```env
PRIVATE_KEY_SEPOLIA=your_private_key_here
ACCOUNT_ADDRESS_SEPOLIA=your_account_address_here
RPC_URL_SEPOLIA=https://sepolia-rollup.arbitrum.io/rpc
VRF_WRAPPER_ADDRESS=0x29576aB8152A09b9DC634804e4aDE73dA1f3a3CC
```

#### For Arbitrum Mainnet
```env
PRIVATE_KEY_MAINNET=your_private_key_here
ACCOUNT_ADDRESS_MAINNET=your_account_address_here
RPC_URL_MAINNET=https://arb1.arbitrum.io/rpc
```

**Note:** The Solidity deployment scripts automatically load the `.env` file from `packages/stylus/` (configured in `packages/solidity/scripts/utils/deployment.ts`, `packages/solidity/scripts/utils/network.ts`, and `packages/solidity/scripts/deploy.ts`). This ensures both Stylus and Solidity packages use the same environment configuration.

## Available Scripts

### Deploy Contracts

Deploy both ERC20Example and VrfConsumer contracts with automatic interdependency configuration:

```bash
# From project root - defaults to devnet if network not specified
yarn solidity:deploy

# Explicitly specify network
yarn solidity:deploy --network devnet

# Or with additional options
yarn solidity:deploy --network arbitrumSepolia --verify
```

#### Deployment Options

- `--network` or `-net`: Network to deploy to (optional)
  - Options: `devnet`, `arbitrumSepolia`, `arbitrum`, `arbitrumNova`, etc.
  - **Default: `devnet`** (set in `packages/solidity/scripts/utils/deployment.ts` line 27)
  - If not specified, defaults to `devnet` which maps to `arbitrumNitro` (local development network)
  
- `--estimate-gas` or `-eg`: Only estimate gas without deploying
  ```bash
  yarn solidity:deploy --network devnet --estimate-gas
  ```

- `--max-fee` or `-mf`: Set maximum fee per gas in gwei
  ```bash
  yarn solidity:deploy --network devnet --max-fee 100
  ```

- `--verify` or `-v`: Verify contracts on block explorer (requires ETHERSCAN_API_KEY)
  ```bash
  yarn solidity:deploy --network arbitrumSepolia --verify
  ```

#### What Happens During Deployment

1. **Compilation**: Contracts are compiled using `forge build`
2. **ERC20 Deployment**: Deploys `ERC20Example` with constructor args:
   - Name: "LotteryToken"
   - Symbol: "LUK"
   - Cap: 1000000000000000000000000 (1 million tokens with 18 decimals)
   - Owner: Your deployer address
3. **VRF Consumer Deployment**: Deploys `VrfConsumer` with constructor args:
   - VRF Wrapper Address: Network-specific (defaults to Arbitrum Sepolia wrapper)
   - Owner: Your deployer address
4. **Interdependency Setup**:
   - Sets VRF Consumer as authorized minter on ERC20 contract
   - Sets ERC20 token address on VRF Consumer contract
5. **ABI Export**: Automatically exports ABIs to `packages/stylus/deployments/{contract-name}/`
6. **Deployment Info**: Saves addresses to `packages/stylus/deployments/{chainId}_latest.json`

### Export ABIs

Export contract ABIs manually (usually done automatically during deployment):

```bash
# From project root
yarn solidity:export-abi ERC20Example
yarn solidity:export-abi VrfConsumer
```

Or from the solidity package directory:

```bash
cd packages/solidity
yarn export-abi ERC20Example
```

**Note:** ABIs are automatically exported during deployment, so this is typically only needed if you want to re-export without redeploying.

### Compile Contracts

Compile contracts without deploying:

```bash
cd packages/solidity
forge build
```

### Run Tests

Run Foundry tests (if you add test files):

```bash
cd packages/solidity
forge test
# Or from root
yarn workspace @ss/solidity test
```

## Contract Details

### ERC20Example

An ERC20 token contract with:
- **Capped supply**: Maximum total supply limit
- **Burnable**: Tokens can be burned
- **Authorized minter**: Can mint tokens (owner or authorized address)
- **Ownable**: Access control via OpenZeppelin Ownable

**Constructor Parameters:**
1. `name`: Token name (string)
2. `symbol`: Token symbol (string)
3. `cap`: Maximum supply cap (uint256)
4. `owner`: Initial owner address (address)

**Key Functions:**
- `mint(address account, uint256 value)`: Mint tokens (owner or authorized minter only)
- `setAuthorizedMinter(address minter)`: Set authorized minter (owner only)
- Standard ERC20 functions: `transfer`, `approve`, `transferFrom`, `burn`, etc.

### VrfConsumer

A VRF consumer contract that:
- Requests randomness from Chainlink VRF V2+ wrapper
- Implements a lottery system with participant management
- Mints ERC20 tokens to winners
- Uses native ETH for VRF payment

**Constructor Parameters:**
1. `vrfV2PlusWrapper`: Address of Chainlink VRF V2+ wrapper contract
2. `owner`: Initial owner address

**Key Functions:**
- `requestRandomWords()`: Request randomness from VRF (pays in native ETH)
- `participateInLottery()`: Pay entry fee to join lottery (payable function)
- `setErc20Token(address tokenAddress)`: Set ERC20 token address (owner only)
- `setLotteryEntryFee(uint256 fee)`: Set entry fee (owner only)
- `setLotteryIntervalHours(uint256 hours)`: Set lottery interval (owner only)
- `getLastFulfilledId()`: Get last fulfilled request ID
- `getLastFulfilledValue()`: Get last fulfilled random value

**Lottery Flow:**
1. Users call `participateInLottery()` with exact entry fee amount
2. Owner calls `requestRandomWords()` to trigger lottery resolution
3. VRF wrapper calls back with random numbers
4. Winner is selected from participants
5. Winner receives ERC20 tokens (entry fees * participant count)
6. Participants array is cleared

## Deployment Directory Structure

All deployment artifacts are stored in the shared `packages/stylus/deployments/` directory:

```
packages/stylus/deployments/
├── 421614_latest.json          # Deployment addresses (chain ID)
├── ERC20Example/
│   └── abi.json                # ERC20 ABI
└── VrfConsumer/
    └── abi.json                # VRF Consumer ABI
```

The `{chainId}_latest.json` file contains:
```json
{
  "ERC20Example": {
    "address": "0x...",
    "txHash": "0x...",
    "contract": "ERC20Example"
  },
  "VrfConsumer": {
    "address": "0x...",
    "txHash": "0x...",
    "contract": "VrfConsumer"
  }
}
```

## Supported Networks

The scripts support the same networks as the Stylus package:

- `devnet` / `arbitrumNitro`: Local development network
- `arbitrumSepolia` / `sepolia`: Arbitrum Sepolia testnet
- `arbitrum` / `mainnet`: Arbitrum One mainnet
- `arbitrumNova` / `nova`: Arbitrum Nova
- `eduChainTestnet`: EduChain testnet
- `eduChain`: EduChain mainnet
- `superposition`: Superposition network
- `superpositionTestnet`: Superposition testnet

## Troubleshooting

### "Foundry not found" Error

Make sure Foundry is installed and in your PATH:
```bash
foundryup
forge --version
```

### "Contract not found" Error

Ensure contracts are compiled:
```bash
cd packages/solidity
forge build
```

### "Insufficient balance" Error

Make sure your deployer account has enough ETH for:
- Contract deployment gas costs
- VRF request payments (for VrfConsumer)

### "ABI not found" Error

ABIs are automatically exported during deployment. If you need to re-export:
```bash
yarn solidity:export-abi <ContractName>
```

### Verification Fails

If contract verification fails:
1. Ensure `ETHERSCAN_API_KEY` is set in your `.env`
2. Wait a few blocks after deployment before verifying
3. Check that the contract source matches exactly

### Workspace Resolution Error

If you see workspace resolution errors:
```bash
yarn install
```

This updates the lockfile with the new `@ss/solidity` workspace.

## Integration with Frontend

The deployed contracts are automatically available to the Next.js frontend through the shared deployment directory. The frontend reads from `packages/stylus/deployments/` to get contract addresses and ABIs.

Contract names used in the frontend:
- `ERC20Example` - for the ERC20 token contract
- `VrfConsumer` - for the VRF consumer contract

These match the contract names saved in the deployment files.

## Example Workflow

1. **Start local chain** (in separate terminal):
   ```bash
   yarn chain
   ```

2. **Deploy contracts**:
   ```bash
   yarn solidity:deploy --network devnet
   ```

3. **Verify deployment**:
   Check `packages/stylus/deployments/421614_latest.json` for addresses

4. **Interact with contracts**:
   Use the frontend debug page or write custom scripts using the deployed addresses

5. **Deploy to testnet**:
   ```bash
   yarn solidity:deploy --network arbitrumSepolia --verify
   ```

## Additional Notes

- The deployment scripts automatically handle contract interdependencies (setting authorized minter, linking ERC20 to VRF consumer)
- ABIs are exported in the same format as Stylus contracts for frontend compatibility
- All deployment data is stored in the shared `packages/stylus/deployments/` directory
- The scripts use the same network configuration and environment variables as the Stylus package

