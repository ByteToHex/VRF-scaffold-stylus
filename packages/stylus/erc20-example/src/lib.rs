#![cfg_attr(not(any(test, feature = "export-abi")), no_main)]
extern crate alloc;

use alloc::vec::Vec;

use openzeppelin_stylus::{
    access::ownable::{self, IOwnable, Ownable},
    token::erc20::{
        self,
        extensions::{capped, Capped, Erc20Metadata, ICapped, IErc20Burnable, IErc20Metadata},
        Erc20, IErc20,
    },
    utils::introspection::erc165::IErc165,
};
use stylus_sdk::{
    alloy_primitives::{aliases::B32, uint, Address, U256, U8},
    prelude::*,
    storage::{StorageAddress, StorageBool},
};

const DECIMALS: U8 = uint!(10_U8); // 10

#[derive(SolidityError, Debug)]
enum Error {
    ExceededCap(capped::ERC20ExceededCap),
    InvalidCap(capped::ERC20InvalidCap),
    InsufficientBalance(erc20::ERC20InsufficientBalance),
    InvalidSender(erc20::ERC20InvalidSender),
    InvalidReceiver(erc20::ERC20InvalidReceiver),
    InsufficientAllowance(erc20::ERC20InsufficientAllowance),
    InvalidSpender(erc20::ERC20InvalidSpender),
    InvalidApprover(erc20::ERC20InvalidApprover),
    UnauthorizedAccount(ownable::OwnableUnauthorizedAccount),
    InvalidOwner(ownable::OwnableInvalidOwner),
}

impl From<capped::Error> for Error {
    fn from(value: capped::Error) -> Self {
        match value {
            capped::Error::ExceededCap(e) => Error::ExceededCap(e),
            capped::Error::InvalidCap(e) => Error::InvalidCap(e),
        }
    }
}

impl From<erc20::Error> for Error {
    fn from(value: erc20::Error) -> Self {
        match value {
            erc20::Error::InsufficientBalance(e) => Error::InsufficientBalance(e),
            erc20::Error::InvalidSender(e) => Error::InvalidSender(e),
            erc20::Error::InvalidReceiver(e) => Error::InvalidReceiver(e),
            erc20::Error::InsufficientAllowance(e) => Error::InsufficientAllowance(e),
            erc20::Error::InvalidSpender(e) => Error::InvalidSpender(e),
            erc20::Error::InvalidApprover(e) => Error::InvalidApprover(e),
        }
    }
}

impl From<ownable::Error> for Error {
    fn from(value: ownable::Error) -> Self {
        match value {
            ownable::Error::UnauthorizedAccount(e) => Error::UnauthorizedAccount(e),
            ownable::Error::InvalidOwner(e) => Error::InvalidOwner(e),
        }
    }
}

#[entrypoint]
#[storage]
struct Erc20Token {
    erc20: Erc20,
    metadata: Erc20Metadata,
    capped: Capped,
    ownable: Ownable,
    authorized_minter: StorageAddress,
    minting: StorageBool,
}

#[public]
impl Erc20Token {
    #[constructor]
    pub fn constructor(
        &mut self,
        name: String,
        symbol: String,
        cap: U256,
        owner: Address,
    ) -> Result<(), Error> {
        println!("Erc20Token constructor called");
        self.metadata.constructor(name, symbol);
        self.capped.constructor(cap)?;
        self.ownable.constructor(owner)?;
        Ok(())
    }

    // Add token minting feature.
    //
    // Make sure to handle `Capped` properly. You should not call
    // [`Erc20::_update`] to mint tokens -- it will the break `Capped`
    // mechanism.
    pub fn mint(&mut self, account: Address, value: U256) -> Result<(), Error> {
        if self.minting.get() {
            return Err(Error::InvalidSender(erc20::ERC20InvalidSender {
                sender: self.vm().msg_sender(),
            }));
        }
        self.minting.set(true);

        // Allow either owner or authorized minter to mint
        let caller = self.vm().msg_sender();
        let owner = self.ownable.owner();
        let authorized = self.authorized_minter.get();
        
        if caller != owner && (authorized == Address::ZERO || caller != authorized) {
            self.minting.set(false);
            return Err(ownable::Error::UnauthorizedAccount(ownable::OwnableUnauthorizedAccount {
                account: caller,
            }))?;
        }

        let max_supply = self.capped.cap();

        // Overflow check required.
        let supply = self
            .erc20
            .total_supply()
            .checked_add(value)
            .expect("new supply should not exceed `U256::MAX`");

        if supply > max_supply {
            self.minting.set(false);
            return Err(capped::Error::ExceededCap(capped::ERC20ExceededCap {
                increased_supply: supply,
                cap: max_supply,
            }))?;
        }

        let result = self.erc20._mint(account, value);
        self.minting.set(false);
        result?;
        Ok(())
    }

    // IErc20 trait implementations
    pub fn total_supply(&self) -> U256 { // current minted/circulating supply, not fully diluted/fdv
        self.erc20.total_supply()
    }

    pub fn balance_of(&self, account: Address) -> U256 {
        self.erc20.balance_of(account)
    }

    pub fn transfer(&mut self, to: Address, value: U256) -> Result<bool, Error> {
        Ok(self.erc20.transfer(to, value)?)
    }

    pub fn allowance(&self, owner: Address, spender: Address) -> U256 {
        self.erc20.allowance(owner, spender)
    }

    pub fn approve(&mut self, spender: Address, value: U256) -> Result<bool, Error> {
        Ok(self.erc20.approve(spender, value)?)
    }

    pub fn transfer_from(
        &mut self,
        from: Address,
        to: Address,
        value: U256,
    ) -> Result<bool, Error> {
        Ok(self.erc20.transfer_from(from, to, value)?)
    }

    // IErc20Burnable trait implementations
    pub fn burn(&mut self, value: U256) -> Result<(), Error> {
        Ok(self.erc20.burn(value)?)
    }

    pub fn burn_from(&mut self, account: Address, value: U256) -> Result<(), Error> {
        Ok(self.erc20.burn_from(account, value)?)
    }

    // IErc20Metadata trait implementations
    pub fn name(&self) -> String {
        self.metadata.name()
    }

    pub fn symbol(&self) -> String {
        self.metadata.symbol()
    }

    pub fn decimals(&self) -> U8 {
        DECIMALS
    }

    // ICapped trait implementations
    pub fn cap(&self) -> U256 {
        self.capped.cap()
    }

    // IErc165 trait implementations
    pub fn supports_interface(&self, interface_id: B32) -> bool {
        Erc20::supports_interface(&self.erc20, interface_id)
            || Erc20Metadata::supports_interface(&self.metadata, interface_id)
    }

    // Authorized minter getter and setter
    pub fn authorized_minter(&self) -> Address {
        self.authorized_minter.get()
    }

    pub fn set_authorized_minter(&mut self, minter: Address) -> Result<(), Error> {
        self.ownable.only_owner()?;
        self.authorized_minter.set(minter);
        Ok(())
    }
}