import { describe, it, expect, assert } from "vitest";
import { parseNameIntoSymbol } from "./minter-defaults";

describe("parseNameIntoSymbol", () => {
  it("removes spaces and vowels and converts to uppercase", () => {
    const symbol = parseNameIntoSymbol("My 4 To *5 @-Name");

    expect(symbol).toBe("$MY4T");
  });
  it("works with less than 4 characters", () => {
    const symbol = parseNameIntoSymbol("M4y a");

    expect(symbol).toBe("$M4Y");
  });

  it("works with no characters", () => {
    assert.throws(() => {
      parseNameIntoSymbol("AEIO U");
    }, "Not enough valid characters to generate a symbol");
  });
});
