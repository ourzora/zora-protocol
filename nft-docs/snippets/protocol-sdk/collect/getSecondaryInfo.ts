import { getSecondaryInfo } from "@zoralabs/protocol-sdk";
import { usePublicClient } from "wagmi";

const publicClient = usePublicClient()!;

const secondaryInfo = await getSecondaryInfo({
  contract: "0xd42557f24034b53e7340a40bb5813ef9ba88f2b4",
  tokenId: 4n,
  publicClient,
});

// -- cut --
secondaryInfo;
