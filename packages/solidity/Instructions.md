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

To deploy contracts using Foundry:

```bash
forge script script/Deploy.sol:DeployScript --rpc-url <RPC_URL> --broadcast --verify
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