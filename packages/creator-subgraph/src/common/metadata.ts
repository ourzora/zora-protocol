import { ethereum } from "@graphprotocol/graph-ts";
import { getIPFSHostFromURI } from "./getIPFSHostFromURI";
import { MetadataInfo as MetadataInfoTemplate } from "../../generated/templates";

export function extractIPFSIDFromContract(
  result: ethereum.CallResult<string>
): string | null {
  if (result.reverted) {
    return null;
  }
  return getIPFSHostFromURI(result.value);
}

export function loadMetadataInfoFromID(id: string | null): string | null {
  if (id !== null) {
    MetadataInfoTemplate.create(id);
  }

  return id;
}
