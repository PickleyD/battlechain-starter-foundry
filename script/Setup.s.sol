// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VulnerableVault} from "../src/VulnerableVault.sol";
import {IBattleChainDeployer} from "../src/interfaces/IBattleChain.sol";

/// @notice Step 1 (Protocol): Deploy VulnerableVault and seed it with tokens.
///
/// Prerequisites — set in .env:
///   TOKEN_ADDRESS  (the deployed token with onTransfer hook)
///
/// Usage:
///   forge script script/Setup.s.sol --rpc-url battlechain --broadcast
///
/// After running, copy the logged address into your .env file.
contract Setup is Script {
    // BattleChain testnet
    address constant BATTLECHAIN_DEPLOYER = 0x8f57054CBa2021bEE15631067dd7B7E0B43F17Dc;

    uint256 constant SEED_AMOUNT = 1_000e18; // tokens seeded into vault as "protocol liquidity"

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);
        address tokenAddr   = vm.envAddress("TOKEN_ADDRESS");

        vm.startBroadcast(deployerKey);

        // 1. Deploy VulnerableVault via BattleChainDeployer so it is
        //    automatically registered with the AttackRegistry
        IBattleChainDeployer bcDeployer = IBattleChainDeployer(BATTLECHAIN_DEPLOYER);

        bytes memory bytecode = abi.encodePacked(
            type(VulnerableVault).creationCode,
            abi.encode(tokenAddr) // constructor arg: token address
        );
        bytes32 salt = keccak256(abi.encodePacked("vulnerable-vault-v1", deployer));

        address vault = bcDeployer.deployCreate2(salt, bytecode);
        console.log("VulnerableVault deployed:", vault);

        // 2. Seed the vault with tokens to represent protocol liquidity
        IERC20(tokenAddr).transfer(vault, SEED_AMOUNT);
        console.log("Vault seeded with", SEED_AMOUNT / 1e18, "tokens");

        vm.stopBroadcast();

        console.log("\n--- Add to your .env ---");
        console.log("VAULT_ADDRESS=%s", vault);
    }
}
