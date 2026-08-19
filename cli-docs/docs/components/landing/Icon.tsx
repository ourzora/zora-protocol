import type { CSSProperties, ReactElement } from "react";

/**
 * Inline line-icon set for the landing page.
 *
 * The Figma source uses Zora's Central Icons (`square-outlined-radius-0-stroke-1.5`),
 * a license-gated package the docs build doesn't pull in. Rather than approximate
 * those glyphs, the path data below is lifted VERBATIM from that package so the
 * marks are pixel-identical to Figma — same 24-unit grid, same 1.5 stroke, same
 * per-path linecaps. Each element carries its own stroke/fill attributes (the
 * source mixes square/round/butt caps and one filled sparkle), so the wrapper
 * only sets the viewBox and dimensions. Everything inherits `currentColor`, so the
 * chip/title color drives the glyph.
 */

export type IconName =
  | "profile"
  | "dms"
  | "wallet"
  | "network"
  | "code"
  | "skill"
  | "copy"
  | "check";

export interface IconProps {
  name: IconName;
  className?: string;
  size?: number | string;
}

const S = "currentColor";

const PATHS: Record<IconName, ReactElement> = {
  // IconPeopleCircle — head-and-shoulders avatar in a circle.
  profile: (
    <>
      <path
        d="M15.25 10C15.25 11.7949 13.7949 13.25 12 13.25C10.2051 13.25 8.75 11.7949 8.75 10C8.75 8.20507 10.2051 6.75 12 6.75C13.7949 6.75 15.25 8.20507 15.25 10Z"
        stroke={S}
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
      <path
        d="M21.25 12C21.25 14.7509 20.0491 17.2214 18.143 18.9157C16.5094 20.3679 14.3577 21.25 12 21.25C9.6423 21.25 7.49061 20.3679 5.85697 18.9157C3.95086 17.2214 2.75 14.7509 2.75 12C2.75 6.89137 6.89137 2.75 12 2.75C17.1086 2.75 21.25 6.89137 21.25 12Z"
        stroke={S}
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
      <path
        d="M6.16406 18.5C7.49493 16.8187 9.53084 15.75 12.0009 15.75C14.4709 15.75 16.5068 16.8187 17.8377 18.5"
        stroke={S}
        strokeWidth="1.5"
        strokeLinejoin="round"
      />
    </>
  ),
  // IconChatBubbles — two overlapping rounded chat bubbles.
  dms: (
    <>
      <path
        d="M15.5 21.25C12.3244 21.25 9.75 18.8995 9.75 16C9.75 13.1005 12.3244 10.75 15.5 10.75C18.6756 10.75 21.25 13.1005 21.25 16C21.25 17.1969 20.8113 18.3003 20.0727 19.1834C20.1895 19.7834 20.3821 20.3647 20.6111 20.9412C19.8114 20.8935 19.0587 20.7718 18.3293 20.5715C17.494 21.0034 16.5285 21.25 15.5 21.25Z"
        stroke={S}
        strokeWidth="1.5"
      />
      <path
        d="M17.171 8.5C16.652 5.24629 13.6391 2.75 10 2.75C5.99594 2.75 2.75 5.77208 2.75 9.5C2.75 11.0389 3.30315 12.4576 4.23444 13.593C4.0872 14.3644 3.84429 15.1117 3.55556 15.8529C4.5639 15.7916 5.5129 15.6351 6.43259 15.3777C6.78577 15.5639 7.15739 15.7233 7.54427 15.8529"
        stroke={S}
        strokeWidth="1.5"
      />
    </>
  ),
  // IconCryptoWallet — wallet body with a clasp + hexagon coin + value dot.
  wallet: (
    <>
      <path
        d="M16.25 8.75H6C4.75736 8.75 3.75 7.74264 3.75 6.5M16.25 8.75H20.25V20.25H12.25M16.25 8.75V3.75H6.5C4.98122 3.75 3.75 4.98122 3.75 6.5M3.75 11.25V6.5"
        stroke={S}
        strokeWidth="1.5"
        strokeLinecap="square"
      />
      <path
        d="M6 13.4583L9.25 15.3541V19.1458L6 21.0416L2.75 19.1458V15.3541L6 13.4583Z"
        stroke={S}
        strokeWidth="1.5"
        strokeLinecap="round"
      />
      <path
        d="M15.5 14.5V14.49M15.75 14.5C15.75 14.6381 15.6381 14.75 15.5 14.75C15.3619 14.75 15.25 14.6381 15.25 14.5C15.25 14.3619 15.3619 14.25 15.5 14.25C15.6381 14.25 15.75 14.3619 15.75 14.5Z"
        stroke={S}
        strokeWidth="1.5"
        strokeLinecap="round"
      />
    </>
  ),
  // IconAgentNetwork — four nodes (atoms) linked by connection lines.
  network: (
    <>
      <circle cx="18.5" cy="7.5" r="2.5" stroke={S} strokeWidth="1.5" />
      <circle cx="5.5" cy="16.5" r="2.5" stroke={S} strokeWidth="1.5" />
      <circle cx="8.5" cy="6.5" r="3.5" stroke={S} strokeWidth="1.5" />
      <circle cx="15.5" cy="17.5" r="3.5" stroke={S} strokeWidth="1.5" />
      <path
        d="M12 6.8501L16 7.2501M17.75 10.0001L16.55 14.0001M13.5 14.3572L12 12.0001L10.4091 9.5001M6.25 14.0001L7.45 10.0001M8 16.7501L12 17.1501"
        stroke={S}
        strokeWidth="1.5"
      />
    </>
  ),
  // IconCode — < > chevrons inside a square frame.
  code: (
    <path
      d="M10.5 9L7.5 12L10.5 15M13.5 9L16.5 12L13.5 15M3.75 3.75H20.25V20.25H3.75V3.75Z"
      stroke={S}
      strokeWidth="1.5"
    />
  ),
  // IconCodeAnalyze — document with text lines + a filled sparkle (the Figma "Skill" glyph).
  skill: (
    <>
      <path d="M13 3.75H3.75V20.25H20.25V11" stroke={S} strokeWidth="1.5" />
      <path d="M7 8.25H13" stroke={S} strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M7 12H10.5" stroke={S} strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M12 12H17" stroke={S} strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M7 15.75H14" stroke={S} strokeWidth="1.5" strokeLinejoin="round" />
      <path
        d="M19 1L20.0804 3.91964L23 5L20.0804 6.08036L19 9L17.9196 6.08036L15 5L17.9196 3.91964L19 1Z"
        fill={S}
      />
    </>
  ),
  // IconSquareBehindSquare1 — front square with an open back square (copy).
  copy: (
    <path
      d="M15.25 8.75V2.75H2.75V15.25H8.75M8.75 8.75H21.25V21.25H8.75V8.75Z"
      stroke={S}
      strokeWidth="1.5"
      strokeLinecap="square"
    />
  ),
  // IconCheckmark1 — square-capped checkmark.
  check: (
    <path
      d="M4.75 12.7768L10 19.25L19.25 4.75"
      stroke={S}
      strokeWidth="1.5"
      strokeLinecap="square"
    />
  ),
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
      aria-hidden="true"
    >
      {PATHS[name]}
    </svg>
  );
}
