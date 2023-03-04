// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import {ICreatorCommands} from "../interfaces/ICreatorCommands.sol";

library SaleCommandHelper {
    function setSize(ICreatorCommands.CommandSet memory commandSet, uint256 size) internal pure {
        commandSet.commands = new ICreatorCommands.Command[](size);
    }

    /// todo: should tokenid be removed
    function mint(ICreatorCommands.CommandSet memory commandSet, address to, uint256 tokenId, uint256 quantity) internal pure {
        unchecked {
            commandSet.commands[commandSet.at++] = ICreatorCommands.Command({
                method: ICreatorCommands.CreatorActions.MINT,
                args: abi.encode(to, tokenId, quantity)
            });
        }
    }

    function transfer(ICreatorCommands.CommandSet memory commandSet, address to, uint256 amount) internal pure {
        unchecked {
            commandSet.commands[commandSet.at++] = ICreatorCommands.Command({method: ICreatorCommands.CreatorActions.SEND_ETH, args: abi.encode(to, amount)});
        }
    }
}
