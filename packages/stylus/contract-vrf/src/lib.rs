//!
//! VrfConsumer in Stylus Rust
//!
//! A VRF consumer contract that requests randomness from Chainlink VRF V2+ wrapper
//! using native tokens (ETH) for payment.
//!
//! This is the Stylus Rust equivalent of the Solidity VrfConsumer.
//!

// Allow `cargo stylus export-abi` to generate a main function.
#![cfg_attr(not(any(test, feature = "export-abi")), no_main)]
#![cfg_attr(not(any(test, feature = "export-abi")), no_std)]

#[macro_use]
extern crate alloc;

use alloc::vec::Vec;
use alloc::string::String;

/// Import items from the SDK. The prelude contains common traits and macros.
use stylus_sdk::{
    alloy_primitives::{Address, Bytes, U16, U256, U32},
    alloy_sol_types::sol,
    prelude::*,
    stylus_core::calls::context::Call,
    stylus_core::log,
};

// Import deprecated Call for sol_interface! compatibility
#[allow(deprecated)]
use stylus_sdk::call::Call as OldCall;

/// Import OpenZeppelin Ownable functionality
use openzeppelin_stylus::access::ownable::{self, Ownable};

// Define persistent storage using the Solidity ABI.
sol_storage! {
    #[entrypoint]
    pub struct VrfConsumer {
        // VRF variables
        address i_vrf_v2_plus_wrapper;
        mapping(uint256 => uint256) s_requests_paid; // store the amount paid for request random words
        mapping(uint256 => uint256) s_requests_value; // store random word returned
        mapping(uint256 => bool) s_requests_fulfilled; // store if request was fulfilled
        uint256[] request_ids;
        uint256 last_request_id;
        uint32 callback_gas_limit;
        uint16 request_confirmations;
        uint32 num_words;
        Ownable ownable;
        bool withdrawing;

        // Event variables
        bool event_started; // flag for "EventStarted"
        uint256 last_request_timestamp; // block timestamp for the last time request_random_words was called

        // Token distribution variables
        address erc20_token_address; // ERC20 token address for token distribution
        mapping(string => uint256) user_stakes; // user address (as string) : staked amount (no decimals)
        string[] user_addresses; // user addresses preserved for order
        uint256 total_staked; // sum of total staked amounts
    }
}

// Define the VRF V2+ Wrapper interface
sol_interface! {
    interface IVRFV2PlusWrapper {
        function calculateRequestPriceNative(uint32 _callbackGasLimit, uint32 _numWords) external view returns (uint256);
        function requestRandomWordsInNative(
            uint32 _callbackGasLimit,
            uint16 _requestConfirmations,
            uint32 _numWords,
            bytes calldata extraArgs
        ) external payable returns (uint256 requestId);
    }
}

// Define ERC20 interface
sol_interface! {
    interface IERC20 {
        // Standard ERC20 functions
        function totalSupply() external view returns (uint256);
        function balanceOf(address account) external view returns (uint256);
        function transfer(address to, uint256 amount) external returns (bool);
        function allowance(address owner, address spender) external view returns (uint256);
        function approve(address spender, uint256 amount) external returns (bool);
        function transferFrom(address from, address to, uint256 amount) external returns (bool);
        
        // ERC20 Burnable functions
        function burn(uint256 value) external;
        function burnFrom(address account, uint256 value) external;
        
        // ERC20 Metadata functions
        function name() external view returns (string);
        function symbol() external view returns (string);
        function decimals() external view returns (uint8);
        
        // Capped functions
        function cap() external view returns (uint256);
        
        // ERC165 function
        function supportsInterface(bytes4 interfaceId) external view returns (bool);
        
        // Mint function (owner only, but included for completeness)
        function mint(address account, uint256 value) external;
    }
}

// Define events
sol! {
    event RequestSent(uint256 indexed requestId, uint32 numWords);
    event RequestFulfilled(uint256 indexed requestId, uint256[] randomWords, uint256 payment);
    event Received(address indexed sender, uint256 value);
}

// Define custom errors
sol! {
    #[derive(Debug)]
    error OnlyVRFWrapperCanFulfill(address have, address want);
}

