// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {MockToken} from "../src/MockToken.sol";
import {IConfidencePool} from "bc-confidence-pools/interfaces/IConfidencePool.sol";

/// @dev `minStake` and `eligibleStake` are public state on the pool (auto-generated getters)
///      but aren't part of IConfidencePool, so read them through this minimal view interface.
interface IConfidencePoolViews {
    function minStake() external view returns (uint256);
    function eligibleStake(address staker) external view returns (uint256);
}

/// @notice (Optional) Stake confidence that the protocol will SURVIVE attack mode.
///
/// A staker deposits tokens into the pool; if the agreement ends in PRODUCTION the staker
/// reclaims their stake plus a pro-rata share of the bonus (via the pool's `claimSurvived`).
/// If the protocol is corrupted the stake is forfeit. This mints the stake to the sender,
/// approves the pool, and stakes in one broadcast.
///
/// Staking is only open while the agreement is pre-terminal (NOT_DEPLOYED, NEW_DEPLOYMENT,
/// ATTACK_REQUESTED, or UNDER_ATTACK) and before the pool's expiry — i.e. any time after
/// `create-confidence-pool` up through the attack, but before `mark-corrupted`. The amount
/// must be at least the pool's `minStake`.
///
/// Prerequisites — set in .env:
///   SENDER_ADDRESS, CONFIDENCE_POOL_ADDRESS, TOKEN_ADDRESS
///
/// Optional .env overrides:
///   STAKE_AMOUNT   (default: the pool's minStake — read on-chain)
///
/// Usage:
///   just stake-confidence
contract StakeConfidence is Script {
    function run() external {
        address pool = vm.envAddress("CONFIDENCE_POOL_ADDRESS");
        address token = vm.envAddress("TOKEN_ADDRESS");
        address sender = vm.envAddress("SENDER_ADDRESS");

        // Default to the pool's own minimum stake so the demo always clears BelowMinStake.
        uint256 minStake = IConfidencePoolViews(pool).minStake();
        uint256 amount = _envUintOr("STAKE_AMOUNT", minStake);
        require(amount >= minStake, "STAKE_AMOUNT below pool minStake");

        console.log("Staking", amount / 1e18, "tokens; pool minStake:", minStake / 1e18);

        vm.startBroadcast();

        // Mint the stake to the staker and approve the pool to pull it.
        MockToken(token).mint(msg.sender, amount);
        MockToken(token).approve(pool, amount);

        IConfidencePool(pool).stake(amount);

        vm.stopBroadcast();

        console.log("Staked. Eligible stake:", IConfidencePoolViews(pool).eligibleStake(sender) / 1e18, "tokens");
    }

    /// @dev Like vm.envOr, but treats an empty string ("") the same as unset.
    function _envUintOr(string memory name, uint256 defaultValue) private view returns (uint256) {
        string memory raw = vm.envOr(name, string(""));
        return bytes(raw).length == 0 ? defaultValue : vm.parseUint(raw);
    }
}
