import { afterEach, describe, expect, it, vi } from "vitest";
import { client } from "../client/client.gen";
import { apiUrl } from "./api-raw";

const mockBaseUrl = (baseUrl: string | undefined) =>
  vi
    .spyOn(client, "getConfig")
    .mockReturnValue({ baseUrl } as ReturnType<typeof client.getConfig>);

describe("apiUrl", () => {
  const expected = "https://api.example.com/some/path";

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("joins base without trailing slash and path with leading slash", () => {
    mockBaseUrl("https://api.example.com");
    expect(apiUrl("/some/path")).toBe(expected);
  });

  it("joins base without trailing slash and path without leading slash", () => {
    mockBaseUrl("https://api.example.com");
    expect(apiUrl("some/path")).toBe(expected);
  });

  it("joins base with trailing slash and path with leading slash", () => {
    mockBaseUrl("https://api.example.com/");
    expect(apiUrl("/some/path")).toBe(expected);
  });

  it("joins base with trailing slash and path without leading slash", () => {
    mockBaseUrl("https://api.example.com/");
    expect(apiUrl("some/path")).toBe(expected);
  });

  it("collapses multiple trailing slashes on the base", () => {
    mockBaseUrl("https://api.example.com///");
    expect(apiUrl("some/path")).toBe(expected);
  });

  it("collapses multiple leading slashes on the path", () => {
    mockBaseUrl("https://api.example.com");
    expect(apiUrl("///some/path")).toBe(expected);
  });

  it("preserves the protocol's double slashes", () => {
    mockBaseUrl("https://api.example.com/");
    expect(apiUrl("/some/path")).toContain("https://");
  });

  it("handles an undefined base url", () => {
    mockBaseUrl(undefined);
    expect(apiUrl("/some/path")).toBe("/some/path");
  });

  it("handles an empty path", () => {
    mockBaseUrl("https://api.example.com");
    expect(apiUrl("")).toBe("https://api.example.com/");
  });
});
