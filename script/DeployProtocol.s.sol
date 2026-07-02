// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {BCDeploy} from "battlechain-lib/BCDeploy.sol";
import {VulnerableVault} from "../src/VulnerableVault.sol";

/// @notice Step 1 (Protocol): Deploy the vulnerable protocol in ONE transaction.
/// The VulnerableVault seeds itself by minting from a SHARED, canonical MockToken
/// (not a per-run token) so the token's address is stable and pre-allowlisted on the
/// ConfidencePoolFactory. The vault is deployed via the BattleChainDeployer (registered).
///
/// Prerequisites — set in .env (or rely on the default):
///   TOKEN_ADDRESS (default: the canonical demo token, already allowlisted on the factory)
///
/// Usage:
///   just deploy-protocol            # keystore
///   just deploy-protocol-browser    # your own wallet (MetaMask/Trezor)
///
/// After running, copy the logged VAULT_ADDRESS into your .env.
contract DeployProtocol is BCDeploy {
    uint256 constant SEED_AMOUNT = 1_000e18;
    // Canonical demo MockToken, pre-allowlisted on the ConfidencePoolFactory.
    address constant DEFAULT_TOKEN = 0x12EA23f5600d831cEE92cdbfA10F534a5e7BEF39;

    function run() external {
        address token = vm.envOr("TOKEN_ADDRESS", DEFAULT_TOKEN);

        vm.startBroadcast();
        bytes32 salt = keccak256(abi.encodePacked("vulnerable-vault-v1", msg.sender));
        address vault = bcDeployCreate2(
            salt,
            abi.encodePacked(type(VulnerableVault).creationCode, abi.encode(SEED_AMOUNT, token))
        );
        vm.stopBroadcast();

        console.log("VulnerableVault deployed + seeded with", SEED_AMOUNT / 1e18, "tokens:", vault);
        console.log("Stake token (shared, pre-allowlisted):", token);
        console.log("\n--- Add to your .env ---");
        console.log("VAULT_ADDRESS=%s", vault);
        console.log("TOKEN_ADDRESS=%s", token);
    }
}
