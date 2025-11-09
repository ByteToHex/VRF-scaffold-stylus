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

## Examples

### Deploy to Local Node
```bash
export RPC_URL=http://127.0.0.1:8547
./deploy.sh
```

### Deploy to Testnet
```bash
export RPC_URL=https://sepolia-rollup.arbitrum.io/rpc
export PRIVATE_KEY=your_private_key_here
./deploy.sh
```

### Test Deployed Contracts
```bash
./test.sh
```

## Manual Commands

If you prefer manual deployment, see `../Instructions.md` for step-by-step cast commands.

