import { AnimatePresence, motion, useReducedMotion } from "motion/react";

import { PROFILE_DECKS, type HeadlineTerm } from "../data";
import { useHoverCapable } from "../lib/useHoverCapable";
import { DmConversation } from "./DmConversation";
import { ProfileCard } from "./ProfileCard";
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

// The agent shown in BOTH the solo (profile) and trio (network) views. It stays
// dead-centre and never moves; only its scale eases between the two states.
const CENTER = PROFILE_DECKS.profile[0];
// The two flanking agents, in render order [left, right]. They fan out from
// behind the centre card when the headline reaches "network".
const SIDES = PROFILE_DECKS.network.filter((p) => p.handle !== CENTER.handle);

// Card scales relative to the 486×282 base, matching the Figma trio
// (solo/centre/side ≈ 540/360/296px wide). The centre card is identical in the
// solo and network views — only the side cards mount/unmount — so the morph is
// pure scale + fade with no reflow, no FLIP, and no drift toward the CTA.
const SOLO_SCALE = 1.111;
const CENTER_SCALE = 0.741;
const SIDE_SCALE = 0.609;
// Horizontal offset of each side card's centre from the deck centre.
const SIDE_X = 348;
// Side cards enter/exit from closer to centre (sliding out from behind zari).
const SIDE_X_HIDDEN = 170;

// Mobile "network" view: a fanned cascade. The centre card (zari) lifts up and
// sits in front; the two flanking cards drop lower + behind and fan out wide
// enough that each one's outer half stays readable. Upright (no tilt). Outer
// edges may bleed to the viewport sides — clipped by `.zora-landing`'s
// overflow-x guard — so the trio reads as "more agents" with no doc overflow.
const MOBILE_CENTER_SCALE = 0.68;
const MOBILE_CENTER_Y = -16;
const MOBILE_SIDE_SCALE = 0.62;
const MOBILE_SIDE_X = 90;
const MOBILE_SIDE_Y = 6;
// Side cards enter/exit tucked closer behind the centre card.
const MOBILE_SIDE_X_HIDDEN = 34;

/**
 * The hero visual that swaps in lockstep with the cycling headline word. "DMs"
 * shows an iMessage-style conversation, "wallet" a Zora wallet screen, and
 * "profile" / "network" the profile-card deck. The card↔panel swap cross-fades
 * as a group; within the deck, profile↔network keeps the centre card fixed and
 * fans the two side cards in/out. Transform + opacity only; reduced-motion-gated.
 */
