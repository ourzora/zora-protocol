import { describe, it, expect, vi, afterEach } from "vitest";
import { outputJson, outputErrorAndExit, outputData } from "./output.js";

describe("outputJson", () => {
  afterEach(() => vi.restoreAllMocks());

  it("prints JSON with 2-space indentation", () => {
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    outputJson({ name: "test", value: 42 });
    expect(logSpy).toHaveBeenCalledWith(JSON.stringify({ name: "test", value: 42 }, null, 2));
  });
});

describe("outputErrorAndExit", () => {
  afterEach(() => vi.restoreAllMocks());

  it("prints styled error to stderr in table mode", () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    vi.spyOn(process, "exit").mockImplementation((code) => { throw new Error(`exit ${code}`); });

    expect(() => outputErrorAndExit(false, "Something broke", "Try again")).toThrow("exit 1");
    expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining("Something broke"));
    expect(errorSpy).toHaveBeenCalledWith(expect.stringContaining("Try again"));
  });

  it("prints JSON error to stdout in json mode", () => {
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    vi.spyOn(process, "exit").mockImplementation((code) => { throw new Error(`exit ${code}`); });

    expect(() => outputErrorAndExit(true, "Bad request", "Use --help")).toThrow("exit 1");
    const output = JSON.parse(logSpy.mock.calls[0][0]);
    expect(output.error).toBe("Bad request");
    expect(output.suggestion).toBe("Use --help");
  });

  it("omits suggestion in JSON when not provided", () => {
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    vi.spyOn(process, "exit").mockImplementation((code) => { throw new Error(`exit ${code}`); });

    expect(() => outputErrorAndExit(true, "Not found")).toThrow("exit 1");
    const output = JSON.parse(logSpy.mock.calls[0][0]);
    expect(output.error).toBe("Not found");
    expect(output.suggestion).toBeUndefined();
  });
});

describe("outputData", () => {
  afterEach(() => vi.restoreAllMocks());

  it("prints JSON in json mode", () => {
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const tableFn = vi.fn();
    outputData(true, { json: { count: 5 }, table: tableFn });
    expect(logSpy).toHaveBeenCalled();
    expect(tableFn).not.toHaveBeenCalled();
  });

  it("calls table function in table mode", () => {
    const logSpy = vi.spyOn(console, "log").mockImplementation(() => {});
    const tableFn = vi.fn();
    outputData(false, { json: { count: 5 }, table: tableFn });
    expect(tableFn).toHaveBeenCalled();
  });
});