#[derive(SolidityError, Debug)]
pub enum Error {
    OnlyVRFWrapperCanFulfill(OnlyVRFWrapperCanFulfill),
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
/// Declare that `VrfConsumer` is a contract with the following external methods.
#[public]
impl VrfConsumer {
    /// Constructor - initializes the contract with VRF wrapper address and ERC20 token address
    #[constructor]
    pub fn constructor(
        &mut self,
        vrf_v2_plus_wrapper: Address,
        owner: Address,
        erc20_token: Address,
    ) -> Result<(), Error> {
        // Debug: Print addresses received in constructor
        #[cfg(debug_assertions)]
        {
            debug_print_addresses(vrf_v2_plus_wrapper, owner, erc20_token);
        }
        
        self.ownable.constructor(owner)?;
        self.i_vrf_v2_plus_wrapper.set(vrf_v2_plus_wrapper);
        self.erc20_token_address.set(erc20_token);
        
        // Debug: Print stored addresses after setting
        #[cfg(debug_assertions)]
        {
            let stored_vrf = self.i_vrf_v2_plus_wrapper.get();
            let stored_erc20 = self.erc20_token_address.get();
            debug_print_address("Stored VRF Wrapper", stored_vrf);
            debug_print_address("Stored ERC20 Token", stored_erc20);
        }
        
        self.callback_gas_limit.set(U32::from(100000));
        self.request_confirmations.set(U16::from(3));
        self.num_words.set(U32::from(1));
        Ok(())
    }

    /// Internal function to request randomness paying in native ETH token
    fn request_randomness_pay_in_native(
        &mut self,
        callback_gas_limit: u32,
        request_confirmations: u16,
        num_words: u32,
    ) -> Result<(U256, U256), Vec<u8>> {
        let external_vrf_wrapper_address = self.i_vrf_v2_plus_wrapper.get();

        let external_vrf_wrapper = IVRFV2PlusWrapper::new(external_vrf_wrapper_address);

        // Calculate request price
        let request_price = external_vrf_wrapper.calculate_request_price_native(
            &mut *self,
            callback_gas_limit,
            num_words,
        )?;

        let extra_args = get_extra_args_for_native_payment();

        // Create call context with value. This is to ensure that the consumer can pay for the request.
        // Using OldCall here is necessary for compatibility with sol_interface! generated code
        #[allow(deprecated)]
        let config = OldCall::new().value(request_price);

        // Request random words
        let request_id = external_vrf_wrapper.request_random_words_in_native(
            config,
            callback_gas_limit,
            request_confirmations,
            num_words,
            extra_args,
        )?;

        Ok((request_id, request_price))
    }

    pub fn request_random_words(&mut self) -> Result<U256, Vec<u8>> {
        let block_timestamp = U256::from(self.vm().block_timestamp());
        let last_timestamp = self.last_request_timestamp.get();
        let one_hour = U256::from(3600);
        if block_timestamp < last_timestamp + one_hour {
            return Err(b"Raffle can only be performed once every hour".to_vec());
        }
    
        let callback_gas_limit = self.callback_gas_limit.get().try_into().unwrap_or(100000);
        let request_confirmations = self.request_confirmations.get().try_into().unwrap_or(3);
        let num_words = self.num_words.get().try_into().unwrap_or(1);
    
        let (request_id, req_price) = self.request_randomness_pay_in_native(
            callback_gas_limit,
            request_confirmations,
            num_words,
        )?;
    
        self.s_requests_fulfilled.insert(request_id, false);
        self.s_requests_paid.insert(request_id, req_price);
    
        self.request_ids.push(request_id);
        self.last_request_id.set(request_id);
        self.last_request_timestamp.set(block_timestamp);
    
        log(
            self.vm(),
            RequestSent {
                requestId: request_id,
                numWords: num_words,
            },
        );
    
        Ok(request_id)
    }

