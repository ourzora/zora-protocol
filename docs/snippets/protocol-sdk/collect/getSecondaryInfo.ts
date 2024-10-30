import { createCollectorClient } from "@zoralabs/protocol-sdk";
import { useChainId, usePublicClient } from "wagmi";

const chainId = useChainId();
const publicClient = usePublicClient()!;

const collectorClient = createCollectorClient({ chainId, publicClient });

const secondaryInfo = await collectorClient.getSecondaryInfo({
  contract: "0xd42557f24034b53e7340a40bb5813ef9ba88f2b4",
  tokenId: 4n,
});

// -- cut --
secondaryInfo;
