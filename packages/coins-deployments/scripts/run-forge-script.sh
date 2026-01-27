#!/bin/bash

# Secure forge script runner that reads PRIVATE_KEY from .env
# Usage: ./scripts/run-forge-script.sh <script_name> <chain> [flags]
#
# Flags:
#   --deploy    Broadcast and verify the deployment
#   --resume    Resume a previous deployment and reverify
#   --dev       Use development mode (DEV=true)
#   --ffi       Enable FFI (foreign function interface) for external commands
#
# Examples:
#   ./scripts/run-forge-script.sh DeployLimitOrders.s.sol base              # Dry run
#   ./scripts/run-forge-script.sh DeployLimitOrders.s.sol base --deploy     # Deploy and verify
#   ./scripts/run-forge-script.sh DeployLimitOrders.s.sol base --resume     # Resume and reverify
#   ./scripts/run-forge-script.sh DeployLimitOrders.s.sol base --deploy --dev  # Dev deployment
#   ./scripts/run-forge-script.sh GenerateDeterministicParams.s.sol base --ffi  # With FFI enabled

set -e

# Check if script name and chain are provided
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "Usage: $0 <script_name> <chain> [flags]"
    echo ""
    echo "Flags:"
    echo "  --deploy    Broadcast and verify the deployment"
    echo "  --resume    Resume a previous deployment and reverify"
    echo "  --dev       Use development mode (DEV=true)"
    echo "  --ffi       Enable FFI (foreign function interface) for external commands"
    echo ""
    echo "Examples:"
    echo "  $0 DeployLimitOrders.s.sol base              # Dry run"
    echo "  $0 DeployLimitOrders.s.sol base --deploy     # Deploy and verify"
    echo "  $0 DeployLimitOrders.s.sol base --resume     # Resume and reverify"
    echo "  $0 DeployLimitOrders.s.sol base --deploy --dev  # Dev deployment"
    echo "  $0 GenerateDeterministicParams.s.sol base --ffi  # With FFI enabled"
    exit 1
fi

SCRIPT_NAME=$1
CHAIN=$2
shift 2

# Parse flags
DEPLOY_MODE=""
DEV_MODE=""
FFI_FLAG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --deploy)
            DEPLOY_MODE="--broadcast --verify"
            shift
            ;;
        --resume)
            DEPLOY_MODE="--broadcast --resume --verify"
            shift
            ;;
        --dev)
            DEV_MODE="true"
            shift
            ;;
        --ffi)
            FFI_FLAG="--ffi"
            shift
            ;;
        *)
            echo "Unknown flag: $1"
            exit 1
            ;;
    esac
done

# Check if .env exists
if [ ! -f .env ]; then
    echo "Error: .env file not found"
    echo "Copy .env.example to .env and fill in your PRIVATE_KEY"
    exit 1
fi

# Source .env to load PRIVATE_KEY into environment
set -a
source .env
set +a

# Check if PRIVATE_KEY is set
if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not found in .env"
    exit 1
fi

# Set DEV environment variable if --dev flag was passed
if [ -n "$DEV_MODE" ]; then
    export DEV="$DEV_MODE"
fi

# Run forge script with chains command and private key from environment
echo "Running forge script: $SCRIPT_NAME on chain: $CHAIN"
if [ -n "$DEV_MODE" ]; then
    echo "Mode: Development (DEV=true)"
else
    echo "Mode: Production"
fi
if [ -z "$DEPLOY_MODE" ]; then
    echo "Action: Dry run (no broadcast)"
else
    echo "Action: $DEPLOY_MODE"
fi
echo ""

forge script "script/$SCRIPT_NAME" \
    $(chains "$CHAIN" --deploy) \
    --private-key="$PRIVATE_KEY" \
    $DEPLOY_MODE \
    $FFI_FLAG
