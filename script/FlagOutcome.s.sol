// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {IConfidencePool} from "bc-confidence-pools/interfaces/IConfidencePool.sol";

interface IMockConfidencePoolModerator {
    function flagCorruptedGoodFaith(address pool, address attacker) external;
}

/// @notice Step 6 (Pool outcomeModerator): Flag the pool's outcome as a good-faith corruption
///         attributed to the attacker.
///
/// The pool's outcomeModerator is the factory's default moderator — on testnet that's the
/// permissionless `MockConfidencePoolModerator`, which lets ANYONE flag an outcome (agreement-
/// state checks still run on the pool). So rather than calling `pool.flagOutcome` directly
/// (which reverts with `NotModerator` unless the caller IS the moderator), this routes through
/// the mock's `flagCorruptedGoodFaith`, which forwards to the pool. Same permissionless-testnet
/// pattern as attack-mode approval.
///
/// `goodFaith = true` matches the existing demo, where the attacker honours the Safe Harbor
/// terms (returns 90% to recovery, keeps 10% as bounty). It entitles the named attacker to
/// claim the pool's pot via `claimAttackerBounty` (Step 7).
///
/// Prerequisites — set in .env:
///   SENDER_ADDRESS, CONFIDENCE_POOL_ADDRESS
///
/// Optional .env overrides:
///   ATTACKER_ADDRESS      (default: SENDER_ADDRESS — the demo is single-wallet)
///   POOL_MODERATOR        (default: deployed testnet MockConfidencePoolModerator)
///
/// Usage:
///   just flag-outcome
contract FlagOutcome is Script {
    address private constant DEFAULT_POOL_MODERATOR = 0x33DD28D60eaD559ABf9EA19d3D7efd76c08f41bc;

    function run() external {
        address pool = vm.envAddress("CONFIDENCE_POOL_ADDRESS");
        address sender = vm.envAddress("SENDER_ADDRESS");
        address attacker = _envAddressOr("ATTACKER_ADDRESS", sender);
        address moderator = _envAddressOr("POOL_MODERATOR", DEFAULT_POOL_MODERATOR);

        vm.startBroadcast();
        IMockConfidencePoolModerator(moderator).flagCorruptedGoodFaith(pool, attacker);
        vm.stopBroadcast();

        console.log("Outcome flagged: CORRUPTED (good-faith)");
        console.log("Attacker:           ", attacker);
        console.log("Bounty entitlement: ", IConfidencePool(pool).bountyEntitlement() / 1e18, "tokens");
    }

    /// @dev Like vm.envOr, but treats an empty string ("") the same as unset.
    function _envAddressOr(string memory name, address defaultValue) private view returns (address) {
        string memory raw = vm.envOr(name, string(""));
        return bytes(raw).length == 0 ? defaultValue : vm.parseAddress(raw);
    }
}
