import { MetadataUpdated } from "../../../generated/templates/DropMetadataRenderer/DropMetadataRenderer";
import {
  DropMetadata,
  OnChainMetadataHistory,
  ZoraCreateContract,
} from "../../../generated/schema";
import { MetadataInfo as MetadataInfoTemplate } from "../../../generated/templates";
import { getDefaultTokenId } from "../../common/getTokenId";
import { makeTransaction } from "../../common/makeTransaction";
import { METADATA_ERC721_DROP } from "../../constants/metadataHistoryTypes";
import { getOnChainMetadataKey } from "../../common/getOnChainMetadataKey";
import { getIPFSHostFromURI } from "../../common/getIPFSHostFromURI";

export function handleMetadataUpdated(event: MetadataUpdated): void {
  const metadata = new DropMetadata(getOnChainMetadataKey(event));
  metadata.contractURI = event.params.contractURI;
  metadata.extension = event.params.metadataExtension;
  metadata.base = event.params.metadataBase;
  metadata.freezeAt = event.params.freezeAt;
  metadata.save();

  const metadataCompat = new DropMetadata(event.params.target.toHex());
  metadataCompat.contractURI = event.params.contractURI;
  metadataCompat.extension = event.params.metadataExtension;
  metadataCompat.base = event.params.metadataBase;
  metadataCompat.freezeAt = event.params.freezeAt;
  metadataCompat.save();

  const metadataLinkHistorical = new OnChainMetadataHistory(
    getOnChainMetadataKey(event)
  );
  metadataLinkHistorical.rendererAddress = event.address;
  metadataLinkHistorical.createdAtBlock = event.block.number;
  metadataLinkHistorical.dropMetadata = metadata.id;
  metadataLinkHistorical.tokenAndContract = getDefaultTokenId(
    event.params.target
  );

  const txn = makeTransaction(event);
  metadataLinkHistorical.txn = txn;
  metadataLinkHistorical.block = event.block.number;
  metadataLinkHistorical.timestamp = event.block.timestamp;
  metadataLinkHistorical.address = event.address;

  metadataLinkHistorical.knownType = METADATA_ERC721_DROP;
  metadataLinkHistorical.save();

  // update contract uri
  const contract = ZoraCreateContract.load(event.params.target.toHex());
  if (contract) {
    contract.contractURI = event.params.contractURI;

    // Update overall contract object uri from metadata path
    if (contract.contractURI) {
      const ipfsHostPath = getIPFSHostFromURI(contract.contractURI);
      if (ipfsHostPath !== null) {
        contract.metadata = ipfsHostPath;
        MetadataInfoTemplate.create(ipfsHostPath);
      }
    }

    contract.save();
  }
}
