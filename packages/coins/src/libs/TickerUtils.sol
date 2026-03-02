// SPDX-License-Identifier: ZORA-DELAYED-OSL-v1
// This software is licensed under the Zora Delayed Open Source License.
// Under this license, you may use, copy, modify, and distribute this software for
// non-commercial purposes only. Commercial use and competitive products are prohibited
// until the "Open Date" (3 years from first public distribution or earlier at Zora's discretion),
// at which point this software automatically becomes available under the MIT License.
// Full license terms available at: https://docs.zora.co/coins/license
pragma solidity ^0.8.23;

/// @title TickerUtils
/// @notice Library for ASCII case-folding ticker symbols for uniqueness checking
library TickerUtils {
    /// @notice Converts a ticker string to lowercase (ASCII case-folding)
    /// @param ticker The ticker symbol to fold
    /// @return The lowercase ticker bytes
    function foldTicker(string memory ticker) internal pure returns (bytes memory) {
        bytes memory tickerBytes = bytes(ticker);
        bytes memory result = new bytes(tickerBytes.length);

        for (uint256 i = 0; i < tickerBytes.length; i++) {
            bytes1 char = tickerBytes[i];
            // If uppercase A-Z (0x41-0x5A), convert to lowercase (add 0x20)
            if (char >= 0x41 && char <= 0x5A) {
                result[i] = bytes1(uint8(char) + 32);
            } else {
                result[i] = char;
            }
        }

        return result;
    }

    /// @notice Computes a hash of the case-folded ticker for uniqueness checking
    /// @param ticker The ticker symbol to hash
    /// @return The keccak256 hash of the lowercase ticker
    function tickerHash(string memory ticker) internal pure returns (bytes32) {
        return keccak256(foldTicker(ticker));
    }

    /// @notice Converts spaces in ticker to '+' for URI encoding
    /// @param ticker The ticker symbol to encode
    /// @return The ticker with spaces replaced by '+'
    function tickerToUri(string memory ticker) internal pure returns (string memory) {
        bytes memory tickerBytes = bytes(ticker);
        bytes memory result = new bytes(tickerBytes.length);

        for (uint256 i = 0; i < tickerBytes.length; i++) {
            bytes1 char = tickerBytes[i];
            // Replace space (0x20) with '+' (0x2B)
            if (char == 0x20) {
                result[i] = 0x2B;
            } else {
                result[i] = char;
            }
        }

        return string(result);
    }

    /// @notice Validates that a ticker symbol contains only allowed characters
    /// @dev Allowed characters: space (0x20), 0-9 (0x30-0x39), A-Z (0x41-0x5A), a-z (0x61-0x7A), dash (0x2D)
    /// @param ticker The ticker symbol to validate
    /// @return true if all characters are valid
    function validateTickerCharacters(string memory ticker) internal pure returns (bool) {
        bytes memory tickerBytes = bytes(ticker);
        // Empty string is not allowed
        if (tickerBytes.length == 0) {
            return false;
        }
        for (uint256 i = 0; i < tickerBytes.length; i++) {
            bytes1 char = tickerBytes[i];
            bool isValid =
                char == 0x20 ||                    // space
                char == 0x2D ||                    // dash (-)
                (char >= 0x30 && char <= 0x39) || // 0-9
                (char >= 0x41 && char <= 0x5A) || // A-Z
                (char >= 0x61 && char <= 0x7A);    // a-z

            if (!isValid) {
                return false;
            }
        }
        return true;
    }
}
