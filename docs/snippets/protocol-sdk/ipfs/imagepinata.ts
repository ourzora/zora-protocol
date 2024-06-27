import { makeMediaTokenMetadata } from "@zoralabs/protocol-sdk";
import { pinFileWithPinata, pinJsonWithPinata } from "./pinata";

export async function makeImageTokenMetadata({
  imageFile,
  thumbnailFile,
}: {
  imageFile: File;
  thumbnailFile: File;
}) {
  // upload image and thumbnail to Pinata
  const mediaFileIpfsUrl = await pinFileWithPinata(imageFile);
  const thumbnailFileIpfsUrl = await pinFileWithPinata(thumbnailFile);

  // build token metadata json from the text and thumbnail file
  // ipfs urls
  const metadataJson = makeMediaTokenMetadata({
    mediaUrl: mediaFileIpfsUrl,
    thumbnailUrl: thumbnailFileIpfsUrl,
    name: imageFile.name,
  });
  // upload token metadata json to Pinata and get ipfs uri
  const jsonMetadataUri = await pinJsonWithPinata(metadataJson);

  return jsonMetadataUri;
}
