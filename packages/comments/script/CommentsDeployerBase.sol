// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import {ProxyDeployerScript, DeterministicContractConfig, DeterministicDeployerAndCaller} from "@zoralabs/shared-contracts/deployment/ProxyDeployerScript.sol";
import {CommentsImpl} from "../src/CommentsImpl.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {CallerAndCommenterImpl} from "../src/utils/CallerAndCommenterImpl.sol";
import {CallerAndCommenter} from "../src/proxy/CallerAndCommenter.sol";

// Temp script
contract CommentsDeployerBase is ProxyDeployerScript {
    uint256 internal constant SPARK_VALUE = 0.000001 ether;
    address internal constant PROTOCOL_REWARDS = 0x7777777F279eba3d3Ad8F4E708545291A6fDBA8B;
    address internal constant ZORA_TIMED_SALE_STRATEGY = 0x777777722D078c97c6ad07d9f36801e653E356Ae;
    address internal constant SECONDARY_SWAP = 0x777777EDF27Ac61671e3D5718b10bf6a8802f9f1;

    using stdJson for string;

    struct CommentsDeployment {
        address comments;
        address commentsImpl;
        string commentsVersion;
        address callerAndCommenter;
        address callerAndCommenterImpl;
        string callerAndCommenterVersion;
        uint256 commentsBlockNumber;
        uint256 commentsImplBlockNumber;
    }

    function addressesFile() internal view returns (string memory) {
        return string.concat("./addresses/", vm.toString(block.chainid), ".json");
    }

    function saveDeployment(CommentsDeployment memory deployment) internal {
        string memory objectKey = "config";

        vm.serializeAddress(objectKey, "COMMENTS", deployment.comments);
        vm.serializeUint(objectKey, "COMMENTS_BLOCK_NUMBER", deployment.commentsBlockNumber);
        vm.serializeAddress(objectKey, "COMMENTS_IMPL", deployment.commentsImpl);
        vm.serializeAddress(objectKey, "CALLER_AND_COMMENTER", deployment.callerAndCommenter);
        vm.serializeAddress(objectKey, "CALLER_AND_COMMENTER_IMPL", deployment.callerAndCommenterImpl);
        vm.serializeString(objectKey, "CALLER_AND_COMMENTER_VERSION", deployment.callerAndCommenterVersion);
        string memory result = vm.serializeUint(objectKey, "COMMENTS_IMPL_BLOCK_NUMBER", deployment.commentsImplBlockNumber);

        vm.writeJson(result, addressesFile());
    }

    function readDeployment() internal returns (CommentsDeployment memory deployment) {
        string memory file = addressesFile();
        if (!vm.exists(file)) {
            return deployment;
        }
        string memory json = vm.readFile(file);

        deployment.comments = readAddressOrDefaultToZero(json, "COMMENTS");
        deployment.commentsImpl = readAddressOrDefaultToZero(json, "COMMENTS_IMPL");
        deployment.commentsVersion = readStringOrDefaultToEmpty(json, "COMMENTS_VERSION");
        deployment.commentsBlockNumber = readUintOrDefaultToZero(json, "COMMENTS_BLOCK_NUMBER");
        deployment.commentsImplBlockNumber = readUintOrDefaultToZero(json, "COMMENTS_IMPL_BLOCK_NUMBER");
        deployment.callerAndCommenter = readAddressOrDefaultToZero(json, "CALLER_AND_COMMENTER");
        deployment.callerAndCommenterImpl = readAddressOrDefaultToZero(json, "CALLER_AND_COMMENTER_IMPL");
        deployment.callerAndCommenterVersion = readStringOrDefaultToEmpty(json, "CALLER_AND_COMMENTER_VERSION");
    }

    function commentsImplCreationCode() internal returns (bytes memory) {
        return abi.encodePacked(type(CommentsImpl).creationCode, abi.encode(SPARK_VALUE, PROTOCOL_REWARDS));
    }

    function getBackfillerAccount() internal pure returns (address) {
        return 0x77baCD258d2E6A5187B7344419A5e2842A49A059;
    }

    function deployCommentsImpl() internal returns (CommentsImpl) {
        return new CommentsImpl(SPARK_VALUE, PROTOCOL_REWARDS, getZoraRecipient());
    }

    function deployCommentsDeterministic(CommentsDeployment memory deployment, DeterministicDeployerAndCaller deployer) internal {
        // read previously saved deterministic royalties config
        DeterministicContractConfig memory commentsConfig = readDeterministicContractConfig("comments");
        DeterministicContractConfig memory callerAndCommenterConfig = readDeterministicContractConfig("callerAndCommenter");

        address backfiller = CommentsDeployerBase.getBackfillerAccount();
        // get deployed implementation address.  it it's not deployed, revert
        address implAddress = address(deployCommentsImpl());

        if (implAddress.code.length == 0) {
            revert("Impl not yet deployed.  Make sure to deploy it with DeployImpl.s.sol");
        }

        address[] memory delegateCommenters = new address[](1);
        delegateCommenters[0] = callerAndCommenterConfig.deployedAddress;

        // build upgrade to and call for comments, with init call
        bytes memory upgradeToAndCall = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector,
            implAddress,
            abi.encodeWithSelector(CommentsImpl.initialize.selector, getProxyAdmin(), backfiller, delegateCommenters)
        );

        // sign royalties deployment with turnkey account
        bytes memory signature = signDeploymentWithTurnkey(commentsConfig, upgradeToAndCall, deployer);

        deployment.comments = deployer.permitSafeCreate2AndCall(
            signature,
            commentsConfig.salt,
            commentsConfig.creationCode,
            upgradeToAndCall,
            commentsConfig.deployedAddress
        );
        deployment.commentsBlockNumber = block.number;
    }

    function deployCallerAndCommenterImpl(address commentsAddress) internal returns (address) {
        return address(new CallerAndCommenterImpl(commentsAddress, ZORA_TIMED_SALE_STRATEGY, SECONDARY_SWAP, SPARK_VALUE));
    }

    function deployCallerAndCommenterDeterministic(CommentsDeployment memory deployment, DeterministicDeployerAndCaller deployer) internal {
        address commentsAddress = readDeterministicContractConfig("comments").deployedAddress;
        DeterministicContractConfig memory callerAndCommenterConfig = readDeterministicContractConfig("callerAndCommenter");

        // deploy caller and commenter impl
        deployment.callerAndCommenterImpl = address(deployCallerAndCommenterImpl(commentsAddress));
        deployment.callerAndCommenterVersion = CallerAndCommenterImpl(deployment.callerAndCommenterImpl).contractVersion();

        bytes memory upgradeToAndCall = abi.encodeWithSelector(
            UUPSUpgradeable.upgradeToAndCall.selector,
            deployment.callerAndCommenterImpl,
            abi.encodeWithSelector(CallerAndCommenterImpl.initialize.selector, getProxyAdmin())
        );

        bytes memory signature = signDeploymentWithTurnkey(callerAndCommenterConfig, upgradeToAndCall, deployer);

        deployment.callerAndCommenter = deployer.permitSafeCreate2AndCall(
            signature,
            callerAndCommenterConfig.salt,
            callerAndCommenterConfig.creationCode,
            upgradeToAndCall,
            callerAndCommenterConfig.deployedAddress
        );
    }
}
