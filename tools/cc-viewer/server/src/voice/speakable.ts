/**
 * Turn an assistant message (often markdown) into text worth saying out loud: no code, tables, link targets or
 * markup, capped near `maxChars` at a sentence end. The page still shows the full message.
 */

export function speakable(markdown: string, maxChars = 1200): string {
  let s = markdown
    .replace(/```[\s\S]*?```/g, " (code on screen) ")
    .replace(/^\s*\|.*\|\s*$/gm, "") // table rows
    .replace(/!\[([^\]]*)\]\([^)]*\)/g, "$1") // images
    .replace(/\[([^\]]+)\]\([^)]*\)/g, "$1") // links keep their words
    .replace(/https?:\/\/\S+/g, "a link")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/^\s{0,3}#{1,6}\s+/gm, "")
    .replace(/^\s*[-*+]\s+/gm, "")
    .replace(/(\*\*|__|\*|_)(\S[\s\S]*?\S|\S)\1/g, "$2")
    .replace(/^\s*>\s?/gm, "")
    .replace(/^\s*(-{3,}|\*{3,})\s*$/gm, "");
  s = s.replace(/\s*\(code on screen\)\s*(\(code on screen\)\s*)+/g, " (code on screen) ");
  s = s
    .replace(/[ \t]+/g, " ")
    .replace(/\s*\n\s*/g, "\n")
    .trim();
  if (s.length <= maxChars) return s;
  const cut = s.slice(0, maxChars);
  const end = Math.max(
    cut.lastIndexOf(". "),
    cut.lastIndexOf("? "),
    cut.lastIndexOf("! "),
    cut.lastIndexOf(".\n"),
  );
  return `${(end > maxChars / 2 ? cut.slice(0, end + 1) : cut).trim()} The rest is on screen.`;
}