    /// View: get the current native price required to request randomness
    pub fn get_request_price(&mut self) -> Result<U256, Vec<u8>> {
        let callback_gas_limit: u32 = self.callback_gas_limit.get().try_into().unwrap_or(100000);
        let num_words: u32 = self.num_words.get().try_into().unwrap_or(1);

        let external_vrf_wrapper_address = self.i_vrf_v2_plus_wrapper.get();
        let external_vrf_wrapper = IVRFV2PlusWrapper::new(external_vrf_wrapper_address);

        let price = external_vrf_wrapper.calculate_request_price_native(
            &mut *self,
            callback_gas_limit,
            num_words,
        )?;

        Ok(price)
    }

    /// Internal function to distribute ERC20 tokens
    fn mint_distribution_reward(
        &mut self,
        recipient: Address,
        amount: U256,
    ) -> Result<(), Vec<u8>> {
        let token_address = self.erc20_token_address.get();
        
        if token_address == Address::ZERO {
            return Err("ERC20 token not set".into());
        }
        
        let erc20 = IERC20::new(token_address);
        erc20.mint(&mut *self, recipient, amount)?;
        Ok(())
    }

    /// Internal function to fulfill random words
    fn fulfill_random_words(
        &mut self,
        request_id: U256,
        random_words: Vec<U256>,
    ) -> Result<(), Error> {
        let paid_amount = self.s_requests_paid.get(request_id);

        if paid_amount == U256::ZERO {
            panic!("Request not found");
        }

        //request_status.fulfilled = true;
        self.s_requests_fulfilled.insert(request_id, true);

        if !random_words.is_empty() {
            self.s_requests_value.insert(request_id, random_words[0]);
        }

        // Emit event
        log(
            self.vm(), // emit the event in the current contract’s execution context
            RequestFulfilled {
                requestId: request_id,
                randomWords: random_words,
                payment: paid_amount,
            },
        );

        Ok(())
        // TODO: implement the distribution of ERC20 tokens based on the random words; pass user addss and number
    }

    /// External function called by VRF wrapper to fulfill randomness
    pub fn raw_fulfill_random_words(
        &mut self,
        request_id: U256,
        random_words: Vec<U256>,
    ) -> Result<(), Error> {
        let vrf_wrapper_addr = self.i_vrf_v2_plus_wrapper.get();
        let msg_sender = self.vm().msg_sender();
        if msg_sender != vrf_wrapper_addr {
            return Err(Error::OnlyVRFWrapperCanFulfill(OnlyVRFWrapperCanFulfill {
                have: msg_sender,
                want: vrf_wrapper_addr,
            }));
        }

        self.fulfill_random_words(request_id, random_words)
    }

    /// Get the status of a randomness request
    pub fn get_request_status(&self, request_id: U256) -> Result<(U256, bool, U256), Vec<u8>> {
        let paid = self.s_requests_paid.get(request_id);

        if paid == U256::ZERO {
            panic!("Request not found");
        }

        let fulfilled = self.s_requests_fulfilled.get(request_id);
        let random_word = self.s_requests_value.get(request_id);

        Ok((paid, fulfilled, random_word))
    }

    /// Get the last request ID
    pub fn get_last_request_id(&self) -> U256 {
        self.last_request_id.get()
    }

    /// Withdraw native tokens
    pub fn withdraw_native(&mut self, amount: U256) -> Result<(), Vec<u8>> {
        self.ownable.only_owner()?;
    
        if self.withdrawing.get() {
            return Err("Only one withdrawal at a time".into());
        }
        self.withdrawing.set(true);

        // Transfer the amount
        self.vm()
            .call(&Call::new().value(amount), self.ownable.owner(), &[])?;

        self.withdrawing.set(false);

        Ok(())
    }

    /// Withdraw ERC20 tokens
    pub fn withdraw_erc20(&mut self, amount: U256) -> Result<(), Vec<u8>> {
        self.ownable.only_owner()?;
    
        if self.withdrawing.get() {
            return Err("Only one withdrawal at a time".into());
        }
        self.withdrawing.set(true);

        let token_address = self.erc20_token_address.get();
        
        if token_address == Address::ZERO {
            self.withdrawing.set(false);
            return Err("ERC20 token not set".into());
        }

        let erc20 = IERC20::new(token_address);
        let owner = self.ownable.owner();
        
        // Transfer ERC20 tokens from contract to owner
        erc20.transfer(&mut *self, owner, amount)?;

        self.withdrawing.set(false);

        Ok(())
    }

