// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IConfidencePool} from "bc-confidence-pools/interfaces/IConfidencePool.sol";

/// @notice Step 7 (Attacker): Claim the ConfidencePool pot as the good-faith attacker.
///
/// After `just flag-outcome` flags a good-faith CORRUPTED outcome, the named attacker is
/// entitled to the pool's pot. Only that attacker can call `claimAttackerBounty` — in this
/// demo that's SENDER_ADDRESS. The bounty is transferred to the caller; this may be called
/// repeatedly until the full entitlement is claimed.
///
/// (Note: `claimCorrupted` exists too, but it sweeps to the recovery address — that's the
/// bad-faith path. The good-faith attacker uses `claimAttackerBounty`.)
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
        console.log("Bounty entitlement:     ", IConfidencePool(pool).bountyEntitlement() / 1e18, "tokens");

        vm.startBroadcast();
        IConfidencePool(pool).claimAttackerBounty();
        vm.stopBroadcast();

        uint256 attackerAfter = IERC20(token).balanceOf(sender);
        uint256 poolAfter = IERC20(token).balanceOf(pool);
        console.log("\n--- Bounty claimed ---");
        console.log("Attacker balance after: ", attackerAfter / 1e18, "tokens");
        console.log("Pool balance after:     ", poolAfter / 1e18, "tokens");
        console.log("Claimed:                ", (attackerAfter - attackerBefore) / 1e18, "tokens");
    }
}
