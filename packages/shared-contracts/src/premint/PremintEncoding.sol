// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {PremintConfig, PremintConfigV2, PremintConfigV3, PremintConfigEncoded, TokenCreationConfig, TokenCreationConfigV2, TokenCreationConfigV3} from "../entities/Premint.sol";
import {IMinter1155} from "../interfaces/IMinter1155.sol";
import {IZoraCreator1155Errors} from "../interfaces/errors/IZoraCreator1155Errors.sol";

library PremintEncoding {
    string internal constant VERSION_1 = "1";
    bytes32 internal constant HASHED_VERSION_1 = keccak256(bytes(VERSION_1));
    string internal constant VERSION_2 = "2";
    bytes32 internal constant HASHED_VERSION_2 = keccak256(bytes(VERSION_2));
    string internal constant VERSION_3 = "3";
    bytes32 internal constant HASHED_VERSION_3 = keccak256(bytes(VERSION_3));

    function encodePremint(PremintConfig memory premintConfig) internal pure returns (PremintConfigEncoded memory) {
        return PremintConfigEncoded(premintConfig.uid, premintConfig.version, premintConfig.deleted, abi.encode(premintConfig.tokenConfig), HASHED_VERSION_1);
    }

    function encodePremint(PremintConfigV2 memory premintConfig) internal pure returns (PremintConfigEncoded memory) {
        return PremintConfigEncoded(premintConfig.uid, premintConfig.version, premintConfig.deleted, abi.encode(premintConfig.tokenConfig), HASHED_VERSION_2);
    }

    function encodePremint(PremintConfigV3 memory premintConfig) internal pure returns (PremintConfigEncoded memory) {
        return PremintConfigEncoded(premintConfig.uid, premintConfig.version, premintConfig.deleted, abi.encode(premintConfig.tokenConfig), HASHED_VERSION_3);
    }

    function decodePremintConfig(PremintConfigEncoded memory premintConfigEncoded) internal pure returns (bytes memory encodedPremintConfig, address minter) {
        bytes32 hashedVersion = premintConfigEncoded.premintConfigVersion;
        if (hashedVersion == HASHED_VERSION_1) {
            // todo: catch with more graceful error
            PremintConfig memory premintConfig = PremintConfig({
                uid: premintConfigEncoded.uid,
                version: premintConfigEncoded.version,
                deleted: premintConfigEncoded.deleted,
                tokenConfig: abi.decode(premintConfigEncoded.tokenConfig, (TokenCreationConfig))
            });

            return (abi.encode(premintConfig), premintConfig.tokenConfig.fixedPriceMinter);
        } else if (hashedVersion == HASHED_VERSION_2) {
            PremintConfigV2 memory config = PremintConfigV2({
                uid: premintConfigEncoded.uid,
                version: premintConfigEncoded.version,
                deleted: premintConfigEncoded.deleted,
                tokenConfig: abi.decode(premintConfigEncoded.tokenConfig, (TokenCreationConfigV2))
            });

            return (abi.encode(config), config.tokenConfig.fixedPriceMinter);
        } else if (hashedVersion == HASHED_VERSION_3) {
            PremintConfigV3 memory config = PremintConfigV3({
                uid: premintConfigEncoded.uid,
                version: premintConfigEncoded.version,
                deleted: premintConfigEncoded.deleted,
                tokenConfig: abi.decode(premintConfigEncoded.tokenConfig, (TokenCreationConfigV3))
            });

            return (abi.encode(config), config.tokenConfig.minter);
        } else {
            revert IZoraCreator1155Errors.InvalidSignatureVersion();
        }
    }
}
