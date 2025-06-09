---
id: rewards
title: Protocol Rewards
---
import { Callout } from 'vocs/components'

# Protocol Rewards

## Introduction

At Zora, we are passionate about providing the best experience to create and earn onchain.
**Protocol Rewards** is a split of the Zora fee allowing:

- Creators to monetize their work
- Developers to earn from facilitating coin creation and trading

[Rewards escrow contract code](https://github.com/ourzora/zora-protocol/tree/main/packages/protocol-rewards)

## Address

Rewards v1.1 is deployed at the same address on all networks.

0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B

## Coin Trading Rewards (V4)

Coin trading rewards are distributed to the creator, create referral, trade referral, protocol, and doppler.

<Callout type="success">
All coins created on the Zora app including web and mobile after June 6th 2025 use the V4 configuration.
</Callout>

The latest V4 coins use a UniswapV4 hook to collect fees, swap to a backing currency, and distribute rewards to recipients on every swap.

### V4 Reward Distribution

| Recipient       | Percentage |
| --------------- | ---------- |
| Creator         | 50% |
| Create Referral | 15% |
| Trade Referral  | 15% |
| Protocol        | 15% |
| Doppler         | 5% |

### Key V4 Features

- **Multi-Hop Reward Swapping**: Automatically converts rewards through intermediate tokens to reach the final payout currency, which is ZORA.
- **Unified Currency Distribution**: All recipients receive rewards in the same target currency (e.g., ZORA)

## V3 Rewards Distribution (Legacy)

<Callout type="warning">
To ensure compatibility, we recommend integrating the V4 configuration into your clients.
</Callout>

V3 coins use the original reward distribution system with separate currency and coin rewards.

### V3 Reward Distribution

| Recipient       | Percentage |
| --------------- | ---------- |
| Creator         | 50% |
| Create Referral | 15% |
| Trade Referral  | 15% |
| Protocol        | 15% |
| Doppler         | 5% |

Note: V3 rewards are distributed in both the coin and its backing currency separately.

## Coin Rewards Terminology

**Trade Referral**: The platform or address that referred a specific trade/swap of a coin. In V4, this is passed through hook data and can trigger referral rewards.

**Create Referral**: The platform that referred the creator to deploy the coin. This is set at coin creation time and earns a percentage of all trading fees.

**Creator/Payout Recipient**: The address designated to receive creator rewards from trading activity. This can be updated by coin owners.

**Protocol**: The Zora protocol treasury that receives a portion of trading fees.

**Doppler**: The Doppler protocol treasury that receives a portion of trading fees.

## How It Works: Creator

1. Creator selects coin creation parameters including payout recipient
2. Creator specifies a wallet address eligible to claim their rewards
3. Creator launches their coin -- **that's it!**

The creator's total rewards are automatically distributed with each trade:
- **V4**: Converted to target currency and sent directly to payout recipient
- **V3**: Accumulated in escrow and can be withdrawn at any time

## How It Works: Developer

### Create Referral Reward

The Create Referral Reward is paid out to the developer or platform that referred the creator to deploy their coin using Zora's contracts.

#### Creating a Coin with Rewards

The `createReferral` address is specified upon coin creation through the factory's deploy function.

```solidity
function deploy(
    address payoutRecipient,
    address[] memory owners,
    string memory uri,
    string memory name,
    string memory symbol,
    bytes memory poolConfig,
    address platformReferrer, // This is the create referral
    uint256 orderSize,
    string memory message,
    bytes32 salt
) external payable returns (address, uint256);
```

### Trade Referral Reward

The Trade Referral Reward is paid out to the platform that referred a specific trade.

#### V4 Trading with Referrals

For V4 coins, trade referrals are passed through the hook data when executing swaps via the Universal Router or other compatible interfaces.

#### V3 Trading with Referrals

For V3 coins, trade referrals are specified in the buy/sell functions:

```solidity
function buy(
    address recipient,
    uint256 orderSize,
    uint256 minAmountOut,
    uint160 sqrtPriceLimitX96,
    address tradeReferrer
) external payable returns (uint256, uint256);
```

## Withdrawing Rewards

### V4 Coins
Rewards are automatically distributed on each trade - no withdrawal needed!

### V3 Coins and NFT Rewards
Rewards must be withdrawn from the escrow contract, which address can be found [in the readme](https://github.com/ourzora/zora-protocol/tree/main/packages/protocol-rewards).

```solidity
function withdraw(address to, uint256 amount) external;
```

Withdraw for another address directly.

```solidity
function withdrawFor(address to, uint256 amount) external;
```

```solidity
function withdrawWithSig(
    address from, 
    address to,
    uint256 amount, 
    uint256 deadline, 
    uint8 v, 
    bytes32 r, 
    bytes32 s
)
```
