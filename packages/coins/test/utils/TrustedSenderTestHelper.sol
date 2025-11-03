// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TrustedMsgSenderProviderLookup} from "../../src/utils/TrustedMsgSenderProviderLookup.sol";
import {ITrustedMsgSenderProviderLookup} from "../../src/interfaces/ITrustedMsgSenderProviderLookup.sol";

/// @title TrustedSenderTestHelper
/// @notice Helper library for deploying TrustedMsgSenderProviderLookup in tests
library TrustedSenderTestHelper {
    /// @notice Deploys a TrustedMsgSenderProviderLookup with direct constructor
    /// @param owner The owner address for the deployed contract
    /// @param initialTrustedSenders Array of initially trusted sender addresses
    /// @return The deployed ITrustedMsgSenderProviderLookup contract
    function deployTrustedMessageSender(address owner, address[] memory initialTrustedSenders) internal returns (ITrustedMsgSenderProviderLookup) {
        // Deploy the contract directly using constructor
        return ITrustedMsgSenderProviderLookup(address(new TrustedMsgSenderProviderLookup(initialTrustedSenders, owner)));
    }
}
