// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PumpPool
 * @dev Pool contract that pairs an ERC-20 token with ETH and implements AMM functionality
 */
contract PumpPool is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;
    
    // Token address
    address public token;
    
    // ETH and token reserves
    uint256 public ethReserves;
    uint256 public tokenReserves;
    
    // Trading state
    bool public tradingPaused;
    bool public sellingEnabled;
    uint256 public sellingEnableTimestamp;
    
    // Anti-bot mechanism
    mapping(address => uint256) public lastBlockBought;
    mapping(uint256 => uint256) public blockTransactionCount;
    uint256 public constant MAX_TX_PER_BLOCK = 3;
    
    // Time constants
    uint256 public constant TWO_HOURS = 2 hours;
    
    // Events
    event Buy(address indexed buyer, uint256 tokenAmount, uint256 ethAmount, uint256 fee);
    event Sell(address indexed seller, uint256 tokenAmount, uint256 ethAmount, uint256 fee);
    event SellingEnabled();
    event EmergencyWithdraw(address indexed recipient, uint256 ethAmount, uint256 tokenAmount);
    event TradingPaused(bool paused);
    
    /**
     * @dev Initializes the pool with token and initial liquidity from creator
     */
    function initialize(address _token, address creator) external payable onlyOwner {
        require(token == address(0), "Already initialized");
        require(_token != address(0), "Invalid token address");
        require(msg.value > 0, "Initial ETH required");
        
        token = _token;
        tradingPaused = false;
        sellingEnabled = false;
        sellingEnableTimestamp = block.timestamp + TWO_HOURS;
        
        // Calculate initial token amount using bonding curve
        uint256 totalSupply = IERC20(token).totalSupply();
        
        // Here you'd define how much of the token supply should be in the pool
        // For example: 80% of total supply
        uint256 initialTokenAmount = (totalSupply * 80) / 100;
        
        // Transfer tokens from creator to pool
        IERC20(_token).safeTransferFrom(creator, address(this), initialTokenAmount);
        
        // Update reserves
        ethReserves = msg.value;
        tokenReserves = initialTokenAmount;
    }
    
    /**
     * @dev Buys tokens with ETH
     * @return tokenAmount Amount of tokens bought
     */
    function buyTokens() external payable nonReentrant returns (uint256 tokenAmount) {
        require(!tradingPaused, "Trading is paused");
        require(msg.value > 0, "Must send ETH");
        
        // Anti-bot mechanism
        require(blockTransactionCount[block.number] < MAX_TX_PER_BLOCK, "Max transactions per block reached");
        blockTransactionCount[block.number] += 1;
        lastBlockBought[msg.sender] = block.number;
        
        // Calculate token amount using bonding curve
        tokenAmount = calculateBuyAmount(msg.value);
        require(tokenAmount > 0, "Token amount too small");
        require(tokenAmount <= tokenReserves, "Not enough tokens in reserve");
        
        // Calculate fee (e.g., 1% fee)
        uint256 fee = (msg.value * 1) / 100;
        uint256 ethForTokens = msg.value - fee;
        
        // Update reserves
        ethReserves += msg.value;
        tokenReserves -= tokenAmount;
        
        // Transfer tokens to buyer
        IERC20(token).safeTransfer(msg.sender, tokenAmount);
        
        emit Buy(msg.sender, tokenAmount, msg.value, fee);
        return tokenAmount;
    }
    
    /**
     * @dev Sells tokens for ETH
     * @param tokenAmount Amount of tokens to sell
     * @return ethAmount Amount of ETH received
     */
    function sellTokens(uint256 tokenAmount) external nonReentrant returns (uint256 ethAmount) {
        require(!tradingPaused, "Trading is paused");
        require(sellingEnabled || block.timestamp >= sellingEnableTimestamp, "Selling is currently disabled");
        require(tokenAmount > 0, "Must sell some tokens");
        
        // Enable selling if timelock has passed
        if (!sellingEnabled && block.timestamp >= sellingEnableTimestamp) {
            sellingEnabled = true;
            emit SellingEnabled();
        }
        
        // Calculate ETH amount using bonding curve
        ethAmount = calculateSellAmount(tokenAmount);
        require(ethAmount > 0, "ETH amount too small");
        require(ethAmount <= ethReserves, "Not enough ETH in reserve");
        
        // Calculate fee (e.g., 1% fee)
        uint256 fee = (ethAmount * 1) / 100;
        uint256 ethToSeller = ethAmount - fee;
        
        // Update reserves
        tokenReserves += tokenAmount;
        ethReserves -= ethAmount;
        
        // Transfer tokens from seller
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
        
        // Transfer ETH to seller
        (bool success, ) = payable(msg.sender).call{value: ethToSeller}("");
        require(success, "ETH transfer failed");
        
        emit Sell(msg.sender, tokenAmount, ethAmount, fee);
        return ethAmount;
    }
    
    /**
     * @dev Calculates token amount to be received when buying with ETH
     * @param ethAmount Amount of ETH to spend
     * @return tokenAmount Amount of tokens to receive
     */
    function calculateBuyAmount(uint256 ethAmount) public view returns (uint256 tokenAmount) {
        // Simple bonding curve: y = k * x / (x + c)
        // where k is a constant and c is a parameter that controls the curve shape
        uint256 k = tokenReserves;
        uint256 c = ethReserves;
        
        return (k * ethAmount) / (c + ethAmount);
    }
    
    /**
     * @dev Calculates ETH amount to be received when selling tokens
     * @param tokenAmount Amount of tokens to sell
     * @return ethAmount Amount of ETH to receive
     */
    function calculateSellAmount(uint256 tokenAmount) public view returns (uint256 ethAmount) {
        // Reverse of the bonding curve for buying
        uint256 k = tokenReserves;
        uint256 c = ethReserves;
        
        return (c * tokenAmount) / (k + tokenAmount);
    }
    
    /**
     * @dev Returns the current token price in ETH
     * @return price Token price in ETH (scaled by 1e18)
     */
    function getTokenPrice() external view returns (uint256 price) {
        if (tokenReserves == 0) return 0;
        return (ethReserves * 1e18) / tokenReserves;
    }
    
    /**
     * @dev Pauses trading in emergency situation
     */
    function pauseTrading() external onlyOwner {
        tradingPaused = true;
        emit TradingPaused(true);
    }
    
    /**
     * @dev Resumes trading after pause
     */
    function resumeTrading() external onlyOwner {
        tradingPaused = false;
        emit TradingPaused(false);
    }
    
    /**
     * @dev Emergency withdraw of assets to owner
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 ethAmount = ethReserves;
        uint256 tokenAmount = IERC20(token).balanceOf(address(this));
        
        ethReserves = 0;
        tokenReserves = 0;
        
        // Transfer ETH to owner
        (bool success, ) = payable(owner()).call{value: ethAmount}("");
        require(success, "ETH transfer failed");
        
        // Transfer tokens to owner
        IERC20(token).safeTransfer(owner(), tokenAmount);
        
        emit EmergencyWithdraw(owner(), ethAmount, tokenAmount);
    }
    
    // Allow contract to receive ETH
    receive() external payable {}
}
