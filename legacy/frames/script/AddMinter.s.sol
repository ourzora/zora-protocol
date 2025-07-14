// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Script} from "forge-std/Script.sol";
import {console2} from "forge-std/console2.sol";

import {IZoraCreator1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155.sol";
import {BoostedMinterImpl} from "../src/BoostedMinterImpl.sol";
import {BoostedMinterFactory} from "../src/BoostedMinterFactory.sol";

contract AddMinter is Script {
    uint256 public constant PERMISSION_BIT_MINTER = 4;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address tokenContract = vm.envAddress("TOKEN_CONTRACT");
        uint256 tokenId = vm.envUint("TOKEN_ID");
        address boostedMinter = vm.envAddress("BOOSTED_MINTER");

        IZoraCreator1155 token = IZoraCreator1155(tokenContract);

        vm.broadcast(deployerPrivateKey);
        token.addPermission(tokenId, boostedMinter, PERMISSION_BIT_MINTER);
    }
}
