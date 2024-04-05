// spdx-license-identifier: MIT
pragma solidity ^0.8.17;

import {ProxyDeployerConfig} from "./Config.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {DeterministicUUPSProxyDeployer} from "./DeterministicUUPSProxyDeployer.sol";
import {ZoraMintsManager} from "@zoralabs/mints-contracts/src/ZoraMintsManager.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ZoraMints1155} from "@zoralabs/mints-contracts/src/ZoraMints1155.sol";
import {ZoraMintsManagerImpl} from "@zoralabs/mints-contracts/src/ZoraMintsManagerImpl.sol";

library ProxyDeployerUtils {
    function createOrGetProxyDeployer(ProxyDeployerConfig memory config) internal returns (DeterministicUUPSProxyDeployer) {
        return DeterministicUUPSProxyDeployer(ImmutableCreate2FactoryUtils.safeCreate2OrGetExisting(config.salt, config.creationCode));
    }

    function mints1155CreationCode() internal pure returns (bytes memory) {
        return type(ZoraMints1155).creationCode;
    }

    function mintsManagerInitializeCall(
        address initialMintsOwner,
        bytes memory _mints1155CreationCode,
        bytes32 mints1155Salt,
        uint256 initialEthTokenId,
        uint256 initialEthPrice
    ) internal pure returns (bytes memory) {
        return
            abi.encodeWithSelector(
                ZoraMintsManagerImpl.initialize.selector,
                initialMintsOwner,
                mints1155Salt,
                _mints1155CreationCode,
                initialEthTokenId,
                initialEthPrice
            );
    }
}
