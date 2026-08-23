#!/usr/bin/env python3
"""Generate appcast.xml, embedding the CHANGELOG section for the released version."""

import argparse
import html
import re
import sys
from email.utils import format_datetime
from datetime import datetime, timezone
from pathlib import Path
from xml.sax.saxutils import quoteattr

NOTES_STYLE = """
:root { color-scheme: light dark; }
body {
  font: -apple-system-body, -apple-system, system-ui, sans-serif;
  margin: 0; padding: 12px 14px;
  color: #1d1d1f; background: transparent;
}
h3 { font-size: 1.02em; margin: 1.1em 0 0.45em; letter-spacing: -0.01em; }
h3:first-child { margin-top: 0; }
ul { margin: 0 0 0.5em; padding-left: 1.25em; }
li { margin-bottom: 0.35em; }
code {
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 0.9em; background: rgba(127,127,127,0.16);
  padding: 0.1em 0.32em; border-radius: 4px;
}
@media (prefers-color-scheme: dark) { body { color: #f5f5f7; } }
"""


def inline_markdown(text: str) -> str:
    """Escape HTML, then re-apply the inline markdown we support."""
    out = html.escape(text)
    out = re.sub(r"`([^`]+)`", r"<code>\1</code>", out)
    out = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", out)
    out = re.sub(r"\*([^*]+)\*", r"<em>\1</em>", out)
    out = re.sub(r"\[([^\]]+)\]\((https?://[^)]+)\)", r'<a href="\2">\1</a>', out)
    return out


def extract_section(changelog: str, version: str) -> str:
    """Return the body of the '## [version]' section, or '' when absent."""
    pattern = rf"^## \[{re.escape(version)}\].*?$(.*?)(?=^## \[|\Z)"
    match = re.search(pattern, changelog, re.MULTILINE | re.DOTALL)
    return match.group(1).strip() if match else ""


def render_notes(section: str) -> str:
    """Convert the supported subset of markdown to HTML."""
    parts, buffer, pending = [], [], []

    def flush_list():
        if buffer:
            parts.append("<ul>" + "".join(f"<li>{item}</li>" for item in buffer) + "</ul>")
            buffer.clear()

    def flush_paragraph():
        if pending:
            parts.append(f"<p>{' '.join(pending)}</p>")
            pending.clear()

    for raw in section.splitlines():
        line = raw.rstrip()
        if line.startswith("### "):
            flush_list(); flush_paragraph()
            parts.append(f"<h3>{inline_markdown(line[4:])}</h3>")
        elif line.startswith("- "):
            flush_paragraph()
            buffer.append(inline_markdown(line[2:]))
        elif line.startswith("  ") and buffer:
            buffer[-1] += " " + inline_markdown(line.strip())
        elif not line:
            flush_list(); flush_paragraph()
        else:
            flush_list()
            pending.append(inline_markdown(line))

    flush_list()
    flush_paragraph()
    return "".join(parts)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--length", required=True)
    parser.add_argument("--signature", required=True)
    parser.add_argument("--app-name", default="Compressyx")
    parser.add_argument("--min-system", default="14.0")
    parser.add_argument("--changelog", default="CHANGELOG.md")
    parser.add_argument("--output", default="appcast.xml")
    parser.add_argument("--pub-date", default=None)
    args = parser.parse_args()

    changelog_path = Path(args.changelog)
    section = extract_section(changelog_path.read_text(), args.version) if changelog_path.exists() else ""
    if not section:
        print(f"warning: no CHANGELOG section for {args.version}; publishing without notes", file=sys.stderr)

    notes = render_notes(section)
    description = ""
    if notes:
        body = f"<style>{NOTES_STYLE}</style>{notes}"
        # A CDATA block cannot contain the terminator itself.
        body = body.replace("]]>", "]]&gt;")
        description = f"\n            <description><![CDATA[{body}]]></description>"

    pub_date = args.pub_date or format_datetime(datetime.now(timezone.utc))

    appcast = f"""<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>{html.escape(args.app_name)}</title>
        <description>{html.escape(args.app_name)} update feed</description>
        <language>en</language>
        <item>
            <title>Version {html.escape(args.version)}</title>
            <sparkle:version>{html.escape(args.version)}</sparkle:version>
            <sparkle:shortVersionString>{html.escape(args.version)}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>{html.escape(args.min_system)}</sparkle:minimumSystemVersion>
            <pubDate>{html.escape(pub_date)}</pubDate>{description}
            <enclosure
                url={quoteattr(args.url)}
                length={quoteattr(args.length)}
                type="application/octet-stream"
                sparkle:edSignature={quoteattr(args.signature)} />
        </item>
    </channel>
</rss>
"""
    Path(args.output).write_text(appcast)
    print(f"wrote {args.output} for {args.version} ({len(notes)} bytes of notes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
