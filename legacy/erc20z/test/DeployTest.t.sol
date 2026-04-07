// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {ZoraTimedSaleStrategy} from "../src/minter/ZoraTimedSaleStrategy.sol";
import {ZoraTimedSaleStrategyImpl} from "../src/minter/ZoraTimedSaleStrategyImpl.sol";
import {Royalties} from "../src/royalties/Royalties.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";

import "./BaseTest.sol";

contract ZoraTimedSaleStrategyTest is Test {
    function saltWithAddressInFirst20Bytes(address addressToMakeSaltWith, uint256 suffix) internal pure returns (bytes32) {
        uint256 shifted = uint256(uint160(address(addressToMakeSaltWith))) << 96;

        // shifted on the left, suffix on the right:

        return bytes32(shifted | suffix);
    }

    address zoraRecipient = makeAddr("zoraRecipient");
    address owner = makeAddr("owner");

    function test_itCanDeployDeterministically() external {
        vm.createSelectFork("zora", 17657267);
        IWETH weth = IWETH(0x4200000000000000000000000000000000000006);
        INonfungiblePositionManager nonfungiblePositionManager = INonfungiblePositionManager(0xB8458EaAe43292e3c1F7994EFd016bd653d23c20);

        (address caller, uint256 privateKey) = makeAddrAndKey("caller");

        bytes32 salt = saltWithAddressInFirst20Bytes(caller, 10);

        DeterministicDeployerAndCaller deployer = new DeterministicDeployerAndCaller();

        bytes memory royaltyCreationCode = type(Royalties).creationCode;
        address expectedRoyaltiesAddress = Create2.computeAddress(salt, keccak256(royaltyCreationCode), address(deployer));

        bytes memory royaltiesInit = abi.encodeWithSelector(Royalties.initialize.selector, weth, nonfungiblePositionManager, zoraRecipient, 2500);

        bytes32 royaltiesDigest = deployer.hashDigest(salt, royaltyCreationCode, royaltiesInit);

        // sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, royaltiesDigest);
        // combine into a single bytes array
        bytes memory signature = abi.encodePacked(r, s, v);

        address royaltiesAddress = deployer.permitSafeCreate2AndCall(signature, salt, royaltyCreationCode, royaltiesInit, expectedRoyaltiesAddress);

        // now create the zora timed sale strategy
        bytes memory timedSaleStrategyInitCode = deployer.proxyCreationCode(type(ZoraTimedSaleStrategy).creationCode);

        ZoraTimedSaleStrategyImpl zoraTimedSaleStrategyImpl = new ZoraTimedSaleStrategyImpl();
        ERC20Z erc20zImpl = new ERC20Z(Royalties(payable(royaltiesAddress)));

        bytes memory zoraTimedSaleStrategyInit = abi.encodeWithSelector(
            ZoraTimedSaleStrategyImpl.initialize.selector,
            owner,
            zoraRecipient,
            erc20zImpl,
            IProtocolRewards(0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B)
        );

        bytes memory upgradeToAndCall = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector,
            address(zoraTimedSaleStrategyImpl),
            zoraTimedSaleStrategyInit
        );

        address expectedTimedSaleStrategyAddress = Create2.computeAddress(salt, keccak256(timedSaleStrategyInitCode), address(deployer));

        bytes32 zoraTimedSaleStrategyDigest = deployer.hashDigest(salt, timedSaleStrategyInitCode, upgradeToAndCall);

        (v, r, s) = vm.sign(privateKey, zoraTimedSaleStrategyDigest);
        signature = abi.encodePacked(r, s, v);

        address deployedAddress = deployer.permitSafeCreate2AndCall(
            signature,
            salt,
            timedSaleStrategyInitCode,
            upgradeToAndCall,
            expectedTimedSaleStrategyAddress
        );

        assertEq(ZoraTimedSaleStrategyImpl(deployedAddress).owner(), owner);
    }
}
