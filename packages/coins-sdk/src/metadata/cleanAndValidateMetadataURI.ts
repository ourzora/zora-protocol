export type ValidMetadataURI =
  | `ipfs://${string}`
  | `ar://${string}`
  | `data:${string}`
  | `https://${string}`;

/**
 * Clean the metadata URI to HTTPS format
 * @param metadataURI - The metadata URI to clean from IPFS or Arweave
 * @returns The cleaned metadata URI
 * @throws If the metadata URI is a data URI
 */
export function cleanAndValidateMetadataURI(uri: ValidMetadataURI) {
  if (uri.startsWith("ipfs://")) {
    return uri.replace(
      "ipfs://",
      "https://magic.decentralized-content.com/ipfs/",
    );
  }
  if (uri.startsWith("ar://")) {
    return uri.replace("ar://", "http://arweave.net/");
  }
  if (uri.startsWith("data:")) {
    throw new Error("Data URIs are not supported");
  }
  if (uri.startsWith("http://") || uri.startsWith("https://")) {
    return uri;
  }

  throw new Error("Invalid metadata URI");
}
