/**
 * ImagePart — renders an inline image part (pasted images, SendUserFile
 * deliveries, image tool results). `src` is either a data: URL (bytes in the
 * transcript) or `/admin/file?path=…` (streamed from disk by the backend).
 *
 * Click opens the full image in a new tab. Broken/missing files degrade to a
 * small placeholder rather than a busted <img>.
 */

import { useState } from "react";

export function ImagePart({ src, alt, caption }: { src: string; alt?: string; caption?: string }) {
  const [broken, setBroken] = useState(false);

  if (broken) {
    return (
      <div
        style={{
          fontSize: 11.5,
          color: "var(--fg-muted)",
          fontFamily: "var(--font-mono)",
          border: "1px dashed var(--border)",
          borderRadius: 8,
          padding: "8px 10px",
        }}
      >
        image unavailable{alt ? ` — ${alt}` : ""}
      </div>
    );
  }

  return (
    <figure style={{ margin: 0, display: "flex", flexDirection: "column", gap: 6 }}>
      <a href={src} target="_blank" rel="noreferrer" style={{ display: "inline-block", lineHeight: 0 }}>
        <img
          src={src}
          alt={alt ?? "image"}
          loading="lazy"
          onError={() => setBroken(true)}
          style={{
            maxWidth: "100%",
            maxHeight: 380,
            objectFit: "contain",
            borderRadius: 8,
            border: "1px solid var(--border)",
            background: "var(--bg-canvas)",
          }}
        />
      </a>
      {caption && (
        <figcaption style={{ fontSize: 11.5, color: "var(--fg-muted)", lineHeight: 1.4 }}>
          {caption}
        </figcaption>
      )}
    </figure>
  );
}
