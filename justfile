set dotenv-load

import "lib/battlechain-lib/battlechain.just"

RPC    := "https://testnet.battlechain.com"
ACCT   := "battlechain"

# ── Protocol role ──────────────────────────────────────────────────────────────

# Step 1: Deploy MockToken + VulnerableVault, seed the vault
setup:
    forge script script/Setup.s.sol --rpc-url {{RPC}} --broadcast -vvv --account {{ACCT}} --sender $SENDER_ADDRESS --skip-simulation

# Step 2: Create Safe Harbor agreement (requires VAULT_ADDRESS in .env)
create-agreement:
    forge script script/CreateAgreement.s.sol --rpc-url {{RPC}} --broadcast -vvv --account {{ACCT}} --sender $SENDER_ADDRESS --skip-simulation

# Step 2b: Deploy a ConfidencePool for the agreement and seed it with a bonus
create-confidence-pool:
    forge script script/CreateConfidencePool.s.sol --rpc-url {{RPC}} --broadcast -vvv --account {{ACCT}} --sender $SENDER_ADDRESS --skip-simulation

# Step 3: Request attack mode (requires AGREEMENT_ADDRESS in .env)
request-attack-mode:
    forge script script/RequestAttackMode.s.sol --rpc-url {{RPC}} --broadcast -vvv --account {{ACCT}} --sender $SENDER_ADDRESS --skip-simulation

# ── Whitehat role ──────────────────────────────────────────────────────────────

# Step 4: Execute the attack (requires DAO approval first)
attack:
    forge script script/Attack.s.sol --rpc-url {{RPC}} --broadcast -vvv --account {{ACCT}} --sender $SENDER_ADDRESS --skip-simulation --verify {{bc-verify-flags}}

# ── Browser wallet (AI-initiated, user-approved) ─────────────────────────────

# Step 1: Deploy MockToken + VulnerableVault, seed the vault (browser wallet)
setup-browser:
    forge script script/Setup.s.sol --rpc-url {{RPC}} --broadcast -vvv --browser --chain {{bc-chain-id}} --skip-simulation --verify {{bc-verify-flags}}

# Step 2: Create Safe Harbor agreement (browser wallet)
create-agreement-browser:
    forge script script/CreateAgreement.s.sol --rpc-url {{RPC}} --broadcast -vvv --browser --chain {{bc-chain-id}} --skip-simulation --verify {{bc-verify-flags}}

# Step 2b: Deploy a ConfidencePool and seed it with a bonus (browser wallet)
create-confidence-pool-browser:
    forge script script/CreateConfidencePool.s.sol --rpc-url {{RPC}} --broadcast -vvv --browser --chain {{bc-chain-id}} --skip-simulation --verify {{bc-verify-flags}}

# Step 3: Request attack mode (browser wallet)
request-attack-mode-browser:
    forge script script/RequestAttackMode.s.sol --rpc-url {{RPC}} --broadcast -vvv --browser --chain {{bc-chain-id}} --skip-simulation --verify {{bc-verify-flags}}

# Step 4: Execute the attack (browser wallet)
attack-browser:
    forge script script/Attack.s.sol --rpc-url {{RPC}} --broadcast -vvv --browser --chain {{bc-chain-id}} --skip-simulation --verify {{bc-verify-flags}}

# ── Verification ──────────────────────────────────────────────────────────────

# Verify all contracts from the Setup broadcast
verify-setup:
    just bc-verify-broadcast script/Setup.s.sol

# Verify the deployed ConfidencePool by reading its constructor args off-chain.
# Reads CONFIDENCE_POOL_ADDRESS from .env.
verify-confidence-pool:
    #!/usr/bin/env bash
    set -euo pipefail
    addr="${CONFIDENCE_POOL_ADDRESS:?CONFIDENCE_POOL_ADDRESS not set in .env}"
    echo "Reading constructor args from $addr..."
    registry=$(cast call "$addr" "registry()(address)" --rpc-url {{RPC}})
    agreement=$(cast call "$addr" "agreement()(address)" --rpc-url {{RPC}})
    stake_token=$(cast call "$addr" "stakeToken()(address)" --rpc-url {{RPC}})
    outcome_moderator=$(cast call "$addr" "outcomeModerator()(address)" --rpc-url {{RPC}})
    recovery=$(cast call "$addr" "recoveryAddress()(address)" --rpc-url {{RPC}})
    owner=$(cast call "$addr" "owner()(address)" --rpc-url {{RPC}})
    args=$(cast abi-encode "constructor(address,address,address,address,address,address)" \
        "$registry" "$agreement" "$stake_token" "$outcome_moderator" "$recovery" "$owner")
    echo "Verifying ConfidencePool at $addr"
    forge verify-contract "$addr" src/ConfidencePool.sol:ConfidencePool \
        --constructor-args "$args" \
        --chain-id {{bc-chain-id}} \
        {{bc-verify-flags}} \
        --rpc-url {{RPC}}

# ── Utilities ──────────────────────────────────────────────────────────────────

# Generate a random private key and import it as the 'battlechain' keystore account
generate-key:
    cast wallet import battlechain --private-key 0x$(openssl rand -hex 32)

# Check agreement state (2=ATTACK_REQUESTED, 3=UNDER_ATTACK)
check-state:
    cast call $ATTACK_REGISTRY "getAgreementState(address)(uint8)" $AGREEMENT_ADDRESS \
        --rpc-url https://testnet.battlechain.com

build:
    forge build

test:
    forge test -vvv
