#!/bin/bash
set -e

# Load environment variables from .env file
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
else
  echo "Error: .env file not found. Copy .env.example to .env and configure it."
  exit 1
fi

# Validate required variables
if [ -z "$TENDERLY_ACCOUNT" ] || [ -z "$TENDERLY_PROJECT" ] || [ -z "$TESTNET_ID" ] || [ -z "$TENDERLY_DEPLOYER_PRIVATE_KEY" ] || [ -z "$TENDERLY_ACCESS_KEY" ] || [ -z "$TENDERLY_VIRTUAL_TESTNET_RPC_URL" ]; then
  echo "Error: Missing required environment variables. Check your .env file."
  exit 1
fi

# Construct verifier URL for virtual testnet
export VERIFIER_URL="${TENDERLY_VIRTUAL_TESTNET_RPC_URL}/verify/etherscan"

# Function to fund an account on Tenderly testnet
fund_account() {
  local private_key=$1
  local amount=${2:-"0xDE0B6B3A7640000"} # Default to 1 ETH if not specified

  echo "Funding account..."
  local address=$(cast wallet address "${private_key}")
  echo "Address: ${address}"

  curl -s "${TENDERLY_VIRTUAL_TESTNET_RPC_URL}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "{
      \"jsonrpc\": \"2.0\",
      \"method\": \"tenderly_setBalance\",
      \"params\": [
        [
          \"${address}\"
        ],
        \"${amount}\"
      ],
      \"id\": \"1234\"
    }" > /dev/null

  echo "Account funded successfully"
  echo ""
}

# Function to run forge scripts with optional broadcasting
run_script() {
  local script_name=$1
  local broadcast=$2

  if [ "$broadcast" = "true" ]; then
    forge script "$script_name" \
      --rpc-url="${TENDERLY_VIRTUAL_TESTNET_RPC_URL}" \
      --private-key="${TENDERLY_DEPLOYER_PRIVATE_KEY}" \
      --verify \
      --verifier-url="${VERIFIER_URL}" \
      --etherscan-api-key="${TENDERLY_ACCESS_KEY}" \
      --broadcast \
      --slow
  else
    forge script "$script_name" \
      --rpc-url="${TENDERLY_VIRTUAL_TESTNET_RPC_URL}"
  fi
}

echo "=== Tenderly Deployment Setup ==="
echo "Account: ${TENDERLY_ACCOUNT}"
echo "Project: ${TENDERLY_PROJECT}"
echo "Testnet ID: ${TESTNET_ID}"
echo "RPC URL: ${TENDERLY_VIRTUAL_TESTNET_RPC_URL}"
echo ""

# Fund the deployer account
fund_account "${TENDERLY_DEPLOYER_PRIVATE_KEY}"

# Step 1: Compute deterministic addresses (no deployment, just computation)
echo "Step 1: Computing deterministic addresses..."
run_script script/ComputeDeterministicAddresses.s.sol false

# Step 2: Deploy TrustedMsgSenderProviderLookup
echo ""
echo "Step 2: Deploying TrustedMsgSenderProviderLookup..."
run_script script/DeployTrustedMsgSenderLookup.s.sol true

# Step 3: Deploy Limit Order Book contracts
echo ""
echo "Step 3: Deploying Limit Order Book contracts..."
run_script script/DeployLimitOrders.s.sol true

# Step 4: Upgrade Coin Implementation
echo ""
echo "Step 4: Upgrading coin implementation..."
run_script script/UpgradeCoinImpl.sol true

# Step 5: Print upgrade command
echo ""
echo "Step 5: Printing upgrade command..."
run_script script/PrintUpgradeCommand.s.sol false

echo ""
echo "=== Deployment Complete ==="
