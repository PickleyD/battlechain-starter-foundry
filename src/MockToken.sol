// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @dev Callback interface implemented by contracts that want to react to
///      receiving MockToken (used to make the CEI vulnerability exploitable).
interface ITokenReceiver {
    function onTokenReceived(address from, uint256 amount) external;
}

/// @title MockToken
/// @notice A mintable ERC20 with a transfer callback hook.
/// @dev When tokens are transferred to a contract address, MockToken calls
///      `onTokenReceived` on the recipient (if implemented). This simulates
///      token standards that notify recipients — and is what makes the
///      CEI violation in VulnerableVault exploitable.
contract MockToken is ERC20 {
    constructor() ERC20("BattleChain Demo Token", "BCDT") {}

    /// @notice Anyone can mint. This is intentional for the tutorial.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev Overrides transfer to notify contract recipients via callback.
    function transfer(address to, uint256 amount) public override returns (bool) {
        bool success = super.transfer(to, amount);

        // If the recipient is a contract, attempt the callback.
        // Wrapped in try/catch so a reverting callback never blocks the transfer.
        if (to.code.length > 0) {
            try ITokenReceiver(to).onTokenReceived(msg.sender, amount) {} catch {}
        }

        return success;
    }
}
