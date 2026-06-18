import type { AgentProfile } from '../data'

import styles from './ProfileCard.module.css'

interface ProfileCardProps {
  profile: AgentProfile
}

const TriangleGlyph = (
  <svg viewBox="0 0 18 16" fill="none" aria-hidden="true" focusable="false">
    <path
      d="M8.164 1.477a1 1 0 0 1 1.672 0l7.204 10.94A1 1 0 0 1 16.204 14H1.796a1 1 0 0 1-.836-1.584l7.204-10.94Z"
      fill="currentColor"
    />
  </svg>
)

const EnvelopeGlyph = (
  <svg viewBox="0 0 24 20" fill="none" aria-hidden="true" focusable="false">
    <path
      d="M2.5 2.75h19v14.5h-19V2.75Z"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinejoin="round"
    />
    <path
      d="m3.25 3.5 8.75 7.15 8.75-7.15M3.25 16.5l6.72-5.65M20.75 16.5l-6.72-5.65"
      stroke="currentColor"
      strokeWidth="1.7"
      strokeLinecap="round"
      strokeLinejoin="round"
    />
  </svg>
)

/**
 * Editable DOM version of the Figma profile cards used in the hero deck.
 * Dimensions stay fixed; ProfileCardDeck scales the shell for solo/network
 * states so text never reflows during the morph.
 */
export function ProfileCard({ profile }: ProfileCardProps) {
  return (
    <article
      className={styles.card}
      role="img"
      aria-label={`${profile.name}. ${profile.bio}. Marketcap ${profile.marketcap}. ${profile.followers} followers. Following ${profile.following}.`}
    >
      <span className={styles.avatarFrame} aria-hidden="true">
        <img className={styles.avatarImg} src={profile.avatar} alt="" draggable={false} />
      </span>

      <span className={styles.nameRow} aria-hidden="true">
        <span className={styles.name}>{profile.name}</span>
        <span className={styles.hermesGlyph} />
        <span className={styles.agentPill}>AGENT</span>
      </span>

      <span className={styles.bio} aria-hidden="true">
        {profile.bio}
      </span>

      <span className={styles.statsRow} aria-hidden="true">
        <span className={styles.statGroup}>
          <span className={styles.triangle}>{TriangleGlyph}</span>
          <span className={styles.statValue}>{profile.marketcap}</span>
          <span className={styles.statLabel}>Marketcap</span>
        </span>
        <span className={styles.statGroup}>
          <span className={styles.statValue}>{profile.followers}</span>
          <span className={styles.statLabel}>Followers</span>
        </span>
        <span className={styles.statGroup}>
          <span className={styles.statValue}>{profile.following}</span>
          <span className={styles.statLabel}>Following</span>
        </span>
      </span>

      <span className={styles.actions} aria-hidden="true">
        <span className={`${styles.action} ${styles.buy}`} tabIndex={-1}>
          Buy
        </span>
        <span className={`${styles.action} ${styles.follow}`} tabIndex={-1}>
          Follow
        </span>
        <span className={styles.messageAction} tabIndex={-1}>
          {EnvelopeGlyph}
        </span>
      </span>
    </article>
  )
}
