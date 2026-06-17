import { AnimatePresence, motion, useReducedMotion } from "motion/react";

import { PROFILE_DECKS, type HeadlineTerm } from "../data";
import { DmConversation } from "./DmConversation";
import styles from "./ProfileCardDeck.module.css";
import { WalletPanel } from "./WalletPanel";

interface ProfileCardDeckProps {
  /** Active cycling term — kept in lockstep with the headline by the parent. */
  term: HeadlineTerm;
  /**
   * Reports pointer enter/leave on the deck so the parent can pause the
   * auto-cycle while the user inspects the current panel. The parent passes
   * `undefined` on touch (non-hover) pointers, so a tap never strands the
   * cycle in a paused state.
   */
  onHoverChange?: (hovered: boolean) => void;
}

// The card present in BOTH the solo (profile) and trio (network) decks. It
// persists across that swap and morphs in place rather than cross-fading.
const CENTER_HANDLE = PROFILE_DECKS.profile[0].handle;

/**
 * The hero visual that swaps in lockstep with the cycling headline word. "DMs"
 * shows an iMessage-style conversation, "wallet" a Zora wallet screen, and
 * "profile" / "network" the card deck. Those two SHARE one stage so the centre
 * card (the same agent in both) persists and morphs — resizing from the solo
 * 540px to the trio 420px while the two side cards fan in — instead of
 * cross-fading. Card↔panel swaps still cross-fade as a group. Transform +
 * opacity only; reduced-motion-gated.
 */
export function ProfileCardDeck({ term, onHoverChange }: ProfileCardDeckProps) {
  const reduceMotion = useReducedMotion();

  // On-screen morph budget, locked to the headline beat.
  const duration = reduceMotion ? 0.18 : 0.34;
  // Tuple-typed so motion reads it as one cubic-bezier, not an Easing[].
  const ease: [number, number, number, number] = [0.645, 0.045, 0.355, 1]; // --ease-in-out-cubic

  // profile + network share ONE stage key, so swapping between them updates in
  // place (centre card persists + morphs, side cards fan in) instead of
  // cross-fading. DMs / wallet are their own stages, so card↔panel still fades.
  const stageKey =
    term === "DMs" ? "dms" : term === "wallet" ? "wallet" : "cards";
  const deck = PROFILE_DECKS[term];

  return (
    <div className={styles.viewport}>
      <AnimatePresence mode="popLayout" initial={false}>
        <motion.div
          key={stageKey}
          className={styles.stage}
          initial={
            reduceMotion
              ? { opacity: 0 }
              : { opacity: 0, transform: "translateY(12px) scale(0.985)" }
          }
          animate={{ opacity: 1, transform: "translateY(0px) scale(1)" }}
          exit={
            reduceMotion
              ? { opacity: 0 }
              : { opacity: 0, transform: "translateY(-12px) scale(0.985)" }
          }
          transition={{ duration, ease }}
        >
          {term === "DMs" ? (
            <DmConversation
              reduceMotion={reduceMotion}
              onHoverChange={onHoverChange}
            />
          ) : term === "wallet" ? (
            <WalletPanel
              reduceMotion={reduceMotion}
              onHoverChange={onHoverChange}
            />
          ) : (
            <div
              className={styles.deck}
              onMouseEnter={
                onHoverChange ? () => onHoverChange(true) : undefined
              }
              onMouseLeave={
                onHoverChange ? () => onHoverChange(false) : undefined
              }
            >
              {deck.map((profile, i) => {
                // The centre card persists across profile↔network and `layout`-
                // morphs (540 solo → 420 trio). The side cards mount on network
                // and fan out from behind it (transform entrance — kept off the
                // `layout` track to avoid transform fights).
                const isCenter = profile.handle === CENTER_HANDLE;
                const fanX = i === 0 ? 32 : -32; // left starts shifted right, right shifted left
                return (
                  <motion.img
                    // Stable per-handle key: the centre agent is reused across
                    // profile↔network (so it persists + morphs); the siblings
                    // mount/unmount.
                    key={profile.handle}
                    src={profile.image}
                    alt={`${profile.name} — ${profile.bio}`}
                    className={styles.imageCard}
                    draggable={false}
                    tabIndex={-1}
                    layout={!reduceMotion && isCenter}
                    transition={{ duration: 0.42, ease }}
                    {...(reduceMotion || isCenter
                      ? {}
                      : {
                          initial: { opacity: 0, scale: 0.82, x: fanX },
                          animate: { opacity: 1, scale: 1, x: 0 },
                        })}
                    {...(reduceMotion ? {} : { whileHover: { y: -6 } })}
                  />
                );
              })}
            </div>
          )}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
