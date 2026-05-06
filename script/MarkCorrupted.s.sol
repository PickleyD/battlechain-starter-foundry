// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {IAttackRegistry} from "../src/interfaces/IAttackRegistry.sol";

/// @notice Step 5 (Protocol/Moderator): Mark the agreement as CORRUPTED on the AttackRegistry.
///
/// Nothing on-chain auto-detects a successful exploit, so after `just attack` the agreement
/// is still in UNDER_ATTACK (3). The agreement's attack moderator (set to the agreement
/// owner at registration — i.e. our deployer in this demo) must explicitly call
/// `markCorrupted` to transition the agreement to CORRUPTED (6). This unlocks
/// `flagOutcome` and `claimCorrupted` on any associated ConfidencePool.
///
/// Prerequisites — set in .env:
///   SENDER_ADDRESS, AGREEMENT_ADDRESS, ATTACK_REGISTRY
///
/// Usage:
///   just mark-corrupted
contract MarkCorrupted is Script {
    function run() external {
        address registry = vm.envAddress("ATTACK_REGISTRY");
        address agreement = vm.envAddress("AGREEMENT_ADDRESS");

        IAttackRegistry.ContractState before = IAttackRegistry(registry).getAgreementState(agreement);
        console.log("Agreement state before:", uint8(before), "(expect 3 = UNDER_ATTACK)");

        vm.startBroadcast();
        IAttackRegistry(registry).markCorrupted(agreement);
        vm.stopBroadcast();

        IAttackRegistry.ContractState afterState = IAttackRegistry(registry).getAgreementState(agreement);
        console.log("Agreement state after: ", uint8(afterState), "(expect 6 = CORRUPTED)");
    }
}
