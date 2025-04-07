import { Address } from "viem";
import { getCoin } from "@zoralabs/coins-sdk";

try {
  const response = await getCoin({ address: "0xCoinAddress" as Address });
  //    ^^^
  // Process response...
  console.log(response);
} catch (error: any) {
  if (error.status === 404) {
    console.error("Coin not found");
  } else if (error.status === 401) {
    console.error("API key invalid or missing");
  } else {
    console.error("Unexpected error:", error.message);
  }
}
