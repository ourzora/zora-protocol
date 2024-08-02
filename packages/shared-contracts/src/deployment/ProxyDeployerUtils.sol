// spdx-license-identifier: MIT
pragma solidity ^0.8.20;

import {ProxyDeployerConfig} from "./Config.sol";
import {ImmutableCreate2FactoryUtils} from "../utils/ImmutableCreate2FactoryUtils.sol";
import {DeterministicUUPSProxyDeployer} from "./DeterministicUUPSProxyDeployer.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

// import {ZoraSparks1155} from "@zoralabs/sparks-contracts/src/ZoraSparks1155.sol";
// import {ZoraSparksManagerImpl} from "@zoralabs/sparks-contracts/src/ZoraSparksManagerImpl.sol";

library ProxyDeployerUtils {
    function createOrGetProxyDeployer(ProxyDeployerConfig memory config) internal returns (address) {
        // return DeterministicUUPSProxyDeployer(config.deployedAddress);
        return ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(config.salt, config.creationCode);
    }

    // function sparks1155CreationCode() internal pure returns (bytes memory) {
    //     return type(ZoraSparks1155).creationCode;
    // }

    // function sparksManagerInitializeCall(
    //     address initialSparksOwner,
    //     bytes memory _sparks1155CreationCode,
    //     bytes32 sparks1155Salt,
    //     uint256 initialEthTokenId,
    //     uint256 initialEthPrice
    // ) internal pure returns (bytes memory) {
    //     return
    //         abi.encodeWithSelector(
    //             ZoraSparksManagerImpl.initialize.selector,
    //             initialSparksOwner,
    //             sparks1155Salt,
    //             _sparks1155CreationCode,
    //             initialEthTokenId,
    //             initialEthPrice,
    //             "https://zora.co/assets/sparks/metadata/",
    //             "https://zora.co/assets/sparks/metadata/"
    //         );
    // }
}
