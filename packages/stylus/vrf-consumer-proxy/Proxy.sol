// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title VrfConsumerProxy
 * @dev Upgradeable proxy contract for VRF Consumer
 * 
 * This Solidity proxy uses delegatecall to forward all calls to the Stylus implementation.
 * This is the recommended approach for proxy patterns with Stylus contracts, as it provides
 * true delegatecall semantics where the implementation code runs in the proxy's storage context.
 */
contract VrfConsumerProxy {
    // EIP-1967 implementation slot
    // keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant _IMPLEMENTATION_SLOT = 
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    
    // EIP-1967 admin slot
    // keccak256("eip1967.proxy.admin") - 1
    bytes32 private constant _ADMIN_SLOT = 
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);

    error ImplementationNotSet();
    error Unauthorized();

    constructor(address implementation, address admin) {
        if (implementation == address(0)) {
            revert ImplementationNotSet();
        }
        _setImplementation(implementation);
        _setAdmin(admin);
    }

    modifier onlyAdmin() {
        if (msg.sender != _getAdmin()) {
            revert Unauthorized();
        }
        _;
    }

    function _getImplementation() internal view returns (address) {
        return _getAddressSlot(_IMPLEMENTATION_SLOT);
    }

    function _setImplementation(address newImplementation) internal {
        _setAddressSlot(_IMPLEMENTATION_SLOT, newImplementation);
        emit Upgraded(newImplementation);
    }

    function _getAdmin() internal view returns (address) {
        return _getAddressSlot(_ADMIN_SLOT);
    }

    function _setAdmin(address newAdmin) internal {
        address oldAdmin = _getAdmin();
        _setAddressSlot(_ADMIN_SLOT, newAdmin);
        emit AdminChanged(oldAdmin, newAdmin);
    }

    function _getAddressSlot(bytes32 slot) internal pure returns (address addr) {
        assembly {
            addr := sload(slot)
        }
    }

    function _setAddressSlot(bytes32 slot, address addr) internal {
        assembly {
            sstore(slot, addr)
        }
    }

    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    function upgradeImplementation(address newImplementation) external onlyAdmin {
        if (newImplementation == address(0)) {
            revert ImplementationNotSet();
        }
        _setImplementation(newImplementation);
    }

    function getAdmin() external view returns (address) {
        return _getAdmin();
    }

    function changeAdmin(address newAdmin) external onlyAdmin {
        _setAdmin(newAdmin);
    }

    /**
     * @dev Fallback function that delegates all calls to the implementation.
     * This function uses delegatecall, so the implementation code runs in the proxy's storage context.
     */
    fallback() external payable {
        address impl = _getImplementation();
        if (impl == address(0)) {
            revert ImplementationNotSet();
        }

        assembly {
            // Copy calldata to memory
            calldatacopy(0, 0, calldatasize())

            // Delegate call to implementation
            let result := delegatecall(gas(), impl, 0, calldatasize(), 0, 0)

            // Copy return data
            returndatacopy(0, 0, returndatasize())

            // Return or revert
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /**
     * @dev Receive function for handling plain ETH transfers
     */
    receive() external payable {
        // Forward to implementation if it has a receive function
        address impl = _getImplementation();
        if (impl != address(0)) {
            (bool success, ) = impl.delegatecall("");
            // Silently ignore if implementation doesn't have receive
            // This allows the proxy to accept ETH even if impl doesn't handle it
        }
    }
}

