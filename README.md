# Battlechain Starter

- [About](#about)
- [Getting Started](#getting-started)
  - [Requirements](#requirements)
  - [Installation](#installation)
  - [Quickstart](#quickstart)
- [Usage](#usage)
  - [Protocol Role](#protocol-role)
  - [Whitehat Role](#whitehat-role)
  - [Settle the ConfidencePool](#settle-the-confidencepool)
  - [Utilities](#utilities)

# About

A starter repo for interacting with the Battlechain Safe Harbor protocol. Includes scripts for deploying a vulnerable vault, creating a Safe Harbor agreement, requesting attack mode, and executing a whitehat rescue.

# Getting Started

## Requirements

- [git](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)
  - You'll know you did it right if you can run `git --version` and you see a response like `git version x.x.x`
- [foundry](https://getfoundry.sh/)
  - You'll know you did it right if you can run `forge --version` and you see a response like `forge 0.2.0 (816e00b 2023-03-16T00:05:26.396218Z)`
  - For browser wallet targets (`just *-browser`), you need forge >= `1.6.0-nightly` (commit `c1cdc6c1`, 2026-03-10) or later
- [just](https://github.com/casey/just)
  - You'll know you did it right if you can run `just --version` and you see a response like `just 1.x.x`

## Installation

```bash
git clone <MY_REPO>
cd <MY_REPO>
```

## Quickstart

```bash
just build
```

# Usage

## Protocol Role

```bash
# Step 1: Deploy MockToken + VulnerableVault, seed the vault
just setup

# Step 2: Create Safe Harbor agreement (requires VAULT_ADDRESS in .env)
# Optionally set RECOVERY_ADDRESS first — it's baked into the agreement and
# also used by Step 2b and Step 4. Defaults to SENDER_ADDRESS if unset.
just create-agreement

# Step 2b: Deploy a ConfidencePool and seed it with a bonus
# (requires AGREEMENT_ADDRESS, TOKEN_ADDRESS in .env)
just create-confidence-pool

# Step 3: Request attack mode (requires AGREEMENT_ADDRESS in .env)
just request-attack-mode
```

### ConfidencePool

A ConfidencePool is a small contract bound 1:1 to a Safe Harbor agreement that holds a pre-funded bonus (and any later stakes). Whitehat bots use the pool's total pot to rank attackable agreements by expected payoff, so seeding it before requesting attack mode means the bonus is visible from the moment the agreement becomes attackable. The default seeds the pool with 1000 tokens — override with `BONUS_AMOUNT` in `.env` if needed.

## Whitehat Role

```bash
# Step 4: Execute the attack (requires DAO approval first)
just attack
```

## Settle the ConfidencePool

After the attack drains the vault, the agreement is still in `UNDER_ATTACK` (3) — nothing on-chain detects the exploit automatically. Settling the ConfidencePool takes three more transactions:

```bash
# Step 5 (Moderator): Mark the agreement as CORRUPTED on the AttackRegistry.
# Callable by the agreement's attack moderator (= the deployer in this demo).
just mark-corrupted

# Step 6 (Pool outcomeModerator): Flag the pool outcome as good-faith corruption,
# attributed to the attacker. Callable by the pool's outcomeModerator
# (defaults to SENDER_ADDRESS at create-confidence-pool time).
just flag-outcome

# Step 7 (Attacker): Drain the pool's entire pot to the attacker's wallet.
just claim-corrupted
```

In this single-wallet demo all three steps are signed by `SENDER_ADDRESS`, but the contracts enforce three distinct roles. Confirm the result:

```bash
# Pool should now hold 0 tokens
cast call $CONFIDENCE_POOL_ADDRESS "totalPot()(uint256)" --rpc-url https://testnet.battlechain.com
```

## Utilities

```bash
# Check agreement state (2=ATTACK_REQUESTED, 3=UNDER_ATTACK)
just check-state

# Run tests
just test
```
