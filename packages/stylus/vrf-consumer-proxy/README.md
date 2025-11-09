# VRF Consumer Proxy - Upgradeable Contract Pattern

This directory contains a draft implementation of an upgradeable proxy pattern for the VRF Consumer contract.

## What's Included

1. **`Proxy.sol`** - A Solidity proxy contract (RECOMMENDED for production)
   - Uses standard EIP-1967 storage slots
   - Implements true delegatecall semantics
   - Proven security patterns

2. **`src/lib.rs`** - A Stylus proxy contract (experimental)
   - Draft implementation for Stylus-native proxy
   - May have limitations with delegatecall
   - Requires verification of Stylus SDK capabilities

3. **`PROXY_PATTERN_GUIDE.md`** - Comprehensive guide
   - Architecture explanation
   - Deployment instructions
   - Upgrade procedures
   - Security considerations

## Quick Start

### Recommended: Solidity Proxy

1. Deploy your VRF Consumer implementation:
   ```bash
   cd ../vrf-consumer
   cargo stylus deploy --constructor-args "VRF_WRAPPER" "OWNER"
   ```

2. Deploy the Solidity proxy:
   ```bash
   # Using Foundry
   forge create Proxy --constructor-args IMPLEMENTATION_ADDRESS OWNER_ADDRESS
   ```

3. Use the proxy address for all interactions.

### Alternative: Stylus Proxy

⚠️ **Note**: The Stylus proxy is experimental and may not provide true delegatecall semantics. Use with caution.

1. Deploy implementation (same as above)
2. Deploy Stylus proxy:
   ```bash
   cd vrf-consumer-proxy
   cargo stylus deploy --constructor-args IMPLEMENTATION_ADDRESS OWNER_ADDRESS
   ```

## Key Features

- ✅ **Upgradeable Logic**: Change implementation without changing address
- ✅ **Storage Preservation**: All state maintained across upgrades
- ✅ **Owner Control**: Only owner can upgrade
- ✅ **EIP-1967 Compatible**: Standard storage slots

## Important Considerations

1. **Storage Layout**: Never remove or reorder storage variables when upgrading
2. **Testing**: Always test upgrades on testnet first
3. **Security**: Protect the owner's private key (consider multi-sig)
4. **Stylus Limitations**: Stylus proxy may not support true delegatecall - use Solidity proxy for production

## Next Steps

1. Review `PROXY_PATTERN_GUIDE.md` for detailed instructions
2. Test deployment on testnet
3. Verify upgrade process works correctly
4. Deploy to mainnet when ready

## Questions?

- Check the guide: `PROXY_PATTERN_GUIDE.md`
- Review the code comments in `Proxy.sol` and `src/lib.rs`
- Test thoroughly on testnet before mainnet deployment