    pub fn owner(&self) -> Address {
        self.ownable.owner()
    }

    // Getter functions for configuration
    pub fn callback_gas_limit(&self) -> U32 {
        self.callback_gas_limit.get()
    }

    pub fn request_confirmations(&self) -> U16 {
        self.request_confirmations.get()
    }

    pub fn num_words(&self) -> U32 {
        self.num_words.get()
    }

    pub fn i_vrf_v2_plus_wrapper(&self) -> Address {
        self.i_vrf_v2_plus_wrapper.get()
    }

    pub fn erc20_token_address(&self) -> Address {
        self.erc20_token_address.get()
    }

    pub fn set_erc20_token(&mut self, token_address: Address) -> Result<(), Error> {
        self.ownable.only_owner()?;
        self.erc20_token_address.set(token_address);
        Ok(())
    }

    pub fn event_started(&self) -> bool {
        self.event_started.get()
    }

    /// Set the event started flag (internal)
    fn set_event_started(&mut self, started: bool) -> Result<(), Error> {
        self.event_started.set(started);
        Ok(())
    }

    pub fn last_request_timestamp(&self) -> U256 {
        self.last_request_timestamp.get()
    }

    pub fn get_user_stake(&self, user_address: String) -> U256 {
        self.user_stakes.get(user_address)
    }

    pub fn get_user_addresses_count(&self) -> U256 {
        U256::from(self.user_addresses.len())
    }

    pub fn get_user_address(&self, index: U256) -> Result<String, Vec<u8>> {
        let idx: usize = index.try_into().map_err(|_| "Index out of bounds".as_bytes().to_vec())?;
        if idx >= self.user_addresses.len() {
            return Err("Index out of bounds".into());
        }
        Ok(self.user_addresses.get(idx).cloned().unwrap_or_default())
    }

    pub fn total_staked(&self) -> U256 {
        self.total_staked.get()
    }

    /// Receive function equivalent - handles incoming ETH
    #[receive]
    #[payable]
    pub fn receive(&mut self) -> Result<(), Vec<u8>> {
        log(
            self.vm(),
            Received {
                sender: self.vm().msg_sender(),
                value: self.vm().msg_value(),
            },
        );
        Ok(())
    }
}

// Note: We keep ownership management internal through `ownable`.

/// Debug helper function to print an address with a label
#[cfg(debug_assertions)]
fn debug_print_address(label: &str, address: Address) {
    let address_hex = format!("{:?}", address);
    println!("[VRF DEBUG] {}: {}", label, address_hex);
}

/// Debug helper function to print multiple addresses
#[cfg(debug_assertions)]
fn debug_print_addresses(
    vrf_wrapper: Address,
    owner: Address,
    erc20_token: Address,
) {
    debug_print_address("VRF Wrapper Address", vrf_wrapper);
    debug_print_address("Owner Address", owner);
    debug_print_address("ERC20 Token Address", erc20_token);
}

fn get_extra_args_for_native_payment() -> Bytes {
    // Encode extra args according to VRFV2PlusClient._argsToBytes()
    // Format: abi.encodeWithSelector(EXTRA_ARGS_V1_TAG, extraArgs)
    // where EXTRA_ARGS_V1_TAG = bytes4(keccak256("VRF ExtraArgsV1")) = 0x92fd1338
    let mut extra_args_vec = Vec::new();
    extra_args_vec.extend_from_slice(&[0x92, 0xfd, 0x13, 0x38]); // EXTRA_ARGS_V1_TAG
    extra_args_vec.extend_from_slice(&[0x00; 28]); // Padding for struct alignment
    extra_args_vec.extend_from_slice(&[0x00, 0x00, 0x00, 0x01]); // nativePayment: true
    extra_args_vec.extend_from_slice(&[0x00; 28]); // Final padding
    Bytes::from(extra_args_vec)
}
