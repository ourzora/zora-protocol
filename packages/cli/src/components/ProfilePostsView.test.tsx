import { describe, it, expect, vi } from "vitest";
import { render } from "ink-testing-library";
import { ProfilePostsView } from "./ProfilePostsView.js";
import type { PageResult } from "./PaginatedTableView.js";
import type { PostNode } from "./ProfilePostsView.js";

const makePost = (overrides = {}) => ({
  name: "TestPost",
  address: "0x1234567890abcdef1234567890abcdef12345678",
  coinType: "CONTENT" as const,
  symbol: "TEST",
  marketCap: "1000000",
  volume24h: "50000",
  marketCapDelta24h: "10000",
  createdAt: new Date().toISOString(),
  ...overrides,
});

const makePage = (
  overrides?: Partial<PageResult<PostNode>>,
): PageResult<PostNode> => ({
  items: [makePost()],
  pageInfo: { hasNextPage: false },
  count: 1,
  ...overrides,
});

describe("ProfilePostsView", () => {
  it("shows spinner while loading", () => {
    const { lastFrame } = render(
      <ProfilePostsView
        fetchPage={() => new Promise(() => {})}
        identifier="testuser"
        limit={20}
      />,
    );
    expect(lastFrame()).toContain("Loading posts");
  });

  it("renders table after data loads", async () => {
    const { lastFrame } = render(
      <ProfilePostsView
        fetchPage={() => Promise.resolve(makePage())}
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestPost");
    });
    expect(lastFrame()).toContain("Posts");
    expect(lastFrame()).toContain("testuser");
    expect(lastFrame()).toContain("Page 1");
    expect(lastFrame()).toContain("1 of 1");
  });

  it("shows empty state when no posts", async () => {
    const { lastFrame } = render(
      <ProfilePostsView
        fetchPage={() => Promise.resolve(makePage({ items: [], count: 0 }))}
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("No posts found");
    });
    expect(lastFrame()).toContain("q to exit");
  });

  it("shows error state on fetch failure", async () => {
    const { lastFrame } = render(
      <ProfilePostsView
        fetchPage={() => Promise.reject(new Error("Network error"))}
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Error: Network error");
    });
    expect(lastFrame()).toContain("q to exit");
  });

  it("shows next hint when next page is available", async () => {
    const { lastFrame } = render(
      <ProfilePostsView
        fetchPage={() =>
          Promise.resolve(
            makePage({
              pageInfo: { endCursor: "cursor_abc", hasNextPage: true },
              count: 40,
            }),
          )
        }
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestPost");
    });
    expect(lastFrame()).toContain("next");
    expect(lastFrame()).not.toContain("prev");
  });

  it("navigates to next page on n key", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce(
        makePage({
          items: [makePost({ name: "Page1Post" })],
          pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
          count: 2,
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [makePost({ name: "Page2Post" })],
          pageInfo: { hasNextPage: false },
          count: 2,
        }),
      );

    const { lastFrame, stdin } = render(
      <ProfilePostsView
        fetchPage={fetchPage}
        identifier="testuser"
        limit={1}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page1Post");
    });

    stdin.write("n");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page2Post");
    });
    expect(lastFrame()).toContain("Page 2");
    expect(fetchPage).toHaveBeenCalledWith("cursor_page2");
  });

  it("navigates back on p key", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce(
        makePage({
          items: [makePost({ name: "Page1Post" })],
          pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
          count: 2,
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [makePost({ name: "Page2Post" })],
          pageInfo: { hasNextPage: false },
          count: 2,
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [makePost({ name: "Page1Post" })],
          pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
          count: 2,
        }),
      );

    const { lastFrame, stdin } = render(
      <ProfilePostsView
        fetchPage={fetchPage}
        identifier="testuser"
        limit={1}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page1Post");
    });

    stdin.write("n");
    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page2Post");
    });

    stdin.write("p");
    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page 1");
    });
  });

  it("shows prev hint after navigating forward", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce(
        makePage({
          items: [makePost({ name: "Page1Post" })],
          pageInfo: { endCursor: "cursor_page2", hasNextPage: true },
          count: 2,
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [makePost({ name: "Page2Post" })],
          pageInfo: { hasNextPage: false },
          count: 2,
        }),
      );

    const { lastFrame, stdin } = render(
      <ProfilePostsView
        fetchPage={fetchPage}
        identifier="testuser"
        limit={1}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page1Post");
    });
    expect(lastFrame()).not.toContain("prev");

    stdin.write("n");
    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Page2Post");
    });
    expect(lastFrame()).toContain("prev");
  });

  it("numbers ranks across pages", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce(
        makePage({
          items: [makePost({ name: "Post1" }), makePost({ name: "Post2" })],
          pageInfo: { endCursor: "c2", hasNextPage: true },
          count: 3,
        }),
      )
      .mockResolvedValueOnce(
        makePage({
          items: [makePost({ name: "Post3" })],
          pageInfo: { hasNextPage: false },
          count: 3,
        }),
      );

    const { lastFrame, stdin } = render(
      <ProfilePostsView
        fetchPage={fetchPage}
        identifier="testuser"
        limit={2}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Post1");
    });

    stdin.write("n");
    await vi.waitFor(() => {
      expect(lastFrame()).toContain("Post3");
    });
    // Rank on page 2 with limit=2 starts at 3
    expect(lastFrame()).toContain("3");
  });

  it("refreshes on r key press", async () => {
    const fetchPage = vi
      .fn()
      .mockResolvedValueOnce(
        makePage({ items: [makePost({ name: "OldPost" })] }),
      )
      .mockResolvedValueOnce(
        makePage({ items: [makePost({ name: "FreshPost" })] }),
      );

    const { lastFrame, stdin } = render(
      <ProfilePostsView
        fetchPage={fetchPage}
        identifier="testuser"
        limit={20}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("OldPost");
    });

    stdin.write("r");

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("FreshPost");
    });
    expect(fetchPage).toHaveBeenCalledTimes(2);
  });

  it("shows auto-refresh countdown when enabled", async () => {
    const { lastFrame } = render(
      <ProfilePostsView
        fetchPage={() => Promise.resolve(makePage())}
        identifier="testuser"
        limit={20}
        autoRefresh={true}
        intervalSeconds={30}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestPost");
    });
    expect(lastFrame()).toMatch(/r refresh \(\d+s\)/);
  });

  it("does not show countdown when autoRefresh is false", async () => {
    const { lastFrame } = render(
      <ProfilePostsView
        fetchPage={() => Promise.resolve(makePage())}
        identifier="testuser"
        limit={20}
        autoRefresh={false}
      />,
    );

    await vi.waitFor(() => {
      expect(lastFrame()).toContain("TestPost");
    });
    expect(lastFrame()).toContain("r refresh");
    expect(lastFrame()).not.toMatch(/r refresh \(\d+s\)/);
  });
});
