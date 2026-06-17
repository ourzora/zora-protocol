import type { CSSProperties, ReactElement } from "react";

/**
 * Inline line-icon set for the landing page.
 *
 * The Figma source used Central Icons (`square-outlined-radius-0-stroke-1.5`),
 * a license-gated package we don't pull into the docs build. These are
 * hand-authored equivalents on the same 24-unit grid (1.5 stroke, currentColor)
 * so the chip/title color drives them. Visually in-family with that set.
 */

export type IconName =
  | "profile"
  | "dms"
  | "wallet"
  | "network"
  | "code"
  | "sparkle"
  | "copy"
  | "check";

export interface IconProps {
  name: IconName;
  className?: string;
  size?: number | string;
}

const PATHS: Record<IconName, ReactElement> = {
  // Head-and-shoulders avatar in a circle — reads as "profile".
  profile: (
    <>
      <circle cx="12" cy="12" r="9.25" />
      <circle cx="12" cy="9.6" r="2.85" />
      <path d="M6.4 18.6a5.85 5.85 0 0 1 11.2 0" />
    </>
  ),
  // Two overlapping speech bubbles.
  dms: (
    <>
      <path d="M3 8.5a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v3.5a2 2 0 0 1-2 2H8l-3 2.8V14H5a2 2 0 0 1-2-2z" />
      <path d="M10 6.6V6a2 2 0 0 1 2-2h7a2 2 0 0 1 2 2v3.5a2 2 0 0 1-2 2h-1.2" />
    </>
  ),
  // Wallet body with a clasp pocket + button on the right edge.
  wallet: (
    <>
      <rect x="3" y="6.5" width="18" height="12" rx="2.5" />
      <path d="M16.25 11.5H21v3.5h-4.75a1.75 1.75 0 0 1 0-3.5z" />
      <circle cx="17.4" cy="13.25" r="0.9" fill="currentColor" stroke="none" />
    </>
  ),
  // Three connected nodes — a small social graph.
  network: (
    <>
      <circle cx="12" cy="5" r="2.3" />
      <circle cx="5" cy="17.5" r="2.3" />
      <circle cx="19" cy="17.5" r="2.3" />
      <path d="M11 7.1 6 15.4M13 7.1 18 15.4M7.2 17.5h9.6" />
    </>
  ),
  // < > code chevrons.
  code: (
    <>
      <path d="M8.5 7 3.5 12l5 5" />
      <path d="M15.5 7 20.5 12l-5 5" />
    </>
  ),
  // Four-point sparkle / star.
  sparkle: (
    <path d="M12 3l1.45 7.55L21 12l-7.55 1.45L12 21l-1.45-7.55L3 12l7.55-1.45z" />
  ),
  // Two stacked squares (copy).
  copy: (
    <>
      <rect x="8" y="8" width="11" height="11" />
      <path d="M15.5 8V5H5v10.5H8" />
    </>
  ),
  // Checkmark.
  check: <path d="M4.5 12.5 9.5 17.5 19.5 6.5" />,
};

export function Icon({ name, className, size = 24 }: IconProps) {
  const dimension = typeof size === "number" ? `${size}px` : size;
  const style: CSSProperties = { width: dimension, height: dimension };

  return (
    <svg
      viewBox="0 0 24 24"
      width={dimension}
      height={dimension}
      style={style}
      className={className}
      fill="none"
      stroke="currentColor"
      strokeWidth="1.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden="true"
    >
      {PATHS[name]}
    </svg>
  );
}
