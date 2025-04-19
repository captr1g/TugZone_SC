// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./PumpToken.sol";
import "./PumpPool.sol";

/**
 * @title TokenFactory
 * @dev Creates new ERC-20 tokens and associated pools
 */
contract TokenFactory {
    address public owner;
    
    // All created tokens and pools
    address[] public tokens;
    address[] public pools;
    
    // Mapping from token to pool
    mapping(address => address) public tokenToPool;
    
    // Metadata URLs for tokens
    mapping(address => string) public tokenMetadata;
    
    // Events
    event TokenCreated(address indexed tokenAddress, string name, string symbol, string metadataUrl, address indexed creator);
    event PoolCreated(address indexed tokenAddress, address indexed poolAddress);
    
    constructor() {
        owner = msg.sender;
    }
    
    /**
     * @dev Creates a new token and its associated pool
     * @param name Token name
     * @param symbol Token symbol
     * @param metadataUrl URL for token metadata (image & description)
     * @return tokenAddress Address of the newly created token
     */
    function createToken(
        string memory name,
        string memory symbol,
        string memory metadataUrl
    ) external payable returns (address tokenAddress) {
        require(msg.value > 0, "Must send ETH for initial liquidity");
        
        // Create new token with 1 billion supply (1,000,000,000 * 10^18)
        PumpToken token = new PumpToken(name, symbol);
        tokenAddress = address(token);
        
        // Create new pool
        PumpPool pool = new PumpPool();
        address poolAddress = address(pool);
        
        // Store token information
        tokens.push(tokenAddress);
        tokenMetadata[tokenAddress] = metadataUrl;
        
        // Store pool information
        pools.push(poolAddress);
        tokenToPool[tokenAddress] = poolAddress;
        
        // Initialize the pool with initial liquidity
        // The msg.value is forwarded to initialize the pool
        token.approve(poolAddress, token.totalSupply());
        pool.initialize{value: msg.value}(tokenAddress, msg.sender);
        
        // Emit events
        emit TokenCreated(tokenAddress, name, symbol, metadataUrl, msg.sender);
        emit PoolCreated(tokenAddress, poolAddress);
        
        return tokenAddress;
    }
    
    /**
     * @dev Returns all created tokens
     */
    function getAllTokens() external view returns (address[] memory) {
        return tokens;
    }
    
    /**
     * @dev Returns all created pools
     */
    function getAllPools() external view returns (address[] memory) {
        return pools;
    }
    
    /**
     * @dev Returns the pool address for a token
     */
    function getPoolForToken(address token) external view returns (address) {
        address pool = tokenToPool[token];
        require(pool != address(0), "Pool not found for token");
        return pool;
    }
    
    /**
     * @dev Returns the metadata URL for a token
     */
    function getTokenMetadata(address token) external view returns (string memory) {
        return tokenMetadata[token];
    }
}