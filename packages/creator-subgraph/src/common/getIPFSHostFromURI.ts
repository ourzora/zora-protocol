export function getIPFSHostFromURI(uri: string | null): string | null {
  if (uri !== null && uri.startsWith("ipfs://")) {
    // Removes query string which is invalid in IPFS urls (added by 721 metadata contracts)
    return uri.replace("ipfs://", "").split('?', 1)[0];
  }
  return null;
}