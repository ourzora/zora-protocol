// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

contract ZoraAccountFactoryImpl {
    function createWallet(address defaultOwner) external {
        create2(abi.encode(defaultOwner), XXX);
    }


}