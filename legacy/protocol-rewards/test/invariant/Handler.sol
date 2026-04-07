// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Base.sol";

import "../ProtocolRewardsTest.sol";

contract Handler is CommonBase, StdCheats, StdUtils {
    uint256 internal constant ETH_SUPPLY = 120_200_000 ether;
    ProtocolRewards internal immutable rewards;

    uint256 public ghost_depositSum;
    uint256 public ghost_withdrawSum;

    address internal currentActor;
    uint256 public numActors;
    mapping(uint256 => address) public actors;

    constructor(ProtocolRewards _rewards) {
        rewards = _rewards;

        vm.deal(address(this), ETH_SUPPLY);
    }

    modifier validateActor(address actor) {
        if (actor == address(0) || actor <= address(0x9)) {
            return;
        }

        _;
    }

    modifier createActor(address actor) {
        currentActor = msg.sender;

        actors[++numActors] = currentActor;

        _;
    }

    modifier useActor(uint256 actorSeed) {
        if (numActors == 0) {
            return;
        }

        currentActor = actors[(actorSeed % numActors) + 1];

        _;
    }

    modifier validateWithdraw() {
        if (rewards.balanceOf(currentActor) == 0) {
            return;
        }

        _;
    }

    function deposit(uint256 amount) public validateActor(msg.sender) createActor(msg.sender) {
        amount = bound(amount, 0, address(this).balance);

        (bool success, ) = currentActor.call{value: amount}("");
        if (!success) {
            return;
        }

        vm.prank(currentActor);
        rewards.deposit{value: amount}(currentActor, "", "");

        ghost_depositSum += amount;
    }

    function withdraw(uint256 actorSeed, uint256 amount) public validateActor(msg.sender) useActor(actorSeed) validateWithdraw {
        amount = bound(amount, 0, rewards.balanceOf(currentActor));

        amount == 0 ? ghost_withdrawSum += rewards.balanceOf(currentActor) : ghost_withdrawSum += amount;

        vm.prank(currentActor);
        rewards.withdraw(currentActor, amount);
    }

    function forEachActor(function(address) external func) public {
        for (uint256 i = 1; i < numActors; ++i) {
            func(actors[i]);
        }
    }
}
