export type ValidMetadataURI =
  | `ipfs://${string}`
  | `ar://${string}`
  | `data:${string}`
  | `https://${string}`;

/**
 * Result from uploading a file to a storage provider
 */
export type UploadResult = {
  url: ValidMetadataURI;
  size: number | undefined;
  mimeType: string | undefined;
};

/**
 * Interface for file uploaders (IPFS, Arweave, etc.)
 */
export interface Uploader {
  upload(file: File): Promise<UploadResult>;
}

export type CreateMetadataParameters = {
  name: string;
  symbol: string;
  uri: `ipfs://${string}`;
};
