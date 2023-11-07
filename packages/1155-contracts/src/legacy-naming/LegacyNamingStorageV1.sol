// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

abstract contract LegacyNamingStorageV1 {
    struct LegacyNamingStorageData {
        string _name;
    }

    function _getLegacyNamingStorage() internal pure returns (LegacyNamingStorageData storage $) {
        assembly {
            $.slot := 403
        }
    }
}