export function ProfileCardDeck({ term, onHoverChange }: ProfileCardDeckProps) {
  const reduceMotion = useReducedMotion();
  const hoverable = useHoverCapable();

  // Hover-lift only on real (fine, hover-capable) pointers, so a touch tap on a
  // large tablet never strands a card in its lifted state.
  const liftOnHover = hoverable && !reduceMotion;

  // Stage cross-fade budget, locked to the headline beat.
  const ease: [number, number, number, number] = [0.33, 1, 0.68, 1]; // easeOutCubic — settles, never overshoots
  const stageDuration = reduceMotion ? 0.18 : 0.26;
  // The card morph (Zari rescaling, side cards fanning) is transform-only, so it
  // takes a very subtle spring to feel alive — a faint settle, bounce kept low
  // so the scale never visibly pops (per /emil-design-engineering spring guidance).
  const cardTransition = reduceMotion
    ? { duration: 0 }
    : { type: "spring" as const, duration: 0.55, bounce: 0.14 };

  // profile + network share ONE stage key so swapping between them animates the
  // deck in place; DMs / wallet are their own stages, so card↔panel cross-fades.
  const stageKey =
    term === "DMs" ? "dms" : term === "wallet" ? "wallet" : "cards";
  const isNetwork = term === "network";

  const hoverHandlers = onHoverChange
    ? {
        onMouseEnter: () => onHoverChange(true),
        onMouseLeave: () => onHoverChange(false),
      }
    : {};

  return (
    <div className={styles.viewport}>
      {/* Default (sync) mode — NOT popLayout. The stages are grid-stacked
          (grid-area 1/1), so they overlap and cross-dissolve in place. Pure
          opacity — no vertical drift or scale — keeps the term swap clean and
          snappy, so the panels never read as two ghosts sliding past each other. */}
      <AnimatePresence initial={false}>
        <motion.div
          key={stageKey}
          className={styles.stage}
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          transition={{ duration: stageDuration, ease }}
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
            // profile / network — render BOTH decks; CSS media queries (in the
            // module) reveal exactly one. Toggling `display` instead of branching
            // in JS keeps SSR and first paint in agreement, so the prerendered
            // page never flips decks on hydration (no layout flash). `display`
            // also overrides the cards' inline motion transforms cleanly.
            <>
              {/* Desktop: cards stack in one centred cell and animate with
                  transform + opacity only. The centre card is always mounted and
                  only rescales between solo and network; the side cards fan in
                  from behind it. */}
              <div className={styles.stack} {...hoverHandlers}>
                <motion.div
                  className={styles.stackCard}
                  style={{ zIndex: 2 }}
                  animate={{
                    x: 0,
                    scale: isNetwork ? CENTER_SCALE : SOLO_SCALE,
                  }}
                  transition={cardTransition}
                  {...(liftOnHover ? { whileHover: { y: -6 } } : {})}
                >
                  <ProfileCard profile={CENTER} />
                </motion.div>

                <AnimatePresence initial={false}>
                  {isNetwork &&
                    SIDES.map((profile, i) => {
                      const dir = i === 0 ? -1 : 1;
                      return (
                        <motion.div
                          key={profile.handle}
                          className={styles.stackCard}
                          style={{ zIndex: 1 }}
                          initial={
                            reduceMotion
                              ? { opacity: 0 }
                              : {
                                  opacity: 0,
                                  x: dir * SIDE_X_HIDDEN,
                                  scale: SIDE_SCALE * 0.82,
                                }
                          }
                          animate={{
                            opacity: 1,
                            x: dir * SIDE_X,
                            scale: SIDE_SCALE,
                          }}
                          exit={
                            reduceMotion
                              ? { opacity: 0 }
                              : {
                                  opacity: 0,
                                  x: dir * SIDE_X_HIDDEN,
                                  scale: SIDE_SCALE * 0.82,
                                }
                          }
                          transition={cardTransition}
                          {...(liftOnHover ? { whileHover: { y: -6 } } : {})}
                        >
                          <ProfileCard profile={profile} />
                        </motion.div>
                      );
                    })}
                </AnimatePresence>
              </div>

              {/* Mobile: a compact centred stack. The centre card (zari) is
                  always mounted and only rescales between solo/network; the two
                  side cards tuck in/out behind it as a tight peek. Card scales
                  fluidly to the phone — no horizontal scroll, no fixed widths. */}
              <div className={styles.mobileStack} {...hoverHandlers}>
                <motion.div
                  className={styles.mobileLayer}
                  style={{ zIndex: 2 }}
                  animate={{
                    x: 0,
                    y: isNetwork ? MOBILE_CENTER_Y : 0,
                    scale: isNetwork ? MOBILE_CENTER_SCALE : 1,
                  }}
                  transition={cardTransition}
                >
                  <div className={styles.mobileScaler}>
                    <ProfileCard profile={CENTER} />
                  </div>
                </motion.div>

                <AnimatePresence initial={false}>
                  {isNetwork &&
                    SIDES.map((profile, i) => {
                      const dir = i === 0 ? -1 : 1;
                      const hidden = reduceMotion
                        ? { opacity: 0 }
                        : {
                            opacity: 0,
                            x: dir * MOBILE_SIDE_X_HIDDEN,
                            y: MOBILE_SIDE_Y * 0.5,
                            scale: MOBILE_SIDE_SCALE * 0.92,
                          };
                      return (
                        <motion.div
                          key={profile.handle}
                          className={styles.mobileLayer}
                          /* Left-to-right shingle: Rook (left) sits behind the centre
                           card, Atelier (right) in front — so each card's top-left
                           avatar peeks past its neighbour and all three read. */
                          style={{ zIndex: dir === 1 ? 3 : 1 }}
                          initial={hidden}
                          animate={{
                            opacity: 1,
                            x: dir * MOBILE_SIDE_X,
                            y: MOBILE_SIDE_Y,
                            scale: MOBILE_SIDE_SCALE,
                          }}
                          exit={hidden}
                          transition={cardTransition}
                        >
                          <div className={styles.mobileScaler}>
                            <ProfileCard profile={profile} />
                          </div>
                        </motion.div>
                      );
                    })}
                </AnimatePresence>
              </div>
            </>
          )}
        </motion.div>
      </AnimatePresence>
    </div>
  );
}
