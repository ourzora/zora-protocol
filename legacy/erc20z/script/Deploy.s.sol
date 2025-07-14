// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";

import {IProtocolRewards} from "@zoralabs/shared-contracts/interfaces/IProtocolRewards.sol";
import {IWETH} from "@zoralabs/shared-contracts/interfaces/IWETH.sol";
import {INonfungiblePositionManager} from "@zoralabs/shared-contracts/interfaces/uniswap/INonfungiblePositionManager.sol";

import {ERC20Z} from "../src/ERC20Z.sol";
import {ZoraTimedSaleStrategyImpl} from "../src/minter/ZoraTimedSaleStrategyImpl.sol";
import {Royalties} from "../src/royalties/Royalties.sol";
import {DeterministicDeployerAndCaller, DeterministicContractConfig} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {DeployerBase} from "./DeployerBase.sol";

/// @notice Deploy full erc20z protocol
contract DeployScript is DeployerBase {
    function run() public {
        IProtocolRewards protocolRewards = IProtocolRewards(PROTOCOL_REWARDS);
        address owner = getProxyAdmin();
        address zoraRecipient = getZoraRecipient();

        DeploymentConfig memory config = readDeployment();

        vm.startBroadcast();
        // deploy impl
        ZoraTimedSaleStrategyImpl impl = new ZoraTimedSaleStrategyImpl();

        address zoraTimedSaleStrategyImplAddress = address(impl);

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

        // update the deployment config with the new addresses
        config.saleStrategy = minterConfig.deployedAddress;
        config.saleStrategyImpl = address(impl);
        config.saleStrategyImplVersion = impl.contractVersion();
        config.erc20z = address(erc20z);
        config.royalties = deployedRoyalties;
        config.nonfungiblePositionManager = address(nonfungiblePositionManager);
        config.weth = address(weth);

        // save the deployment json
        saveDeployment(config);
    }
}
