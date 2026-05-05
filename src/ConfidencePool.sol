// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { Ownable2Step } from "@openzeppelin/contracts/access/Ownable2Step.sol";

import { IAttackRegistry } from "./interfaces/IAttackRegistry.sol";

/// @title ConfidencePool
/// @notice 1:1 with a Safe Harbor agreement. Holds a protocol-funded `bonus`
///         (also toppable by sponsors) and per-staker confidence stakes.
///         Resolves on terminal AttackRegistry state:
///           - PRODUCTION  → stakers split stake + bonus pro-rata
///           - CORRUPTED + good-faith attacker  → entire pot to attacker
///           - CORRUPTED + bad-faith / unattributed → entire pot to recovery
// aderyn-ignore-next-line(centralization-risk)
contract ConfidencePool is ReentrancyGuard, Ownable2Step {
    using SafeERC20 for IERC20;

    uint256 public constant WITHDRAW_DELAY = 72 hours;

    IAttackRegistry public immutable registry;
    address public immutable agreement;
    IERC20 public immutable stakeToken;
    address public immutable outcomeModerator;

    /// Recovery destination for the bad-faith CORRUPTED path. Mutable to
    /// mirror the underlying Safe Harbor Agreement, which allows the protocol
    /// to update its asset recovery address outside the commitment window.
    /// Locked once the outcome moderator has flagged a result.
    address public recoveryAddress;

    uint256 public bonus;
    uint256 public totalStaked;
    mapping(address staker => uint256) public stakeOf;
    mapping(address contributor => uint256) public bonusContributedBy;

    struct PendingWithdraw {
        uint256 amount;
        uint256 releaseAt;
    }

    mapping(address staker => PendingWithdraw) public pendingWithdraw;
    uint256 public totalPendingWithdraw;

    address public flaggedAttacker;
    bool public flaggedGoodFaith;
    bool public outcomeFlagged;

    /// On the first PRODUCTION claim we snapshot the bonus and stake totals so
    /// later claimants compute their share against frozen denominators (no
    /// last-claimer rounding loss, no dependence on call ordering).
    uint256 public bonusAtResolution;
    uint256 public totalStakedAtResolution;
    bool public productionResolved;

    bool public corruptedResolved;

    event RecoveryAddressUpdated(address indexed oldRecovery, address indexed newRecovery);
    event BonusContributed(address indexed contributor, uint256 amount, uint256 newBonus);
    event Staked(address indexed staker, uint256 amount, uint256 newTotalStaked);
    event WithdrawRequested(address indexed staker, uint256 amount, uint256 releaseAt);
    event WithdrawExecuted(address indexed staker, uint256 amount);
    event OutcomeFlagged(address indexed attacker, bool goodFaith);
    event ClaimedSurvived(address indexed staker, uint256 stakePaid, uint256 bonusPaid);
    event ClaimedCorrupted(address indexed attacker, uint256 amount);
    event SweptToRecovery(address indexed recovery, uint256 amount);

    error WrongState(IAttackRegistry.ContractState state);
    error AlreadyResolved();
    error AlreadyFlagged();
    error NotFlagged();
    error NotOutcomeModerator();
    error NotAttacker();
    error NoStake();
    error InsufficientStake();
    error WithdrawNotReady();
    error NoPendingWithdraw();
    error AttackerEligible();
    error ZeroAmount();
    error ZeroAddress();

    /// @param _registry         BattleChain AttackRegistry.
    /// @param _agreement        Safe Harbor agreement this pool is bound to.
    /// @param _stakeToken       ERC20 used for stakes, bonus, and payouts.
    /// @param _outcomeModerator If `address(0)`, defaults to the agreement's
    ///                          attack moderator from the registry.
    /// @param _recoveryAddress  Destination for the bad-faith CORRUPTED sweep.
    /// @param _initialOwner     Initial owner — typically the protocol team.
    ///                          Owner can rotate `recoveryAddress` until the
    ///                          outcome moderator flags a result.
    constructor(
        address _registry,
        address _agreement,
        address _stakeToken,
        address _outcomeModerator,
        address _recoveryAddress,
        address _initialOwner
    ) Ownable(_initialOwner) {
        if (_recoveryAddress == address(0)) revert ZeroAddress();

        registry = IAttackRegistry(_registry);
        agreement = _agreement;
        stakeToken = IERC20(_stakeToken);
        // aderyn-fp-next-line(reentrancy-state-change)
        outcomeModerator = _outcomeModerator == address(0)
            ? IAttackRegistry(_registry).getAttackModerator(_agreement)
            : _outcomeModerator;
        recoveryAddress = _recoveryAddress;
    }

    /* ------------------------------------------------------------------ */
    /*                         Recovery rotation                          */
    /* ------------------------------------------------------------------ */

    /// Owner-only update of the recovery destination. Locked once the
    /// outcome moderator has flagged a result, so the post-CORRUPTED sweep
    /// path can't be rerouted between flag and sweep.
    function setRecoveryAddress(address newRecovery) external onlyOwner {
        if (newRecovery == address(0)) revert ZeroAddress();
        if (outcomeFlagged) revert AlreadyFlagged();
        address old = recoveryAddress;
        recoveryAddress = newRecovery;
        emit RecoveryAddressUpdated(old, newRecovery);
    }

    /* ------------------------------------------------------------------ */
    /*                              Funding                               */
    /* ------------------------------------------------------------------ */

    /// Add to the bonus pot. Allowed any time before terminal resolution.
    /// Per-address attribution is tracked but funds are pooled at resolution.
    function contributeBonus(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (productionResolved || corruptedResolved) revert AlreadyResolved();
        // aderyn-fp-next-line(reentrancy-state-change)
        IAttackRegistry.ContractState s = registry.getAgreementState(agreement);
        if (
            s == IAttackRegistry.ContractState.PRODUCTION ||
            s == IAttackRegistry.ContractState.CORRUPTED
        ) revert WrongState(s);

        bonus += amount;
        bonusContributedBy[msg.sender] += amount;
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit BonusContributed(msg.sender, amount, bonus);
    }

    /// Stake confidence in the protocol surviving attack mode.
    /// Allowed during UNDER_ATTACK and PROMOTION_REQUESTED.
    function stake(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        // aderyn-fp-next-line(reentrancy-state-change)
        IAttackRegistry.ContractState s = registry.getAgreementState(agreement);
        if (
            s != IAttackRegistry.ContractState.UNDER_ATTACK &&
            s != IAttackRegistry.ContractState.PROMOTION_REQUESTED
        ) revert WrongState(s);

        stakeOf[msg.sender] += amount;
        totalStaked += amount;
        stakeToken.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount, totalStaked);
    }

    /* ------------------------------------------------------------------ */
    /*                             Withdrawals                            */
    /* ------------------------------------------------------------------ */

    /// Queue a withdrawal. New requests are accepted only during UNDER_ATTACK
    /// — PROMOTION_REQUESTED disables them, and the in-flight queue's release
    /// timers stop progressing (executeWithdraw reverts) until terminal state.
    /// Multiple requests stack into a single pending entry that bumps the
    /// release timer forward — a staker can't dodge the delay by requesting
    /// in tiny increments before an exploit lands.
    function requestWithdraw(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        // aderyn-fp-next-line(reentrancy-state-change)
        IAttackRegistry.ContractState s = registry.getAgreementState(agreement);
        if (s != IAttackRegistry.ContractState.UNDER_ATTACK) revert WrongState(s);
        if (stakeOf[msg.sender] < amount) revert InsufficientStake();

        stakeOf[msg.sender] -= amount;
        totalStaked -= amount;

        PendingWithdraw storage p = pendingWithdraw[msg.sender];
        uint256 newAmount = p.amount + amount;
        uint256 releaseAt = block.timestamp + WITHDRAW_DELAY;
        p.amount = newAmount;
        p.releaseAt = releaseAt;
        totalPendingWithdraw += amount;

        emit WithdrawRequested(msg.sender, amount, releaseAt);
    }

    /// Execute a queued withdrawal. Allowed during UNDER_ATTACK after the
    /// release timer expires, or during PRODUCTION immediately (the protocol
    /// survived; the staker forfeits the bonus on the pending portion but
    /// gets their principal). Disallowed during PROMOTION_REQUESTED (timer
    /// freeze) and CORRUPTED (funds stay in the pot for the attacker/recovery
    /// to claim per the resolution rules).
    function executeWithdraw() external nonReentrant {
        PendingWithdraw memory p = pendingWithdraw[msg.sender];
        if (p.amount == 0) revert NoPendingWithdraw();

        // aderyn-fp-next-line(reentrancy-state-change)
        IAttackRegistry.ContractState s = registry.getAgreementState(agreement);
        if (s == IAttackRegistry.ContractState.UNDER_ATTACK) {
            if (block.timestamp < p.releaseAt) revert WithdrawNotReady();
        } else if (s != IAttackRegistry.ContractState.PRODUCTION) {
            revert WrongState(s);
        }

        delete pendingWithdraw[msg.sender];
        totalPendingWithdraw -= p.amount;
        stakeToken.safeTransfer(msg.sender, p.amount);

        emit WithdrawExecuted(msg.sender, p.amount);
    }

    /* ------------------------------------------------------------------ */
    /*                             Resolution                             */
    /* ------------------------------------------------------------------ */

    /// Outcome moderator names the attacker and judges good-faith compliance.
    /// Only callable once, only after the registry's state has gone CORRUPTED.
    /// `attacker = address(0)` or `goodFaith = false` routes the pool to the
    /// recovery address via `sweepBadFaithToRecovery`.
    function flagOutcome(address attacker, bool goodFaith) external {
        if (msg.sender != outcomeModerator) revert NotOutcomeModerator();
        if (outcomeFlagged) revert AlreadyFlagged();
        // aderyn-fp-next-line(reentrancy-state-change)
        IAttackRegistry.ContractState s = registry.getAgreementState(agreement);
        if (s != IAttackRegistry.ContractState.CORRUPTED) revert WrongState(s);

        flaggedAttacker = attacker;
        flaggedGoodFaith = goodFaith;
        outcomeFlagged = true;

        emit OutcomeFlagged(attacker, goodFaith);
    }

    /// Stakers claim their pro-rata share of stake + bonus on PRODUCTION.
    /// First call snapshots the denominators so each staker's payout is
    /// independent of call ordering and there is no last-claimer rounding loss.
    function claimSurvived() external nonReentrant {
        // aderyn-fp-next-line(reentrancy-state-change)
        IAttackRegistry.ContractState s = registry.getAgreementState(agreement);
        if (s != IAttackRegistry.ContractState.PRODUCTION) revert WrongState(s);

        uint256 share = stakeOf[msg.sender];
        if (share == 0) revert NoStake();

        if (!productionResolved) {
            bonusAtResolution = bonus;
            totalStakedAtResolution = totalStaked;
            productionResolved = true;
        }

        // Frozen denominators — totalStakedAtResolution > 0 because share > 0
        // and share <= totalStaked at resolution time.
        uint256 bonusShare = (bonusAtResolution * share) / totalStakedAtResolution;
        uint256 payout = share + bonusShare;

        stakeOf[msg.sender] = 0;
        // We don't decrement totalStaked here — it is no longer load-bearing
        // (totalStakedAtResolution is what payouts compute against), and
        // leaving it intact keeps the post-mortem state inspectable.

        stakeToken.safeTransfer(msg.sender, payout);
        emit ClaimedSurvived(msg.sender, share, bonusShare);
    }

    /// Designated good-faith attacker claims the entire pool on CORRUPTED.
    /// `balanceOf` is used (not the bonus/totalStaked accounting) so any
    /// funds still in pending withdrawals — which the staker forfeits when
    /// CORRUPTED is flagged before their release time — are included.
    function claimCorrupted() external nonReentrant {
        if (corruptedResolved) revert AlreadyResolved();
        if (!outcomeFlagged) revert NotFlagged();
        if (msg.sender != flaggedAttacker || flaggedAttacker == address(0)) revert NotAttacker();
        if (!flaggedGoodFaith) revert NotAttacker();

        // aderyn-fp-next-line(reentrancy-state-change)
        IAttackRegistry.ContractState s = registry.getAgreementState(agreement);
        if (s != IAttackRegistry.ContractState.CORRUPTED) revert WrongState(s);

        corruptedResolved = true;
        uint256 amount = stakeToken.balanceOf(address(this));
        stakeToken.safeTransfer(msg.sender, amount);

        emit ClaimedCorrupted(msg.sender, amount);
    }

    /// Sweep the entire pool to the recovery address when the moderator
    /// flagged a bad-faith outcome (or refused to attribute,
    /// `attacker == address(0)`). Permissionless — anyone can trigger the
    /// transfer once the moderator's flag has set the path.
    function sweepBadFaithToRecovery() external nonReentrant {
        if (corruptedResolved) revert AlreadyResolved();
        if (!outcomeFlagged) revert NotFlagged();
        if (flaggedGoodFaith && flaggedAttacker != address(0)) revert AttackerEligible();

        // aderyn-fp-next-line(reentrancy-state-change)
        IAttackRegistry.ContractState s = registry.getAgreementState(agreement);
        if (s != IAttackRegistry.ContractState.CORRUPTED) revert WrongState(s);

        corruptedResolved = true;
        address recovery = recoveryAddress;
        uint256 amount = stakeToken.balanceOf(address(this));
        stakeToken.safeTransfer(recovery, amount);

        emit SweptToRecovery(recovery, amount);
    }

    /* ------------------------------------------------------------------ */
    /*                               Views                                */
    /* ------------------------------------------------------------------ */

    function getAgreementState() external view returns (IAttackRegistry.ContractState) {
        return registry.getAgreementState(agreement);
    }

    function totalPot() external view returns (uint256) {
        return totalStaked + totalPendingWithdraw + bonus;
    }
}
