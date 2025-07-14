// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {IMinter1155} from "../../src/interfaces/IMinter1155.sol";
import {IERC165Upgradeable} from "@zoralabs/openzeppelin-contracts-upgradeable/contracts/interfaces/IERC165Upgradeable.sol";
import {IZoraCreator1155} from "../../src/interfaces/IZoraCreator1155.sol";
import {ICreatorCommands} from "../../src/interfaces/ICreatorCommands.sol";
import {SaleCommandHelper} from "../../src/minters/utils/SaleCommandHelper.sol";

contract SimpleMinter is IMinter1155 {
    using SaleCommandHelper for ICreatorCommands.CommandSet;
    bool receiveETH;
    uint256 public num;

    function setReceiveETH(bool _receiveETH) external {
        receiveETH = _receiveETH;
    }

    function requestMint(
        address,
        uint256 tokenId,
        uint256 quantity,
        uint256,
        bytes calldata minterArguments
    ) external pure returns (ICreatorCommands.CommandSet memory commands) {
        address recipient = abi.decode(minterArguments, (address));
        commands.setSize(1);
        commands.mint(recipient, tokenId, quantity);
    }

    function setNum(uint256 _num) external {
        if (_num == 0) {
            revert();
        }
        num = _num;
    }

    receive() external payable {
        require(receiveETH, "SimpleMinter: not accepting ETH");
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == type(IMinter1155).interfaceId || interfaceId == type(IERC165Upgradeable).interfaceId;
    }

    function settleMint(address collection, uint256 tokenId, uint256 newMaxSupply) external {
        IZoraCreator1155(collection).reduceSupply(tokenId, newMaxSupply);
    }
}
