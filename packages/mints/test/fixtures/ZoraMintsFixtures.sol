// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";

import {ZoraMints1155} from "../../src/ZoraMints1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ReceiveRejector} from "@zoralabs/shared-contracts/mocks/ReceiveRejector.sol";
import {MockPreminter} from "../mocks/MockPreminter.sol";
import {ContractCreationConfig, PremintConfigV2, TokenCreationConfigV2, MintArguments} from "@zoralabs/shared-contracts/entities/Premint.sol";
import {PremintEncoding, EncodedPremintConfig} from "@zoralabs/shared-contracts/premint/PremintEncoding.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IZoraMints1155} from "../../src/interfaces/IZoraMints1155.sol";
import {IZoraMintsMinterManager} from "../../src/interfaces/IZoraMintsMinterManager.sol";
import {ZoraMintsManagerImpl} from "../../src/ZoraMintsManagerImpl.sol";
import {ZoraMintsManager} from "../../src/ZoraMintsManager.sol";
import {ProxyShim} from "../../src/utils/ProxyShim.sol";

interface IUpgradeableProxy {
    function upgradeTo(address newImplementation) external;

    function initialize(address newOwner) external;
}

library ZoraMintsFixtures {
    function setupMintsProxyWithMockPreminter(
        address proxyAdmin,
        address initialOwner,
        uint256 initialEthTokenId,
        uint256 initialEthTokenPrice
    ) internal returns (MockPreminter mockPreminter, ZoraMints1155 mints, ZoraMintsManagerImpl mintsManager) {
        mockPreminter = new MockPreminter();

        ZoraMintsManagerImpl mintsManagerImpl = new ZoraMintsManagerImpl(mockPreminter);

        ZoraMintsManager proxy = new ZoraMintsManager(address(mintsManagerImpl));

        mockPreminter.initialize(IZoraMintsMinterManager(address(proxy)));

        mintsManager = ZoraMintsManagerImpl(address(proxy));

        bytes32 zoraMintsSalt;

        bytes memory zoraMintsImplCreationCode = abi.encodePacked(type(ZoraMints1155).creationCode, abi.encode(address(mockPreminter)));

        mints = ZoraMints1155(
            address(mintsManager.initialize(initialOwner, zoraMintsSalt, zoraMintsImplCreationCode, initialEthTokenId, initialEthTokenPrice, "", ""))
        );
    }
}
