import NumberFlow, { type Format } from "@number-flow/react";
import { useEffect, useState, type CSSProperties } from "react";

import {
  WALLET_ACTIONS,
  WALLET_TICK_MAX,
  WALLET_TICK_MIN,
  WALLET_VALUE,
  WALLET_VALUE_BASE,
  WALLET_VALUE_CEILING,
  type WalletActionIcon,
} from "../data";
import styles from "./WalletPanel.module.css";

// Snappy spring easing from https://www.kvin.me/css-springs — the same curve +
// timings web's MotionNumberFlow ships, so the roll feels identical to the app.
const NUMBERFLOW_EASING_CURVE =
  "linear(0, 0.0018, 0.0069 1.16%, 0.0262 2.32%, 0.0642, 0.1143 5.23%, 0.2244 7.84%, 0.5881 15.68%, 0.6933, 0.7839, 0.8591, 0.9191 26.13%, 0.9693, 1.0044 31.93%, 1.0234, 1.0358 36.58%, 1.0434 39.19%, 1.046 42.39%, 1.0446 44.71%, 1.0404 47.61%, 1.0118 61.84%, 1.0028 69.39%, 0.9981 80.42%, 0.9991 99.87%)";

// How often the balance climbs. > the 425ms roll so each jump lands as a clean,
// punchy individual roll rather than a frantic blur.
const TICK_MS = 600;

const TRANSFORM_TIMING = { duration: 425, easing: NUMBERFLOW_EASING_CURVE };
const OPACITY_TIMING = { duration: 250 };
const VALUE_FORMAT: Format = {
  style: "currency",
  currency: "USD",
  minimumFractionDigits: 2,
};

/**
 * The real Zora wordmark, copied verbatim from the mobile app's
 * `mobile-ui/src/components/Icon/ZoraWordmark` (viewBox 0 0 3487 1200) so the
 * panel header matches production instead of generic bold text. Fill follows
 * `currentColor`; inline SVG (not an <img>) keeps the viewBox aspect ratio.
 */
const ZoraWordmark = (
  <svg
    className={styles.wordmark}
    viewBox="0 0 3487 1200"
    fill="currentColor"
    aria-hidden="true"
  >
    <path d="M0,1180.1v-212l499.8-752H56.2V19.8h696.6v182.1l-520.7,782h541.2v196.3H0V1180.1z" />
    <path d="M758.4,607.1c0-138.2,20.5-252.1,61.3-341.5C860.6,176.2,914,109.5,980,65.8C1046,21.9,1125.9,0,1219.9,0 c136.2,0,247.1,52,332.8,155.9c85.7,104,128.6,252,128.6,444.1s-45.4,345.9-136.2,455.1c-79.7,96.6-187.9,144.8-324.6,144.8 s-246.4-47.7-326.1-143.2C803.7,947.5,758.3,797.6,758.4,607.1L758.4,607.1z M956.3,599.2c0,133.5,25.4,233.6,76.1,300.4 c50.7,66.8,113.6,100.2,188.7,100.2c75,0,138.2-33.1,187.9-99.3s74.5-167.9,74.5-305.2c0-137.2-24.2-234-72.6-298.4 c-48.3-64.3-111.7-96.6-189.9-96.6s-141.9,32.4-191,97.4C980.8,362.5,956.3,463,956.3,599.2z" />
    <path d="M1735.2,1180.1V19.8h404.4c103.4,0,177.3,10.4,221.6,31.2c44.4,20.9,80.8,57,109.2,108.4c28.5,51.4,42.7,113.1,42.7,184.8 c0,90.8-21.7,163.8-65.3,219.3c-43.4,55.5-105.2,90.3-185.5,104.5c41.2,29.5,75.2,61.9,102.1,97c26.9,35.1,63.6,98,110,188.8 l115.6,226.4h-229.2l-139.1-252.5c-50-91.3-84-148.4-102-171.4s-37-38.8-57-47.5c-20.1-8.7-52.2-13.1-96.6-13.1h-39.6v484.4H1735.2 L1735.2,1180.1z M1926.8,510.5h142.5c87.1,0,142.5-3.8,166.2-11.5c23.8-7.7,43-23.1,57.8-46.3c14.7-23.2,22.1-54,22.1-92.6 s-7.4-66.6-22.1-89c-14.8-22.4-34.8-37.8-60.2-46.3c-18-5.8-69.9-8.7-155.9-8.7h-150.4L1926.8,510.5L1926.8,510.5z" />
    <path d="M3487,1180.1h-208.2l-83.3-262.8h-380.9l-78.7,262.8h-204.2L2902.2,19.8h203.5L3487,1180.1z M3133.6,721l-131.4-430.6 L2873.3,721H3133.6z" />
  </svg>
);

/** $-in-circle (Phosphor CurrencyCircleDollar). */
const CashOutGlyph = (
  <svg viewBox="0 0 256 256" fill="currentColor" aria-hidden="true">
    <path d="M128,24A104,104,0,1,0,232,128,104.12,104.12,0,0,0,128,24Zm0,192a88,88,0,1,1,88-88A88.1,88.1,0,0,1,128,216Z" />
    <path d="M140,120H116a12,12,0,0,1,0-24h40a8,8,0,0,0,0-16H136V72a8,8,0,0,0-16,0v8h-4a28,28,0,0,0,0,56h24a12,12,0,0,1,0,24H104a8,8,0,0,0,0,16h16v8a8,8,0,0,0,16,0v-8h4a28,28,0,0,0,0-56Z" />
  </svg>
);

