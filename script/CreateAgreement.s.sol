// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";
import {BCSafeHarbor} from "battlechain-lib/BCSafeHarbor.sol";
import {IAgreementFactory} from "battlechain-lib/interfaces/IAgreementFactory.sol";
import {
    AgreementDetails,
    Contact,
    BountyTerms,
    IdentityRequirements
} from "battlechain-lib/types/AgreementTypes.sol";

/// @notice Step 2 (Protocol): Create a Safe Harbor agreement scoping the vault.
///
/// Prerequisites — set in .env:
///   SENDER_ADDRESS, VAULT_ADDRESS
///
/// Optional .env overrides:
///   RECOVERY_ADDRESS (default: SENDER_ADDRESS — also used by Attack and ConfidencePool steps;
///                     this is the agreement's protocol + recovery address)
///
/// Keystore:  just create-agreement   (broadcasts via run())
/// Browser:   just create-agreement-browser   (genCalldata() prints the create()
///            calldata, which is then sent with `cast send --data` — forge script
///            itself hangs in the browser wallet, so we only use it to build calldata)
///
/// After running, copy AGREEMENT_ADDRESS into your .env file.
contract CreateAgreement is BCSafeHarbor {
    /// @dev Builds the agreement scoping `vault`, with `owner` as protocol + recovery.
    function _buildDetails(address vault, address owner) internal view returns (AgreementDetails memory details) {
        Contact[] memory contacts = new Contact[](1);
        contacts[0] = Contact({name: "Security Team", contact: "security@example.com"});

        address[] memory contracts_ = new address[](1);
        contracts_[0] = vault;

        details = defaultAgreementDetails("BattleChain Starter Demo", contacts, contracts_, owner);
        details.bountyTerms = BountyTerms({
            bountyPercentage: 10,
            bountyCapUsd: 5_000_000,
            retainable: true,
            identity: IdentityRequirements.Anonymous,
            diligenceRequirements: "",
            aggregateBountyCapUsd: 0
        });
    }

    function _salt(address owner, address vault) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("agreement-v1", owner, vault));
    }

    /// @notice Keystore path: build + create the agreement in one broadcast.
    function run() external {
        address vault = vm.envAddress("VAULT_ADDRESS");
        address recovery = _envAddressOr("RECOVERY_ADDRESS", msg.sender);

        vm.startBroadcast();
        AgreementDetails memory details = _buildDetails(vault, recovery);
        address agreement = createAgreement(details, msg.sender, _salt(msg.sender, vault));
        vm.stopBroadcast();

        console.log("Agreement created:", agreement);
        console.log("\n--- Add to your .env ---");
        console.log("AGREEMENT_ADDRESS=%s", agreement);
    }

    /// @notice Browser path: print the AgreementFactory.create() calldata (no broadcast,
    ///         so no browser-wallet hang). Send it with `cast send <factory> --data <calldata>`.
    function genCalldata() external view {
        address owner = vm.envAddress("SENDER_ADDRESS");
        address vault = vm.envAddress("VAULT_ADDRESS");
        address recovery = _envAddressOr("RECOVERY_ADDRESS", owner);

        AgreementDetails memory details = _buildDetails(vault, recovery);
        bytes memory cd = abi.encodeCall(IAgreementFactory.create, (details, owner, _salt(owner, vault)));

        console.log("AGREEMENT_CREATE_CALLDATA=%s", vm.toString(cd));
    }

    /// @dev Like vm.envOr, but treats an empty string ("") the same as unset.
    function _envAddressOr(string memory name, address defaultValue) private view returns (address) {
        string memory raw = vm.envOr(name, string(""));
        return bytes(raw).length == 0 ? defaultValue : vm.parseAddress(raw);
    }
}
