# Deployment and Testing Scripts

This directory contains scripts for deploying and testing the Solidity contracts.

## Scripts

### `deploy.sh`
Deploys all contracts (MockVRFV2PlusWrapper, ERC20Example, VrfConsumer) and configures them for integration.

**Usage:**
- Linux/Mac: `chmod +x deploy.sh && ./deploy.sh`

**Environment Variables:**
- `RPC_URL` - RPC endpoint (default: `http://127.0.0.1:8547`)
- `PRIVATE_KEY` - Private key for deployment (default: dev node key)

**`.env` File Support:**
The script automatically loads environment variables from a `.env` file, but **only when not deploying to a local node**. 

- **Local node detection**: If `RPC_URL` is empty, points to `127.0.0.1:8547`, or contains `localhost`, the `.env` file is skipped
- **Non-local networks**: When deploying to testnets/mainnets, the script will look for `.env` files in:
  1. Project root (workspace root)
  2. `packages/solidity/` directory
  3. Current working directory

The `.env` file should contain `KEY=VALUE` pairs (one per line). Comments (lines starting with `#`) and empty lines are ignored. Example:
```
RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
PRIVATE_KEY=0x...
ARBISCAN_API_KEY=your_api_key_here
CHAIN_ID=421614
```

**Note:** Environment variables set in your shell take precedence over `.env` file values.

**Output:**
- Contract addresses printed to console
- ABIs exported to `../deployments/abis/`
- Deployment info saved to `../deployments/deployment_info.json`

### `test.sh`
Tests deployed contracts using cast commands. Demonstrates various interactions.

**Usage:**
```bash
chmod +x test.sh
./test.sh
```

**Requirements:**
- Contracts must be deployed first (run `deploy.sh`)
- `jq` must be installed (for parsing deployment info)

### `export_abis.sh`
Exports ABIs from compiled contracts to `deployments/abis/`.

**Usage:**
```bash
chmod +x export_abis.sh
./export_abis.sh
```

**Note:** Contracts must be compiled first (`forge build`).

### `verify.sh`
Verifies deployed contracts on block explorers (Arbiscan, Etherscan) for public interaction.

**Usage:**
```bash
chmod +x verify.sh
./verify.sh
```

**Automatic Mode (called from deploy.sh):**
The verification script is automatically called by `deploy.sh` when deploying to non-local networks. It uses environment variables set during deployment.

**Manual Mode:**
```bash
# Verify a single contract
./verify.sh <address> <contract_name> [constructor_args]

# Example with constructor args
./verify.sh 0x123... contracts/ERC20Example.sol:ERC20Example "$(cast abi-encode 'constructor(string,string,uint256,address)' 'Token' 'TKN' 1000000 0xOwner)"
```

**Environment Variables:**
- `ARBISCAN_API_KEY` - API key for Arbitrum networks (required for chain IDs 421614, 42161)
- `ETHERSCAN_API_KEY` - API key for Ethereum networks (required for chain IDs 1, 11155111)
- `CHAIN_ID` - Chain ID (auto-detected from RPC_URL if not set)
- `RPC_URL` - RPC endpoint (default: `http://127.0.0.1:8547`)
- `VERIFY_SKIP` - Set to `true` to skip verification

**Note:** 
- Verification is automatically skipped on local networks
- Contracts must be deployed before verification
- Get API keys from [Arbiscan](https://arbiscan.io/myapikey) or [Etherscan](https://etherscan.io/myapikey)

## Examples

### Deploy to Local Node
```bash
export RPC_URL=http://127.0.0.1:8547
./deploy.sh
```

### Deploy to Testnet

**Option 1: Using environment variables**
```bash
export RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
export PRIVATE_KEY=your_private_key_here
export ARBISCAN_API_KEY=your_arbiscan_api_key_here
./deploy.sh
```

**Option 2: Using .env file (recommended)**
Create a `.env` file in the project root:
```bash
RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
PRIVATE_KEY=your_private_key_here
ARBISCAN_API_KEY=your_arbiscan_api_key_here
CHAIN_ID=421614
```

Then simply run:
```bash
./deploy.sh
```

The script will automatically detect it's not a local node and load the `.env` file.

**Note:** 
- If `ARBISCAN_API_KEY` is set, contracts will be automatically verified after deployment
- The `.env` file is **not** loaded when deploying to local nodes (127.0.0.1:8547 or localhost)

### Test Deployed Contracts
```bash
./test.sh
```

### Verify Contracts Manually
```bash
# Verify all contracts (uses environment variables from deployment)
./verify.sh

# Or verify a specific contract
./verify.sh 0x123... contracts/VrfConsumer.sol:VrfConsumer "$(cast abi-encode 'constructor(address,address)' 0xVRFWrapper 0xOwner)"
```

## Manual Commands

If you prefer manual deployment, see `../Instructions.md` for step-by-step cast commands.

