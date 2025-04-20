// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Script.sol";
import "../src/TokenFactory.sol";
import "../src/PumpToken.sol";
import "../src/PumpPool.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy TokenFactory
        TokenFactory factory = new TokenFactory();
        console.log("TokenFactory deployed to:", address(factory));
        
        // Create a token with 1 ETH initial liquidity
        (bool success, bytes memory result) = address(factory).call{value: 1 ether}(
            abi.encodeWithSelector(
                factory.createToken.selector,
                "TugZone Token",
                "TUG",
                "https://tugzone.io/metadata"
            )
        );
        
        if (success) {
            address tokenAddress = abi.decode(result, (address));
            console.log("Token deployed to:", tokenAddress);
            
            address poolAddress = factory.tokenToPool(tokenAddress);
            console.log("Pool deployed to:", poolAddress);
        } else {
            console.log("Token creation failed");
        }
        
        vm.stopBroadcast();
    }
}
