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
        mapping(uint256 => uint256) s_requests_paid;
        mapping(uint256 => uint256) s_requests_value;
        mapping(uint256 => bool) s_requests_fulfilled;
        uint256[] request_ids;
        uint256 last_request_id;

        // 🔧 changed: smaller ints -> uint256 to match 32-byte slot
        uint256 callback_gas_limit;
        uint256 request_confirmations;
        uint256 num_words;

        Ownable ownable;
        bool withdrawing;

        // Event variables
        bool accepting_participants;
        uint256 lottery_interval_hours; 
        uint256 last_request_timestamp;

        // Token distribution variables
        address erc20_token_address;
        address[] participants;
        uint256 lottery_entry_fee;
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

// Define ERC20 interface - minimal interface with only functions we actually use
sol_interface! {
    interface IERC20 {
        // Standard ERC20 functions
        // function totalSupply() external view returns (uint256);
        // function balanceOf(address account) external view returns (uint256);
        function transfer(address to, uint256 amount) external returns (bool);
        // function allowance(address owner, address spender) external view returns (uint256);
        // function approve(address spender, uint256 amount) external returns (bool);
        // function transferFrom(address from, address to, uint256 amount) external returns (bool);
        
        // // ERC20 Burnable functions
        // function burn(uint256 value) external;
        // function burnFrom(address account, uint256 value) external;
        
        // // ERC20 Metadata functions
        // function name() external view returns (string);
        // function symbol() external view returns (string);
        // function decimals() external view returns (uint8);

        // function cap() external view returns (uint256);
        // function supportsInterface(bytes4 interfaceId) external view returns (bool);
        function mint(address account, uint256 value) external;
    }
}

