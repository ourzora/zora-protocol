# Zora Protocol Deployments

Contains deployed abis and addresses for the Zora Protocol, in an easy to consume format compatible
with viem.sh and ethers.js.

## Usage

Import abis and addresses for a contract from the package:

```typescript
import { zoraCreator1155FactoryImplConfig } from "@zoralabs/protocol-deployments";
```

## :wrench: Constants

- [iImmutableCreate2FactoryABI](#gear-iimmutablecreate2factoryabi)
- [iImmutableCreate2FactoryAddress](#gear-iimmutablecreate2factoryaddress)
- [iImmutableCreate2FactoryConfig](#gear-iimmutablecreate2factoryconfig)
- [zoraCreator1155FactoryImplABI](#gear-zoracreator1155factoryimplabi)
- [zoraCreator1155FactoryImplAddress](#gear-zoracreator1155factoryimpladdress)
- [zoraCreator1155FactoryImplConfig](#gear-zoracreator1155factoryimplconfig)
- [zoraCreator1155ImplABI](#gear-zoracreator1155implabi)
- [zoraCreator1155PremintExecutorImplABI](#gear-zoracreator1155premintexecutorimplabi)
- [zoraCreator1155PremintExecutorImplAddress](#gear-zoracreator1155premintexecutorimpladdress)
- [zoraCreator1155PremintExecutorImplConfig](#gear-zoracreator1155premintexecutorimplconfig)
- [zoraCreatorFixedPriceSaleStrategyABI](#gear-zoracreatorfixedpricesalestrategyabi)
- [zoraCreatorFixedPriceSaleStrategyAddress](#gear-zoracreatorfixedpricesalestrategyaddress)
- [zoraCreatorFixedPriceSaleStrategyConfig](#gear-zoracreatorfixedpricesalestrategyconfig)
- [zoraCreatorMerkleMinterStrategyABI](#gear-zoracreatormerkleminterstrategyabi)
- [zoraCreatorMerkleMinterStrategyAddress](#gear-zoracreatormerkleminterstrategyaddress)
- [zoraCreatorMerkleMinterStrategyConfig](#gear-zoracreatormerkleminterstrategyconfig)
- [zoraCreatorRedeemMinterFactoryABI](#gear-zoracreatorredeemminterfactoryabi)
- [zoraCreatorRedeemMinterFactoryAddress](#gear-zoracreatorredeemminterfactoryaddress)
- [zoraCreatorRedeemMinterFactoryConfig](#gear-zoracreatorredeemminterfactoryconfig)

### :gear: iImmutableCreate2FactoryABI

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)

| Constant | Type |
| ---------- | ---------- |
| `iImmutableCreate2FactoryABI` | `readonly [{ readonly stateMutability: "view"; readonly type: "function"; readonly inputs: readonly [{ readonly name: "salt"; readonly internalType: "bytes32"; readonly type: "bytes32"; }, { readonly name: "initCode"; readonly internalType: "bytes"; readonly type: "bytes"; }]; readonly name: "findCreate2Address"; rea...` |

### :gear: iImmutableCreate2FactoryAddress

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)

| Constant | Type |
| ---------- | ---------- |
| `iImmutableCreate2FactoryAddress` | `{ readonly 1: "0x0000000000FFe8B47B3e2130213B802212439497"; readonly 5: "0x0000000000FFe8B47B3e2130213B802212439497"; readonly 10: "0x0000000000FFe8B47B3e2130213B802212439497"; ... 7 more ...; readonly 11155111: "0x0000000000FFe8B47B3e2130213B802212439497"; }` |

### :gear: iImmutableCreate2FactoryConfig

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x0000000000FFe8B47B3e2130213B802212439497)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x0000000000FFe8B47B3e2130213B802212439497)

| Constant | Type |
| ---------- | ---------- |
| `iImmutableCreate2FactoryConfig` | `{ readonly address: { readonly 1: "0x0000000000FFe8B47B3e2130213B802212439497"; readonly 5: "0x0000000000FFe8B47B3e2130213B802212439497"; readonly 10: "0x0000000000FFe8B47B3e2130213B802212439497"; ... 7 more ...; readonly 11155111: "0x0000000000FFe8B47B3e2130213B802212439497"; }; readonly abi: readonly [...]; }` |

### :gear: zoraCreator1155FactoryImplABI

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x13dAA8E9e3f68deDE7b1386ACdc12eA98F2FB688)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreator1155FactoryImplABI` | `readonly [{ readonly stateMutability: "nonpayable"; readonly type: "constructor"; readonly inputs: readonly [{ readonly name: "_zora1155Impl"; readonly internalType: "contract IZoraCreator1155"; readonly type: "address"; }, { ...; }, { ...; }, { ...; }]; }, ... 46 more ..., { ...; }]` |

### :gear: zoraCreator1155FactoryImplAddress

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x13dAA8E9e3f68deDE7b1386ACdc12eA98F2FB688)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreator1155FactoryImplAddress` | `{ readonly 1: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021"; readonly 5: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021"; readonly 10: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021"; ... 7 more ...; readonly 11155111: "0x13dAA8E9e3f68deDE7b1386ACdc12eA98F2FB688"; }` |

### :gear: zoraCreator1155FactoryImplConfig

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x777777C338d93e2C7adf08D102d45CA7CC4Ed021)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x13dAA8E9e3f68deDE7b1386ACdc12eA98F2FB688)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreator1155FactoryImplConfig` | `{ readonly address: { readonly 1: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021"; readonly 5: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021"; readonly 10: "0x777777C338d93e2C7adf08D102d45CA7CC4Ed021"; ... 7 more ...; readonly 11155111: "0x13dAA8E9e3f68deDE7b1386ACdc12eA98F2FB688"; }; readonly abi: readonly [...]; }` |

### :gear: zoraCreator1155ImplABI

| Constant | Type |
| ---------- | ---------- |
| `zoraCreator1155ImplABI` | `readonly [{ readonly stateMutability: "nonpayable"; readonly type: "constructor"; readonly inputs: readonly [{ readonly name: "_mintFeeRecipient"; readonly internalType: "address"; readonly type: "address"; }, { ...; }, { ...; }]; }, ... 133 more ..., { ...; }]` |

### :gear: zoraCreator1155PremintExecutorImplABI

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreator1155PremintExecutorImplABI` | `readonly [{ readonly stateMutability: "nonpayable"; readonly type: "constructor"; readonly inputs: readonly [{ readonly name: "_factory"; readonly internalType: "contract IZoraCreator1155Factory"; readonly type: "address"; }]; }, ... 58 more ..., { ...; }]` |

### :gear: zoraCreator1155PremintExecutorImplAddress

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreator1155PremintExecutorImplAddress` | `{ readonly 1: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340"; readonly 5: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340"; readonly 10: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340"; ... 4 more ...; readonly 7777777: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340"; }` |

### :gear: zoraCreator1155PremintExecutorImplConfig

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x7777773606e7e46C8Ba8B98C08f5cD218e31d340)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreator1155PremintExecutorImplConfig` | `{ readonly address: { readonly 1: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340"; readonly 5: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340"; readonly 10: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340"; ... 4 more ...; readonly 7777777: "0x7777773606e7e46C8Ba8B98C08f5cD218e31d340"; }; readonly abi: readonly [...]; }` |

### :gear: zoraCreatorFixedPriceSaleStrategyABI

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x3678862f04290E565cCA2EF163BAeb92Bb76790C)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0xA5E8d0d4FCed34E86AF6d4E16131C7210Ba8b4b7)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreatorFixedPriceSaleStrategyABI` | `readonly [{ readonly type: "error"; readonly inputs: readonly []; readonly name: "SaleEnded"; }, { readonly type: "error"; readonly inputs: readonly []; readonly name: "SaleHasNotStarted"; }, { readonly type: "error"; readonly inputs: readonly [...]; readonly name: "UserExceedsMintLimit"; }, ... 11 more ..., { ...; }]` |

### :gear: zoraCreatorFixedPriceSaleStrategyAddress

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x3678862f04290E565cCA2EF163BAeb92Bb76790C)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0xA5E8d0d4FCed34E86AF6d4E16131C7210Ba8b4b7)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreatorFixedPriceSaleStrategyAddress` | `{ readonly 1: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a"; readonly 5: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a"; readonly 10: "0x3678862f04290E565cCA2EF163BAeb92Bb76790C"; ... 7 more ...; readonly 11155111: "0xA5E8d0d4FCed34E86AF6d4E16131C7210Ba8b4b7"; }` |

### :gear: zoraCreatorFixedPriceSaleStrategyConfig

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x3678862f04290E565cCA2EF163BAeb92Bb76790C)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x04E2516A2c207E84a1839755675dfd8eF6302F0a)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0xA5E8d0d4FCed34E86AF6d4E16131C7210Ba8b4b7)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreatorFixedPriceSaleStrategyConfig` | `{ readonly address: { readonly 1: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a"; readonly 5: "0x04E2516A2c207E84a1839755675dfd8eF6302F0a"; readonly 10: "0x3678862f04290E565cCA2EF163BAeb92Bb76790C"; ... 7 more ...; readonly 11155111: "0xA5E8d0d4FCed34E86AF6d4E16131C7210Ba8b4b7"; }; readonly abi: readonly [...]; }` |

### :gear: zoraCreatorMerkleMinterStrategyABI

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x899ce31dF6C6Af81203AcAaD285bF539234eF4b8)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Base Basescan__](https://basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x357D8108A77762B41Ea0C4D69fBb1eF4391251eC)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreatorMerkleMinterStrategyABI` | `readonly [{ readonly type: "error"; readonly inputs: readonly [{ readonly name: "mintTo"; readonly internalType: "address"; readonly type: "address"; }, { readonly name: "merkleProof"; readonly internalType: "bytes32[]"; readonly type: "bytes32[]"; }, { ...; }]; readonly name: "InvalidMerkleProof"; }, ... 15 more .....` |

### :gear: zoraCreatorMerkleMinterStrategyAddress

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x899ce31dF6C6Af81203AcAaD285bF539234eF4b8)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Base Basescan__](https://basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x357D8108A77762B41Ea0C4D69fBb1eF4391251eC)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreatorMerkleMinterStrategyAddress` | `{ readonly 1: "0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7"; readonly 5: "0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7"; readonly 10: "0x899ce31dF6C6Af81203AcAaD285bF539234eF4b8"; ... 7 more ...; readonly 11155111: "0x357D8108A77762B41Ea0C4D69fBb1eF4391251eC"; }` |

### :gear: zoraCreatorMerkleMinterStrategyConfig

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x899ce31dF6C6Af81203AcAaD285bF539234eF4b8)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Base Basescan__](https://basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x357D8108A77762B41Ea0C4D69fBb1eF4391251eC)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreatorMerkleMinterStrategyConfig` | `{ readonly address: { readonly 1: "0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7"; readonly 5: "0xf48172CA3B6068B20eE4917Eb27b5472f1f272C7"; readonly 10: "0x899ce31dF6C6Af81203AcAaD285bF539234eF4b8"; ... 7 more ...; readonly 11155111: "0x357D8108A77762B41Ea0C4D69fBb1eF4391251eC"; }; readonly abi: readonly [...]; }` |

### :gear: zoraCreatorRedeemMinterFactoryABI

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x1B28A04b7eB7b93f920ddF2021aa3fAE065395f2)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x66e7bE0b5A7dD9eb7999AAbE7AbdFa40381b6d5E)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreatorRedeemMinterFactoryABI` | `readonly [{ readonly stateMutability: "nonpayable"; readonly type: "constructor"; readonly inputs: readonly []; }, { readonly type: "error"; readonly inputs: readonly []; readonly name: "CallerNotZoraCreator1155"; }, ... 13 more ..., { ...; }]` |

### :gear: zoraCreatorRedeemMinterFactoryAddress

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x1B28A04b7eB7b93f920ddF2021aa3fAE065395f2)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x66e7bE0b5A7dD9eb7999AAbE7AbdFa40381b6d5E)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreatorRedeemMinterFactoryAddress` | `{ readonly 1: "0x78964965cF77850224513a367f899435C5B69174"; readonly 5: "0x78964965cF77850224513a367f899435C5B69174"; readonly 10: "0x1B28A04b7eB7b93f920ddF2021aa3fAE065395f2"; ... 7 more ...; readonly 11155111: "0x66e7bE0b5A7dD9eb7999AAbE7AbdFa40381b6d5E"; }` |

### :gear: zoraCreatorRedeemMinterFactoryConfig

- [__View Contract on Ethereum Etherscan__](https://etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Goerli Etherscan__](https://goerli.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Op Mainnet Optimism Explorer__](https://explorer.optimism.io/address/0x1B28A04b7eB7b93f920ddF2021aa3fAE065395f2)
- [__View Contract on Optimism Goerli Etherscan__](https://goerli-optimism.etherscan.io/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Zora Goerli Testnet Explorer__](https://testnet.explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Base Basescan__](https://basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Base Goerli Basescan__](https://goerli.basescan.org/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Zora Explorer__](https://explorer.zora.energy/address/0x78964965cF77850224513a367f899435C5B69174)
- [__View Contract on Sepolia Etherscan__](https://sepolia.etherscan.io/address/0x66e7bE0b5A7dD9eb7999AAbE7AbdFa40381b6d5E)

| Constant | Type |
| ---------- | ---------- |
| `zoraCreatorRedeemMinterFactoryConfig` | `{ readonly address: { readonly 1: "0x78964965cF77850224513a367f899435C5B69174"; readonly 5: "0x78964965cF77850224513a367f899435C5B69174"; readonly 10: "0x1B28A04b7eB7b93f920ddF2021aa3fAE065395f2"; ... 7 more ...; readonly 11155111: "0x66e7bE0b5A7dD9eb7999AAbE7AbdFa40381b6d5E"; }; readonly abi: readonly [...]; }` |


