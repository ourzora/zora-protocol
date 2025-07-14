// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "forge-std/Test.sol";
import {ProtocolRewards} from "@zoralabs/protocol-rewards/src/ProtocolRewards.sol";
import {ZoraCreator1155Impl} from "../../../src/nft/ZoraCreator1155Impl.sol";
import {Zora1155} from "../../../src/proxies/Zora1155.sol";
import {IZoraCreator1155Errors} from "../../../src/interfaces/IZoraCreator1155Errors.sol";
import {IRenderer1155} from "../../../src/interfaces/IRenderer1155.sol";
import {ICreatorRoyaltiesControl} from "../../../src/interfaces/ICreatorRoyaltiesControl.sol";
import {ILimitedMintPerAddressErrors} from "../../../src/interfaces/ILimitedMintPerAddress.sol";
import {IZoraCreator1155Factory} from "../../../src/interfaces/IZoraCreator1155Factory.sol";
import {ZoraCreatorMerkleMinterStrategy} from "../../../src/minters/merkle/ZoraCreatorMerkleMinterStrategy.sol";

contract ZoraCreatorMerkleMinterStrategyTest is Test {
    ProtocolRewards internal protocolRewards;
    ZoraCreator1155Impl internal target;
    ZoraCreatorMerkleMinterStrategy internal merkleMinter;
    address payable internal admin = payable(address(0x999));
    address internal zora;
    address internal mintTo;
    address[] internal rewardRecipients;

    event SaleSet(address indexed sender, uint256 indexed tokenId, ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings merkleSaleSettings);

    function setUp() external {
        zora = makeAddr("zora");
        mintTo = address(1);
        bytes[] memory emptyData = new bytes[](0);
        rewardRecipients = new address[](1);
        protocolRewards = new ProtocolRewards();
        ZoraCreator1155Impl targetImpl = new ZoraCreator1155Impl(zora, address(0x1234), address(protocolRewards), makeAddr("timedSaleStrategy"));
        Zora1155 proxy = new Zora1155(address(targetImpl));
        target = ZoraCreator1155Impl(payable(address(proxy)));
        target.initialize("test", "test", ICreatorRoyaltiesControl.RoyaltyConfiguration(0, 0, address(0)), admin, emptyData);
        merkleMinter = new ZoraCreatorMerkleMinterStrategy();
    }

    function test_ContractURI() external {
        assertEq(merkleMinter.contractURI(), "https://github.com/ourzora/zora-1155-contracts/");
    }

    function test_ContractName() external {
        assertEq(merkleMinter.contractName(), "Merkle Tree Sale Strategy");
    }

    function test_Version() external {
        assertEq(merkleMinter.contractVersion(), "1.0.0");
    }

    function test_MintFlow() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(merkleMinter), target.PERMISSION_BIT_MINTER());
        vm.expectEmit(false, false, false, false);
        bytes32 root = bytes32(0x7e7a334f9b622e055f2dd48534a493de2cf6a28e114e7b53129b75ed44742ca8);
        emit SaleSet(
            address(target),
            newTokenId,
            ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({presaleStart: 0, presaleEnd: type(uint64).max, fundsRecipient: address(0), merkleRoot: root})
        );
        target.callSale(
            newTokenId,
            merkleMinter,
            abi.encodeWithSelector(
                ZoraCreatorMerkleMinterStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({
                    presaleStart: 0,
                    presaleEnd: type(uint64).max,
                    fundsRecipient: address(0),
                    merkleRoot: root
                })
            )
        );
        vm.stopPrank();

        uint256 totalSale = 10 ether;
        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        uint256 totalValue = totalSale + totalReward;

        vm.deal(mintTo, totalValue);

        uint256 maxQuantity = 10;
        uint256 pricePerToken = 1 ether;
        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = bytes32(0x71013e6ce1f439aaa91aa706ddd0769517fbaa4d72a936af4a7c75d29b1ca862);

        vm.startPrank(mintTo);
        target.mint{value: totalValue}(merkleMinter, newTokenId, 10, rewardRecipients, abi.encode(mintTo, maxQuantity, pricePerToken, merkleProof));

        assertEq(target.balanceOf(mintTo, newTokenId), 10);
        assertEq(address(target).balance, 10 ether);

        vm.stopPrank();
    }

    function test_PreSaleStart() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(merkleMinter), target.PERMISSION_BIT_MINTER());
        bytes32 root = bytes32(0x7e7a334f9b622e055f2dd48534a493de2cf6a28e114e7b53129b75ed44742ca8);
        target.callSale(
            newTokenId,
            merkleMinter,
            abi.encodeWithSelector(
                ZoraCreatorMerkleMinterStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({
                    presaleStart: uint64(block.timestamp + 1 days),
                    presaleEnd: type(uint64).max,
                    fundsRecipient: address(0),
                    merkleRoot: root
                })
            )
        );
        vm.stopPrank();

        uint256 totalSale = 10 ether;
        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        uint256 totalValue = totalSale + totalReward;

        vm.deal(mintTo, totalValue);

        uint256 maxQuantity = 10;
        uint256 pricePerToken = 1 ether;
        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = bytes32(0x71013e6ce1f439aaa91aa706ddd0769517fbaa4d72a936af4a7c75d29b1ca862);

        vm.prank(mintTo);
        vm.expectRevert(abi.encodeWithSignature("SaleHasNotStarted()"));
        target.mint{value: totalValue}(merkleMinter, newTokenId, 10, rewardRecipients, abi.encode(mintTo, maxQuantity, pricePerToken, merkleProof));
    }

    function test_PreSaleEnd() external {
        vm.warp(2 days);
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(merkleMinter), target.PERMISSION_BIT_MINTER());
        bytes32 root = bytes32(0x7e7a334f9b622e055f2dd48534a493de2cf6a28e114e7b53129b75ed44742ca8);
        target.callSale(
            newTokenId,
            merkleMinter,
            abi.encodeWithSelector(
                ZoraCreatorMerkleMinterStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({
                    presaleStart: 0,
                    presaleEnd: uint64(block.timestamp - 1 days),
                    fundsRecipient: address(0),
                    merkleRoot: root
                })
            )
        );
        vm.stopPrank();

        vm.deal(mintTo, 20 ether);

        uint256 maxQuantity = 10;
        uint256 pricePerToken = 1000000000000000000;
        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = bytes32(0x71013e6ce1f439aaa91aa706ddd0769517fbaa4d72a936af4a7c75d29b1ca862);

        vm.prank(mintTo);
        vm.expectRevert(abi.encodeWithSignature("SaleEnded()"));
        target.mint{value: 10 ether}(merkleMinter, newTokenId, 10, rewardRecipients, abi.encode(mintTo, maxQuantity, pricePerToken, merkleProof));
    }

    function test_FundsRecipientt() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(merkleMinter), target.PERMISSION_BIT_MINTER());
        bytes32 root = bytes32(0x7e7a334f9b622e055f2dd48534a493de2cf6a28e114e7b53129b75ed44742ca8);
        vm.expectEmit(true, true, true, true);
        emit SaleSet(
            address(target),
            newTokenId,
            ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({presaleStart: 0, presaleEnd: type(uint64).max, fundsRecipient: address(1234), merkleRoot: root})
        );
        target.callSale(
            newTokenId,
            merkleMinter,
            abi.encodeWithSelector(
                ZoraCreatorMerkleMinterStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({
                    presaleStart: 0,
                    presaleEnd: type(uint64).max,
                    fundsRecipient: address(1234),
                    merkleRoot: root
                })
            )
        );
        vm.stopPrank();

        uint256 totalSale = 10 ether;
        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        uint256 totalValue = totalSale + totalReward;

        vm.deal(mintTo, totalValue);

        uint256 maxQuantity = 10;
        uint256 pricePerToken = 1000000000000000000;
        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = bytes32(0x71013e6ce1f439aaa91aa706ddd0769517fbaa4d72a936af4a7c75d29b1ca862);

        vm.prank(mintTo);
        target.mint{value: totalValue}(merkleMinter, newTokenId, 10, rewardRecipients, abi.encode(mintTo, maxQuantity, pricePerToken, merkleProof));

        assertEq(address(1234).balance, 10 ether);
    }

    function test_InvalidMerkleProof() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(merkleMinter), target.PERMISSION_BIT_MINTER());
        vm.expectEmit(true, true, true, true);
        bytes32 root = bytes32(0x7e7a334f9b622e055f2dd48534a493de2cf6a28e114e7b53129b75ed44742ca8);
        emit SaleSet(
            address(target),
            newTokenId,
            ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({presaleStart: 0, presaleEnd: type(uint64).max, fundsRecipient: address(0), merkleRoot: root})
        );
        target.callSale(
            newTokenId,
            merkleMinter,
            abi.encodeWithSelector(
                ZoraCreatorMerkleMinterStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({
                    presaleStart: 0,
                    presaleEnd: type(uint64).max,
                    fundsRecipient: address(0),
                    merkleRoot: root
                })
            )
        );
        vm.stopPrank();

        vm.deal(mintTo, 20 ether);

        uint256 maxQuantity = 10;
        uint256 pricePerToken = 1000000000000000000;
        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = bytes32(0);

        vm.prank(mintTo);
        vm.expectRevert(abi.encodeWithSignature("InvalidMerkleProof(address,bytes32[],bytes32)", mintTo, merkleProof, root));
        target.mint{value: 10 ether}(merkleMinter, newTokenId, 10, rewardRecipients, abi.encode(mintTo, maxQuantity, pricePerToken, merkleProof));
    }

    function test_MaxQuantity() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(merkleMinter), target.PERMISSION_BIT_MINTER());
        vm.expectEmit(true, true, true, true);
        bytes32 root = bytes32(0x7e7a334f9b622e055f2dd48534a493de2cf6a28e114e7b53129b75ed44742ca8);
        emit SaleSet(
            address(target),
            newTokenId,
            ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({presaleStart: 0, presaleEnd: type(uint64).max, fundsRecipient: address(0), merkleRoot: root})
        );
        target.callSale(
            newTokenId,
            merkleMinter,
            abi.encodeWithSelector(
                ZoraCreatorMerkleMinterStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({
                    presaleStart: 0,
                    presaleEnd: type(uint64).max,
                    fundsRecipient: address(0),
                    merkleRoot: root
                })
            )
        );
        vm.stopPrank();

        uint256 totalSale = 10 ether;
        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        uint256 totalValue = totalSale + totalReward;

        vm.deal(mintTo, totalValue);

        uint256 maxQuantity = 10;
        uint256 pricePerToken = 1000000000000000000;
        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = bytes32(0x71013e6ce1f439aaa91aa706ddd0769517fbaa4d72a936af4a7c75d29b1ca862);

        vm.startPrank(mintTo);
        target.mint{value: totalValue}(merkleMinter, newTokenId, 10, rewardRecipients, abi.encode(mintTo, maxQuantity, pricePerToken, merkleProof));

        vm.deal(mintTo, 1.000777 ether);

        vm.expectRevert(abi.encodeWithSelector(ILimitedMintPerAddressErrors.UserExceedsMintLimit.selector, mintTo, 10, 11));
        target.mint{value: 1.000777 ether}(merkleMinter, newTokenId, 1, rewardRecipients, abi.encode(mintTo, maxQuantity, pricePerToken, merkleProof));

        vm.stopPrank();
    }

    function test_PricePerToken() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(merkleMinter), target.PERMISSION_BIT_MINTER());
        vm.expectEmit(false, false, false, false);
        bytes32 root = bytes32(0x7e7a334f9b622e055f2dd48534a493de2cf6a28e114e7b53129b75ed44742ca8);
        emit SaleSet(
            address(target),
            newTokenId,
            ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({presaleStart: 0, presaleEnd: type(uint64).max, fundsRecipient: address(0), merkleRoot: root})
        );
        target.callSale(
            newTokenId,
            merkleMinter,
            abi.encodeWithSelector(
                ZoraCreatorMerkleMinterStrategy.setSale.selector,
                newTokenId,
                ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({
                    presaleStart: 0,
                    presaleEnd: type(uint64).max,
                    fundsRecipient: address(0),
                    merkleRoot: root
                })
            )
        );
        vm.stopPrank();

        uint256 totalSale = 10 ether;
        uint256 totalReward = target.computeTotalReward(target.mintFee(), 10);
        uint256 totalValue = totalSale + totalReward;

        vm.deal(mintTo, totalValue);

        uint256 maxQuantity = 10;
        uint256 pricePerToken = 1 ether;
        bytes32[] memory merkleProof = new bytes32[](1);
        merkleProof[0] = bytes32(0x71013e6ce1f439aaa91aa706ddd0769517fbaa4d72a936af4a7c75d29b1ca862);

        vm.startPrank(mintTo);
        vm.expectRevert(abi.encodeWithSignature("WrongValueSent()"));
        target.mint{value: totalValue - 1}(merkleMinter, newTokenId, 10, rewardRecipients, abi.encode(mintTo, maxQuantity, pricePerToken, merkleProof));
    }

    function test_ResetSale() external {
        vm.startPrank(admin);
        uint256 newTokenId = target.setupNewToken("https://zora.co/testing/token.json", 10);
        target.addPermission(newTokenId, address(merkleMinter), target.PERMISSION_BIT_MINTER());
        vm.expectEmit(false, false, false, false);
        emit SaleSet(
            address(target),
            newTokenId,
            ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings({presaleStart: 0, presaleEnd: 0, fundsRecipient: address(0), merkleRoot: bytes32(0)})
        );
        target.callSale(newTokenId, merkleMinter, abi.encodeWithSelector(ZoraCreatorMerkleMinterStrategy.resetSale.selector, newTokenId));
        vm.stopPrank();

        ZoraCreatorMerkleMinterStrategy.MerkleSaleSettings memory sale = merkleMinter.sale(address(target), newTokenId);
        assertEq(sale.presaleStart, 0);
        assertEq(sale.presaleEnd, 0);
        assertEq(sale.fundsRecipient, address(0));
        assertEq(sale.merkleRoot, bytes32(0));
    }

    function test_MerkleSaleSupportsInterface() public {
        assertTrue(merkleMinter.supportsInterface(0x6890e5b3));
        assertTrue(merkleMinter.supportsInterface(0x01ffc9a7));
        assertFalse(merkleMinter.supportsInterface(0x0));
    }
}

