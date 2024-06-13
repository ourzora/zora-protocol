import { collection, uid } from "./createPremint";
import {
  useAccount,
  useChainId,
  usePublicClient,
  useWriteContract,
} from "wagmi";
import { createCollectorClient } from "@zoralabs/protocol-sdk";

const chainId = useChainId();
const publicClient = usePublicClient()!;
const { address } = useAccount();

const collectorClient = createCollectorClient({ chainId, publicClient });

const { parameters } = await collectorClient.mint({
  tokenContract: collection,
  mintType: "premint",
  uid,
  quantityToMint: 3,
  minterAccount: address!,
  // mintReferral address will get mint referral reward // [!code hl]
  mintReferral: "0x64B585fabf03B932D637B15112cDa02C77b5cef9", // [!code hl]
});

const { writeContract } = useWriteContract();

writeContract(parameters);
