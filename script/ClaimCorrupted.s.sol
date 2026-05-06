// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IConfidencePool {
    function claimCorrupted() external;
    function totalPot() external view returns (uint256);
}

/// @notice Step 7 (Attacker): Claim the entire ConfidencePool pot.
///
/// After `just flag-outcome`, the pool knows the attacker is entitled to the pot. Only
/// the flagged attacker can call `claimCorrupted` — in this demo that's SENDER_ADDRESS.
/// The full `stakeToken.balanceOf(pool)` is transferred to the caller in a single tx.
///
/// Prerequisites — set in .env:
///   SENDER_ADDRESS, CONFIDENCE_POOL_ADDRESS, TOKEN_ADDRESS
///
/// Usage:
///   just claim-corrupted
contract ClaimCorrupted is Script {
    function run() external {
        address pool = vm.envAddress("CONFIDENCE_POOL_ADDRESS");
        address token = vm.envAddress("TOKEN_ADDRESS");
        address sender = vm.envAddress("SENDER_ADDRESS");

        uint256 attackerBefore = IERC20(token).balanceOf(sender);
        uint256 poolBefore = IERC20(token).balanceOf(pool);
        console.log("Attacker balance before:", attackerBefore / 1e18, "tokens");
        console.log("Pool balance before:    ", poolBefore / 1e18, "tokens");
        console.log("Pool totalPot():        ", IConfidencePool(pool).totalPot() / 1e18, "tokens");

        vm.startBroadcast();
        IConfidencePool(pool).claimCorrupted();
        vm.stopBroadcast();

        uint256 attackerAfter = IERC20(token).balanceOf(sender);
        uint256 poolAfter = IERC20(token).balanceOf(pool);
        console.log("\n--- Pool drained ---");
        console.log("Attacker balance after: ", attackerAfter / 1e18, "tokens");
        console.log("Pool balance after:     ", poolAfter / 1e18, "tokens");
        console.log("Claimed:                ", (attackerAfter - attackerBefore) / 1e18, "tokens");
    }
}
