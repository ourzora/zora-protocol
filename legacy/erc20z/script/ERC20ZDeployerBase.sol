// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

contract ERC20ZDeployerBase is Script {
    using stdJson for string;

    struct ERC20zContractAddresses {
        address swapHelper;
        address erc20z;
        address nonfungiblePositionManager;
        address royalties;
        address saleStrategy;
        address saleStrategyImpl;
        string saleStrategyImplVersion;
        address weth;
    }

    function configPath() private returns (string memory) {
        return string.concat("./addresses/", vm.toString(block.chainid), ".json");
    }

    function saveDeployment(ERC20zContractAddresses memory addresses) internal {
        string memory objectKey = "config";

        vm.serializeAddress(objectKey, "SALE_STRATEGY", addresses.saleStrategy);
        vm.serializeAddress(objectKey, "SALE_STRATEGY_IMPL", addresses.saleStrategyImpl);
        vm.serializeString(objectKey, "SALE_STRATEGY_IMPL_VERSION", addresses.saleStrategyImplVersion);
        vm.serializeAddress(objectKey, "ERC20Z", addresses.erc20z);
        vm.serializeAddress(objectKey, "ROYALTIES", addresses.royalties);
        vm.serializeAddress(objectKey, "NONFUNGIBLE_POSITION_MANAGER", addresses.nonfungiblePositionManager);
        string memory result = vm.serializeAddress(objectKey, "WETH", addresses.weth);

        vm.writeJson(result, configPath());
    }

    function loadDeployment() internal returns (ERC20zContractAddresses memory addresses) {
        string memory json = vm.readFile(configPath());

        addresses.swapHelper = vm.parseJsonAddress(json, ".SWAP_HELPER");
        addresses.erc20z = vm.parseJsonAddress(json, ".ERC20Z");
        addresses.nonfungiblePositionManager = vm.parseJsonAddress(json, ".NONFUNGIBLE_POSITION_MANAGER");
        addresses.royalties = vm.parseJsonAddress(json, ".ROYALTIES");
        addresses.saleStrategy = vm.parseJsonAddress(json, ".SALE_STRATEGY");
        addresses.saleStrategyImpl = vm.parseJsonAddress(json, ".SALE_STRATEGY_IMPL");
        addresses.saleStrategyImplVersion = vm.parseJsonString(json, ".SALE_STRATEGY_IMPL_VERSION");
        addresses.weth = vm.parseJsonAddress(json, ".WETH");
    }
}
