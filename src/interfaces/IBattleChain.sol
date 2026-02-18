// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ─────────────────────────────────────────────
// Enums
// ─────────────────────────────────────────────

enum ChildContractScope {
    None,
    ExistingAtTimeOfAgreement,
    All
}

enum IdentityRequirements {
    Anonymous,
    Pseudonymous,
    Named
}

enum ContractState {
    NOT_DEPLOYED,       // 0
    NEW_DEPLOYMENT,     // 1
    ATTACK_REQUESTED,   // 2
    UNDER_ATTACK,       // 3
    PROMOTION_REQUESTED,// 4
    PRODUCTION,         // 5
    CORRUPTED           // 6
}

// ─────────────────────────────────────────────
// Structs
// ─────────────────────────────────────────────

struct Contact {
    string name;
    string contact;
}

struct ScopeAccount {
    string accountAddress;       // e.g. "0x1234..."
    ChildContractScope childContractScope;
}

struct ScopeChain {
    string caip2ChainId;         // e.g. "eip155:627"
    string assetRecoveryAddress; // address that receives recovered funds
    ScopeAccount[] accounts;
}

struct BountyTerms {
    uint256 bountyPercentage;       // e.g. 10 = 10%
    uint256 bountyCapUsd;           // max bounty per whitehat in USD
    bool retainable;                // whitehat keeps bounty from recovered funds
    IdentityRequirements identity;
    string diligenceRequirements;
    uint256 aggregateBountyCapUsd;  // 0 = no cap
}

struct AgreementDetails {
    string protocolName;
    Contact[] contactDetails;
    ScopeChain[] chains;
    BountyTerms bountyTerms;
    string agreementURI;
}

// ─────────────────────────────────────────────
// Interfaces
// ─────────────────────────────────────────────

interface IBattleChainDeployer {
    function deployCreate2(bytes32 salt, bytes memory bytecode) external returns (address);
    function deployCreate3(bytes32 salt, bytes memory bytecode) external returns (address);
    function deployCreate(bytes memory bytecode) external returns (address);
}

interface IAgreementFactory {
    function create(
        AgreementDetails memory details,
        address owner,
        bytes32 salt
    ) external returns (address agreementAddress);

    function isAgreementContract(address agreementAddress) external view returns (bool);
    function getBattleChainCaip2ChainId() external view returns (string memory);
}

interface IAgreement {
    function extendCommitmentWindow(uint256 newCantChangeUntil) external;
    function getDetails() external view returns (AgreementDetails memory);
    function getAssetRecoveryAddress(string memory caip2ChainId) external view returns (string memory);
    function isContractInScope(address contractAddress) external view returns (bool);
}

interface ISafeHarborRegistry {
    function adoptSafeHarbor(address agreementAddress) external;
    function isAgreementValid(address agreementAddress) external view returns (bool);
}

interface IAttackRegistry {
    function requestUnderAttack(address agreementAddress) external;
    function requestUnderAttackByNonAuthorized(address agreementAddress) external;
    function getAgreementState(address agreementAddress) external view returns (ContractState);
    function getAgreementForContract(address contractAddress) external view returns (address);
    function isTopLevelContractUnderAttack(address contractAddress) external view returns (bool);
}
