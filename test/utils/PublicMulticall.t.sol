// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";

import {PublicMulticall} from "../../src/utils/PublicMulticall.sol";

contract DemoMulticall is PublicMulticall {
    uint256 public num;
    address public user;

    constructor() {
        num = 999;
        user = address(0);
    }

    function bop(uint256 _num) public {
        num = _num;
    }

    function clear() public {
        require(num > 0, "cannot clear already cleared");
        num = 0;
    }

    function setUser() public {
        user = msg.sender;
    }
}

contract PublicMulticallTest is Test {
    DemoMulticall demo;

    function setUp() public {
        demo = new DemoMulticall();
    }

    function testCallsSucceed() public {
        assertEq(demo.num(), 999);
        bytes[] memory calls = new bytes[](3);

        calls[0] = abi.encodeWithSelector(DemoMulticall.clear.selector);
        calls[1] = abi.encodeWithSelector(DemoMulticall.bop.selector, 3);
        calls[2] = abi.encodeWithSelector(DemoMulticall.clear.selector);
        demo.multicall(calls);
        assertEq(demo.num(), 0);
    }

    function testCallsFail() public {
        assertEq(demo.num(), 999);
        bytes[] memory calls = new bytes[](2);

        calls[0] = abi.encodeWithSelector(DemoMulticall.clear.selector);
        calls[1] = abi.encodeWithSelector(DemoMulticall.clear.selector);
        vm.expectRevert();
        demo.multicall(calls);
    }

    function testCallsComeFromUser() public {
        assertEq(demo.num(), 999);
        bytes[] memory calls = new bytes[](1);

        calls[0] = abi.encodeWithSelector(DemoMulticall.setUser.selector);
        vm.prank(address(0x999));
        demo.multicall(calls);

        assertEq(demo.user(), address(0x999));
    }
}
