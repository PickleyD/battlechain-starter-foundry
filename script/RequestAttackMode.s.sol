// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {BCSafeHarbor} from "battlechain-lib/BCSafeHarbor.sol";

/// @notice Step 3 (Protocol): Submit the attack mode request for DAO review.
///
/// Prerequisites — set in .env:
///   SENDER_ADDRESS, AGREEMENT_ADDRESS
///
/// Usage:
///   just request-attack-mode
///
/// After running, wait for DAO approval. Check status with:
///   just check-state
///   # 2 = ATTACK_REQUESTED, 3 = UNDER_ATTACK (approved)
contract RequestAttackMode is BCSafeHarbor {
    function run() external {
        address agreement = vm.envAddress("AGREEMENT_ADDRESS");

        vm.startBroadcast();

        requestAttackMode(agreement);

        vm.stopBroadcast();

        console.log("Attack mode requested for agreement:", agreement);
        console.log("State is now ATTACK_REQUESTED (2) - awaiting DAO approval.");
        console.log("Once approved, state moves to UNDER_ATTACK (3).");
    }
}
