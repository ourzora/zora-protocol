import { useState, useCallback, useRef, type ReactNode } from "react";

function ClipboardIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <rect x="9" y="9" width="13" height="13" rx="0" ry="0" />
      <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg
      width="16"
      height="16"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      strokeLinecap="round"
      strokeLinejoin="round"
    >
      <polyline points="20 6 9 17 4 12" />
    </svg>
  );
}

export function CopyBox({ children }: { children: ReactNode }) {
  const [copied, setCopied] = useState(false);
  const contentRef = useRef<HTMLSpanElement>(null);

  const handleCopy = useCallback(() => {
    const text =
      typeof children === "string"
        ? children
        : (contentRef.current?.textContent ?? "");
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, [children]);

  return (
    <div
      style={{
        position: "relative",
        border: "1px solid var(--zora-border-neutral)",
        background: "transparent",
        padding: "0.75rem 2.5rem 0.75rem 1rem",
        fontFamily: "var(--font-mono)",
        fontSize: "0.875rem",
        lineHeight: 1.6,
        overflow: "auto",
      }}
    >
      <span ref={contentRef}>{children}</span>
      <button
        onClick={handleCopy}
        style={{
          position: "absolute",
          top: "50%",
          right: "0.625rem",
          transform: "translateY(-50%)",
          background: "none",
          border: "none",
          cursor: "pointer",
          padding: "0.25rem",
          opacity: copied ? 1 : 0.4,
          transition: "opacity 0.2s",
          color: copied
            ? "var(--vocs-color_textAccent)"
            : "var(--vocs-color_text2)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
        onMouseEnter={(e) => (e.currentTarget.style.opacity = "1")}
        onMouseLeave={(e) =>
          (e.currentTarget.style.opacity = copied ? "1" : "0.4")
        }
      >
        {copied ? <CheckIcon /> : <ClipboardIcon />}
      </button>
    </div>
  );
}
