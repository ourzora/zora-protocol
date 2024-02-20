import {
  SetupNewContract,
  Upgraded,
  ZoraCreator1155FactoryImpl,
} from "../../generated/ZoraNFTCreatorFactory1155V1/ZoraCreator1155FactoryImpl";

import {
  Upgrade,
  ZoraCreate1155Factory,
  ZoraCreateContract,
} from "../../generated/schema";
import {
  ZoraCreator1155Impl as ZoraCreator1155ImplTemplate,
  MetadataInfo as MetadataInfoTemplate,
  ZoraCreatorFixedPriceSaleStrategy,
  ZoraCreatorMerkleMinterStrategy,
  ZoraCreatorRedeemMinterFactory,
} from "../../generated/templates";
import { makeTransaction } from "../common/makeTransaction";
import { getIPFSHostFromURI } from "../common/getIPFSHostFromURI";
import { TOKEN_STANDARD_ERC1155 } from "../constants/tokenStandard";
import { ZoraCreator1155Impl } from "../../generated/templates/ZoraCreator1155Impl/ZoraCreator1155Impl";
import { getContractId } from "../common/getContractId";
import {
  extractIPFSIDFromContract,
  loadMetadataInfoFromID,
} from "../common/metadata";
import { BigInt } from "@graphprotocol/graph-ts";

export function handleNewContractCreated(event: SetupNewContract): void {
  const createdContract = new ZoraCreateContract(
    getContractId(event.params.newContract)
  );

  createdContract.address = event.params.newContract;
  createdContract.contractStandard = TOKEN_STANDARD_ERC1155;
  createdContract.contractURI = event.params.contractURI;

  // The creator being msg.sender cannot be guaranteed for premint 
  createdContract.creator = event.params.defaultAdmin;

  createdContract.initialDefaultAdmin = event.params.defaultAdmin;
  createdContract.owner = event.params.defaultAdmin;
  createdContract.name = event.params.name;
  createdContract.symbol = null;
  createdContract.contractVersion = createdContract.contractVersion;
  createdContract.rendererContract = createdContract.rendererContract;

  const ipfsHostPath = getIPFSHostFromURI(event.params.contractURI);
  if (ipfsHostPath !== null) {
    createdContract.metadata = ipfsHostPath;
    MetadataInfoTemplate.create(ipfsHostPath);
  }

  const txn = makeTransaction(event);
  createdContract.txn = txn;
  createdContract.block = event.block.number;
  createdContract.address = event.params.newContract;
  createdContract.timestamp = event.block.timestamp;

  createdContract.createdAtBlock = event.block.number;

  // query for more information about contract
  const impl = ZoraCreator1155Impl.bind(event.params.newContract);

  // temporary fix: testnet deploy temporarily removed this function
  const attemptMintFee = impl.try_mintFee();
  if (attemptMintFee.reverted) {
    createdContract.mintFeePerQuantity = BigInt.fromI64(777000000000000);
  } else {
    createdContract.mintFeePerQuantity = attemptMintFee.value;
  }
  createdContract.contractVersion = impl.contractVersion();
  createdContract.contractStandard = TOKEN_STANDARD_ERC1155;

  createdContract.metadataIPFSID = extractIPFSIDFromContract(
    impl.try_contractURI()
  );
  createdContract.metadata = loadMetadataInfoFromID(
    createdContract.metadataIPFSID
  );

  createdContract.save();

  ZoraCreator1155ImplTemplate.create(event.params.newContract);
}

export function handle1155FactoryUpgraded(event: Upgraded): void {
  const upgrade = new Upgrade(
    `${event.transaction.hash.toHex()}-${event.transactionLogIndex}`
  );
  const factory = new ZoraCreate1155Factory(event.address.toHex());
  const creator = ZoraCreator1155FactoryImpl.bind(event.address);

  // Handle bad upgrade, do not remove.
  if (creator.try_fixedPriceMinter().reverted) {
    return;
  }

  // Create child factory listeners
  ZoraCreatorFixedPriceSaleStrategy.create(creator.fixedPriceMinter());
  ZoraCreatorMerkleMinterStrategy.create(creator.merkleMinter());

  // Check if this version supports the redeem factory
  const redeemFactory = creator.try_redeemMinterFactory();
  if (!redeemFactory.reverted) {
    ZoraCreatorRedeemMinterFactory.create(redeemFactory.value);
    factory.redeemMinterStrategyAddress = redeemFactory.value;
  }

  const txn = makeTransaction(event);
  upgrade.txn = txn;
  upgrade.block = event.block.number;
  upgrade.timestamp = event.block.timestamp;
  upgrade.impl = event.params.implementation;
  upgrade.address = event.address;
  upgrade.type = "1155Factory";

  // Save required factories.
  factory.txn = txn;
  factory.block = event.block.number;
  factory.timestamp = event.block.timestamp;

  factory.fixedPriceSaleStrategyAddress = creator.fixedPriceMinter();
  factory.merkleSaleStrategyAddress = creator.merkleMinter();
  factory.implementation = event.params.implementation;
  factory.version = creator.contractVersion();

  upgrade.save();
  factory.save();
}
