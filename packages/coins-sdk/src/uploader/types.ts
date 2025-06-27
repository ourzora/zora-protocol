/**
 * Result from uploading a file to a storage provider
 */
export type UploadResult = {
  url: string;
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
