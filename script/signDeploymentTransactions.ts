import { createAccount } from "@turnkey/viem";
import { TurnkeyClient } from "@turnkey/http";
import { createPublicClient, http } from "viem";
import { zoraTestnet } from "viem/chains";
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
import { getDeployFactoryProxyDeterminsticTx } from '../package/deployment';
import { testConfig } from "../package/deploymentConfig";
import * as path from "path";
import * as dotenv from "dotenv";

// Load environment variables from `.env.local`
dotenv.config({ path: path.resolve(process.cwd(), "../.env") });

async function main() {
  const publicClient = createPublicClient({
    chain: zoraTestnet,
    transport: http()
  });

  // Create a Turnkey HTTP client with API key credentials
  const httpClient = new TurnkeyClient(
    {
      baseUrl: "https://api.turnkey.com",
    },
    // This uses API key credentials.
    // If you're using passkeys, use `@turnkey/webauthn-stamper` to collect webauthn signatures:
    // new WebauthnStamper({...options...})
    new ApiKeyStamper({
      apiPublicKey: process.env.API_PUBLIC_KEY!,
      apiPrivateKey: process.env.API_PRIVATE_KEY!,
    })
  );

  // Create the Viem custom account
  const turnkeyAccount = await createAccount({
    client: httpClient,
    organizationId: "f7e5bec5-b7f9-486a-a8c3-cd1ec7362709",
    privateKeyId: "3e3c5029-7ad7-4559-936f-93d21763143b",
    // optional; will be fetched from Turnkey if not provided
    ethereumAddress: "0x4F9991C82C76aE04CC39f23aB909AA919886ba12"
  });

  const { createTransaction, initializeTx } = await getDeployFactoryProxyDeterminsticTx({
    account: turnkeyAccount,
    determinsticDeploymentConfig: testConfig,
    factoryImplAddress: "0xf76aFcB896AA18864D7EC4dfe0445E385688843A",
    factoryOwner: "0xE84DBB2B25F761751231a9D0DAfbdD4dC3aa8252",
    // @ts-ignore
    publicClient
  });

  console.log({ createTransaction, initializeTx });
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});