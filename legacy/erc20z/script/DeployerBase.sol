// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ProxyDeployerScript} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";

contract DeployerBase is ProxyDeployerScript {
    address internal constant PROTOCOL_REWARDS = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;
    address internal constant COMMENTS = 0x7777777bE14a1F7Fd6896B5FBDa5ceD5FC6e501a;

    struct DeploymentConfig {
        address saleStrategy;
        address saleStrategyImpl;
        string saleStrategyImplVersion;
        address erc20z;
        address royalties;
        address nonfungiblePositionManager;
        address weth;
        address swapHelper;
    }

    function addressesFile() internal view returns (string memory) {
        return string.concat("./addresses/", vm.toString(block.chainid), ".json");
    }

    function saveDeployment(DeploymentConfig memory config) internal {
        string memory objectKey = "config";

        vm.serializeAddress(objectKey, "SALE_STRATEGY", config.saleStrategy);
        vm.serializeAddress(objectKey, "SALE_STRATEGY_IMPL", config.saleStrategyImpl);
        vm.serializeString(objectKey, "SALE_STRATEGY_IMPL_VERSION", config.saleStrategyImplVersion);
        vm.serializeAddress(objectKey, "ERC20Z", config.erc20z);
        vm.serializeAddress(objectKey, "ROYALTIES", config.royalties);
        vm.serializeAddress(objectKey, "NONFUNGIBLE_POSITION_MANAGER", config.nonfungiblePositionManager);
        vm.serializeAddress(objectKey, "SWAP_HELPER", config.swapHelper);

        string memory result = vm.serializeAddress(objectKey, "WETH", config.weth);

        vm.writeJson(result, addressesFile());
    }

    function readDeployment() internal view returns (DeploymentConfig memory) {
        string memory json = vm.readFile(addressesFile());

        return
            DeploymentConfig({
                saleStrategy: readAddressOrDefaultToZero(json, "SALE_STRATEGY"),
                saleStrategyImpl: readAddressOrDefaultToZero(json, "SALE_STRATEGY_IMPL"),
                saleStrategyImplVersion: readStringOrDefaultToEmpty(json, "SALE_STRATEGY_IMPL_VERSION"),
                erc20z: readAddressOrDefaultToZero(json, "ERC20Z"),
                royalties: readAddressOrDefaultToZero(json, "ROYALTIES"),
                nonfungiblePositionManager: readAddressOrDefaultToZero(json, "NONFUNGIBLE_POSITION_MANAGER"),
                weth: readAddressOrDefaultToZero(json, "WETH"),
                swapHelper: readAddressOrDefaultToZero(json, "SWAP_HELPER")
            });
    }
}
