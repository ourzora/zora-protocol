export function getIPFSHostFromURI(uri: string | null): string | null {
  if (uri !== null && uri.startsWith("ipfs://")) {
    return uri.replace("ipfs://", "");
  }
  return null;
}