// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {PremintConfig, PremintConfigV2, Erc20PremintConfigV1} from "../entities/Premint.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";

struct EncodedPremintConfig {
    bytes premintConfig;
    bytes32 premintConfigVersion;
    uint32 uid;
    address minter;
}

library PremintEncoding {
    string internal constant VERSION_1 = "1";
    bytes32 internal constant HASHED_VERSION_1 = keccak256(bytes(VERSION_1));
    string internal constant VERSION_2 = "2";
    bytes32 internal constant HASHED_VERSION_2 = keccak256(bytes(VERSION_2));
    string internal constant ERC20_VERSION_1 = "ERC20_1";
    bytes32 internal constant HASHED_ERC20_VERSION_1 = keccak256(bytes(ERC20_VERSION_1));

    function encodePremintV1(PremintConfig memory premintConfig) internal pure returns (EncodedPremintConfig memory) {
        return EncodedPremintConfig(abi.encode(premintConfig), HASHED_VERSION_1, premintConfig.uid, premintConfig.tokenConfig.fixedPriceMinter);
    }

    function encodePremintV2(PremintConfigV2 memory premintConfig) internal pure returns (EncodedPremintConfig memory) {
        return EncodedPremintConfig(abi.encode(premintConfig), HASHED_VERSION_2, premintConfig.uid, premintConfig.tokenConfig.fixedPriceMinter);
    }

    function encodePremintErc20V1(Erc20PremintConfigV1 memory premintConfig) internal pure returns (EncodedPremintConfig memory)  {
        return EncodedPremintConfig(abi.encode(premintConfig), HASHED_ERC20_VERSION_1, premintConfig.uid, premintConfig.tokenConfig.erc20Minter);
    }
}
