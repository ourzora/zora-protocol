import { useState, useEffect, useRef } from "react";

// ── Design tokens (hardcoded for consistent look in light/dark mode) ──
const BG = "#ffffff";
const FG = "#1a1a1a";
const DIM = "#999999";
const GREEN = "#00df00";
const PINK = "#ff00f0";
const BORDER = "#e5e5e5";

const FONT_FAMILY =
  '"ABC Monument Grotesk Mono", "SF Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace';

const PROMPT = "\u276f";
const FPS = 30;
const TOTAL_FRAMES = 315;

// ── Scene 1: explore ──
const CMD_EXPLORE = "Find the top coins on Zora";

const TABLE_COLUMNS = [
  { label: "Name", flex: 1, align: "left" as const },
  { label: "Type", width: "13ch", align: "left" as const },
  { label: "Market Cap", width: "12ch", align: "right" as const },
  { label: "Vol 24h", width: "10ch", align: "right" as const },
  { label: "Change", width: "10ch", align: "right" as const },
];

const TABLE_ROWS = [
  { n: "1", name: "benjitaylor", type: "creator-coin", cap: "$42.3K", vol: "$8.7K", change: "+12.4%", positive: true },
  { n: "2", name: "horse", type: "post", cap: "$18.1K", vol: "$5.2K", change: "+89.3%", positive: true },
  { n: "3", name: "adhd", type: "trend", cap: "$9.4K", vol: "$3.1K", change: "-2.8%", positive: false },
  { n: "4", name: "worklunch", type: "trend", cap: "$6.7K", vol: "$1.9K", change: "+34.1%", positive: true },
  { n: "5", name: "ruihuangart", type: "creator-coin", cap: "$31.5K", vol: "$4.6K", change: "+7.2%", positive: true },
];

// ── Scene 2: buy ──
const CMD_BUY = "Buy $20 of the #1 coin";
const BUY_OUTPUT = [
  "\u2713 Bought 1,813.12 benjitaylor",
  "  Spent:    0.0064 ETH ($20.00)",
  "  Price:    $0.01103 per coin",
  "  Network:  Base",
];

// ── Scene 3: balance ──
const CMD_BALANCE = "Track my positions";
const COIN_COLUMNS = [
  { label: "Name", flex: 1, align: "left" as const },
  { label: "Type", width: "13ch", align: "left" as const },
  { label: "Balance", width: "12ch", align: "right" as const },
  { label: "Value", width: "10ch", align: "right" as const },
];

const COIN_ROW = {
  n: "1",
  name: "benjitaylor",
  type: "creator-coin",
  balance: "1,813.12",
};

const COST_BASIS = 20;
const VALUE_TICKS = [20.12, 18.2, 22.1, 26.1, 31.2, 35.2, 40.12];

// ── Physics ──

function computeSpring(
  framesSinceStart: number,
  config: { damping: number; stiffness: number; mass: number },
): number {
  if (framesSinceStart <= 0) return 0;
  let position = 0;
  let velocity = 0;
  const dt = 1 / FPS;
  for (let i = 0; i < framesSinceStart; i++) {
    const springForce = -config.stiffness * (position - 1);
    const dampingForce = -config.damping * velocity;
    velocity += ((springForce + dampingForce) / config.mass) * dt;
    position += velocity * dt;
  }
  return Math.max(0, Math.min(position, 2));
}

function lerp(
  value: number,
  inMin: number,
  inMax: number,
  outMin: number,
  outMax: number,
): number {
  const t = Math.max(0, Math.min(1, (value - inMin) / (inMax - inMin)));
  return outMin + t * (outMax - outMin);
}

function typedChars(
  frame: number,
  start: number,
  speed: number,
  text: string,
): number {
  const elapsed = frame - start;
  if (elapsed < 0) return 0;
  return Math.min(Math.floor(elapsed * speed), text.length);
}

function fade(frame: number, start: number, duration = 6): number {
  return lerp(frame, start, start + duration, 0, 1);
}

// ── Sub-components ──

function Cursor({ visible }: { visible: boolean }) {
  return (
    <span
      style={{
        display: "inline-block",
        width: "0.6em",
        height: "1.15em",
        backgroundColor: visible ? GREEN : "transparent",
        verticalAlign: "text-bottom",
        marginLeft: 1,
      }}
    />
  );
}

