// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../BaseTest.sol";

contract Handler {
    ZoraTimedSaleStrategyImpl internal immutable saleStrategy;
    address internal immutable collection;
    uint256 internal immutable tokenId;

    constructor(ZoraTimedSaleStrategyImpl _saleStrategy, address _collection, uint256 _tokenId) {
        saleStrategy = _saleStrategy;
        collection = _collection;
        tokenId = _tokenId;
    }

    function launchMarket() public {
        if (saleStrategy.sale(collection, tokenId).secondaryActivated) {
            return;
        }

        saleStrategy.launchMarket(collection, tokenId);
    }
}
