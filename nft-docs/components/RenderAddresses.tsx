import * as chains from "viem/chains";

function getChainById(id: string) {
  if (id === "999") {
    return {
      ...chains.zoraTestnet,
      name: "Zora Goerli Testnet (Deprecated)",
    };
  }
  return Object.values(chains).find((chain) => `${chain.id}` === id);
}

const CONTRACT_INFO_BY_TYPE_BY_NAME = {
  "1155": {
    CONTRACT_1155_IMPL: "Current 1155 Implementation",
    ERC20_MINTER: "ERC20 Dynamic Minter Module",
    FACTORY_IMPL: "Current 1155 Factory Implementation",
    FACTORY_PROXY: "1155 Factory (Proxy) Address",
    FIXED_PRICE_SALE_STRATEGY: "Fixed Price Minter Module",
    MERKLE_MINT_SALE_STRATEGY: "Merkle Allowlist Minter Module",
    PREMINTER_IMPL: "Current Preminter Implementation",
    PREMINTER_PROXY: "1155 Preminter (Proxy) Address",
    REDEEM_MINTER_FACTORY: "Redemption Minter Factory Address (Deprecated)",
    UPGRADE_GATE: "Contract Version Upgrade Gate",
  },
};

type SourcesType = Record<string, Record<string, string>>;

export const RenderAddresses = ({ sources, type }: {sources: SourcesType, type: keyof typeof CONTRACT_INFO_BY_TYPE_BY_NAME}) => {
  let result = [];
  for (const [chainId, deployments] of Object.entries(sources)) {
    const chain = getChainById(chainId);
    result.push(
      <tr className="vocs_TableRow" key={chainId}>
        <td colSpan={2} className="vocs_TableCell vocs_H2 vocs_Heading">
          {chain?.name} ({chainId})
        </td>
      </tr>,
    );
    for (const [contract, address] of Object.entries(deployments as any)) {
      if (contract === "timestamp" || contract.endsWith("_VERSION")) {
        continue;
      }
      const contractInfo = (CONTRACT_INFO_BY_TYPE_BY_NAME[type] as any)?.[contract];
      result.push(
        <tr className="vocs_TableRow" key={`${contract}-${address}`}>
          <td className="vocs_TableCell ">
            <div>{contract}</div>
            {contractInfo && <div>{contractInfo}</div>}
          </td>
          <td className="vocs_TableCell">
            <a
              className="vocs_Anchor vocs_Link vocs_Link_accent_underlined vocs_ExternalLink"
              style={{
                "--vocs_ExternalLink_iconUrl":
                  "url(/.vocs/icons/arrow-diagonal.svg)",
                fontFamily: "var(--vocs-fontFamily_mono)",
                fontSize: "0.9em",
              } as any}
              target="_blank"
              href={
                chain
                  ? `${chain?.blockExplorers?.default.url || ""}/address/${address}`
                  : ""
              }
            >{`${address}`}</a>
          </td>
        </tr>,
      );
    }
  }
  return <table className="vocs_Table">{result}</table>;
};
