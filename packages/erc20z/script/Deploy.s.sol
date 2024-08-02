// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IProtocolRewards} from "@zoralabs/protocol-rewards/src/interfaces/IProtocolRewards.sol";
import {IWETH} from "../src/interfaces/IWETH.sol";
import {INonfungiblePositionManager} from "../src/interfaces/uniswap/INonfungiblePositionManager.sol";
import {IZoraTimedSaleStrategy} from "../src/interfaces/IZoraTimedSaleStrategy.sol";

import {ERC20Z} from "../src/ERC20Z.sol";
import {ZoraTimedSaleStrategyImpl} from "../src/minter/ZoraTimedSaleStrategyImpl.sol";
import {ZoraTimedSaleStrategy} from "../src/minter/ZoraTimedSaleStrategy.sol";
import {Royalties} from "../src/royalties/Royalties.sol";
import {ProxyDeployerScript, DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {ProxyShim} from "@zoralabs/shared-contracts/deployment/DeterministicDeployerAndCaller.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ImmutableCreate2FactoryUtils} from "@zoralabs/shared-contracts/utils/ImmutableCreate2FactoryUtils.sol";
import {LibString} from "solady/utils/LibString.sol";

// Temp script
contract DeployScript is ProxyDeployerScript {
    address internal constant PROTOCOL_REWARDS = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;

    function saveDeployment(
        address saleStrategy,
        address saleStrategyImpl,
        address erc20z,
        address royalties,
        address _nonfungiblePositionManager,
        address _weth
    ) internal {
        string memory objectKey = "config";

        vm.serializeAddress(objectKey, "SALE_STRATEGY", saleStrategy);
        vm.serializeAddress(objectKey, "SALE_STRATEGY_IMPL", saleStrategyImpl);
        vm.serializeAddress(objectKey, "ERC20Z", erc20z);
        vm.serializeAddress(objectKey, "ROYALTIES", royalties);
        vm.serializeAddress(objectKey, "NONFUNGIBLE_POSITION_MANAGER", _nonfungiblePositionManager);
        string memory result = vm.serializeAddress(objectKey, "WETH", _weth);

        vm.writeJson(result, string.concat("./addresses/", vm.toString(block.chainid), ".json"));
    }

    function signDeploymentWithTurnkey(
        DeterministicContractConfig memory config,
        bytes memory init,
        DeterministicDeployerAndCaller deployer
    ) internal returns (bytes memory signature) {
        string[] memory args = new string[](8);

        args[0] = "pnpm";
        args[1] = "tsx";
        args[2] = "scripts/signDeployAndCall.ts";

        args[3] = vm.toString(block.chainid);

        // salt
        args[4] = vm.toString(config.salt);

        // creation code:
        args[5] = LibString.toHexString(config.creationCode);

        // init
        args[6] = LibString.toHexString(init);

        // deployer address
        args[7] = vm.toString(address(deployer));

        signature = vm.ffi(args);
    }

    function run() public {
        IProtocolRewards protocolRewards = IProtocolRewards(PROTOCOL_REWARDS);
        address owner = getProxyAdmin();
        address zoraRecipient = getZoraRecipient();

        // get deployed implementation address.  it it's not deployed, revert
        address zoraTimedSaleStrategyImplAddress = ImmutableCreate2FactoryUtils.immutableCreate2Address(type(ZoraTimedSaleStrategyImpl).creationCode);

        if (zoraTimedSaleStrategyImplAddress.code.length == 0) {
            revert("Impl not yet deployed.  Make sure to deploy it with DeployImpl.s.sol");
        }

        vm.startBroadcast();

        // get deployer contract
        DeterministicDeployerAndCaller deployer = createOrGetDeployerAndCaller();

        // read previously saved deterministic royalties config
        DeterministicContractConfig memory royaltiesConfig = readDeterministicContractConfig("royalties");

        // read weth and nonfungible position manager from chain config
        IWETH weth = IWETH(getWeth());
        INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(getNonFungiblePositionManager());

        // build royalties init call
        // royalties.initialize(weth, nonfungiblePositionManager);
        bytes memory royaltiesInit = abi.encodeWithSelector(Royalties.initialize.selector, weth, nonfungiblePositionManager, zoraRecipient, 2500);

        // sign royalties deployment with turnkey account
        bytes memory royaltiesSignature = signDeploymentWithTurnkey(royaltiesConfig, royaltiesInit, deployer);

        // deterministically deploy royalties contract using the signature
        address deployedRoyalties = deployer.permitSafeCreate2AndCall(
            royaltiesSignature,
            royaltiesConfig.salt,
            royaltiesConfig.creationCode,
            royaltiesInit,
            royaltiesConfig.deployedAddress
        );

        Royalties royalties = Royalties(payable(deployedRoyalties));

        // create erc20z
        ERC20Z erc20z = new ERC20Z(royalties);

        // build initialization call for zora timed sale strategy
        bytes memory zoraTimedSaleStrategyInit = abi.encodeWithSelector(
            ZoraTimedSaleStrategyImpl.initialize.selector,
            owner,
            zoraRecipient,
            erc20z,
            protocolRewards
        );

        // build upgrade to and call for timed sale strategy, with init call
        // defined above
        bytes memory upgradeToAndCall = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector,
            zoraTimedSaleStrategyImplAddress,
            zoraTimedSaleStrategyInit
        );

        // get previously generated deterministic deployment config for zora timed sale strategy
        DeterministicContractConfig memory minterConfig = readDeterministicContractConfig("zoraTimedSaleStrategy");

        // sign the deployment with the turnkey account
        bytes memory minterSignature = signDeploymentWithTurnkey(minterConfig, upgradeToAndCall, deployer);

        // deploy the zora timed sale strategy
        deployer.permitSafeCreate2AndCall(minterSignature, minterConfig.salt, minterConfig.creationCode, upgradeToAndCall, minterConfig.deployedAddress);

        vm.stopBroadcast();

        // save the deployment json
        saveDeployment(
            minterConfig.deployedAddress,
            zoraTimedSaleStrategyImplAddress,
            address(erc20z),
            deployedRoyalties,
            address(nonfungiblePositionManager),
            address(weth)
        );
    }
}