// Define events
sol! {
    event RequestSent(uint256 indexed requestId, uint32 numWords);
    event RequestFulfilled(uint256 indexed requestId, uint256[] randomWords, uint256 payment, address winner);
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
        owner: Address
    ) -> Result<(), Error> {        
        self.ownable.constructor(owner)?;
        self.i_vrf_v2_plus_wrapper.set(vrf_v2_plus_wrapper);
        self.erc20_token_address.set(Address::ZERO);

        self.lottery_entry_fee.set(U256::from(500000));
        self.lottery_interval_hours.set(U256::from(4));
        self.accepting_participants.set(true);
        
        self.callback_gas_limit.set(U256::from(100000u32));
        self.request_confirmations.set(U256::from(3u16));
        self.num_words.set(U256::from(1u32));
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
        let lottery_interval_hours = self.lottery_interval_hours.get();
        let lottery_interval_seconds = lottery_interval_hours * U256::from(3600);
        if block_timestamp < last_timestamp + lottery_interval_seconds {
            return Err(b"Too soon".to_vec());
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
            return Err(b"Token not set".to_vec());
        }
        
        let erc20 = IERC20::new(token_address);
        erc20.mint(&mut *self, recipient, amount)?;
        Ok(())
    }

    /// Internal function to decide the winner
    fn decide_winner(
        &mut self,
        random_words: Vec<U256>,
    ) -> Result<Address, Vec<u8>> {
        if self.participants.is_empty() {
            return Err(b"No participants".to_vec());
        }
    
        if random_words.is_empty() {
            return Err(b"No words".to_vec());
        }
    
        let winner_index: usize = (random_words[0] % U256::from(self.participants.len() as u64))
            .try_into()
            .expect("winner index too large");

        let winner_address = self.participants.get(winner_index)
            .ok_or_else(|| b"Invalid index".to_vec())?;
        let zero_address = Address::repeat_byte(0);

        if winner_address == zero_address {
            return Err(b"No winner".to_vec());
        }

        let total_prize = self.lottery_entry_fee.get() * U256::from(self.participants.len() as u64);
        let reward_amount = total_prize * U256::from(85) / U256::from(100);
    
        self.mint_distribution_reward(winner_address, reward_amount)?;
    
        Ok(winner_address)
    }

    /// Internal function to begin the lottery
    fn fulfill_random_words(
        &mut self,
        request_id: U256,
        random_words: Vec<U256>,
    ) -> Result<(), Error> {
        let paid_amount = self.s_requests_paid.get(request_id);
    
        if paid_amount == U256::ZERO {
            panic!("Request not found");
        }
        self.s_requests_fulfilled.insert(request_id, true);
    
        if !random_words.is_empty() {
            self.s_requests_value.insert(request_id, random_words[0]);
        }
    
        self.accepting_participants.set(false);
    
        let winner_address = match self.decide_winner(random_words.clone()) {
            Ok(addr) => addr,
            Err(_) => Address::ZERO,
        };
    
        log(
            self.vm(), // emit the event in the current contract's execution context
            RequestFulfilled {
                requestId: request_id,
                randomWords: random_words.clone(),
                payment: paid_amount,
                winner: winner_address,
            },
        );
        self.accepting_participants.set(true); // accept new participants again
        Ok(())
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

    /// Withdraw tokens (native or ERC20) If token_address is Address::ZERO, withdraws native tokens
    pub fn withdraw(&mut self, amount: U256, token_address: Address) -> Result<(), Vec<u8>> {
        self.ownable.only_owner()?;
    
        if self.withdrawing.get() {
            return Err(b"Withdrawal in progress".to_vec());
        }
        self.withdrawing.set(true);

        let owner = self.ownable.owner();

        // Determine if withdrawing native or ERC20 tokens
        let is_native = token_address == Address::ZERO;
        
        if is_native {
            // Transfer native tokens
            self.vm()
                .call(&Call::new().value(amount), owner, &[])?;
        } else {
            // Withdraw ERC20 tokens
            let erc20 = IERC20::new(token_address);
            
            // Transfer ERC20 tokens from contract to owner
            erc20.transfer(&mut *self, owner, amount)?;
        }

        self.withdrawing.set(false);

        Ok(())
    }

    /// Withdraw native tokens (backward compatibility)
    pub fn withdraw_native(&mut self, amount: U256) -> Result<(), Vec<u8>> {
        self.withdraw(amount, Address::ZERO)
    }

    /// Withdraw ERC20 tokens (backward compatibility)
    /// Uses the stored ERC20 token address
    pub fn withdraw_erc20(&mut self, amount: U256) -> Result<(), Vec<u8>> {
        let token_address = self.erc20_token_address.get();
        if token_address == Address::ZERO {
            return Err(b"Token not set".to_vec());
        }
        self.withdraw(amount, token_address)
    }

    pub fn owner(&self) -> Address {
        self.ownable.owner()
    }

    // Getter functions for configuration
    pub fn callback_gas_limit(&self) -> u32 {
        self.callback_gas_limit.get().try_into().unwrap_or(100000)
    }
    
    pub fn request_confirmations(&self) -> u16 {
        self.request_confirmations.get().try_into().unwrap_or(3)
    }
    
    pub fn num_words(&self) -> u32 {
        self.num_words.get().try_into().unwrap_or(1)
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

    pub fn accepting_participants(&self) -> bool {
        self.accepting_participants.get()
    }

    // /// Set the event started flag (internal)
    // fn set_accepting_participants(&mut self, started: bool) -> Result<(), Error> {
    //     self.accepting_participants.set(started);
    //     Ok(())
    // }

    pub fn last_request_timestamp(&self) -> U256 {
        self.last_request_timestamp.get()
    }

    pub fn get_user_addresses_count(&self) -> U256 {
        U256::from(self.participants.len())
    }

    pub fn get_user_address(&self, index: U256) -> Result<Address, Vec<u8>> {
        let idx: usize = index.try_into().map_err(|_| b"OOB".to_vec())?;
        if idx >= self.participants.len() {
            return Err(b"OOB".to_vec());
        }
    
        self.participants.get(idx)
            .ok_or_else(|| b"OOB".to_vec())
    }

    /// Participate in the lottery by paying the entry fee
    /// Takes a flat amount from user's wallet and adds them to participants list
    #[payable]
    pub fn participate_in_lottery(&mut self) -> Result<(), Vec<u8>> {
        if !self.accepting_participants.get() {
            return Err(b"Not accepting participants".to_vec());
        }

        if self.participants.contains(&self.vm().msg_sender()) {
            return Err(b"Already participating".to_vec());
        }

        // Get the required entry fee
        let entry_fee = self.lottery_entry_fee.get();
        
        if entry_fee == U256::ZERO {
            return Err(b"Fee not set".to_vec());
        }

        let sent_amount = self.vm().msg_value();
        if sent_amount != entry_fee {
            return Err(b"Wrong amount".to_vec());
        }

        // Get the participant's address
        let participant_address = self.vm().msg_sender();
        
        // Push the address directly (no need to convert to string and back)
        self.participants.push(participant_address);

        Ok(())
    }

    /// Get the lottery entry fee
    pub fn lottery_entry_fee(&self) -> U256 {
        self.lottery_entry_fee.get()
    }

    /// Set the lottery entry fee (owner only)
    pub fn set_lottery_entry_fee(&mut self, fee: U256) -> Result<(), Error> {
        self.ownable.only_owner()?;
        self.lottery_entry_fee.set(fee);
        Ok(())
    }

    /// Get the lottery interval in hours
    pub fn lottery_interval_hours(&self) -> U256 {
        self.lottery_interval_hours.get()
    }

    /// Set the lottery interval in hours (owner only)
    pub fn set_lottery_interval_hours(&mut self, interval_hours: U256) -> Result<(), Error> {
        self.ownable.only_owner()?;
        self.lottery_interval_hours.set(interval_hours);
        Ok(())
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
