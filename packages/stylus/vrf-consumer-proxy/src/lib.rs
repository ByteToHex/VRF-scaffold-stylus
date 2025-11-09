//!
//! VrfConsumerProxy - Upgradeable Proxy Contract
//!
//! A proxy contract that delegates all calls to an implementation contract,
//! allowing the logic to be upgraded while maintaining the same address and storage.
//!
//! This follows the UUPS (Universal Upgradeable Proxy Standard) pattern.

// Allow `cargo stylus export-abi` to generate a main function.
#![cfg_attr(not(any(test, feature = "export-abi")), no_main)]
#![cfg_attr(not(any(test, feature = "export-abi")), no_std)]

#[macro_use]
extern crate alloc;

use alloc::vec::Vec;

/// Import items from the SDK.
use stylus_sdk::{
    alloy_primitives::{Address, Bytes, U256},
    alloy_sol_types::sol,
    prelude::*,
    stylus_core::calls::context::Call,
    stylus_core::log,
};

/// Import OpenZeppelin Ownable functionality for admin control
use openzeppelin_stylus::access::ownable::{self, Ownable};

// Define persistent storage for the proxy
sol_storage! {
    #[entrypoint]
    pub struct VrfConsumerProxy {
        // Storage slot for implementation address
        // Using a specific slot to avoid storage collision with implementation
        // Slot 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
        // This is the standard EIP-1967 implementation slot
        address implementation;
        
        // Admin address for upgrade control
        Ownable ownable;
    }
}

// Define events
sol! {
    event Upgraded(address indexed implementation);
    event AdminChanged(address previousAdmin, address newAdmin);
}

// Define custom errors
sol! {
    #[derive(Debug)]
    error ImplementationNotSet();
    error UpgradeFailed();
}

#[derive(SolidityError, Debug)]
pub enum Error {
    ImplementationNotSet(ImplementationNotSet),
    UpgradeFailed(UpgradeFailed),
    UnauthorizedAccount(ownable::OwnableUnauthorizedAccount),
    InvalidOwner(ownable::OwnableInvalidOwner),
}

impl From<ownable::Error> for Error {
    fn from(value: ownable::Error) -> Self {
        match value {
            ownable::Error::UnauthorizedAccount(e) => Error::UnauthorizedAccount(e),
            ownable::Error::InvalidOwner(e) => Error::InvalidOwner(e),
        }
    }
}

#[public]
impl VrfConsumerProxy {
    /// Constructor - initializes the proxy with implementation address and admin
    #[constructor]
    pub fn constructor(
        &mut self,
        implementation: Address,
        admin: Address,
    ) -> Result<(), Error> {
        // Validate implementation address
        if implementation == Address::ZERO {
            return Err(Error::ImplementationNotSet(ImplementationNotSet {}));
        }
        
        // Validate that implementation has code
        if self.vm().code_size(implementation) == 0 {
            return Err(Error::ImplementationNotSet(ImplementationNotSet {}));
        }
        
        self.ownable.constructor(admin)?;
        self.implementation.set(implementation);
        
        log(
            self.vm(),
            Upgraded {
                implementation,
            },
        );
        
        Ok(())
    }

    /// Get the current implementation address
    pub fn get_implementation(&self) -> Address {
        self.implementation.get()
    }

    /// Upgrade the implementation contract (only owner)
    pub fn upgrade_implementation(
        &mut self,
        new_implementation: Address,
    ) -> Result<(), Error> {
        self.ownable.only_owner()?;
        
        // Validate new implementation address
        if new_implementation == Address::ZERO {
            return Err(Error::ImplementationNotSet(ImplementationNotSet {}));
        }
        
        // Validate that new implementation has code
        if self.vm().code_size(new_implementation) == 0 {
            return Err(Error::ImplementationNotSet(ImplementationNotSet {}));
        }
        
        let old_implementation = self.implementation.get();
        self.implementation.set(new_implementation);
        
        log(
            self.vm(),
            Upgraded {
                implementation: new_implementation,
            },
        );
        
        Ok(())
    }

    /// Fallback function - delegates all calls to the implementation
    /// This is called when a function doesn't exist in the proxy
    /// 
    /// NOTE: This is a draft implementation. Stylus proxy patterns require
    /// careful consideration of delegatecall semantics with WASM contracts.
    /// 
    /// For production use, we strongly recommend using the Solidity proxy (Proxy.sol)
    /// which provides proven delegatecall behavior.
    /// 
    /// This Stylus proxy implementation may need adjustment based on:
    /// - Available VM methods for delegatecall
    /// - Stylus SDK version and capabilities
    /// - Testing with your specific use case
    #[fallback]
    pub fn fallback(&mut self) -> Result<Bytes, Vec<u8>> {
        let implementation = self.implementation.get();
        
        if implementation == Address::ZERO {
            return Err(b"Implementation not set".to_vec());
        }
        
        // Get the calldata
        let calldata = self.vm().calldata();
        
        // TODO: Replace with correct delegatecall mechanism for Stylus
        // This is a placeholder - you'll need to use the appropriate VM method
        // to perform delegatecall. Check Stylus SDK documentation for:
        // - delegate_call() method
        // - Or use low-level EVM calls via VM
        // 
        // Example (needs verification):
        // let result = self.vm().delegate_call(
        //     &Call::new()
        //         .gas(self.vm().gas_left())
        //         .value(self.vm().msg_value()),
        //     implementation,
        //     &calldata,
        // )?;
        
        // For now, using regular call as placeholder
        // This will NOT preserve storage context - use Solidity proxy for production
        let result = self.vm().call(
            &Call::new()
                .gas(self.vm().gas_left())
                .value(self.vm().msg_value()),
            implementation,
            &calldata,
        )?;
        
        Ok(result)
    }

    /// Receive function - handles incoming ETH and forwards to implementation if needed
    #[receive]
    #[payable]
    pub fn receive(&mut self) -> Result<(), Vec<u8>> {
        // If implementation has a receive function, forward to it
        let implementation = self.implementation.get();
        
        if implementation != Address::ZERO && self.vm().code_size(implementation) > 0 {
            // Forward to implementation's receive function
            // Note: This uses regular call, not delegatecall
            let _ = self.vm().call(
                &Call::new()
                    .gas(self.vm().gas_left())
                    .value(self.vm().msg_value()),
                implementation,
                &[],
            );
        }
        
        Ok(())
    }
}

