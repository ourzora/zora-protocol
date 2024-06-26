import { createAccount } from "@turnkey/viem";
import { TurnkeyClient } from "@turnkey/http";
import { ApiKeyStamper } from "@turnkey/api-key-stamper";
import { fileURLToPath } from "url";
import dotenv from "dotenv";
import { dirname } from "path";
import path from "path";
import { createWalletClient } from "viem";

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Load environment variables from `.env.local`
dotenv.config({ path: path.resolve(__dirname, "../.env") });

async function main() {
  // Create a Turnkey HTTP client with API key credentials
  const httpClient = new TurnkeyClient(
    {
      baseUrl: "https://api.turnkey.com",
    },
    // This uses API key credentials.
    // If you're using passkeys, use `@turnkey/webauthn-stamper` to collect webauthn signatures:
    new ApiKeyStamper({
      apiPublicKey: process.env.TURNKEY_API_PUBLIC_KEY!,
      apiPrivateKey: process.env.TURNKEY_API_PRIVATE_KEY!,
    }),
  );

  console.log("has client", httpClient);

  // Create the Viem custom account
  const turnkeyAccount = await createAccount({
    client: httpClient,
    organizationId: process.env.TURNKEY_ORGANIZATION_ID!,
    signWith: process.env.TURNKEY_PRIVATE_KEY_ID!,
    // optional; will be fetched from Turnkey if not provided
    ethereumAddress: process.env.TURNKEY_TARGET_ADDRESS!,
  });

  const message =
    "I verify that I'm the owner of 0x680E26B472d8cae8148ee21FCAd6A69D73766436 and I'm an optimist.";

  console.log(turnkeyAccount);
  const msg = await turnkeyAccount.signMessage({ message });
  console.log({ msg });

  const walletClient = createWalletClient(turnkeyAccount);

  const signingResponse = await walletClient.signMessage({ message: message });
  console.log(signingResponse);
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
