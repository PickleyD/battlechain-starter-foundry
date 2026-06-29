# Battlechain Starter

- [About](#about)
- [Getting Started](#getting-started)
  - [Requirements](#requirements)
  - [Installation](#installation)
- [Usage](#usage)
  - [1. Set up a wallet](#1-set-up-a-wallet)
  - [2. Protocol role](#2-protocol-role)
  - [3. Whitehat role](#3-whitehat-role)
  - [Settle the ConfidencePool](#settle-the-confidencepool)
  - [Verify on the explorer](#verify-on-the-explorer)
  - [Sign with your own wallet (MetaMask/Trezor)](#sign-with-your-own-wallet-metamasktrezor)
  - [Utilities](#utilities)

# About

A starter repo for interacting with the BattleChain Safe Harbor protocol. It walks the
full flow: deploy a deliberately vulnerable vault, register a Safe Harbor agreement,
open it for attack, and execute a whitehat rescue that splits the proceeds per the
agreement terms.

Every step is a **single transaction**, so it works equally well from a keystore (below)
or signed in your own browser wallet (see [Sign with your own wallet](#sign-with-your-own-wallet-metamasktrezor)).

## Networks

| Network             | Chain ID | RPC                              |
| ------------------- | -------- | -------------------------------- |
| BattleChain         | 626      | https://mainnet.battlechain.com  |
| BattleChain Testnet | 627      | https://testnet.battlechain.com  |

The Safe Harbor core contracts (registry, agreement factory, attack registry), CreateX,
and the Safe contract suite are deployed on both networks, and both have a block explorer
with contract verification: [mainnet](https://explorer.mainnet.battlechain.com/) and
[testnet](https://explorer.testnet.battlechain.com/). The flows here target **BattleChain
Testnet**, since the mock dependencies (such as the permissionless `MockRegistryModerator`
used to approve attack mode) are testnet-only.

# Getting Started

## Requirements

- [git](https://git-scm.com/) — `git --version`
- [foundry](https://getfoundry.sh/) — `forge --version`
  - The browser-wallet targets (`just *-browser`) need Foundry **nightly**: `foundryup -i nightly`
- [just](https://github.com/casey/just) — `just --version`

## Installation

```bash
git clone <MY_REPO>
cd <MY_REPO>
forge install
just build
```

# Usage

The steps chain by passing addresses through `.env`. After each deploy step, copy the
logged address into `.env` before running the next one.

## 1. Set up a wallet

Create a fresh keystore account named `battlechain` and put its address in `.env`:

```bash
just generate-key                 # imports a random key as the `battlechain` keystore account
```

Add to `.env` (use the address `generate-key` prints; for this demo the protocol's
recovery address is just your own wallet):

```
SENDER_ADDRESS=0xYourAddress
RECOVERY_ADDRESS=0xYourAddress
```

`RECOVERY_ADDRESS` is baked into the agreement at create time and reused by the
ConfidencePool and the attack step; it defaults to `SENDER_ADDRESS` if unset.

Fund the address with a little BattleChain Testnet ETH for gas (bridge Sepolia ETH at
https://portal.battlechain.com/bridge).

## 2. Protocol role

```bash
# Deploy the vulnerable protocol. The vault deploys + seeds its own MockToken.
# Copy the logged VAULT_ADDRESS and TOKEN_ADDRESS into .env.
just deploy-protocol

# Register a Safe Harbor agreement scoping the vault. Copy AGREEMENT_ADDRESS into .env.
just create-agreement

# Deploy a ConfidencePool for the agreement and seed it with a bonus
# (requires AGREEMENT_ADDRESS, TOKEN_ADDRESS in .env). Copy CONFIDENCE_POOL_ADDRESS into .env.
just create-confidence-pool

# Lock the agreement's commitment window — REQUIRED before attack mode can be
# requested (the AttackRegistry reverts with InsufficientCommitment otherwise).
just set-commitment-window

# Adopt the agreement in the registry.
just adopt-agreement

# Request attack mode for the agreement.
just request-attack-mode
```

### ConfidencePool

A ConfidencePool is a small contract bound 1:1 to a Safe Harbor agreement that holds a pre-funded bonus (and any later stakes). Whitehat bots use the pool's total pot to rank attackable agreements by expected payoff, so seeding it before requesting attack mode means the bonus is visible from the moment the agreement becomes attackable. The default seeds the pool with 1000 tokens — override with `BONUS_AMOUNT` in `.env` if needed.

## 3. Whitehat role

```bash
# Deploy the Exploit: it approves attack mode (via the permissionless testnet
# moderator), drains the vault via reentrancy, and splits the proceeds
# (90% returned to the recovery address, 10% kept as the bounty).
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

## Verify on the explorer

```bash
just verify-protocol            # verify MockToken + VulnerableVault
just verify-exploit             # verify the Exploit + Attacker
just verify-confidence-pool     # verify the ConfidencePool
```

## Sign with your own wallet (MetaMask/Trezor)

Every step above has a `-browser` variant that signs in your own wallet instead of a
keystore. These need Foundry **nightly** (`foundryup -i nightly`) and use `cast` under
the hood (`forge script --browser` hangs waiting on the wallet; `cast send` doesn't):

```bash
just deploy-protocol-browser
just create-agreement-browser
just create-confidence-pool-browser
just set-commitment-window-browser
just adopt-agreement-browser
just request-attack-mode-browser
just attack-browser

# Settle the ConfidencePool
just mark-corrupted-browser
just flag-outcome-browser
just claim-corrupted-browser
```

Approve each transaction in your wallet when it pops up, then copy the resulting address
into `.env` (the deployed addresses appear in the `ContractCreation` logs of the receipt).

## Utilities

```bash
just check-state         # agreement state (2=ATTACK_REQUESTED, 3=UNDER_ATTACK)
just test                # run the reentrancy tests
just set-commitment-window   # optional: lock the agreement terms for a period
```
