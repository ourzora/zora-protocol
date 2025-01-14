import { collection, uid } from "./createPremint";
import { useAccount, usePublicClient, useWriteContract } from "wagmi";
import { mint } from "@zoralabs/protocol-sdk";

const publicClient = usePublicClient()!;
const { address } = useAccount();

const { parameters } = await mint({
  tokenContract: collection,
  mintType: "premint",
  uid,
  quantityToMint: 3,
  minterAccount: address!,
  // mintReferral address will get mint referral reward
  mintReferral: "0x64B585fabf03B932D637B15112cDa02C77b5cef9",
  publicClient,
});

const { writeContract } = useWriteContract();

writeContract(parameters);
