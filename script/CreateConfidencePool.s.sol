// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {MockToken} from "../src/MockToken.sol";
import {IConfidencePoolFactory} from "bc-confidence-pools/interfaces/IConfidencePoolFactory.sol";
import {IConfidencePool} from "bc-confidence-pools/interfaces/IConfidencePool.sol";

/// @notice Step 2b (Protocol): Deploy a ConfidencePool for the agreement and seed it with a bonus.
///
/// A ConfidencePool is a small contract bound 1:1 to a Safe Harbor agreement that holds a
/// pre-funded bonus + optional stakes. AI whitehat bots use the pool's total pot to rank
/// attackable agreements by expected payoff. Creating it before attack mode means the
/// bonus is visible from the moment the agreement becomes attackable.
///
/// Prerequisites — set in .env:
///   SENDER_ADDRESS, AGREEMENT_ADDRESS, TOKEN_ADDRESS, VAULT_ADDRESS
///
/// Optional .env overrides:
///   RECOVERY_ADDRESS   (default: SENDER_ADDRESS — should match what create-agreement used)
///   BONUS_AMOUNT       (default: 1000e18 — matches vault TVL)
///   EXPIRY             (default: now + 31 days — when the pool auto-resolves if no outcome flagged;
///                       must be at least now + 30 days or the pool reverts ExpiryTooSoon)
///   MIN_STAKE          (default: 1e18 — the pool requires a non-zero minimum stake, even though
///                       this demo only seeds a bonus and never stakes)
///   FACTORY_ADDRESS    (default: deployed BattleChain testnet factory)
///
/// Usage:
///   just create-confidence-pool
///
/// After running, copy CONFIDENCE_POOL_ADDRESS into your .env file.
contract CreateConfidencePool is Script {
    address private constant DEFAULT_FACTORY = 0x44aF705d8289e97c0E48441E4E566c5faf43Ffa8;
    uint256 private constant DEFAULT_BONUS = 1_000e18;
    // The pool enforces expiry >= now + 30 days (_MIN_EXPIRY_LEAD). Use 31 days so the
    // margin survives the gap between forge's simulation and the actual broadcast block.
    uint256 private constant DEFAULT_EXPIRY_PERIOD = 31 days;
    uint256 private constant DEFAULT_MIN_STAKE = 1e18; // pool requires minStake > 0

    function run() external {
        address agreement = vm.envAddress("AGREEMENT_ADDRESS");
        address token = vm.envAddress("TOKEN_ADDRESS");
        address vault = vm.envAddress("VAULT_ADDRESS");
        address sender = vm.envAddress("SENDER_ADDRESS");

        address recovery = _envAddressOr("RECOVERY_ADDRESS", sender);
        uint256 bonusAmount = _envUintOr("BONUS_AMOUNT", DEFAULT_BONUS);
        uint256 expiry = _envUintOr("EXPIRY", block.timestamp + DEFAULT_EXPIRY_PERIOD);
        uint256 minStake = _envUintOr("MIN_STAKE", DEFAULT_MIN_STAKE);
        address factory = _envAddressOr("FACTORY_ADDRESS", DEFAULT_FACTORY);

        // Scope the pool to the vault, matching the agreement's in-scope contract.
        address[] memory accounts = new address[](1);
        accounts[0] = vault;

        vm.startBroadcast();

        // 1. Deploy the pool via the factory. The factory assigns its default outcome
        //    moderator; the pool's owner is the caller (sender).
        address pool =
            IConfidencePoolFactory(factory).createPool(agreement, token, expiry, minStake, recovery, accounts);

        // 2. Mint the bonus to the deployer and approve the pool to pull it
        MockToken(token).mint(msg.sender, bonusAmount);
        MockToken(token).approve(pool, bonusAmount);

        // 3. Seed the pool
        IConfidencePool(pool).contributeBonus(bonusAmount);

        vm.stopBroadcast();

        console.log("ConfidencePool deployed:", pool);
        console.log("Bonus seeded:", bonusAmount / 1e18, "tokens");
        console.log("\n--- Add to your .env ---");
        console.log("CONFIDENCE_POOL_ADDRESS=%s", pool);
    }

    /// @dev Like vm.envOr, but treats an empty string ("") the same as unset.
    function _envAddressOr(string memory name, address defaultValue) private view returns (address) {
        string memory raw = vm.envOr(name, string(""));
        return bytes(raw).length == 0 ? defaultValue : vm.parseAddress(raw);
    }

    /// @dev Like vm.envOr, but treats an empty string ("") the same as unset.
    function _envUintOr(string memory name, uint256 defaultValue) private view returns (uint256) {
        string memory raw = vm.envOr(name, string(""));
        return bytes(raw).length == 0 ? defaultValue : vm.parseUint(raw);
    }
}
