import { ContractMetadataJson } from "@zoralabs/protocol-sdk";
import { pinFileWithPinata, pinJsonWithPinata } from "./pinata";

export async function makeContractMetadata({
  imageFile,
  name,
  description,
}: {
  imageFile: File;
  name: string;
  description?: string;
}) {
  // upload image to Pinata
  const imageFileIpfsUrl = await pinFileWithPinata(imageFile);

  // build contract metadata json
  const metadataJson: ContractMetadataJson = {
    description,
    image: imageFileIpfsUrl,
    name,
  };

  // upload token metadata json to Pinata and get ipfs uri
  const contractMetadataJsonUri = await pinJsonWithPinata(metadataJson);

  return contractMetadataJsonUri;
}
