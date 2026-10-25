#!/usr/bin/env python3
"""
tools/post_discord_changelog.py

Posts newly generated release notes / recent merged PR changelog
to a Discord webhook thread for TortoiseBotsManager.

Usage:
  export DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/..."
  export THREAD_ID="1542647578548772954"
  python3 tools/post_discord_changelog.py --notes /tmp/discord_notes.md --title "TortoiseBotsManager Update" --tag "v2026-09-21"
"""

import argparse
import json
import os
import sys
import urllib.request
import urllib.error


def split_text(text, max_len=3900):
    """Split markdown text cleanly along paragraph or line boundaries."""
    if len(text) <= max_len:
        return [text]

    chunks = []
    lines = text.split("\n")
    current_chunk = []
    current_len = 0

    for line in lines:
        line_len = len(line) + 1
        if current_len + line_len > max_len and current_chunk:
            chunks.append("\n".join(current_chunk))
            current_chunk = [line]
            current_len = line_len
        else:
            current_chunk.append(line)
            current_len += line_len

    if current_chunk:
        chunks.append("\n".join(current_chunk))

    return chunks


def send_discord_message(url, payload, method="POST"):
    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    headers = {
        "User-Agent": "TortoiseBotsManager-Changelog-Notifier/1.0"
    }
    if data:
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(
        url,
        data=data,
        headers=headers,
        method=method
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.status in (200, 204), resp.status
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")
        print(f"Discord API error HTTP {e.code}: {body}", file=sys.stderr)
        return False, e.code
    except Exception as e:
        print(f"Network error sending to Discord: {e}", file=sys.stderr)
        return False, 0


def main():
    parser = argparse.ArgumentParser(description="Post changelog or release announcement to Discord webhook thread.")
    parser.add_argument("--notes", default="", help="Path to markdown release notes file (optional if --short).")
    parser.add_argument("--title", default="TortoiseBotsManager Update", help="Title for the announcement.")
    parser.add_argument("--tag", default="", help="Release tag or version identifier.")
    parser.add_argument("--repo", default="Sagiroth/TortoiseBotsManager", help="GitHub repository name.")
    parser.add_argument("--thread-id", default="", help="Target Discord thread ID.")
    parser.add_argument("--username", default="TortoiseBotsManager Releases", help="Webhook bot display name.")
    parser.add_argument("--avatar-url", default="", help="Optional bot avatar image URL.")
    parser.add_argument("--short", action="store_true", help="Post a concise release announcement with download link instead of full changelog dump.")
    parser.add_argument("--edit-message-id", default="", help="Optional Discord message ID to edit in place.")
    parser.add_argument("--delete-message-id", default="", help="Optional Discord message ID to delete.")
    parser.add_argument("--changelog-thread-id", default="", help="With --short: link to this Discord changelog thread instead of previewing the notes.")
    args = parser.parse_args()

    webhook_url = os.environ.get("DISCORD_WEBHOOK_URL", "").strip()
    thread_id = (args.thread_id or os.environ.get("THREAD_ID", "")).strip()

    if not webhook_url:
        print("Warning: DISCORD_WEBHOOK_URL is not set. Skipping Discord notification.")
        sys.exit(0)

    base_webhook = webhook_url.split("?")[0]
    query_params = ["wait=true"]
    if thread_id:
        query_params.append(f"thread_id={thread_id}")
    post_url = f"{base_webhook}?{'&'.join(query_params)}"
    fallback_url = f"{base_webhook}?wait=true"

    if args.delete_message_id:
        del_url = f"{base_webhook}/messages/{args.delete_message_id}"
        if thread_id:
            del_url += f"?thread_id={thread_id}"
        print(f"Deleting Discord message {args.delete_message_id}...")
        success, code = send_discord_message(del_url, payload=None, method="DELETE")
        if not success and thread_id and code in (400, 404):
            print("Retrying delete without thread_id...", file=sys.stderr)
            success, _ = send_discord_message(f"{base_webhook}/messages/{args.delete_message_id}", payload=None, method="DELETE")
        if not success:
            sys.exit(1)
        print(f"Successfully deleted Discord message {args.delete_message_id}.")
        return

    release_url = f"https://github.com/{args.repo}/releases/tag/{args.tag}" if args.tag else f"https://github.com/{args.repo}"
    download_url = f"https://github.com/{args.repo}/releases/download/{args.tag}/TortoiseBotsManager.zip" if args.tag else ""

    notes_text = ""
    if args.notes and os.path.exists(args.notes):
        with open(args.notes, "r", encoding="utf-8") as f:
            notes_text = f.read().strip()

    if args.short:
        embed_title = f"{args.title}"
        if args.tag and args.tag not in args.title:
            embed_title += f" • {args.tag}"

        desc_parts = [
            f"A new release of **TortoiseBotsManager Addon** ({args.tag or 'latest'}) is now available.",
            ""
        ]
        if notes_text and not args.changelog_thread_id:
            preview = notes_text[:600]
            if len(notes_text) > 600:
                last_nl = preview.rfind("\n")
                if last_nl > 200:
                    preview = preview[:last_nl]
                preview += "\n..."
            desc_parts.append(preview)
            desc_parts.append("")

        desc_parts.append(f"**[Download Addon & View Changelog on GitHub]({release_url})**")
        if args.changelog_thread_id:
            # A thread is a channel: <#id> renders as a link to it.
            desc_parts.append(f"**What changed:** <#{args.changelog_thread_id}>")

        embed = {
            "title": embed_title,
            "url": release_url,
            "description": "\n".join(desc_parts),
            "color": 0x3498DB,  # Nice Addon Blue
            "footer": {
                "text": f"{args.repo} • Released via GitHub Actions",
            }
        }
        if download_url:
            embed["fields"] = [
                {
                    "name": "⬇️ Direct Download (.zip)",
                    "value": f"[Download TortoiseBotsManager.zip]({download_url})",
                    "inline": False,
                }
            ]

        payload = {
            "username": args.username,
            "embeds": [embed]
        }
        if args.avatar_url:
            payload["avatar_url"] = args.avatar_url

        target_url = f"{base_webhook}/messages/{args.edit_message_id}?{'&'.join(query_params)}" if args.edit_message_id else post_url
        method = "PATCH" if args.edit_message_id else "POST"

        success, code = send_discord_message(target_url, payload, method=method)
        if not success and thread_id and code in (400, 404):
            print(f"Warning: Discord thread {thread_id} failed with HTTP {code}. Retrying directly to root webhook...", file=sys.stderr)
            fallback_target = f"{base_webhook}/messages/{args.edit_message_id}?wait=true" if args.edit_message_id else fallback_url
            success, _ = send_discord_message(fallback_target, payload, method=method)
        if not success:
            sys.exit(1)

        action_word = "edited" if args.edit_message_id else "posted"
        print(f"Successfully {action_word} release announcement in Discord thread {thread_id or 'channel'}.")
        return

    # Full changelog mode
    if not args.notes or not os.path.exists(args.notes):
        print(f"Error: Notes file not found at {args.notes}", file=sys.stderr)
        sys.exit(1)

    if not notes_text:
        print("Notes file is empty. Nothing to post to Discord.")
        sys.exit(0)

    chunks = split_text(notes_text, max_len=3900)
    total_parts = len(chunks)

    print(f"Posting changelog to Discord ({total_parts} part(s))...")

    for i, chunk in enumerate(chunks, 1):
        embed_title = args.title
        if total_parts > 1:
            embed_title += f" (Part {i}/{total_parts})"

        embed = {
            "title": embed_title,
            "description": chunk,
            "color": 0x2ECC71,  # Emerald Green
        }

        if args.tag and i == 1:
            embed["url"] = release_url
            if download_url:
                embed["fields"] = [
                    {
                        "name": "📦 Direct Addon Download",
                        "value": f"[Download TortoiseBotsManager.zip]({download_url})",
                        "inline": False,
                    }
                ]

        if i == total_parts:
            embed["footer"] = {
                "text": f"{args.repo} • Released via GitHub Actions",
            }

        payload = {
            "username": args.username,
            "embeds": [embed]
        }
        if args.avatar_url:
            payload["avatar_url"] = args.avatar_url

        success, code = send_discord_message(post_url, payload)
        if not success and thread_id and code in (400, 404):
            print(f"Warning: Discord thread {thread_id} failed with HTTP {code}. Retrying directly to root webhook...", file=sys.stderr)
            success, _ = send_discord_message(fallback_url, payload)
            if success:
                post_url = fallback_url
        if not success:
            print(f"Failed to post part {i}/{total_parts} to Discord.", file=sys.stderr)
            sys.exit(1)
        print(f"Successfully posted part {i}/{total_parts} to Discord.")


if __name__ == "__main__":
    main()
