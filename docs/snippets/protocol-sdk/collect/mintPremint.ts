import { mint } from "@zoralabs/protocol-sdk";
import { collection, uid } from "./createPremint";
import { usePublicClient, useWriteContract } from "wagmi";

const publicClient = usePublicClient()!;

// get parameters to mint a premint, which can be used to simulate and submit the transaction
const { parameters } = await mint({
  // the deterministic premint collection address
  tokenContract: collection,
  // type of item to mint
  mintType: "premint", // [!code hl]
  // the uid of the premint to mint
  uid, // [!code hl]
  // how many tokens to mint
  quantityToMint: 3,
  // Comment to attach to the mint
  mintComment: "Mint comment",
  // the account to execute the transaction
  minterAccount: "0xf69fEc6d858c77e969509843852178bd24CAd2B6",
  publicClient,
});

const { writeContract } = useWriteContract();

writeContract(parameters);
