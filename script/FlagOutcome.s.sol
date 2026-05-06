// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";

interface IConfidencePool {
    function flagOutcome(address attacker, bool goodFaith) external;
    function flaggedAttacker() external view returns (address);
    function flaggedGoodFaith() external view returns (bool);
    function outcomeFlagged() external view returns (bool);
}

/// @notice Step 6 (Pool outcomeModerator): Flag the pool's outcome as a good-faith corruption
///         attributed to the attacker.
///
/// Only the pool's outcomeModerator can call this. By default `just create-confidence-pool`
/// sets that to SENDER_ADDRESS, so the deployer signs this step.
///
/// `goodFaith = true` matches the existing demo, where `Attacker.attack()` honours the Safe
/// Harbor terms (returns 90% to recovery, keeps 10% as bounty). A bad-faith attacker would
/// instead trigger `sweepBadFaithToRecovery` — out of scope here.
///
/// Prerequisites — set in .env:
///   SENDER_ADDRESS, CONFIDENCE_POOL_ADDRESS
///
/// Optional .env overrides:
///   ATTACKER_ADDRESS (default: SENDER_ADDRESS — the demo is single-wallet)
///
/// Usage:
///   just flag-outcome
contract FlagOutcome is Script {
    function run() external {
        address pool = vm.envAddress("CONFIDENCE_POOL_ADDRESS");
        address sender = vm.envAddress("SENDER_ADDRESS");
        address attacker = _envAddressOr("ATTACKER_ADDRESS", sender);

        vm.startBroadcast();
        IConfidencePool(pool).flagOutcome(attacker, true);
        vm.stopBroadcast();

        console.log("flaggedAttacker: ", IConfidencePool(pool).flaggedAttacker());
        console.log("flaggedGoodFaith:", IConfidencePool(pool).flaggedGoodFaith());
        console.log("outcomeFlagged:  ", IConfidencePool(pool).outcomeFlagged());
    }

    /// @dev Like vm.envOr, but treats an empty string ("") the same as unset.
    function _envAddressOr(string memory name, address defaultValue) private view returns (address) {
        string memory raw = vm.envOr(name, string(""));
        return bytes(raw).length == 0 ? defaultValue : vm.parseAddress(raw);
    }
}
