import { Address } from "viem";
import { readFile } from "fs/promises";

export const getCommentsAddress = async (chainId: number) => {
  const addresses = await readFile(`./addresses/${chainId}.json`, "utf8");

  return JSON.parse(addresses) as {
    COMMENTS: Address;
  };
};
