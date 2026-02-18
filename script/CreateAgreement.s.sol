// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {
    IAgreementFactory,
    IAgreement,
    ISafeHarborRegistry,
    AgreementDetails,
    Contact,
    ScopeChain,
    ScopeAccount,
    BountyTerms,
    ChildContractScope,
    IdentityRequirements
} from "../src/interfaces/IBattleChain.sol";

/// @notice Step 2 (Protocol): Create a Safe Harbor agreement and enter attack mode eligibility.
///
/// Prerequisites — set in .env:
///   MOCK_TOKEN, VAULT_ADDRESS
///
/// Usage:
///   forge script script/CreateAgreement.s.sol --rpc-url battlechain --broadcast
///
/// After running, copy AGREEMENT_ADDRESS into your .env file.
contract CreateAgreement is Script {
    // BattleChain testnet
    address constant AGREEMENT_FACTORY   = 0x0EbBEeB3aBeF51801a53Fdd1fb263Ac0f2E3Ed36;
    address constant SAFE_HARBOR_REGISTRY = 0xCb2A561395118895e2572A04C2D8AB8eCA8d7E5D;

    string constant BATTLECHAIN_CAIP2 = "eip155:627";
    uint256 constant COMMITMENT_WINDOW = 30 days;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer    = vm.addr(deployerKey);
        address vault       = vm.envAddress("VAULT_ADDRESS");

        vm.startBroadcast(deployerKey);

        // ── Contact details ────────────────────────────────────────────────
        Contact[] memory contacts = new Contact[](1);
        contacts[0] = Contact({
            name:    "Security Team",
            contact: "security@example.com"
        });

        // ── Scope: put VulnerableVault in scope on BattleChain ─────────────
        ScopeAccount[] memory accounts = new ScopeAccount[](1);
        accounts[0] = ScopeAccount({
            accountAddress:    vm.toString(vault),
            childContractScope: ChildContractScope.All
        });

        ScopeChain[] memory chains = new ScopeChain[](1);
        chains[0] = ScopeChain({
            caip2ChainId:         BATTLECHAIN_CAIP2,
            assetRecoveryAddress: vm.toString(deployer), // recovered funds go back to deployer
            accounts:             accounts
        });

        // ── Bounty terms ───────────────────────────────────────────────────
        BountyTerms memory bountyTerms = BountyTerms({
            bountyPercentage:      10,         // 10%
            bountyCapUsd:          5_000_000,  // $5M cap
            retainable:            true,
            identity:              IdentityRequirements.Anonymous,
            diligenceRequirements: "",
            aggregateBountyCapUsd: 0
        });

        // ── Assemble and create ────────────────────────────────────────────
        AgreementDetails memory details = AgreementDetails({
            protocolName:   "BattleChain Starter Demo",
            contactDetails: contacts,
            chains:         chains,
            bountyTerms:    bountyTerms,
            agreementURI:   ""
        });

        bytes32 salt = keccak256(abi.encodePacked("agreement-v1", deployer));
        address agreement = IAgreementFactory(AGREEMENT_FACTORY).create(details, deployer, salt);
        console.log("Agreement created:", agreement);

        // ── Extend commitment window ───────────────────────────────────────
        IAgreement(agreement).extendCommitmentWindow(block.timestamp + COMMITMENT_WINDOW);
        console.log("Commitment window extended 30 days");

        // ── Adopt Safe Harbor ──────────────────────────────────────────────
        ISafeHarborRegistry(SAFE_HARBOR_REGISTRY).adoptSafeHarbor(agreement);
        console.log("Safe Harbor adopted");

        vm.stopBroadcast();

        console.log("\n--- Add to your .env ---");
        console.log("AGREEMENT_ADDRESS=%s", agreement);
    }
}
