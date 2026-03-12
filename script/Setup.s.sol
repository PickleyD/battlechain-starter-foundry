// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {BCDeploy} from "battlechain-lib/BCDeploy.sol";
import {MockToken} from "../src/MockToken.sol";
import {VulnerableVault} from "../src/VulnerableVault.sol";

/// @notice Step 1 (Protocol): Deploy MockToken + VulnerableVault, seed the vault.
///
/// Prerequisites — set in .env:
///   SENDER_ADDRESS
///
/// Usage:
///   just setup
///
/// After running, copy the logged addresses into your .env file.
contract Setup is BCDeploy {
    uint256 constant SEED_AMOUNT = 1_000e18;

    function run() external {
        vm.startBroadcast();

        // 1. Deploy MockToken via CreateX (BattleChain uses BattleChainDeployer automatically)
        address token = bcDeployCreate(type(MockToken).creationCode);
        console.log("MockToken deployed:", token);

        // 2. Deploy VulnerableVault via CreateX with deterministic address
        bytes32 salt = keccak256(abi.encodePacked("vulnerable-vault-v1", msg.sender));
        address vault = bcDeployCreate2(
            salt,
            abi.encodePacked(type(VulnerableVault).creationCode, abi.encode(token))
        );
        console.log("VulnerableVault deployed:", vault);

        // 3. Seed the vault with tokens to represent protocol liquidity
        MockToken(token).mint(msg.sender, SEED_AMOUNT);
        MockToken(token).approve(vault, SEED_AMOUNT);
        VulnerableVault(vault).deposit(SEED_AMOUNT);
        console.log("Vault seeded with", SEED_AMOUNT / 1e18, "tokens");

        vm.stopBroadcast();

        console.log("\n--- Add to your .env ---");
        console.log("TOKEN_ADDRESS=%s", token);
        console.log("VAULT_ADDRESS=%s", vault);
    }
}
