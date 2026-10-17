"""List new posts about working with AI, for the checkup's research phase.

Reads a short list of RSS and Atom feeds and prints only the items that no
earlier checkup has seen. It never acts on an item; the agent triages each
one with the ambition lenses and files a task or asks the owner.

  scan    fetch the feeds, print unseen items, save them as pending
  record  mark the pending items as seen (run it after the triage)

Feeds: FEEDS below. TOOLING_CHECKUP_AI_FEEDS (one "name url" pair per line)
replaces them; ~/.config/dotfiles/ai-research-feeds (same format, # comments)
adds to them.
State: $TOOLING_CHECKUP_STATE_DIR/ai-research-seen.json and
ai-research-pending.json (default ~/.local/state/tooling-checkup).
"""

import argparse
import http.client
import json
import os
import sys
import time
import urllib.request
import xml.etree.ElementTree as ET
from email.utils import parsedate_to_datetime
from datetime import datetime, timezone
from pathlib import Path

FEEDS = (
    ("claude-code-releases", "https://github.com/anthropics/claude-code/releases.atom"),
    ("simon-willison", "https://simonwillison.net/atom/everything/"),
    ("felix-rieseberg", "https://felixrieseberg.com/rss/"),
    ("latent-space", "https://www.latent.space/feed"),
)
EXTRA_FEEDS_FILE = Path.home() / ".config/dotfiles/ai-research-feeds"
ATOM = "{http://www.w3.org/2005/Atom}"
TIMEOUT_S = 10
SEEN_KEEP_DAYS = 365


def state_dir():
    base = os.environ.get("TOOLING_CHECKUP_STATE_DIR") or os.path.expanduser("~/.local/state/tooling-checkup")
    return Path(base)


def parse_feed_lines(text):
    feeds = []
    for line in text.splitlines():
        line = line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        name, url = (parts[0], parts[1]) if len(parts) > 1 else (parts[0].split("/")[2] or "feed", parts[0])
        feeds.append((name, url))
    return feeds


def load_feeds():
    if os.environ.get("TOOLING_CHECKUP_AI_FEEDS"):
        return parse_feed_lines(os.environ["TOOLING_CHECKUP_AI_FEEDS"])
    feeds = list(FEEDS)
    if EXTRA_FEEDS_FILE.is_file():
        feeds += parse_feed_lines(EXTRA_FEEDS_FILE.read_text())
    return feeds


def parse_date(text):
    if not text:
        return None
    text = text.strip()
    try:
        return parsedate_to_datetime(text).astimezone(timezone.utc)
    except (TypeError, ValueError):
        pass
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00")).astimezone(timezone.utc)
    except ValueError:
        return None


def parse_items(data):
    root = ET.fromstring(data)
    items = []
    for entry in root.iter(f"{ATOM}entry"):
        # An Element with no children is falsy, so compare with None, not `or`.
        link = entry.find(f"{ATOM}link[@rel='alternate']")
        if link is None:
            link = entry.find(f"{ATOM}link")
        items.append({
            "title": (entry.findtext(f"{ATOM}title") or "").strip(),
            "link": link.get("href", "").strip() if link is not None else "",
            "date": parse_date(entry.findtext(f"{ATOM}published") or entry.findtext(f"{ATOM}updated")),
        })
    for item in root.iter("item"):
        items.append({
            "title": (item.findtext("title") or "").strip(),
            "link": (item.findtext("link") or "").strip(),
            "date": parse_date(item.findtext("pubDate")),
        })
    return [i for i in items if i["link"]]


def fetch(url, tries=2):
    # Agent sandbox proxies can cut a large feed short (IncompleteRead); retry once.
    req = urllib.request.Request(url, headers={"User-Agent": "tooling-checkup/1"})
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT_S) as resp:
                return resp.read()
        except http.client.IncompleteRead:
            if attempt == tries - 1:
                raise


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def scan(args):
    seen = read_json(state_dir() / "ai-research-seen.json", {})
    cutoff = time.time() - args.days * 86400
    pending, errors = [], 0
    for name, url in load_feeds():
        try:
            items = parse_items(fetch(url))
        except Exception as exc:  # one bad feed must not stop the scan
            errors += 1
            print(f"source: {name} error: {type(exc).__name__}: {exc}")
            continue
        fresh = [i for i in items if i["link"] not in seen
                 and (i["date"] is None or i["date"].timestamp() >= cutoff)]
        fresh.sort(key=lambda i: i["date"].timestamp() if i["date"] else 0, reverse=True)
        fresh = fresh[: args.limit]
        print(f"source: {name} ok {len(items)} item(s), {len(fresh)} new")
        for i in fresh:
            day = i["date"].strftime("%Y-%m-%d") if i["date"] else "undated"
            print(f"new: {day} {name} | {i['title']} | {i['link']}")
            pending.append(i["link"])
    out = state_dir()
    out.mkdir(parents=True, exist_ok=True)
    (out / "ai-research-pending.json").write_text(json.dumps(pending, indent=2) + "\n")
    print(f"research: {len(pending)} new item(s), {errors} feed error(s)")
    print(f"record: --metric ai_research_new={len(pending)}")
    return 0


def record(_args):
    out = state_dir()
    pending = read_json(out / "ai-research-pending.json", [])
    seen = read_json(out / "ai-research-seen.json", {})
    now = int(time.time())
    for link in pending:
        seen.setdefault(link, now)
    keep_after = now - SEEN_KEEP_DAYS * 86400
    seen = {k: v for k, v in seen.items() if v >= keep_after}
    out.mkdir(parents=True, exist_ok=True)
    (out / "ai-research-seen.json").write_text(json.dumps(seen, indent=2, sort_keys=True) + "\n")
    (out / "ai-research-pending.json").write_text("[]\n")
    print(f"recorded: {len(pending)} item(s) as seen, {len(seen)} kept")
    return 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("scan", help="print unseen feed items and save them as pending")
    s.add_argument("--days", type=int, default=21, help="ignore items older than this")
    s.add_argument("--limit", type=int, default=5, help="new items per feed")
    s.set_defaults(func=scan)
    r = sub.add_parser("record", help="mark the pending items as seen")
    r.set_defaults(func=record)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
