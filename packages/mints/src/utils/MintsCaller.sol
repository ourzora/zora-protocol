// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IMintWithMints} from "../IMintWithMints.sol";
import {IMinter1155} from "@zoralabs/shared-contracts/interfaces/IMinter1155.sol";
import {MintArguments} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {ICollectWithZoraMints} from "../ICollectWithZoraMints.sol";
import {IZoraMints1155Managed} from "../interfaces/IZoraMints1155Managed.sol";

library MintsCaller {
    function makeCollectCall(
        IMintWithMints zoraCreator1155Contract,
        IMinter1155 minter,
        uint256 zoraCreator1155TokenId,
        address[] memory mintRewardsRecipients,
        address mintRecipient,
        string memory mintComment
    ) internal pure returns (bytes memory) {
        ICollectWithZoraMints.CollectMintArguments memory mintArguments = ICollectWithZoraMints.CollectMintArguments({
            mintRewardsRecipients: mintRewardsRecipients,
            mintComment: mintComment,
            minterArguments: abi.encode(mintRecipient, "")
        });

        return abi.encodeWithSelector(ICollectWithZoraMints.collect.selector, zoraCreator1155Contract, minter, zoraCreator1155TokenId, mintArguments);
    }

    function collect(
        IZoraMints1155Managed mints,
        uint256 value,
        uint256[] memory tokenIds,
        uint256[] memory quantities,
        IMintWithMints zoraCreator1155Contract,
        IMinter1155 minter,
        uint256 zoraCreator1155TokenId,
        address[] memory mintRewardsRecipients,
        address mintRecipient,
        string memory mintComment
    ) internal {
        bytes memory call = makeCollectCall(zoraCreator1155Contract, minter, zoraCreator1155TokenId, mintRewardsRecipients, mintRecipient, mintComment);
        mints.transferBatchToManagerAndCall{value: value}(tokenIds, quantities, call);
    }
}
