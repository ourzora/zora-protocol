import { useCallback, useEffect, useRef, useState } from "react";

/**
 * Copy text to the clipboard and flash a `copied` flag for `resetMs`.
 *
 * SSR-safe (guards `navigator`) and **honest**: `copied` only flips to `true`
 * when the text genuinely reached the clipboard — it never shows a false
 * confirmation. `copy()` resolves to a boolean so callers can offer their own
 * fallback when copying isn't possible (an insecure origin with no Clipboard
 * API, or a permissions rejection). Clears its reset timer on unmount.
 */
export function useCopyToClipboard(resetMs = 1800) {
  const [copied, setCopied] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    return () => {
      if (timer.current) clearTimeout(timer.current);
    };
  }, []);

  /** Resolves `true` only when the text actually made it to the clipboard. */
  const copy = useCallback(
    async (text: string): Promise<boolean> => {
      if (typeof navigator === "undefined" || !navigator.clipboard) {
        return false;
      }
      try {
        await navigator.clipboard.writeText(text);
      } catch (error) {
        // Couldn't copy (permissions / not focused). Report failure so the
        // caller can fall back instead of flashing a false confirmation.
        if (process.env.NODE_ENV === "development") {
          console.debug("clipboard copy failed", error);
        }
        return false;
      }
      setCopied(true);
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(() => setCopied(false), resetMs);
      return true;
    },
    [resetMs],
  );

  return { copied, copy };
}