function PromptLine({
  typed,
  showCursor,
}: {
  typed: string;
  showCursor: boolean;
}) {
  return (
    <div style={{ display: "flex", gap: 8 }}>
      <span style={{ color: GREEN }}>{PROMPT}</span>
      <span style={{ color: FG }}>
        {typed}
        <Cursor visible={showCursor} />
      </span>
    </div>
  );
}

// ── Main ──

export function TerminalAnimation() {
  const [frame, setFrame] = useState(0);
  const containerRef = useRef<HTMLDivElement>(null);
  const rafRef = useRef<number>(0);
  const startRef = useRef<number | null>(null);

  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;

    // Respect prefers-reduced-motion
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      setFrame(0);
      return;
    }

    const startLoop = () => {
      const tick = (timestamp: number) => {
        if (startRef.current === null) startRef.current = timestamp;
        const elapsed = timestamp - startRef.current;
        const f = Math.floor((elapsed * FPS) / 1000);
        if (f >= TOTAL_FRAMES) {
          startRef.current = timestamp;
          setFrame(0);
        } else {
          setFrame(f);
        }
        rafRef.current = requestAnimationFrame(tick);
      };
      rafRef.current = requestAnimationFrame(tick);
    };

    const stopLoop = () => {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = 0;
    };

    // Pause when off-screen — truly stop the RAF loop
    const observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          startRef.current = null; // reset timing to avoid jump
          startLoop();
        } else {
          stopLoop();
        }
      },
      { threshold: 0.1 },
    );
    observer.observe(el);

    return () => {
      stopLoop();
      observer.disconnect();
    };
  }, []);

  // ── Timeline ──
  const S1_TYPE_START = 10;
  const S1_SPEED = 1.8;
  const S1_TYPE_END =
    S1_TYPE_START + Math.ceil(CMD_EXPLORE.length / S1_SPEED);
  const S1_LABEL = S1_TYPE_END + 15;
  const S1_HEADER = S1_LABEL + 8;
  const S1_ROWS = S1_HEADER + 8;
  const S1_ROW_GAP = 5;
  const S1_HOLD = S1_ROWS + 5 * S1_ROW_GAP + 20;

  const S2_TYPE_START = S1_HOLD;
  const S2_SPEED = 2.0;
  const S2_TYPE_END = S2_TYPE_START + Math.ceil(CMD_BUY.length / S2_SPEED);
  const S2_OUTPUT = S2_TYPE_END + 12;
  const S2_LINE_GAP = 5;
  const S2_HOLD = S2_OUTPUT + BUY_OUTPUT.length * S2_LINE_GAP + 25;

  const S3_TYPE_START = S2_HOLD;
  const S3_SPEED = 2.0;
  const S3_TYPE_END =
    S3_TYPE_START + Math.ceil(CMD_BALANCE.length / S3_SPEED);
  const S3_OUTPUT = S3_TYPE_END + 12;
  const S3_ROW = S3_OUTPUT + 15;
  const S3_LIVE_START = S3_ROW + 10;
  const S3_TICK_INTERVAL = 8;
  const S3_LAST_TICK =
    S3_LIVE_START + (VALUE_TICKS.length - 1) * S3_TICK_INTERVAL;
  const EXIT_START = S3_LAST_TICK + 20;

  // Cursor
  const cursorBlink = Math.floor(frame / 15) % 2 === 0;

  const s1Typing =
    frame >= S1_TYPE_START &&
    typedChars(frame, S1_TYPE_START, S1_SPEED, CMD_EXPLORE) <
      CMD_EXPLORE.length;
  const s2Typing =
    frame >= S2_TYPE_START &&
    typedChars(frame, S2_TYPE_START, S2_SPEED, CMD_BUY) < CMD_BUY.length;
  const s3Typing =
    frame >= S3_TYPE_START &&
    typedChars(frame, S3_TYPE_START, S3_SPEED, CMD_BALANCE) <
      CMD_BALANCE.length;

  let activeScene = 1;
  if (frame >= S2_TYPE_START) activeScene = 2;
  if (frame >= S3_TYPE_START) activeScene = 3;

  const s1Cursor =
    activeScene === 1 && (s1Typing || (frame < S1_LABEL && cursorBlink));
  const s2Cursor =
    activeScene === 2 && (s2Typing || (frame < S2_OUTPUT && cursorBlink));
  const s3Cursor =
    activeScene === 3 && (s3Typing || (frame < S3_OUTPUT && cursorBlink));

  const s1Typed = CMD_EXPLORE.slice(
    0,
    typedChars(frame, S1_TYPE_START, S1_SPEED, CMD_EXPLORE),
  );
  const s2Typed = CMD_BUY.slice(
    0,
    typedChars(frame, S2_TYPE_START, S2_SPEED, CMD_BUY),
  );
  const s3Typed = CMD_BALANCE.slice(
    0,
    typedChars(frame, S3_TYPE_START, S3_SPEED, CMD_BALANCE),
  );

  // Scroll
  const SCROLL_1 = 180;
  const SCROLL_2 = 150;
  const SCROLL_3 = 180;
  const SCROLL_LEAD = 12;
  const springConfig = { damping: 14, stiffness: 80, mass: 0.8 };

  const spring1 = computeSpring(
    frame - (S2_TYPE_START - SCROLL_LEAD),
    springConfig,
  );
  const spring2 = computeSpring(
    frame - (S3_TYPE_START - SCROLL_LEAD),
    springConfig,
  );
  const spring3 = computeSpring(frame - EXIT_START, springConfig);
  const scrollY = spring1 * SCROLL_1 + spring2 * SCROLL_2 + spring3 * SCROLL_3;

  const exitOpacity = lerp(frame, EXIT_START, EXIT_START + 20, 1, 0);

  const dots = [
    { color: "#ff5f57" },
    { color: "#febc2e" },
    { color: "#28c840" },
  ];

  return (
    <div ref={containerRef} className="terminal-animation">
      <div
        style={{
          width: 580,
          maxWidth: "100%",
          backgroundColor: BG,
          border: `1px solid ${BORDER}`,
          borderRadius: 0,
          fontFamily: FONT_FAMILY,
          fontSize: 14,
          lineHeight: 1.7,
          overflow: "hidden",
        }}
      >
        {/* Title bar */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            gap: 8,
            padding: "10px 14px",
            borderBottom: `1px solid ${BORDER}`,
          }}
        >
          {dots.map((d, i) => (
            <div
              key={i}
              style={{
                width: 12,
                height: 12,
                borderRadius: "50%",
                backgroundColor: d.color,
              }}
            />
          ))}
        </div>

        {/* Terminal body */}
        <div
          style={{
            height: 320,
            overflow: "hidden",
            position: "relative",
          }}
        >
          <div
            style={{
              padding: "16px 20px",
              transform: `translateY(-${scrollY}px)`,
              willChange: "transform",
              opacity: exitOpacity,
            }}
          >
            {/* Scene 1: explore */}
            <PromptLine typed={s1Typed} showCursor={s1Cursor} />

            {frame >= S1_LABEL && (
              <div style={{ marginTop: 12 }}>
                <div
                  style={{
                    opacity: fade(frame, S1_LABEL),
                    marginBottom: 6,
                  }}
                >
                  <span style={{ color: PINK, fontWeight: 700 }}>
                    Trending
                  </span>
                </div>

                <div
                  style={{
                    opacity: fade(frame, S1_HEADER),
                    color: DIM,
                    marginBottom: 2,
                    display: "flex",
                    gap: 0,
                  }}
                >
                  {TABLE_COLUMNS.map((col, i) => (
                    <span
                      key={i}
                      style={{
                        width: "width" in col ? col.width : undefined,
                        flex: "flex" in col ? col.flex : undefined,
                        textAlign: col.align,
                      }}
                    >
                      {col.label}
                    </span>
                  ))}
                </div>

                {TABLE_ROWS.map((row, i) => (
                  <div
                    key={i}
                    style={{
                      opacity: fade(frame, S1_ROWS + i * S1_ROW_GAP),
                      display: "flex",
                      gap: 0,
                    }}
                  >
                    <span style={{ color: FG, flex: 1 }}>
                      {row.name}
                    </span>
                    <span style={{ color: DIM, width: "13ch" }}>
                      {row.type}
                    </span>
                    <span
                      style={{
                        color: FG,
                        width: "12ch",
                        textAlign: "right",
                      }}
                    >
                      {row.cap}
                    </span>
                    <span
                      style={{
                        color: DIM,
                        width: "10ch",
                        textAlign: "right",
                      }}
                    >
                      {row.vol}
                    </span>
                    <span
                      style={{
                        color: row.positive ? GREEN : PINK,
                        width: "10ch",
                        textAlign: "right",
                      }}
                    >
                      {row.change}
                    </span>
                  </div>
                ))}
              </div>
            )}

            {/* Scene 2: buy */}
            {frame >= S2_TYPE_START && (
              <div style={{ marginTop: 16 }}>
                <PromptLine typed={s2Typed} showCursor={s2Cursor} />

                {frame >= S2_OUTPUT && (
                  <div style={{ marginTop: 8 }}>
                    {BUY_OUTPUT.map((line, i) => (
                      <div
                        key={i}
                        style={{
                          opacity: fade(frame, S2_OUTPUT + i * S2_LINE_GAP),
                          color: i === 0 ? GREEN : DIM,
                          fontWeight: i === 0 ? 700 : 400,
                        }}
                      >
                        {line}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {/* Scene 3: balance */}
            {frame >= S3_TYPE_START && (
              <div style={{ marginTop: 16 }}>
                <PromptLine typed={s3Typed} showCursor={s3Cursor} />

                {frame >= S3_OUTPUT &&
                  (() => {
                    const tick =
                      frame >= S3_LIVE_START
                        ? Math.min(
                            Math.floor(
                              (frame - S3_LIVE_START) / S3_TICK_INTERVAL,
                            ),
                            VALUE_TICKS.length - 1,
                          )
                        : 0;
                    const value = VALUE_TICKS[tick];
                    const profitable = value >= COST_BASIS;
                    const valueColor = profitable ? GREEN : PINK;
                    const valueStr = `$${value.toFixed(2)}`;

                    return (
                      <div style={{ marginTop: 8 }}>
                        <div
                          style={{
                            opacity: fade(frame, S3_OUTPUT),
                            color: PINK,
                            fontWeight: 700,
                            marginBottom: 6,
                          }}
                        >
                          Coin Positions
                        </div>
                        <div
                          style={{
                            opacity: fade(frame, S3_OUTPUT + 4),
                            color: DIM,
                            display: "flex",
                            gap: 0,
                            marginBottom: 2,
                          }}
                        >
                          {COIN_COLUMNS.map((col, i) => (
                            <span
                              key={i}
                              style={{
                                width: "width" in col ? col.width : undefined,
                                flex: "flex" in col ? col.flex : undefined,
                                textAlign: col.align,
                              }}
                            >
                              {col.label}
                            </span>
                          ))}
                        </div>
                        <div
                          style={{
                            opacity: fade(frame, S3_ROW),
                            display: "flex",
                            gap: 0,
                          }}
                        >
                          <span style={{ color: FG, flex: 1 }}>
                            {COIN_ROW.name}
                          </span>
                          <span style={{ color: DIM, width: "13ch" }}>
                            {COIN_ROW.type}
                          </span>
                          <span
                            style={{
                              color: DIM,
                              width: "12ch",
                              textAlign: "right",
                            }}
                          >
                            {COIN_ROW.balance}
                          </span>
                          <span
                            style={{
                              color: valueColor,
                              width: "10ch",
                              textAlign: "right",
                              fontWeight: 700,
                            }}
                          >
                            {valueStr}
                          </span>
                        </div>
                      </div>
                    );
                  })()}
              </div>
            )}
          </div>

          {/* New prompt after exit scroll */}
          {frame >= EXIT_START + 10 && (
            <div
              style={{
                position: "absolute",
                top: 0,
                left: 0,
                right: 0,
                padding: "16px 20px",
                opacity: fade(frame, EXIT_START + 10),
              }}
            >
              <PromptLine typed="" showCursor={true} />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
