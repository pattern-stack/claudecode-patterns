/**
 * Cursor atom — blinking emerald block, used inline at the end of a
 * streaming assistant text bubble. Animation lives in globals.css
 * (`apdash-blink`); this is purely a styled span.
 */

export function Cursor() {
  return (
    <span
      aria-hidden="true"
      style={{
        display: "inline-block",
        width: 7,
        height: 14,
        marginLeft: 2,
        background: "var(--accent-emerald)",
        verticalAlign: "-2px",
        animation: "apdash-blink 1s steps(2, start) infinite",
      }}
    />
  );
}
