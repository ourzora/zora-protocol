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
 * Options for file upload operations
 */
export type UploadOptions = {
  /** AbortSignal to cancel the upload */
  signal?: AbortSignal;
  /** Timeout in milliseconds for the upload request (no default) */
  timeout?: number;
};

/**
 * Interface for file uploaders (IPFS, Arweave, etc.)
 */
export interface Uploader {
  upload(file: File, options?: UploadOptions): Promise<UploadResult>;
}

export type CreateMetadataParameters = {
  name: string;
  symbol: string;
  metadata: {
    type: "RAW_URI";
    uri: ValidMetadataURI;
  };
};
