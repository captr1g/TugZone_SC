# TugZone Protocol

## Contract Overview

TugZone is a decentralized finance protocol that implements a custom bonding curve-based AMM (Automated Market Maker) for creating and trading tokens. The protocol consists of three main smart contracts:

### 1. TokenFactory Contract

The TokenFactory serves as the entry point for the TugZone protocol, allowing users to create new tokens and their associated liquidity pools in a single transaction.

**Key Features**:
- **Token Creation**: Creates new PumpToken instances with customizable name, symbol, and metadata
- **Pool Management**: Automatically creates and initializes a PumpPool for each token
- **Registry**: Maintains a registry of all created tokens and pools for discovery
- **Metadata Storage**: Stores metadata URLs for each token to support frontend applications

### 2. PumpToken Contract

PumpToken is a standard ERC-20 token implementation that represents the tradable asset within the protocol.

**Key Features**:
- **Standard ERC-20**: Fully compatible with all ERC-20 applications and wallets
- **Fixed Supply**: Each token has a fixed total supply of 1 billion tokens (1,000,000,000)
- **Owner Controls**: Ownership is transferred to the creator, enabling potential future governance

### 3. PumpPool Contract

PumpPool implements a custom bonding curve-based AMM that enables trading between ETH and a specific PumpToken.

**Key Features**:## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Deploy.s.sol:DeployScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

### Deploying with Hardhat

To deploy contracts using Hardhat, follow these steps:

1. Install Hardhat:
   ```shell
   $ npm install --save-dev hardhat
   ```

2. Create a deployment script in the `scripts` directory.

3. Run the deployment script:
   ```shell
   $ npx hardhat run scripts/deploy.js --network <network_name>
   ```

### Verifying Contracts

To verify contracts on Etherscan:

1. Install the Etherscan plugin:
   ```shell
   $ npm install --save-dev @nomiclabs/hardhat-etherscan
   ```

2. Add the Etherscan API key to your Hardhat configuration.

3. Verify the contract:
   ```shell
   $ npx hardhat verify --network <network_name> <contract_address> <constructor_arguments>
   ```


## Technical Details

Inherits from OpenZeppelin's ReentrancyGuard and Ownable contracts
Uses SafeERC20 for safe token transfers
Implements a specific bonding curve formula: y = k * x / (x + c)
Fees are retained in the contract, improving the liquidity over time
Non-reentrant modifiers to prevent attack vectors
##Important Functions
```initialize(address token, address creator)```: Sets up the pool with initial liquidity
```buyTokens()```: Purchase tokens with ETH based on the bonding curve price
```sellTokens(uint256 tokenAmount)```: Sell tokens for ETH based on the bonding curve price
```calculateBuyAmount(uint256 ethAmount)```: Calculates tokens received for a given ETH amount
```calculateSellAmount(uint256 tokenAmount)```: Calculates ETH received for a given token amount
```getTokenPrice()```: Returns the current token price in ETH
```pauseTrading()``` & resumeTrading(): Emergency controls to stop/resume trading
```emergencyWithdraw()```: Allows the owner to withdraw all assets in case of emergency

### Security Mechanisms

Anti-bot limits (maximum 3 transactions per block)
Selling restrictions within the first 2 hours
Emergency pause functionality
Reentrancy protection
SafeERC20 usage for token transfers

### Protocol Workflow

A creator calls TokenFactory.createToken() with ETH for initial liquidity
The factory deploys a new PumpToken and a new PumpPool
The pool is initialized with 80% of the token supply and the provided ETH
Users can immediately buy tokens from the pool
After 2 hours, users can also sell tokens back to the pool
The bonding curve ensures that prices adjust based on the pool's reserves
Economic Model
The protocol uses a bonding curve that increases token price as more tokens are purchased and decreases price as tokens are sold. The formula ```y = k * x / (x + c) ``` creates a curved relationship between token price and supply, where:

```k``` represents the token reserves
```c```represents the ETH reserves
```x``` is the input amount (ETH for buys, tokens for sells)
```y``` is the output amount (tokens for buys, ETH for sells)
This model ensures that early adopters get better prices while still providing liquidity for later participants.
