#!/usr/bin/env tsx
import { Hex, Address } from "viem";
import { loadTurnkeyAccount } from "./turnkey.js";

const loadParameters = () => {
  const [, , chainId, salt, creationCode, init, deployerAddress] = process.argv;

  // check that all arguments are present
  if (!chainId || !salt || !creationCode || !init || !deployerAddress) {
    throw new Error("missing arguments");
  }

  return {
    chainId: +chainId,
    salt: salt as Hex,
    creationCode: creationCode as Hex,
    init: init as Hex,
    deployerAddress: deployerAddress as Address,
  };
};

/// Deploy the mints manager and 1155 contract deteriministically using turnkey
async function main() {
  const parameters = loadParameters();

  const turnkeyAccount = await loadTurnkeyAccount();

  // "create(bytes32 salt,bytes code,bytes postCreateCall,uint256 postCreateCallValue)");
  const signature = await turnkeyAccount.signTypedData({
    types: {
      create: [
        { name: "salt", type: "bytes32" },
        { name: "code", type: "bytes" },
        { name: "postCreateCall", type: "bytes" },
      ],
    },
    primaryType: "create",
    message: {
      code: parameters.creationCode,
      salt: parameters.salt,
      postCreateCall: parameters.init,
    },
    domain: {
      chainId: parameters.chainId,
      name: "DeterministicDeployerAndCaller",
      version: "1",
      verifyingContract: parameters.deployerAddress,
    },
  });

  console.log(signature);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
