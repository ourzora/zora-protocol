// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "../ProtocolRewardsTest.sol";
import "./Handler.sol";

contract ProtocolRewardsInvariantTest is ProtocolRewardsTest {
    Handler internal handler;

    function setUp() public override {
        super.setUp();

        handler = new Handler(protocolRewards);

        vm.label(address(handler), "HANDLER");

        targetContract(address(handler));

        bytes4[] memory targetSelectors = new bytes4[](2);

        targetSelectors[0] = Handler.deposit.selector;
        targetSelectors[1] = Handler.withdraw.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: targetSelectors}));

        excludeSender(address(handler));
        excludeSender(address(protocolRewards));
        excludeSender(address(this));
    }

    function invariant_TotalSupplyMatchesTotalDeposits() public {
        assertEq(protocolRewards.totalSupply(), handler.ghost_depositSum() - handler.ghost_withdrawSum());
    }

    function invariant_UserBalanceCannotExceedTotalSupply() public {
        handler.forEachActor(this.ensureActorBalanceDoesNotExceedTotalSupply);
    }

    function ensureActorBalanceDoesNotExceedTotalSupply(address actor) external {
        assertLe(protocolRewards.balanceOf(actor), protocolRewards.totalSupply());
    }
}
