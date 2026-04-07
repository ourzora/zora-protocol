// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import "../src/ProtocolRewards.sol";

import "./utils/MockNFTs.sol";

contract ProtocolRewardsTest is Test {
    uint256 internal constant ETH_SUPPLY = 120_200_000 ether;

    ProtocolRewards internal protocolRewards;

    address internal collector;
    address internal creator;
    address internal createReferral;
    address internal mintReferral;
    address internal firstMinter;
    address internal zora;

    function setUp() public virtual {
        protocolRewards = new ProtocolRewards();

        vm.label(address(protocolRewards), "protocolRewards");

        collector = makeAddr("collector");
        creator = makeAddr("creator");
        createReferral = makeAddr("createReferral");
        mintReferral = makeAddr("mintReferral");
        firstMinter = makeAddr("firstMinter");
        zora = makeAddr("zora");
    }
}