/** Bare stroke glyphs sized to fill the 24px action/search wells. */
const strokeProps = {
  viewBox: "0 0 24 24",
  fill: "none",
  stroke: "currentColor",
  strokeWidth: 1.8,
  strokeLinecap: "round" as const,
  strokeLinejoin: "round" as const,
  "aria-hidden": true,
};

const PlusGlyph = (
  <svg {...strokeProps}>
    <path d="M12 5v14M5 12h14" />
  </svg>
);

const SwapGlyph = (
  <svg {...strokeProps}>
    <path d="M4.5 9a7.5 7.5 0 0 1 12.9-4.2L20 7" />
    <path d="M20 3.5V7.5h-4" />
    <path d="M19.5 15a7.5 7.5 0 0 1-12.9 4.2L4 17" />
    <path d="M4 20.5V16.5h4" />
  </svg>
);

const SendGlyph = (
  <svg {...strokeProps}>
    <path d="M7 17 17 7M8.5 7H17v8.5" />
  </svg>
);

const SearchGlyph = (
  <svg {...strokeProps}>
    <circle cx="11" cy="11" r="6.4" />
    <path d="M20 20l-4.3-4.3" />
  </svg>
);

function ActionGlyph({ icon }: { icon: WalletActionIcon }) {
  if (icon === "deposit") return PlusGlyph;
  if (icon === "swap") return SwapGlyph;
  if (icon === "send") return SendGlyph;

  return <span className={styles.cashOutGlyph}>{CashOutGlyph}</span>;
}

interface WalletPanelProps {
  /** Shared from the hero so motion stays gated in one place. */
  reduceMotion?: boolean | null;
  /**
   * Reports pointer enter/leave on the panel so the hero can pause its term
   * cycle while this panel is hovered. Scoped to the panel (not the wider
   * stage) so empty space beside it doesn't trigger the pause; `undefined` on
   * touch pointers.
   */
  onHoverChange?: (hovered: boolean) => void;
}

/**
 * A Zora wallet screen shown in the hero while the headline word is "wallet".
 * On mount the estimated value rolls up from 0 to `WALLET_VALUE_BASE`, then keeps
 * climbing by a chunky random increment every `TICK_MS` — a live "agent earning"
 * ticker that rolls many digit columns each jump (dramatic + obvious). Powered by
 * NumberFlow (matches web's MotionNumberFlow: the kvin.me spring curve, 425ms
 * transform, 250ms opacity fade). Clamped at `WALLET_VALUE_CEILING` so it can't
 * overflow the panel even if the hero is parked off-screen. Under
 * prefers-reduced-motion it renders one value at rest. Decorative — labelled as a
 * single image for AT.
 */
export function WalletPanel({ reduceMotion, onHoverChange }: WalletPanelProps) {
  const [value, setValue] = useState(reduceMotion ? WALLET_VALUE_BASE : 0);

  useEffect(() => {
    if (reduceMotion) {
      setValue(WALLET_VALUE_BASE);

      return;
    }
    // Initial dramatic roll 0 -> base, then keep climbing in chunky jumps.
    setValue(WALLET_VALUE_BASE);
    const id = setInterval(() => {
      setValue((current) => {
        const increment =
          WALLET_TICK_MIN + Math.random() * (WALLET_TICK_MAX - WALLET_TICK_MIN);
        const next = Math.round((current + increment) * 100) / 100;

        return Math.min(next, WALLET_VALUE_CEILING);
      });
    }, TICK_MS);

    return () => clearInterval(id);
  }, [reduceMotion]);

  return (
    <div
      className={styles.panel}
      role="img"
      aria-label={`Zora wallet — estimated value ${WALLET_VALUE}`}
      onMouseEnter={onHoverChange ? () => onHoverChange(true) : undefined}
      onMouseLeave={onHoverChange ? () => onHoverChange(false) : undefined}
    >
      <header className={styles.header} aria-hidden="true">
        <span className={styles.headerSide} />
        {ZoraWordmark}
        <span className={`${styles.headerSide} ${styles.headerEnd}`}>
          <span className={styles.search}>{SearchGlyph}</span>
        </span>
      </header>

      <div className={styles.body} aria-hidden="true">
        <span className={styles.label}>Estimated wallet value</span>

        <NumberFlow
          className={styles.value}
          value={value}
          format={VALUE_FORMAT}
          locales="en-US"
          transformTiming={TRANSFORM_TIMING}
          opacityTiming={OPACITY_TIMING}
          respectMotionPreference
          style={{ "--number-flow-mask-height": "0.1em" } as CSSProperties}
        />

        <div className={styles.actions}>
          {WALLET_ACTIONS.map((action) => (
            <div key={action.icon} className={styles.actionTile}>
              <span className={styles.actionIcon}>
                <ActionGlyph icon={action.icon} />
              </span>
              <span className={styles.actionLabel}>{action.label}</span>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
