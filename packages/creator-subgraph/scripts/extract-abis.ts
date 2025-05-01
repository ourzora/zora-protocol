import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import {
  zoraCreator1155FactoryImplABI,
  zoraCreator1155ImplABI,
  zoraCreator1155PremintExecutorImplABI,
  zoraCreatorFixedPriceSaleStrategyABI,
  zoraCreatorMerkleMinterStrategyABI,
  zoraCreatorRedeemMinterFactoryABI,
  zoraCreatorRedeemMinterStrategyABI,
  protocolRewardsABI,
  erc20MinterABI,
} from "@zoralabs/zora-1155-contracts";
import { zoraTimedSaleStrategyImplABI } from "@zoralabs/erc20z";
import {
  zoraMints1155ABI,
  zoraMintsManagerImplABI,
  zoraSparks1155ABI,
} from "@zoralabs/sparks-contracts";
import {
  cointagFactoryImplABI,
  cointagImplABI as cointagABI,
} from "@zoralabs/cointags-contracts";
import { commentsImplABI } from "@zoralabs/comments-contracts";

// Import JSON files
import erc721DropJSON from "@zoralabs/nft-drop-contracts/dist/artifacts/ERC721Drop.sol/ERC721Drop.json";
import zoraNFTCreatorV1JSON from "@zoralabs/nft-drop-contracts/dist/artifacts/ZoraNFTCreatorV1.sol/ZoraNFTCreatorV1.json";
import editionMetadataRendererJSON from "@zoralabs/nft-drop-contracts/dist/artifacts/EditionMetadataRenderer.sol/EditionMetadataRenderer.json";
import dropMetadataRendererJSON from "@zoralabs/nft-drop-contracts/dist/artifacts/DropMetadataRenderer.sol/DropMetadataRenderer.json";

// Extract ABIs from JSON imports
const erc721Drop = erc721DropJSON.abi;
const zoraNFTCreatorV1 = zoraNFTCreatorV1JSON.abi;
const editionMetadataRenderer = editionMetadataRendererJSON.abi;
const dropMetadataRenderer = dropMetadataRendererJSON.abi;

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const abisPath = path.join(__dirname, "..", "abis");
if (!fs.existsSync(abisPath)) {
  fs.mkdirSync(abisPath);
}

function output_abi(abiName: string, abi: any): void {
  fs.writeFileSync(
    path.join(abisPath, `${abiName}.json`),
    JSON.stringify(abi, null, 2),
  );
}

output_abi("ERC721Drop", erc721Drop);
output_abi("ZoraNFTCreatorV1", zoraNFTCreatorV1);
output_abi("EditionMetadataRenderer", editionMetadataRenderer);
output_abi("DropMetadataRenderer", dropMetadataRenderer);

output_abi("ZoraCreator1155FactoryImpl", zoraCreator1155FactoryImplABI);
output_abi("ZoraCreator1155Impl", zoraCreator1155ImplABI);
output_abi(
  "ZoraCreator1155PremintExecutorImpl",
  zoraCreator1155PremintExecutorImplABI,
);
output_abi(
  "ZoraCreatorFixedPriceSaleStrategy",
  zoraCreatorFixedPriceSaleStrategyABI,
);
output_abi(
  "ZoraCreatorMerkleMinterStrategy",
  zoraCreatorMerkleMinterStrategyABI,
);
output_abi("ZoraCreatorRedeemMinterFactory", zoraCreatorRedeemMinterFactoryABI);
output_abi(
  "ZoraCreatorRedeemMinterStrategy",
  zoraCreatorRedeemMinterStrategyABI,
);
output_abi("ZoraTimedSaleStrategy", zoraTimedSaleStrategyImplABI);

output_abi("ProtocolRewards", protocolRewardsABI);

output_abi("ZoraMints1155", zoraMints1155ABI);
output_abi("ZoraMintsManagerImpl", zoraMintsManagerImplABI);
output_abi("ZoraSparks1155", zoraSparks1155ABI);

output_abi("ERC20Minter", erc20MinterABI);

output_abi("Comments", commentsImplABI);
output_abi("CointagFactory", cointagFactoryImplABI);
output_abi("Cointag", cointagABI);
