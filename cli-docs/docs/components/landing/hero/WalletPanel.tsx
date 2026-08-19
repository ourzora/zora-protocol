import {
  WALLET_ACTIONS,
  WALLET_VALUE,
  WALLET_VALUE_BASE,
  type WalletActionIcon,
} from '../data'
import NumberFlow, { type Format } from '@number-flow/react'
import { useEffect, useState, type CSSProperties } from 'react'

import styles from './WalletPanel.module.css'

// Snappy spring easing from https://www.kvin.me/css-springs — the same curve +
// timings web's MotionNumberFlow ships, so the roll feels identical to the app.
const NUMBERFLOW_EASING_CURVE =
  'linear(0, 0.0018, 0.0069 1.16%, 0.0262 2.32%, 0.0642, 0.1143 5.23%, 0.2244 7.84%, 0.5881 15.68%, 0.6933, 0.7839, 0.8591, 0.9191 26.13%, 0.9693, 1.0044 31.93%, 1.0234, 1.0358 36.58%, 1.0434 39.19%, 1.046 42.39%, 1.0446 44.71%, 1.0404 47.61%, 1.0118 61.84%, 1.0028 69.39%, 0.9981 80.42%, 0.9991 99.87%)'

// Hold at 0 through the panel's enter cross-fade, then roll up ONCE — so the
// digits never scramble mid-transition (which read as glitchy over the outgoing
// card). > the stage's ~0.34s enter so the roll lands on a settled panel.
const ROLL_DELAY_MS = 450

const TRANSFORM_TIMING = { duration: 425, easing: NUMBERFLOW_EASING_CURVE }
const OPACITY_TIMING = { duration: 250 }
const VALUE_FORMAT: Format = {
  style: 'currency',
  currency: 'USD',
  minimumFractionDigits: 2,
}

// Phosphor "regular" glyphs, lifted verbatim from @phosphor-icons/core — the
// exact marks the prod wallet renders via reshaped (`Plus`, `PaperPlaneTilt`,
// `ArrowDown`, `CurrencyCircleDollar`). All four share the 256-unit filled-outline
// style so the action row reads as one family; `currentColor` tracks the tile ink.
const PlusGlyph = (
  <svg viewBox="0 0 256 256" fill="currentColor" aria-hidden="true">
    <path d="M224,128a8,8,0,0,1-8,8H136v80a8,8,0,0,1-16,0V136H40a8,8,0,0,1,0-16h80V40a8,8,0,0,1,16,0v80h80A8,8,0,0,1,224,128Z" />
  </svg>
)

const SendGlyph = (
  <svg viewBox="0 0 256 256" fill="currentColor" aria-hidden="true">
    <path d="M227.32,28.68a16,16,0,0,0-15.66-4.08l-.15,0L19.57,82.84a16,16,0,0,0-2.49,29.8L102,154l41.3,84.87A15.86,15.86,0,0,0,157.74,248q.69,0,1.38-.06a15.88,15.88,0,0,0,14-11.51l58.2-191.94c0-.05,0-.1,0-.15A16,16,0,0,0,227.32,28.68ZM157.83,231.85l-.05.14,0-.07-40.06-82.3,48-48a8,8,0,0,0-11.31-11.31l-48,48L24.08,98.25l-.07,0,.14,0L216,40Z" />
  </svg>
)

const ReceiveGlyph = (
  <svg viewBox="0 0 256 256" fill="currentColor" aria-hidden="true">
    <path d="M205.66,149.66l-72,72a8,8,0,0,1-11.32,0l-72-72a8,8,0,0,1,11.32-11.32L120,196.69V40a8,8,0,0,1,16,0V196.69l58.34-58.35a8,8,0,0,1,11.32,11.32Z" />
  </svg>
)

/** $-in-circle (Phosphor CurrencyCircleDollar) — reshaped ships no circled variant. */
const CashOutGlyph = (
  <svg viewBox="0 0 256 256" fill="currentColor" aria-hidden="true">
    <path d="M128,24A104,104,0,1,0,232,128,104.12,104.12,0,0,0,128,24Zm0,192a88,88,0,1,1,88-88A88.1,88.1,0,0,1,128,216Z" />
    <path d="M140,120H116a12,12,0,0,1,0-24h40a8,8,0,0,0,0-16H136V72a8,8,0,0,0-16,0v8h-4a28,28,0,0,0,0,56h24a12,12,0,0,1,0,24H104a8,8,0,0,0,0,16h16v8a8,8,0,0,0,16,0v-8h4a28,28,0,0,0,0-56Z" />
  </svg>
)

function ActionGlyph({ icon }: { icon: WalletActionIcon }) {
  if (icon === 'deposit') return PlusGlyph
  if (icon === 'send') return SendGlyph
  if (icon === 'receive') return ReceiveGlyph

  return CashOutGlyph
}

interface WalletPanelProps {
  /** Shared from the hero so motion stays gated in one place. */
  reduceMotion?: boolean | null
  /**
   * Reports pointer enter/leave on the panel so the hero can pause its term
   * cycle while this panel is hovered. Scoped to the panel (not the wider
   * stage) so empty space beside it doesn't trigger the pause; `undefined` on
   * touch pointers.
   */
  onHoverChange?: (hovered: boolean) => void
}

/**
 * A Zora wallet screen shown in the hero while the headline word is "wallet".
 * The panel cross-fades in first; once settled, the estimated value rolls up
 * ONCE from 0 to `WALLET_VALUE_BASE` and then holds — no perpetual ticker, so the
 * digits never scramble mid-transition. Powered by NumberFlow (matches web's
 * MotionNumberFlow: the kvin.me spring curve, 425ms transform, 250ms opacity
 * fade). Under prefers-reduced-motion it renders the value at rest immediately.
 * Decorative — labelled as a single image for AT.
 */
export function WalletPanel({ reduceMotion, onHoverChange }: WalletPanelProps) {
  const [value, setValue] = useState(reduceMotion ? WALLET_VALUE_BASE : 0)

  useEffect(() => {
    if (reduceMotion) {
      setValue(WALLET_VALUE_BASE)

      return
    }
    // Hold at 0 through the enter cross-fade, then roll up once on the settled
    // panel. No interval — the value stays static after the single roll.
    const id = setTimeout(() => setValue(WALLET_VALUE_BASE), ROLL_DELAY_MS)

    return () => clearTimeout(id)
  }, [reduceMotion])

  return (
    <div
      className={styles.panel}
      role="img"
      aria-label={`Zora wallet — estimated value ${WALLET_VALUE}`}
      onMouseEnter={onHoverChange ? () => onHoverChange(true) : undefined}
      onMouseLeave={onHoverChange ? () => onHoverChange(false) : undefined}
    >
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
          style={{ '--number-flow-mask-height': '0.1em' } as CSSProperties}
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
  )
}
