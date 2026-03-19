import { describe, it, expect, vi, afterEach } from "vitest";

vi.mock("@inquirer/confirm", () => ({ default: vi.fn() }));
vi.mock("@inquirer/select", () => ({ default: vi.fn() }));
vi.mock("@inquirer/password", () => ({ default: vi.fn() }));

import confirm from "@inquirer/confirm";
import select from "@inquirer/select";
import { confirmOrDefault, selectOrDefault, passwordOrFail } from "./prompt.js";

describe("confirmOrDefault", () => {
  afterEach(() => vi.restoreAllMocks());

  it("returns true when nonInteractive is true (--yes means yes)", async () => {
    const result = await confirmOrDefault({ message: "Continue?", default: false }, true);
    expect(result).toBe(true);
    expect(confirm).not.toHaveBeenCalled();
  });

  it("calls inquirer confirm when nonInteractive is false", async () => {
    vi.mocked(confirm).mockResolvedValue(false);
    const result = await confirmOrDefault({ message: "Continue?", default: true }, false);
    expect(result).toBe(false);
    expect(confirm).toHaveBeenCalled();
  });
});

describe("selectOrDefault", () => {
  afterEach(() => vi.restoreAllMocks());

  it("returns default when nonInteractive is true", async () => {
    const result = await selectOrDefault(
      { message: "Pick", choices: [{ name: "A", value: "a" }], default: "a" },
      true,
    );
    expect(result).toBe("a");
    expect(select).not.toHaveBeenCalled();
  });

  it("calls inquirer select when nonInteractive is false", async () => {
    vi.mocked(select).mockResolvedValue("b" as never);
    const result = await selectOrDefault(
      { message: "Pick", choices: [{ name: "B", value: "b" }], default: "a" },
      false,
    );
    expect(result).toBe("b");
    expect(select).toHaveBeenCalled();
  });
});

describe("passwordOrFail", () => {
  afterEach(() => vi.restoreAllMocks());

  it("exits with error when nonInteractive is true", async () => {
    vi.spyOn(console, "error").mockImplementation(() => {});
    vi.spyOn(process, "exit").mockImplementation((code) => { throw new Error(`exit ${code}`); });

    await expect(
      passwordOrFail(false, { message: "Key:" }, true),
    ).rejects.toThrow("exit 1");
  });
});
