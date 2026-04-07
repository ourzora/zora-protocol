import {
  generateTextNftMetadataFiles,
  makeTextTokenMetadata,
} from "@zoralabs/protocol-sdk";
import { pinFileWithPinata, pinJsonWithPinata } from "./pinata";

export async function makeTextNftMetadata({ text }: { text: string }) {
  // call the sdk helper method to build the files
  // needed for a text based nft
  const {
    name,
    // file containing the text
    mediaUrlFile,
    // generated thumbnail image from the text
    thumbnailFile,
  } = await generateTextNftMetadataFiles(text);

  // upload text file and thumbnail to ipfs with Pinata
  const mediaFileIpfsUrl = await pinFileWithPinata(mediaUrlFile);
  const thumbnailFileIpfsUrl = await pinFileWithPinata(thumbnailFile);

  // build token metadata json from the text and thumbnail file
  // ipfs urls
  const metadataJson = makeTextTokenMetadata({
    name,
    textFileUrl: mediaFileIpfsUrl,
    thumbnailUrl: thumbnailFileIpfsUrl,
  });
  // convert json object to json file
  const jsonMetadataUri = await pinJsonWithPinata(metadataJson);

  return jsonMetadataUri;
}
