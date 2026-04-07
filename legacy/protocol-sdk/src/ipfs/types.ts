export type CreateERC1155TokenAttributes = {
  trait_type: string;
  value: string;
};

export type ContractMetadataJson = {
  name?: string;
  description?: string;
  image?: string;
};

export type TokenMetadataJson = {
  name: string;
  description?: string;
  /** Primary image file */
  image?: string;
  animation_url?: string | null;
  content?: {
    mime: string;
    uri: string;
  } | null;
  attributes: Array<CreateERC1155TokenAttributes>;
};

export type BaseMetadataParams = {
  /** Token name */
  name: string;
  /** Optional description */
  description?: string;
  /** Optional attributes to tag the token with */
  attributes?: CreateERC1155TokenAttributes[];
};

export type MakeTextMetadataParams = BaseMetadataParams & {
  /** Ipfs url where media is hosted */
  textFileUrl: string;
  /** If thumbnail was generate for text file, thumbnail image url */
  thumbnailUrl?: string;
};

export type TextMetadataFiles = {
  name: string;
  /** File that holds the text, and is the primary media */
  mediaUrlFile: File;
  /** Thumbnail image preview of the text */
  thumbnailFile: File;
};

export type MakeMediaMetadataParams = BaseMetadataParams & {
  /** Ipfs url where media is hosted */
  mediaUrl: string;
  /** Ipfs url where thumbnail of media is hosted */
  thumbnailUrl?: string;
};
