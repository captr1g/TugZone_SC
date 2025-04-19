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
    
    // Fee constants
    uint256 public constant FEE_PERCENTAGE = 5; // 0.5%
    uint256 public constant FEE_DENOMINATOR = 1000;
    
    // Anti-bot protection
    uint256 public constant MAX_TX_PER_BLOCK = 3;
    mapping(address => mapping(uint256 => uint256)) public txCounter;
    
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
        uint256 initialTokenAmount = calculateInitialTokenAmount(msg.value, totalSupply);
        
        // Transfer initial tokens from factory to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), initialTokenAmount);
        
        // Initialize reserves
        ethReserves = msg.value;
        tokenReserves = initialTokenAmount;
        
        // Transfer ownership to the creator
        _transferOwnership(creator);
    }
    
    /**
     * @dev Allows users to buy tokens with ETH
     */
    function buyTokens() external payable nonReentrant returns (uint256) {
        require(!tradingPaused, "Trading is paused");
        require(msg.value > 0, "ETH amount must be greater than 0");
        
        // Check anti-bot protection
        checkAntiBot();
        
        // Calculate tokens to receive based on constant product formula
        uint256 tokenAmount = calculateBuyAmount(msg.value);
        
        // Calculate fee
        uint256 feeAmount = tokenAmount * FEE_PERCENTAGE / FEE_DENOMINATOR;
        uint256 tokenAmountAfterFee = tokenAmount - feeAmount;
        
        // Update reserves
        ethReserves += msg.value;
        tokenReserves -= tokenAmount;
        
        // Transfer tokens to buyer
        IERC20(token).safeTransfer(msg.sender, tokenAmountAfterFee);
        
        // Emit event
        emit Buy(msg.sender, tokenAmountAfterFee, msg.value, feeAmount);
        
        return tokenAmountAfterFee;
    }
    
    /**
     * @dev Allows users to sell tokens for ETH
     */
    function sellTokens(uint256 tokenAmount) external nonReentrant returns (uint256) {
        require(!tradingPaused, "Trading is paused");
        require(tokenAmount > 0, "Token amount must be greater than 0");
        
        // Check if selling is enabled
        if (!sellingEnabled) {
            if (block.timestamp >= sellingEnableTimestamp) {
                sellingEnabled = true;
                emit SellingEnabled();
            } else {
                revert("Selling is currently disabled");
            }
        }
        
        // Check anti-bot protection
        checkAntiBot();
        
        // Calculate ETH to receive based on constant product formula
        uint256 ethAmount = calculateSellAmount(tokenAmount);
        
        // Calculate fee
        uint256 feeAmount = ethAmount * FEE_PERCENTAGE / FEE_DENOMINATOR;
        uint256 ethAmountAfterFee = ethAmount - feeAmount;
        
        // Check if contract has enough ETH
        require(ethReserves >= ethAmountAfterFee, "Insufficient ETH liquidity");
        
        // Update reserves
        ethReserves -= ethAmountAfterFee;
        tokenReserves += tokenAmount;
        
        // Transfer tokens from seller to pool
        IERC20(token).safeTransferFrom(msg.sender, address(this), tokenAmount);
        
        // Transfer ETH to seller
        (bool success, ) = payable(msg.sender).call{value: ethAmountAfterFee}("");
        require(success, "ETH transfer failed");
        
        // Emit event
        emit Sell(msg.sender, tokenAmount, ethAmountAfterFee, feeAmount);
        
        return ethAmountAfterFee;
    }
    
    /**
     * @dev Returns the current token price in ETH (scaled by 1e18)
     */
    function getTokenPrice() external view returns (uint256) {
        require(tokenReserves > 0, "No liquidity");
        
        // Price is ETH reserves / token reserves
        return (ethReserves * 10**18) / tokenReserves;
    }
    
    /**
     * @dev Returns time until selling is enabled
     */
    function timeUntilSellingEnabled() external view returns (uint256) {
        if (sellingEnabled || block.timestamp >= sellingEnableTimestamp) {
            return 0;
        }
        return sellingEnableTimestamp - block.timestamp;
    }
    
    /**
     * @dev Emergency: Pause all trading (owner only)
     */
    function pauseTrading() external onlyOwner {
        tradingPaused = true;
        emit TradingPaused(true);
    }
    
    /**
     * @dev Emergency: Resume trading (owner only)
     */
    function resumeTrading() external onlyOwner {
        tradingPaused = false;
        emit TradingPaused(false);
    }
    
    /**
     * @dev Emergency: Withdraw liquidity (owner only)
     */
    function emergencyWithdraw() external onlyOwner {
        uint256 ethAmount = ethReserves;
        uint256 tokenAmount = tokenReserves;
        
        // Reset reserves
        ethReserves = 0;
        tokenReserves = 0;
        
        // Transfer ETH to owner
        (bool success, ) = payable(msg.sender).call{value: ethAmount}("");
        require(success, "ETH transfer failed");
        
        // Transfer tokens to owner
        IERC20(token).safeTransfer(msg.sender, tokenAmount);
        
        // Revoke owner privileges after emergency withdrawal
        renounceOwnership();
        
        // Emit event
        emit EmergencyWithdraw(msg.sender, ethAmount, tokenAmount);
    }
    
    /**
     * @dev Calculate initial token amount using exponential bonding curve (PumpFun style)
     */
    function calculateInitialTokenAmount(uint256 ethAmount, uint256 totalSupply) public pure returns (uint256) {
        // Base price in ETH for the first token (scaled by 1e18)
        uint256 basePrice = 10**15; // 0.001 ETH
        
        // For first purchase, simple calculation without exponential part
        // tokens = ethAmount / basePrice
        uint256 initialTokenAmount = (ethAmount * 10**18) / basePrice;
        
        // Cap at 25% of total supply for initial purchase
        uint256 maxInitialPurchase = totalSupply / 4;
        
        if (initialTokenAmount > maxInitialPurchase) {
            return maxInitialPurchase;
        }
        
        return initialTokenAmount;
    }
    
    /**
     * @dev Calculate token amount for buying with ETH using constant product formula
     */
    function calculateBuyAmount(uint256 ethAmount) public view returns (uint256) {
        require(ethReserves > 0 && tokenReserves > 0, "Insufficient liquidity");
        
        // x * y = k formula
        // (ethReserves + ethAmount) * (tokenReserves - tokenAmount) = ethReserves * tokenReserves
        
        uint256 product = ethReserves * tokenReserves;
        uint256 newEthReserves = ethReserves + ethAmount;
        uint256 newTokenReserves = product / newEthReserves;
        
        uint256 tokenAmount = tokenReserves - newTokenReserves;
        
        require(tokenAmount < tokenReserves, "Invalid calculation");
        
        return tokenAmount;
    }
    
    /**
     * @dev Calculate ETH amount for selling tokens using constant product formula
     */
    function calculateSellAmount(uint256 tokenAmount) public view returns (uint256) {
        require(ethReserves > 0 && tokenReserves > 0, "Insufficient liquidity");
        
        // x * y = k formula
        // (ethReserves - ethAmount) * (tokenReserves + tokenAmount) = ethReserves * tokenReserves
        
        uint256 product = ethReserves * tokenReserves;
        uint256 newTokenReserves = tokenReserves + tokenAmount;
        uint256 newEthReserves = product / newTokenReserves;
        
        uint256 ethAmount = ethReserves - newEthReserves;
        
        require(ethAmount < ethReserves, "Invalid calculation");
        
        return ethAmount;
    }
    
    /**
     * @dev Check anti-bot protection
     */
    function checkAntiBot() internal {
        address sender = msg.sender;
        uint256 blockNumber = block.number;
        
        uint256 currentTxCount = txCounter[sender][blockNumber];
        
        require(currentTxCount < MAX_TX_PER_BLOCK, "Max transactions per block reached");
        
        // Increment tx counter
        txCounter[sender][blockNumber] = currentTxCount + 1;
    }
    
    /**
     * @dev Receive function to allow contract to receive ETH
     */
    receive() external payable {}
}