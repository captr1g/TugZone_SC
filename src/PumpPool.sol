// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/token/ERC20/IERC20.sol";
import "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/access/Ownable.sol";

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
    
    // Vesting mechanism
    uint256 public constant VESTING_PERIOD = 7 days;
    uint256 public constant DAILY_UNLOCK_PERCENTAGE = 1429; // 14.29% with 2 decimal places (100% / 7)
    mapping(address => uint256) public userInitialBalance;
    mapping(address => uint256) public userVestingStart;
    mapping(address => uint256) public userTotalSold;
    
    // Initial phase tracking
    bool public initialPhaseCompleted = false;
    
    // Events
    event Buy(address indexed buyer, uint256 tokenAmount, uint256 ethAmount, uint256 fee);
    event Sell(address indexed seller, uint256 tokenAmount, uint256 ethAmount, uint256 fee);
    event SellingEnabled();
    event EmergencyWithdraw(address indexed recipient, uint256 ethAmount, uint256 tokenAmount);
    event TradingPaused(bool paused);
    event VestingInitialized(address indexed user, uint256 initialBalance, uint256 startTime);
    event PoolInitialized(address indexed token, uint256 initialTokenAmount, uint256 initialEthAmount, uint256 initialPrice);
    
    constructor() Ownable(msg.sender) {
        // Any initialization logic if needed
    }
    
    /**
     * @dev Initializes the pool with token and initial liquidity from creator
     * Places 1B tokens in the pool and determines price based on ETH provided
     */
    function initialize(address _token, address creator) external payable onlyOwner {
        require(token == address(0), "Already initialized");
        require(_token != address(0), "Invalid token address");
        require(msg.value > 0, "Initial ETH required");
        
        token = _token;
        tradingPaused = false;
        sellingEnabled = false;
        sellingEnableTimestamp = block.timestamp + TWO_HOURS;
        
        // Get token total supply
        uint256 totalSupply = IERC20(_token).totalSupply();
        
        // For this example, we'll use 1 billion tokens (assuming 18 decimals)
        uint256 initialTokenAmount = 1_000_000_000 * 10**18;
        
        // If the token's total supply is less than 1B, use the total supply
        if (totalSupply < initialTokenAmount) {
            initialTokenAmount = totalSupply;
        }
        
        // Transfer tokens from creator to pool
        IERC20(_token).safeTransferFrom(creator, address(this), initialTokenAmount);
        
        // Update reserves
        ethReserves = msg.value;
        tokenReserves = initialTokenAmount;
        
        // The initial price is determined by: ETH reserves / token reserves
        // This yields price per whole token (not accounting for decimals)
        // Initial price = msg.value / 1B tokens
        
        // This can be queried via getTokenPrice() which returns:
        // (ethReserves * 1e18) / tokenReserves
        
        emit PoolInitialized(_token, initialTokenAmount, msg.value, (msg.value * 1e18) / initialTokenAmount);
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
        
        // Calculate token amount using AMM formula
        tokenAmount = calculateBuyAmount(msg.value);
        require(tokenAmount > 0, "Token amount too small");
        require(tokenAmount <= tokenReserves, "Not enough tokens in reserve");
        
        // Calculate fee (e.g., 1% fee)
        uint256 fee = (msg.value * 1) / 100;
        uint256 ethForTokens = msg.value - fee;
        
        // Update reserves
        ethReserves += msg.value;
        tokenReserves -= tokenAmount;
        
        // Initialize vesting for user only if bought before selling is enabled
        if (block.timestamp < sellingEnableTimestamp) {
            // Only apply vesting during the initial phase
            if (userVestingStart[msg.sender] == 0) {
                userVestingStart[msg.sender] = block.timestamp;
                userInitialBalance[msg.sender] = tokenAmount;
                userTotalSold[msg.sender] = 0;
                emit VestingInitialized(msg.sender, tokenAmount, block.timestamp);
            } else {
                // Update initial balance with new purchase
                userInitialBalance[msg.sender] += tokenAmount;
            }
        }
        
        // Transfer tokens to buyer
        IERC20(token).safeTransfer(msg.sender, tokenAmount);
        
        // Mark initial phase as completed after first buy
        if (!initialPhaseCompleted) {
            initialPhaseCompleted = true;
        }
        
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
        
        // Check vesting limits only if the user has a vesting schedule
        // (which means they bought during the initial phase)
        if (userVestingStart[msg.sender] > 0 && block.timestamp < userVestingStart[msg.sender] + VESTING_PERIOD) {
            uint256 sellableAmount = getMaxSellableAmount(msg.sender);
            require(tokenAmount <= sellableAmount, "Exceeds vesting allowance");
            
            // Update user's total sold amount for vesting tracking
            userTotalSold[msg.sender] += tokenAmount;
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
     * @dev Gets the maximum amount of tokens a user can sell based on vesting schedule
     * @param user Address of the user
     * @return amount Maximum amount of tokens that can be sold
     */
    function getMaxSellableAmount(address user) public view returns (uint256 amount) {
        if (userVestingStart[user] == 0 || userInitialBalance[user] == 0) {
            return 0;
        }
        
        // Calculate time elapsed since vesting started
        uint256 timeElapsed = block.timestamp - userVestingStart[user];
        
        // If vesting period is complete, allow selling all tokens
        if (timeElapsed >= VESTING_PERIOD) {
            return userInitialBalance[user] - userTotalSold[user];
        }
        
        // Calculate days elapsed (truncated to whole days)
        uint256 daysElapsed = (timeElapsed / 1 days) + 1; // +1 to allow selling on day 1
        if (daysElapsed > 7) daysElapsed = 7; // Cap at 7 days
        
        // Calculate total sellable amount based on days elapsed (linear vesting)
        uint256 totalAllowedToSell = (userInitialBalance[user] * DAILY_UNLOCK_PERCENTAGE * daysElapsed) / 10000;
        
        // Return the remaining amount that can be sold
        if (totalAllowedToSell <= userTotalSold[user]) {
            return 0;
        }
        
        return totalAllowedToSell - userTotalSold[user];
    }
    
    /**
     * @dev Returns the vesting status for a user
     * @param user Address of the user
     * @return vestingStartTime The timestamp when vesting started
     * @return initialBalance The initial token balance when vesting started
     * @return totalSold The total amount sold so far
     * @return maxSellableNow The maximum amount that can be sold now
     * @return vestingEndsAt The timestamp when vesting period ends
     * @return isVestingComplete Whether the vesting period is complete
     */
    function getUserVestingStatus(address user) external view returns (
        uint256 vestingStartTime,
        uint256 initialBalance,
        uint256 totalSold,
        uint256 maxSellableNow,
        uint256 vestingEndsAt,
        bool isVestingComplete
    ) {
        vestingStartTime = userVestingStart[user];
        initialBalance = userInitialBalance[user];
        totalSold = userTotalSold[user];
        maxSellableNow = getMaxSellableAmount(user);
        vestingEndsAt = vestingStartTime + VESTING_PERIOD;
        isVestingComplete = block.timestamp >= vestingEndsAt;
    }
    
    /**
     * @dev Calculates token amount to be received when buying with ETH
     * @param ethAmount Amount of ETH to spend
     * @return tokenAmount Amount of tokens to receive
     */
    function calculateBuyAmount(uint256 ethAmount) public view returns (uint256 tokenAmount) {
        if (ethReserves == 0 || tokenReserves == 0) return 0;
        
        // Use AMM formula (Constant Product): x * y = k
        // If we add dx to x, we get dy from y where (x + dx) * (y - dy) = x * y
        
        // AMM formula: tokenAmount = (tokenReserves * ethAmount) / (ethReserves + ethAmount)
        return (tokenReserves * ethAmount) / (ethReserves + ethAmount);
    }
    
    /**
     * @dev Calculates ETH amount to be received when selling tokens
     * @param tokenAmount Amount of tokens to sell
     * @return ethAmount Amount of ETH to receive
     */
    function calculateSellAmount(uint256 tokenAmount) public view returns (uint256 ethAmount) {
        if (ethReserves == 0 || tokenReserves == 0) return 0;
        
        // Use AMM formula (Constant Product): x * y = k
        // If we add dx to y, we get dy from x where (x - dy) * (y + dx) = x * y
        
        // AMM formula: ethAmount = (ethReserves * tokenAmount) / (tokenReserves + tokenAmount)
        return (ethReserves * tokenAmount) / (tokenReserves + tokenAmount);
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
