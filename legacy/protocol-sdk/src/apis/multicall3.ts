import { Address, Hex } from "viem";

export const multicall3Abi = [
  "struct Call { address target; bytes callData; }",
  "struct Call3 { address target; bool allowFailure; bytes callData; }",
  "struct Call3Value { address target; bool allowFailure; uint256 value; bytes callData; }",
  "struct Result { bool success; bytes returnData; }",
  "function aggregate(Call[] calldata calls) public payable returns (uint256 blockNumber, bytes[] memory returnData)",
  "function aggregate3(Call3[] calldata calls) public payable returns (Result[] memory returnData)",
  "function aggregate3Value(Call3Value[] calldata calls) public payable returns (Result[] memory returnData)",
];

export const multicall3Address = "0xcA11bde05977b3631167028862bE2a173976CA11";

export type Multicall3Call3 = {
  target: Address;
  allowFailure: boolean;
  callData: Hex;
};
