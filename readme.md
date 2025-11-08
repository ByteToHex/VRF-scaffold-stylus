## **Stylus VRF Consumer Lottery & ERC20 Reward System**

### **Purpose**

This project implements a **provably fair on-chain lottery** using **Chainlink VRF V2+** and **Stylus (Arbitrum)**.
It uses two **interdependent contracts**:

* **VRF Consumer:** Manages lottery entries, randomness requests, and winner selection.
* **ERC20 Token:** Handles reward minting and enforces consensus by trusting only the VRF Consumer as the authorized minter.

Together, they form a system where:

1. Participants enter by paying ETH (`participate_in_lottery()`).
2. Chainlink Automation triggers periodic randomness requests (`request_random_words()`).
3. Chainlink VRF provides verifiable randomness (`raw_fulfill_random_words()`).
4. The VRF Consumer selects a random winner.
5. The ERC20 contract mints tokens directly to the winner, validating that the mint request originated from the trusted VRF Consumer.

---

### **Core VRF Flow**

I spent the most time on the smart contracts, which can be found here:
 - **..\vrf-scaffold-stylus\packages\stylus\erc20-example\src\lib.rs**
 - **..\vrf-scaffold-stylus\packages\stylus\vrf-consumer\src\lib.rs**
 
There is a lot of functionality that I was unable to include as it would exceed the 24 MiB limit on deployable contracts to the local node/test chain.

#### 1. **Request Random Outcome**

**`request_random_words()`**

* Currently triggered manually, but intended/designed to be triggered periodically by Chainlink Automation.
* Only callable after `lottery_interval_hours` since last draw.
* Pays native ETH to the VRF Wrapper, logs a `RequestSent` event, and saves timestamp.

#### 2. **Fulfill Randomness**

**`raw_fulfill_random_words(request_id, random_words)`**

* **Intended to only be callable by the VRF wrapper.** There is a bug where all ABIs are public and I am working on to resolve.
* Internally calls `fulfill_random_words()` → records randomness → freezes participation → calls `decide_winner()` → unfreezes participation.
* Emits `RequestFulfilled(requestId, randomWords, winner)`.

---

### **Lottery Mechanics**

#### **Participation**

**`participate_in_lottery()`**

* Payable function for participants to send ETH equal to `lottery_entry_fee`.
* Rejects duplicates or incorrect fees.
* Temporarily blocked while processing a winner.

#### **Winner Selection**

**`decide_winner(random_words)`**

* Uses modulo of the random word to pick a winner index.
* Calculates reward as `entry_fee * participant_count`.
* Calls `mint_distribution_reward(winner, reward)`.
* Clears participants after reward distribution.

#### **Reward Minting**

**`mint_distribution_reward(recipient, amount)`**

* Calls `mint()` on the ERC20 token contract. (`allowed_minter` (the VRF Consumer) can mint tokens).
* The ERC20 restricts minting to calls from the verified VRF Consumer to limit minting to prevent manual or exploitative minting.

---

### **Common Integration**

* **ERC20 Token:**  
  - `mint(address, amount)` — Restricted to the authorized VRF Consumer.  
  - `set_minter(address)` — Owner-only assignment of the VRF Consumer.  
  - Standard ERC20 balance, transfer, and allowance functions.

* **VRF Consumer:**  
  - `set_erc20_token(address)` — Links or updates the ERC20 reward contract (owner-only).  
  - Lottery setters: `set_lottery_entry_fee(fee)`, `set_lottery_interval_hours(interval)`  
  - `get_last_fulfilled_id/value()` — Returns verifiable randomness results.  
  - Emits `RequestFulfilled(requestId, randomWords, winner)` when randomness resolves.

---

### **Core Storage**

```
VrfConsumer {
    vrf_wrapper: Address,         // Chainlink VRF V2+ wrapper
	withdrawing: bool,            // Reentrancy guard
    last_request_id: U256,        // Latest randomness request
    last_random_value: U256,      // Last fulfilled random number
    erc20_token: Address,         // Linked ERC20 reward contract
    participants: Vec<Address>,   // Current lottery entrants
    entry_fee: U256,              // Lottery entry fee (in Wei)
    interval_hours: U256,         // Delay between draws
    accepting_entries: bool,      // Lottery entry toggle
    owner: Address,               // Contract owner
}

RewardToken {
    name: String,
    symbol: String,
    total_supply: U256,
    balances: Map<Address, U256>,
    allowed_minter: Address,      // Authorized VRF Consumer
}
```

---

### **Error & Safety Handling**

* **Reentrancy Guards:** `withdrawing` and `accepting_participants` flags.
* **Authorization Checks:** ERC20 only mints from the trusted VRF Consumer.
* Custom Errors

---

### **Events**

* `RequestFulfilled(requestId, randomWords, winner)`
(`ParticipantJoined` and `MintedReward` are optional for off-chain monitoring.)

---

### **Design Notes**

* **Provable Fairness:** Chainlink VRF ensures winner selection is unpredictable and tamper-proof.
* **Closed Mint Authority:** ERC20 rewards depend exclusively on the VRF’s outcome.
* **Automation-Friendly:** Compatible with Chainlink Automation for periodic execution.
* **Bytecode-Efficient:** Overflow checks trimmed where safe for Stylus deployment.
* **Self-Sustaining Loop:** The VRF decides winners → ERC20 mints rewards → Lottery resets for the next round.

---

### **Deployment**

* Both contracts are deployed on Arbitrum Sepolia. Their addresses are as follows:
  - **VRF Contract: 0xAC96361ff71F185f8E9b7EcC6849f996C615fe06**
  - **ERC20 Contract: 0x4626FaB1392C9347021dCAe73FEFFd03FE080364**
* The website is deployed on Vercel and can be accessed at the following URL:
  - **Frontend: **
---

### **Challenges**

I was ambitious in scope and had aimed to add the following:

* Proxy contract for upgrades
* Tests (unit, e2e)
* Gas optimizations

I was not able to fully complete the assignment. Some features and bugs remain unfinished, but I intend to continue learning and refining this system.