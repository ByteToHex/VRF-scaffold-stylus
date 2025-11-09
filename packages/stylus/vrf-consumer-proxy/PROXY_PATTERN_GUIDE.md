# VRF Consumer Proxy Pattern - Implementation Guide

This guide explains how to use the upgradeable proxy pattern for the VRF Consumer contract.

## Overview

The proxy pattern allows you to:
- **Upgrade the logic** of your contract without changing its address
- **Preserve storage** - all state remains intact after upgrades
- **Maintain compatibility** - users always interact with the same contract address

## Architecture

```
┌─────────────────┐
│  Proxy Contract │  ← Users interact with this (fixed address)
│  (Solidity or   │
│   Stylus Proxy) │
└────────┬────────┘
         │ delegatecall
         │
         ▼
┌─────────────────┐
│ Implementation  │  ← Logic contract (can be upgraded)
│  (vrf-consumer) │
└─────────────────┘
```

## Important Note: Stylus Proxy Patterns

⚠️ **Stylus contracts are compiled to WASM**, which means delegatecall behavior may differ from traditional Solidity proxies. 

**Recommended Approach**: Use the **Solidity proxy** (`Proxy.sol`) that delegates to your Stylus implementation. This provides:
- True delegatecall semantics
- Standard EIP-1967 storage slots
- Proven security patterns
- Full compatibility with existing tooling

The Stylus proxy (`lib.rs`) is provided as an alternative, but may have limitations with delegatecall semantics.

## Components

### 1. Proxy Contract (`vrf-consumer-proxy`)
- Stores the implementation address
- Delegates all function calls to the implementation
- Only the owner can upgrade the implementation
- Maintains the same storage layout as the implementation

### 2. Implementation Contract (`vrf-consumer`)
- Contains all the business logic
- Can be upgraded by deploying a new version
- Storage layout must remain compatible between versions

## Deployment Steps

### Option A: Using Solidity Proxy (Recommended)

#### Step 1: Deploy the Stylus Implementation Contract

```bash
cd packages/stylus/vrf-consumer
cargo stylus deploy --endpoint='YOUR_RPC_URL' --private-key='YOUR_PRIVATE_KEY' \
  --constructor-args "VRF_WRAPPER_ADDRESS" "OWNER_ADDRESS"
```

Save the implementation address: `IMPLEMENTATION_ADDRESS`

#### Step 2: Deploy the Solidity Proxy Contract

Compile and deploy `Proxy.sol` using Foundry, Hardhat, or your preferred Solidity tool:

```bash
# Using Foundry
forge build
forge create Proxy \
  --constructor-args IMPLEMENTATION_ADDRESS OWNER_ADDRESS \
  --rpc-url YOUR_RPC_URL \
  --private-key YOUR_PRIVATE_KEY
```

Save the proxy address: `PROXY_ADDRESS`

### Option B: Using Stylus Proxy

#### Step 1: Deploy the Implementation Contract

Same as Option A, Step 1.

#### Step 2: Deploy the Stylus Proxy Contract

```bash
cd packages/stylus/vrf-consumer-proxy
cargo stylus deploy --endpoint='YOUR_RPC_URL' --private-key='YOUR_PRIVATE_KEY' \
  --constructor-args "IMPLEMENTATION_ADDRESS" "OWNER_ADDRESS"
```

Save the proxy address: `PROXY_ADDRESS`

**Note**: The Stylus proxy may have limitations with delegatecall. Option A (Solidity proxy) is recommended for production.

### Step 3: Use the Proxy Address

- Users interact with `PROXY_ADDRESS`
- All calls are forwarded to the implementation
- Storage is maintained in the proxy contract

## Upgrading the Implementation

### Step 1: Deploy New Implementation

```bash
cd packages/stylus/vrf-consumer
# Make your changes to the contract
cargo stylus deploy --endpoint='YOUR_RPC_URL' --private-key='YOUR_PRIVATE_KEY' \
  --constructor-args "VRF_WRAPPER_ADDRESS" "OWNER_ADDRESS"
```

Save the new implementation address: `NEW_IMPLEMENTATION_ADDRESS`

### Step 2: Upgrade the Proxy

Call the `upgrade_implementation` function on the proxy:

```typescript
// Using ethers.js or similar
await proxyContract.upgradeImplementation(NEW_IMPLEMENTATION_ADDRESS);
```

Or using cast:

```bash
cast send PROXY_ADDRESS "upgradeImplementation(address)" NEW_IMPLEMENTATION_ADDRESS \
  --rpc-url YOUR_RPC_URL \
  --private-key YOUR_PRIVATE_KEY
```

## Important Considerations

### Storage Layout Compatibility

⚠️ **CRITICAL**: When upgrading, you must maintain storage layout compatibility:

1. **Never remove storage variables** - only add new ones at the end
2. **Never change variable types** - changing `uint256` to `uint128` will corrupt data
3. **Never reorder variables** - storage slots are based on declaration order
4. **Use storage gaps** - if you remove variables, leave empty slots as placeholders

Example of safe upgrade:

```rust
// Version 1
sol_storage! {
    pub struct VrfConsumer {
        address i_vrf_v2_plus_wrapper;
        uint256 last_fulfilled_id;
        // ... other fields
    }
}

// Version 2 - SAFE: Adding new field at the end
sol_storage! {
    pub struct VrfConsumer {
        address i_vrf_v2_plus_wrapper;
        uint256 last_fulfilled_id;
        // ... other fields from v1
        uint256 new_feature_flag;  // ✅ Safe: new field at end
    }
}
```

### Testing Upgrades

Before upgrading on mainnet:

1. **Test on testnet** - Deploy proxy and implementation on testnet
2. **Test upgrade process** - Verify upgrade works correctly
3. **Test data preservation** - Ensure all state is preserved
4. **Test functionality** - Verify all functions work after upgrade

### Security Considerations

1. **Owner Control**: Only the owner can upgrade. Protect the owner's private key.
2. **Implementation Validation**: The proxy validates that the new implementation has code
3. **No Storage Collision**: Proxy uses EIP-1967 storage slot for implementation address
4. **Access Control**: Consider using a multi-sig for owner operations

## Storage Layout

The proxy uses the EIP-1967 standard storage slot for the implementation address:
- Slot: `0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc`

This prevents storage collision with the implementation contract's storage.

## Function Calls Flow

1. User calls function on proxy: `proxy.requestRandomWords()`
2. Proxy's `fallback()` function is triggered
3. Proxy delegates call to implementation using `delegatecall`
4. Implementation code executes in proxy's storage context
5. Result is returned to user

## Example Usage

```typescript
// Connect to proxy
const proxy = new ethers.Contract(
  PROXY_ADDRESS,
  vrfConsumerABI,  // Use implementation's ABI
  signer
);

// All calls go through proxy to implementation
await proxy.requestRandomWords();
await proxy.participateInLottery({ value: entryFee });
await proxy.getLastFulfilledId();
```

## Troubleshooting

### "Implementation not set" error
- Ensure the implementation address is set in the proxy
- Verify the implementation contract has code deployed

### Storage corruption after upgrade
- Check that storage layout is compatible
- Verify no variables were removed or reordered

### Upgrade fails
- Ensure you're the owner
- Verify new implementation has code
- Check gas limits

## Next Steps

1. Review the proxy contract code in `src/lib.rs`
2. Test deployment on testnet
3. Test upgrade process
4. Deploy to mainnet when ready

