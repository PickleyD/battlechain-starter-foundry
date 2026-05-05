// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import {MockToken} from "../src/MockToken.sol";

interface IConfidencePoolFactory {
    struct CreateParams {
        address agreement;
        address stakeToken;
        address outcomeModerator;
        address recoveryAddress;
    }

    function createPool(CreateParams calldata p) external returns (address pool);
    function poolOf(address agreement) external view returns (address);
}

interface IConfidencePool {
    function contributeBonus(uint256 amount) external;
    function totalPot() external view returns (uint256);
}

/// @notice Step 2b (Protocol): Deploy a ConfidencePool for the agreement and seed it with a bonus.
///
/// A ConfidencePool is a small contract bound 1:1 to a Safe Harbor agreement that holds a
/// pre-funded bonus + optional stakes. AI whitehat bots use the pool's total pot to rank
/// attackable agreements by expected payoff. Creating it before attack mode means the
/// bonus is visible from the moment the agreement becomes attackable.
///
/// Prerequisites — set in .env:
///   SENDER_ADDRESS, AGREEMENT_ADDRESS, TOKEN_ADDRESS
///
/// Optional .env overrides:
///   RECOVERY_ADDRESS   (default: SENDER_ADDRESS — should match what create-agreement used)
///   BONUS_AMOUNT       (default: 1000e18 — matches vault TVL)
///   OUTCOME_MODERATOR  (default: SENDER_ADDRESS — lets the demo flag outcomes itself)
///   FACTORY_ADDRESS    (default: deployed BattleChain testnet factory)
///
/// Usage:
///   just create-confidence-pool
///
/// After running, copy CONFIDENCE_POOL_ADDRESS into your .env file.
contract CreateConfidencePool is Script {
    address private constant DEFAULT_FACTORY = 0xB2a4d5751e80F6C47DaC5dfCb56CbA5b4D690eAA;
    uint256 private constant DEFAULT_BONUS = 1_000e18;

    function run() external {
        address agreement = vm.envAddress("AGREEMENT_ADDRESS");
        address token = vm.envAddress("TOKEN_ADDRESS");
        address sender = vm.envAddress("SENDER_ADDRESS");

        address recovery = _envAddressOr("RECOVERY_ADDRESS", sender);
        uint256 bonusAmount = _envUintOr("BONUS_AMOUNT", DEFAULT_BONUS);
        address outcomeModerator = _envAddressOr("OUTCOME_MODERATOR", sender);
        address factory = _envAddressOr("FACTORY_ADDRESS", DEFAULT_FACTORY);

        vm.startBroadcast();

        // 1. Deploy the pool via the factory
        address pool = IConfidencePoolFactory(factory).createPool(
            IConfidencePoolFactory.CreateParams({
                agreement: agreement,
                stakeToken: token,
                outcomeModerator: outcomeModerator,
                recoveryAddress: recovery
            })
        );

        // 2. Mint the bonus to the deployer and approve the pool to pull it
        MockToken(token).mint(msg.sender, bonusAmount);
        MockToken(token).approve(pool, bonusAmount);

        // 3. Seed the pool
        IConfidencePool(pool).contributeBonus(bonusAmount);

        vm.stopBroadcast();

        console.log("ConfidencePool deployed:", pool);
        console.log("Bonus seeded:", bonusAmount / 1e18, "tokens");
        console.log("Total pot:", IConfidencePool(pool).totalPot());
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
