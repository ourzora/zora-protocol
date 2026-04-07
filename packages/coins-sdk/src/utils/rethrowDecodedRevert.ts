import {
  Abi,
  BaseError,
  ContractFunctionRevertedError,
  decodeErrorResult,
  Hex,
} from "viem";

export function rethrowDecodedRevert(err: unknown, abi: Abi): never {
  if (err instanceof BaseError) {
    const revertError = err.walk(
      (e) => e instanceof ContractFunctionRevertedError,
    );
    if (revertError instanceof ContractFunctionRevertedError) {
      // Try to decode using factory ABI
      try {
        const revertData =
          typeof (revertError as any).data === "object" &&
          (revertError as any).data !== null &&
          "data" in (revertError as any).data
            ? (revertError as any).data.data
            : (revertError as any).data;
        const decoded = decodeErrorResult({
          abi,
          data: revertData as Hex,
        });
        const name = decoded.errorName;
        const args = decoded.args as ReadonlyArray<unknown> | undefined;
        const message =
          Array.isArray(args) && args.length > 0
            ? `${name}(${args.map((a) => String(a)).join(", ")})`
            : name;
        throw new Error(`Create coin transaction reverted: ${message}`);
      } catch {
        const errorName = (revertError as any).data?.errorName as
          | string
          | undefined;
        if (errorName) {
          const args = (revertError as any).data?.args as unknown[] | undefined;
          const message =
            Array.isArray(args) && args.length > 0
              ? `${errorName}(${args.map((a) => String(a)).join(", ")})`
              : errorName;
          throw new Error(`Create coin transaction reverted: ${message}`);
        }
      }
    }
  }
  throw err;
}
