// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMinter1155} from "../../interfaces/IMinter1155.sol";
import {TransferHelperUtils} from "../../utils/TransferHelperUtils.sol";

contract ZoraCreatorFixedPriceSaleStrategy is IMinter1155 {
    struct SalesConfig {
        uint256 pricePerToken;
        uint64 saleStart;
        uint64 saleEnd;
        uint64 maxTokensPerTransaction;
        uint64 maxTokensPerAddress;
    }
    mapping(uint256 => SalesConfig) internal salesConfigs;
    mapping(uint256 => uint256) internal mintedPerAddress;

    function _getKey(address mediaContract, uint256 tokenId)
        internal
        pure
        returns (uint256)
    {
        return uint256(keccak256(abi.encode(mediaContract, tokenId)));
    }

    error WrongValueSent();
    error SaleEnded();
    error SaleHasNotStarted();

    function requestMint(
        address sender,
        uint256 tokenId,
        uint256 quantity,
        uint256 ethValueSent,
        bytes calldata minterArguments
    ) external {
        SalesConfig memory config = salesConfigs[_getKey(msg.sender, tokenId)];
        if (config.pricePerToken * quantity != ethValueSent) {
            revert WrongValueSent();
        }
        if (config.saleEnd > block.timestamp) {
            revert SaleEnded();
        }
        if (config.saleStart < block.timestamp) {
            revert SaleHasNotStarted();
        }

        // mint command
    }

    function setupSale(
        address mediaContract,
        uint256 tokenId,
        SalesConfig memory salesConfig
    ) external {
        salesConfigs[_getKey(mediaContract, tokenId)] = salesConfig;
        // emit event
    }

    function resetSale() external {}
}
