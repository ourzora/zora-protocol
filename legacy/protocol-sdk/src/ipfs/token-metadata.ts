import { getFetchableUrl } from "./gateway";
import {
  DEFAULT_THUMBNAIL_CID_HASHES,
  TEXT_PLAIN,
  getMimeType,
  isImage,
  mimeTypeToMedia,
} from "./mimeTypes";
import {
  MakeMediaMetadataParams,
  MakeTextMetadataParams,
  TokenMetadataJson,
} from "./types";

/**
 * Takes properties for a text based nft and formats it as proper json metadata
 * for the token, which should be uploaded to IPFS.
 * @param parameters - The parameters to format into metadata {@link MakeTextMetadataParams}
 */
export const makeTextTokenMetadata = (
  parameters: MakeTextMetadataParams,
): TokenMetadataJson => {
  const { name, textFileUrl, thumbnailUrl, attributes = [] } = parameters;

  const content = textFileUrl
    ? {
        mime: TEXT_PLAIN,
        uri: textFileUrl,
      }
    : null;

  const image = thumbnailUrl;
  const animation_url = textFileUrl;

  return {
    name,
    image,
    animation_url,
    content,
    attributes,
  };
};

/**
 * Takes properties for a media based nft (video, image, etc) and formats it as proper json metadata
 * for the token, which should be uploaded to IPFS.
 * @param parameters - The parameters to format into metadata {@link MakeMediaMetadataParams}
 */
export const makeMediaTokenMetadata = async ({
  name,
  description,
  attributes = [],
  mediaUrl,
  thumbnailUrl,
}: MakeMediaMetadataParams): Promise<TokenMetadataJson> => {
  const contentUrl = mediaUrl;
  const fetchableContentUrl = getFetchableUrl(contentUrl);

  if (!fetchableContentUrl)
    throw new Error(`Content url (${contentUrl}) is not fetchable`);

  const mimeType = await getMimeType(fetchableContentUrl);
  const mediaType = mimeTypeToMedia(mimeType);

  let image: string | undefined = undefined;
  let animation_url: string | null = null;

  // If the media is an image, just set the image field
  // Otherwise we require a thumbnail, set image and animation_url
  if (isImage(mimeType)) {
    image = contentUrl;
  } else {
    image = thumbnailUrl;
    animation_url = mediaUrl;
  }

  // If no image determined, use a fallback placeholder
  if (!image)
    image = `ipfs://${
      DEFAULT_THUMBNAIL_CID_HASHES[mediaType] ||
      DEFAULT_THUMBNAIL_CID_HASHES.default
    }`;

  const content = contentUrl
    ? {
        mime: mimeType || "application/octet-stream",
        uri: contentUrl,
      }
    : null;

  return {
    name,
    description,
    image,
    animation_url,
    content,
    attributes,
  };
};

export async function fetchTokenMetadata(tokenMetadataURI: string) {
  const fetchableUrl = getFetchableUrl(tokenMetadataURI);

  if (!fetchableUrl) {
    throw new Error(`Invalid token metadata URI: ${tokenMetadataURI}`);
  }

  const json = (await (await fetch(fetchableUrl)).json()) as
    | TokenMetadataJson
    | undefined;

  if (!json) {
    throw new Error(`Failed to fetch metadata from ${fetchableUrl}`);
  }

  return json;
}
