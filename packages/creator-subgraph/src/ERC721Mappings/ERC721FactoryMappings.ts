import {
  DropMetadataRenderer as DropMetadataRendererFactory,
  EditionMetadataRenderer as EditionMetadataRendererFactory,
} from "../../generated/templates";

import {
  Upgrade,
  ZoraCreateContract,
  ZoraCreate721Factory,
  ZoraCreateToken,
  RoyaltyConfig,
  KnownRenderer,
} from "../../generated/schema";

import {
  CreatedDrop,
  Upgraded,
  ZoraNFTCreatorV1,
} from "../../generated/Zora721V1/ZoraNFTCreatorV1";

import { makeTransaction } from "../common/makeTransaction";

import { ERC721Drop as ERC721DropContract } from "../../generated/templates/ERC721Drop/ERC721Drop";
import { getIPFSHostFromURI } from "../common/getIPFSHostFromURI";
import { ERC721Drop as ERC721DropTemplate } from "../../generated/templates";
import { BigInt } from "@graphprotocol/graph-ts";
import { getDefaultTokenId } from "../common/getTokenId";
import { TOKEN_STANDARD_ERC721 } from "../constants/tokenStandard";
import { getContractId } from "../common/getContractId";
import {
  extractIPFSIDFromContract,
  loadMetadataInfoFromID,
} from "../common/metadata";

export function handleFactoryUpgraded(event: Upgraded): void {
  const upgrade = new Upgrade(
    `${event.transaction.hash.toHex()}-${event.transactionLogIndex}`
  );
  const factory = new ZoraCreate721Factory(event.address.toHex());
  const creator = ZoraNFTCreatorV1.bind(event.address);

  if (creator.try_dropMetadataRenderer().reverted) {
    return;
  }
  const dropRendererAddress = creator.dropMetadataRenderer();

  if (creator.try_editionMetadataRenderer().reverted) {
    return;
  }
  const editionRendererAddress = creator.editionMetadataRenderer();

  DropMetadataRendererFactory.create(dropRendererAddress);
  EditionMetadataRendererFactory.create(editionRendererAddress);

  if (!KnownRenderer.load(dropRendererAddress.toHex())) {
    const knownDropRenderer = new KnownRenderer(dropRendererAddress.toHex());
    const txn = makeTransaction(event);
    knownDropRenderer.txn = txn;
    knownDropRenderer.address = dropRendererAddress;
    knownDropRenderer.block = event.block.number;
    knownDropRenderer.timestamp = event.block.timestamp;
    knownDropRenderer.isEdition = false;

    knownDropRenderer.save();
  }

  if (!KnownRenderer.load(editionRendererAddress.toHex())) {
    const knownEditionRenderer = new KnownRenderer(
      editionRendererAddress.toHex()
    );
    const txn = makeTransaction(event);

    knownEditionRenderer.txn = txn;
    knownEditionRenderer.address = dropRendererAddress;
    knownEditionRenderer.block = event.block.number;
    knownEditionRenderer.timestamp = event.block.timestamp;
    knownEditionRenderer.address = editionRendererAddress;

    knownEditionRenderer.isEdition = true;
    knownEditionRenderer.save();
  }

  const txn = makeTransaction(event);

  upgrade.txn = txn;
  upgrade.block = event.block.number;
  upgrade.timestamp = event.block.timestamp;
  upgrade.impl = event.params.implementation;
  upgrade.address = event.address;
  upgrade.type = "721Factory";

  factory.txn = txn;
  factory.block = event.block.number;
  factory.timestamp = event.block.timestamp;
  factory.address = event.address;

  factory.dropMetadataRendererFactory = creator.dropMetadataRenderer();
  factory.editionMetadataRendererFactory = creator.editionMetadataRenderer();
  factory.implementation = event.params.implementation;
  factory.version = creator.contractVersion().toString();

  upgrade.save();
  factory.save();
}

export function handleCreatedDrop(event: CreatedDrop): void {
  const dropAddress = event.params.editionContractAddress;
  const dropContract = ERC721DropContract.bind(dropAddress);

  const createdContract = new ZoraCreateContract(getContractId(dropAddress));
  createdContract.contractVersion = dropContract.contractVersion().toString();
  const dropConfig = dropContract.config();

  // setup royalties
  const royalties = new RoyaltyConfig(dropAddress.toHex());
  royalties.royaltyRecipient = dropConfig.getFundsRecipient();
  royalties.royaltyMintSchedule = BigInt.zero();
  royalties.contract = getContractId(dropAddress);
  royalties.tokenId = BigInt.zero();
  royalties.royaltyBPS = BigInt.fromU64(dropConfig.getRoyaltyBPS());
  royalties.user = event.params.creator;
  royalties.save();

  createdContract.contractStandard = TOKEN_STANDARD_ERC721;
  const contractURIResponse = dropContract.try_contractURI();
  if (!contractURIResponse.reverted) {
    createdContract.contractURI = contractURIResponse.value;
  }
  createdContract.creator = event.params.creator;
  createdContract.initialDefaultAdmin = event.params.creator;
  createdContract.owner = dropContract.owner();
  createdContract.name = dropContract.name();
  createdContract.symbol = dropContract.symbol();
  createdContract.contractVersion = dropContract.contractVersion().toString();
  createdContract.rendererContract = dropContract.metadataRenderer();

  const knownRenderer = KnownRenderer.load(
    dropConfig.getMetadataRenderer().toHex()
  );
  if (knownRenderer) {
    createdContract.likelyIsEdition = knownRenderer.isEdition;
  }

  const feePerAmount = dropContract.try_zoraFeeForAmount(BigInt.fromI64(1));
  if (feePerAmount.reverted) {
    createdContract.mintFeePerQuantity = BigInt.zero();
  }
  createdContract.mintFeePerQuantity = feePerAmount.value.getFee();

  createdContract.metadataIPFSID =
    extractIPFSIDFromContract(contractURIResponse);
  createdContract.metadata = loadMetadataInfoFromID(
    createdContract.metadataIPFSID
  );

  if (!contractURIResponse.reverted) {
    const ipfsHostPath = getIPFSHostFromURI(contractURIResponse.value);
    if (ipfsHostPath !== null) {
      createdContract.metadata = ipfsHostPath;
    }
  }
  const txn = makeTransaction(event);
  createdContract.timestamp = event.block.timestamp;
  createdContract.block = event.block.number;
  createdContract.address = dropAddress;
  createdContract.txn = txn;
  createdContract.createdAtBlock = event.block.number;

  createdContract.save();

  // create token from contract
  const createTokenId = getDefaultTokenId(dropAddress);
  const newToken = new ZoraCreateToken(createTokenId);

  newToken.holders1155Number = new BigInt(0);
  newToken.address = dropAddress;
  newToken.rendererContract = createdContract.rendererContract;
  newToken.totalSupply = BigInt.zero();
  newToken.maxSupply = event.params.editionSize;
  newToken.totalMinted = BigInt.zero();
  newToken.contract = getContractId(dropAddress);
  newToken.tokenId = BigInt.zero();
  newToken.creator = event.params.creator;

  newToken.txn = txn;
  newToken.timestamp = event.block.timestamp;
  newToken.address = event.address;
  newToken.block = event.block.number;

  newToken.createdAtBlock = event.block.number;
  newToken.tokenStandard = TOKEN_STANDARD_ERC721;
  newToken.save();

  ERC721DropTemplate.create(dropAddress);
}
