import { describe, it, expect, vi } from "vitest";
import { render } from "ink-testing-library";
import { ProfileView, type ProfileData } from "./ProfileView.js";

const makeProfileData = (overrides?: Partial<ProfileData>): ProfileData => ({
  posts: [
    {
      name: "Test Post",
      address: "0x1234567890abcdef1234567890abcdef12345678",
      coinType: "CONTENT",
      symbol: "TEST",
      marketCap: "1000000",
      volume24h: "50000",
      createdAt: new Date().toISOString(),
    },
  ],
  postsCount: 1,
  holdings: [],
  holdingsCount: 0,
  ...overrides,
});

describe("ProfileView", () => {
  it("shows spinner while loading", () => {
    const { lastFrame } = render(
      <ProfileView
        fetchData={() => new Promise(() => {})}
        identifier="testuser"
      />,
    );
    expect(lastFrame()).toContain("Loading profile");
  });

  it("renders posts tab by default", async () => {
    const { lastFrame } = render(
      <ProfileView
        fetchData={() => Promise.resolve(makeProfileData())}
        identifier="testuser"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Posts]");
    });
    expect(lastFrame()).toContain("Test Post");
  });

  it("shows auto-refresh countdown when enabled", async () => {
    const { lastFrame } = render(
      <ProfileView
        fetchData={() => Promise.resolve(makeProfileData())}
        identifier="testuser"
        autoRefresh={true}
        intervalSeconds={30}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Posts]");
    });
    expect(lastFrame()).toMatch(/r refresh \(\d+s\)/);
    expect(lastFrame()).toContain("q quit");
  });

  it("does not show countdown when autoRefresh is false", async () => {
    const { lastFrame } = render(
      <ProfileView
        fetchData={() => Promise.resolve(makeProfileData())}
        identifier="testuser"
        autoRefresh={false}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("[Posts]");
    });
    expect(lastFrame()).toContain("r refresh");
    expect(lastFrame()).not.toMatch(/r refresh \(\d+s\)/);
  });

  it("shows error state", async () => {
    const { lastFrame } = render(
      <ProfileView
        fetchData={() => Promise.reject(new Error("Network error"))}
        identifier="testuser"
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Error: Network error");
    });
    expect(lastFrame()).toContain("q to exit");
  });
});
