// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IZoraCreator1155} from "@zoralabs/zora-1155-contracts/src/interfaces/IZoraCreator1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {BoostedMinterStorageV1} from "./BoostedMinterStorageV1.sol";

contract BoostedMinterImpl is BoostedMinterStorageV1, ReentrancyGuard, Initializable {
    uint256 public immutable FIXED_GAS_PREMIUM = 0.000333 ether;
    uint256 private constant CREATOR_ADMIN_ROLE_PERMISSION_BIT = 2;

    error ONLY_FRAME_MINTER();
    error ONLY_ADMIN();
    error GAS_WITHDRAWAL_FAILED();

    event GasWithdrawn(address indexed tokenContract, uint256 indexed tokenId, address indexed to, uint256 amount);
    event GasDeposited(address indexed tokenContract, uint256 indexed tokenId, address indexed from, uint256 amount);

    modifier onlyFrameMinter() {
        if (msg.sender != frameMinter) {
            revert ONLY_FRAME_MINTER();
        }
        _;
    }

    modifier onlyCreatorAdmin() {
        if (
            !IZoraCreator1155(tokenContract).isAdminOrRole(msg.sender, tokenId, CREATOR_ADMIN_ROLE_PERMISSION_BIT)
                && !IZoraCreator1155(tokenContract).isAdminOrRole(msg.sender, 0, CREATOR_ADMIN_ROLE_PERMISSION_BIT)
        ) {
            revert ONLY_ADMIN();
        }
        _;
    }

    constructor() initializer {}

    function initialize(address _frameMinter, address _tokenContract, uint256 _tokenId)
        external
        nonReentrant
        initializer
    {
        frameMinter = _frameMinter;
        tokenContract = _tokenContract;
        tokenId = _tokenId;
    }

    function mint(address _to, uint256 _amount) external onlyFrameMinter {
        uint256 startGasSnapshot = gasleft();
        IZoraCreator1155(tokenContract).adminMint(_to, tokenId, _amount, "");
        uint256 gasUsed = startGasSnapshot - gasleft();

        _withdrawGas(payable(frameMinter), (gasUsed * tx.gasprice) + FIXED_GAS_PREMIUM);
    }

    function withdrawGas(address payable _to, uint256 _amt) external onlyCreatorAdmin {
        _withdrawGas(_to, _amt);
    }

    function withdrawGas(address payable _to) external onlyCreatorAdmin {
        _withdrawGas(_to, address(this).balance);
    }

    function _withdrawGas(address payable _to, uint256 _amt) internal {
        (bool success,) = _to.call{value: _amt}("");
        if (!success) {
            revert GAS_WITHDRAWAL_FAILED();
        }
        emit GasWithdrawn(tokenContract, tokenId, _to, _amt);
    }

    receive() external payable {
        emit GasDeposited(tokenContract, tokenId, msg.sender, msg.value);
    }
}
