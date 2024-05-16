// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {PremintConfig, PremintConfigV2, Erc20PremintConfigV1, PremintConfigCommon, TokenCreationConfig, TokenCreationConfigV2, Erc20TokenCreationConfigV1} from "../entities/Premint.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IZoraCreator1155Errors} from "../interfaces/errors/IZoraCreator1155Errors.sol";

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

    function encodePremintErc20V1(Erc20PremintConfigV1 memory premintConfig) internal pure returns (EncodedPremintConfig memory) {
        return EncodedPremintConfig(abi.encode(premintConfig), HASHED_ERC20_VERSION_1, premintConfig.uid, premintConfig.tokenConfig.erc20Minter);
    }

    function encodePremintConfig(bytes memory encodedPremintConfig, string calldata premintConfigVersion) internal pure returns (EncodedPremintConfig memory) {
        bytes32 hashedVersion = keccak256(bytes(premintConfigVersion));
        if (hashedVersion == HASHED_VERSION_1) {
            // todo: catch with more graceful error
            PremintConfig memory config = abi.decode(encodedPremintConfig, (PremintConfig));

            return EncodedPremintConfig(encodedPremintConfig, hashedVersion, config.uid, config.tokenConfig.fixedPriceMinter);
        } else if (hashedVersion == HASHED_VERSION_2) {
            PremintConfigV2 memory config = abi.decode(encodedPremintConfig, (PremintConfigV2));

            return EncodedPremintConfig(encodedPremintConfig, hashedVersion, config.uid, config.tokenConfig.fixedPriceMinter);
        } else if (hashedVersion == HASHED_ERC20_VERSION_1) {
            Erc20PremintConfigV1 memory config = abi.decode(encodedPremintConfig, (Erc20PremintConfigV1));

            return EncodedPremintConfig(encodedPremintConfig, hashedVersion, config.uid, config.tokenConfig.erc20Minter);
        } else {
            revert IZoraCreator1155Errors.InvalidSignatureVersion();
        }
    }
}
