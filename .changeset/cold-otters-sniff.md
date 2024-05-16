---
"@zoralabs/zora-1155-contracts": minor
---

`ERC20PremintConfig` replaced by a more general purpose `PremintConfigV3`, which instead of having erc20 premint specific properties, as an abi encoded `premintSalesConfig`, that is passed to the function `setPremintSale` on the corresponding minter contract.

The new `TokenCreationConfigV3` looks like:

```solidity
struct TokenCreationConfigV3 {
  // Metadata URI for the created token
  string tokenURI;
  // Max supply of the created token
  uint256 maxSupply;
  // RoyaltyBPS for created tokens. The royalty amount in basis points for secondary sales.
  uint32 royaltyBPS;
  // The address that the will receive rewards/funds/royalties.
  address payoutRecipient;
  // The address that referred the creation of the token.
  address createReferral;
  // The start time of the mint, 0 for immediate.
  uint64 mintStart;
  // The address of the minter module.
  address minter;
  // The abi encoded data to be passed to the minter to setup the sales config for the premint.
  bytes premintSalesConfig;
}
```

where the `premintSalesConfig` is an abi encoded struct that is passed to the minter's function `setPremintSale`:

```solidity
ERC20Minter.PremintSalesConfig memory premintSalesConfig = ERC20Minter.PremintSalesConfig({
            currency: address(mockErc20),
            pricePerToken: 1e18,
            maxTokensPerAddress: 5000,
            duration: 1000,
            payoutRecipient: collector
        });


// this would be set as the property `premintSalesConfig` in the `TokenCreationConfigV3`
bytes memory encodedPremintSalesConfig = abi.encode(premintSalesConfig);
```

Correspondingly, new minters must implement the new interface `ISetPremintSale` to be compatible with the new `TokenCreationConfigV3`:

```solidity
interface ISetPremintSale {
  function setPremintSale(uint256 tokenId, bytes calldata salesConfig) external;
}

// example implementation:
contract ERC20Minter is ISetPremintSale {
  struct PremintSalesConfig {
    address currency;
    uint256 pricePerToken;
    uint64 maxTokensPerAddress;
    uint64 duration;
    address payoutRecipient;
  }

  function buildSalesConfigForPremint(
    PremintSalesConfig memory config
  ) public view returns (ERC20Minter.SalesConfig memory) {
    uint64 saleStart = uint64(block.timestamp);
    uint64 saleEnd = config.duration == 0
      ? type(uint64).max
      : saleStart + config.duration;

    return
      IERC20Minter.SalesConfig({
        saleStart: saleStart,
        saleEnd: saleEnd,
        maxTokensPerAddress: config.maxTokensPerAddress,
        pricePerToken: config.pricePerToken,
        fundsRecipient: config.payoutRecipient,
        currency: config.currency
      });
  }

  function toSaleConfig(
    bytes calldata encodedPremintSalesConfig
  ) private returns (IERC20Minter.SalesConfig memory) {
    PremintSalesConfig memory premintSalesConfig = abi.decode(
      encodedPremintSalesConfig,
      (PremintSalesConfig)
    );

    return buildSalesConfigForPremint(premintSalesConfig);
  }

  mapping(address => mapping(uint256 => IERC20Minter.SalesConfig)) public sale;

  function setPremintSale(
    uint256 tokenId,
    bytes calldata premintSalesConfig
  ) external override {
    IERC20Minter.SalesConfig memory salesConfig = toSaleConfig(
      premintSalesConfig
    );

    sale[msg.sender][tokenId] = salesConfig;
  }
}
```