/*
Merkle Tree (generated using @openzeppelin/merkle-tree, modified to use single hashing instead of double)

Merkle Root: 0x7e7a334f9b622e055f2dd48534a493de2cf6a28e114e7b53129b75ed44742ca8
{
  "format": "standard-v1",
  "tree": [
    "0x7e7a334f9b622e055f2dd48534a493de2cf6a28e114e7b53129b75ed44742ca8",
    "0xb5831bb831d57b07a9e692e2f35325a7b7efcee902c0bcde0cf2b19063537082",
    "0x71013e6ce1f439aaa91aa706ddd0769517fbaa4d72a936af4a7c75d29b1ca862"
  ],
  "values": [
    {
      "value": [
        "0x0000000000000000000000000000000000000001",
        "10",
        "1000000000000000000"
      ],
      "treeIndex": 1
    },
    {
      "value": [
        "0x0000000000000000000000000000000000000002",
        "10",
        "1000000000000000000"
      ],
      "treeIndex": 2
    }
  ],
  "leafEncoding": [
    "address",
    "uint256",
    "uint256"
  ]
}
Value for proof #0: [
  '0x0000000000000000000000000000000000000001',
  '10',
  '1000000000000000000'
]
Proof #0: [
  '0x71013e6ce1f439aaa91aa706ddd0769517fbaa4d72a936af4a7c75d29b1ca862'
]
Value for proof #1: [
  '0x0000000000000000000000000000000000000002',
  '10',
  '1000000000000000000'
]
Proof #1: [
  '0xb5831bb831d57b07a9e692e2f35325a7b7efcee902c0bcde0cf2b19063537082'
]

*/
