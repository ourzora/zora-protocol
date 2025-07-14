// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {ZoraSparks1155} from "../../src/ZoraSparks1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReceiveRejector} from "@zoralabs/shared-contracts/mocks/ReceiveRejector.sol";
import {ContractCreationConfig, PremintConfigV2, TokenCreationConfigV2, MintArguments} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IZoraSparks1155} from "../../src/interfaces/IZoraSparks1155.sol";
import {IZoraSparksMinterManager} from "../../src/interfaces/IZoraSparksMinterManager.sol";
import {ZoraSparksManagerImpl} from "../../src/ZoraSparksManagerImpl.sol";
import {ZoraSparksManager} from "../../src/ZoraSparksManager.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";

interface IUpgradeableProxy {
    function upgradeTo(address newImplementation) external;

    function initialize(address newOwner) external;
}

library ZoraSparksFixtures {
    function setupSparksProxyWithMockPreminter(
        address,
        address initialOwner,
        uint256 initialEthTokenId,
        uint256 initialEthTokenPrice
    ) internal returns (ZoraSparks1155 sparks, ZoraSparksManagerImpl sparksManager) {
        ZoraSparksManagerImpl sparksManagerImpl = new ZoraSparksManagerImpl();

        ZoraSparksManager proxy = new ZoraSparksManager(address(sparksManagerImpl));

        sparksManager = ZoraSparksManagerImpl(address(proxy));

        bytes32 zoraSparksSalt;

        bytes memory zoraSparksImplCreationCode = type(ZoraSparks1155).creationCode;

        sparks = ZoraSparks1155(
            address(sparksManager.initialize(initialOwner, zoraSparksSalt, zoraSparksImplCreationCode, initialEthTokenId, initialEthTokenPrice, "", ""))
        );
    }
}
