#!/usr/bin/env python3
"""Colibri file agent: lets your local Colibri model read and edit files in THIS folder.

Usage:
    py colibri_agent.py            asks before every write or edit
    py colibri_agent.py --yes      auto-approves writes and edits
    py colibri_agent.py --url http://127.0.0.1:8000/v1   (default)

Requirements: Python 3.8+ (no extra packages) and the Colibri server running.
The agent can only touch files inside the folder this script lives in.
It has no shell access: it can list, read, search, write and edit files, nothing else.
"""
import argparse
import json
import os
import re
import urllib.request

ROOT = os.path.realpath(os.path.dirname(os.path.abspath(__file__)))
MODEL = "qwen3.6-colibri"
SKIP_DIRS = {".git", "node_modules", "__pycache__", "build", ".vs", ".idea"}
MAX_CHARS = 20000  # keep tool output small so the model's context does not overflow
MAX_ROUNDS = 12

SYSTEM = (
    "You are a coding assistant working inside the project folder " + ROOT + ". "
    "Use the tools to look at files before answering questions about code. "
    "Paths are relative to the project folder. Make minimal, targeted changes: "
    "prefer edit_file over write_file for existing files. Be concise."
)

TOOLS = [
    {"type": "function", "function": {
        "name": "list_dir", "description": "List files and folders in a directory.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string", "description": "Relative directory, default '.'"}}}}},
    {"type": "function", "function": {
        "name": "read_file", "description": "Read a text file with line numbers.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"},
            "start_line": {"type": "integer"},
            "end_line": {"type": "integer"}}, "required": ["path"]}}},
    {"type": "function", "function": {
        "name": "search", "description": "Case-insensitive text search across files.",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string"},
            "path": {"type": "string", "description": "Relative directory, default '.'"}},
            "required": ["query"]}}},
    {"type": "function", "function": {
        "name": "write_file", "description": "Create or overwrite a file with full content.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "content": {"type": "string"}},
            "required": ["path", "content"]}}},
    {"type": "function", "function": {
        "name": "edit_file",
        "description": "Replace one exact occurrence of 'old' with 'new' in a file.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}, "old": {"type": "string"}, "new": {"type": "string"}},
            "required": ["path", "old", "new"]}}},
]

AUTO_YES = False


def safe(rel):
    full = os.path.realpath(os.path.join(ROOT, rel or "."))
    try:
        inside = os.path.commonpath([ROOT, full]) == ROOT
    except ValueError:
        inside = False
    if not inside:
        raise ValueError("path is outside the project folder")
    return full


def confirm(msg):
    if AUTO_YES:
        return True
    return input("  " + msg + " [y/N] ").strip().lower() in ("y", "yes")


def clip(text):
    if len(text) > MAX_CHARS:
        return text[:MAX_CHARS] + "\n...[truncated]"
    return text


def t_list_dir(path="."):
    full = safe(path)
    names = []
    for n in sorted(os.listdir(full))[:200]:
        names.append(n + ("/" if os.path.isdir(os.path.join(full, n)) else ""))
    return "\n".join(names) or "(empty)"


def t_read_file(path, start_line=1, end_line=None):
    with open(safe(path), "r", encoding="utf-8", errors="replace") as f:
        lines = f.read().splitlines()
    start = max(1, int(start_line or 1))
    end = int(end_line) if end_line else len(lines)
    out = ["%d\t%s" % (i, lines[i - 1]) for i in range(start, min(end, len(lines)) + 1)]
    return clip("\n".join(out)) or "(empty or out of range)"


def t_search(query, path="."):
    needle = query.lower()
    hits = []
    for dirpath, dirnames, files in os.walk(safe(path)):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in files:
            fp = os.path.join(dirpath, name)
            try:
                if os.path.getsize(fp) > 1_000_000:
                    continue
                with open(fp, "r", encoding="utf-8", errors="ignore") as f:
                    for i, line in enumerate(f, 1):
                        if needle in line.lower():
                            rel = os.path.relpath(fp, ROOT)
                            hits.append("%s:%d: %s" % (rel, i, line.strip()[:200]))
                            if len(hits) >= 50:
                                return "\n".join(hits) + "\n...[50 match limit]"
            except OSError:
                continue
    return "\n".join(hits) or "no matches"


def t_write_file(path, content):
    full = safe(path)
    if not confirm("WRITE %s (%d chars)?" % (path, len(content))):
        return "denied by user"
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8", newline="") as f:
        f.write(content)
    return "wrote %s" % path


def t_edit_file(path, old, new):
    full = safe(path)
    with open(full, "r", encoding="utf-8", newline="") as f:
        text = f.read()
    count = text.count(old)
    if count != 1:
        return "edit failed: 'old' matched %d times (needs exactly 1)" % count
    if not confirm("EDIT %s?\n    - %s\n    + %s" % (path, old[:150], new[:150])):
        return "denied by user"
    with open(full, "w", encoding="utf-8", newline="") as f:
        f.write(text.replace(old, new))
    return "edited %s" % path


HANDLERS = {"list_dir": t_list_dir, "read_file": t_read_file, "search": t_search,
            "write_file": t_write_file, "edit_file": t_edit_file}


def run_tool(name, args):
    fn = HANDLERS.get(name)
    if not fn:
        return "unknown tool: %s" % name
    try:
        return fn(**(args or {}))
    except Exception as e:  # report to the model so it can correct itself
        return "tool error: %s" % e


def post(url, messages):
    body = json.dumps({"model": MODEL, "messages": messages, "tools": TOOLS,
                       "temperature": 0.3, "max_tokens": 2048}).encode()
    req = urllib.request.Request(url + "/chat/completions", data=body,
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=900) as r:
        return json.load(r)["choices"][0]["message"]


TOOL_BLOCK = re.compile(r"<tool_call>\s*(\{.*?\})\s*</tool_call>", re.S)
THINK_BLOCK = re.compile(r"<think>.*?</think>", re.S)


def parse_calls(msg):
    """Return (calls, native). Falls back to <tool_call> JSON blocks in the text."""
    native = msg.get("tool_calls") or []
    if native:
        calls = []
        for c in native:
            fn = c.get("function", {})
            args = fn.get("arguments") or {}
            if isinstance(args, str):
                try:
                    args = json.loads(args)
                except ValueError:
                    args = {}
            calls.append({"id": c.get("id", ""), "name": fn.get("name"), "args": args})
        return calls, True
    calls = []
    for raw in TOOL_BLOCK.findall(msg.get("content") or ""):
        try:
            d = json.loads(raw)
            calls.append({"id": "", "name": d.get("name"), "args": d.get("arguments", {})})
        except ValueError:
            continue
    return calls, False


def main():
    global AUTO_YES
    ap = argparse.ArgumentParser(description="Colibri file agent")
    ap.add_argument("--yes", action="store_true", help="auto-approve writes and edits")
    ap.add_argument("--url", default="http://127.0.0.1:8000/v1")
    args = ap.parse_args()
    AUTO_YES = args.yes

    messages = [{"role": "system", "content": SYSTEM}]
    print("Colibri file agent | folder: %s" % ROOT)
    print("Type 'exit' to quit. Replies can take a minute or two on a local model.")
    while True:
        try:
            user = input("\nyou> ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if user.lower() in ("exit", "quit"):
            break
        if not user:
            continue
        messages.append({"role": "user", "content": user})
        for _ in range(MAX_ROUNDS):
            print("  (thinking...)")
            try:
                msg = post(args.url, messages)
            except Exception as e:
                print("Colibri error: %s\n(is the server running at %s ?)" % (e, args.url))
                break
            content = msg.get("content") or ""
            calls, native = parse_calls(msg)
            shown = TOOL_BLOCK.sub("", THINK_BLOCK.sub("", content)).strip()
            if shown:
                print("\ncolibri> " + shown)
            if native:
                messages.append({"role": "assistant", "content": content,
                                 "tool_calls": msg["tool_calls"]})
            else:
                messages.append({"role": "assistant", "content": content})
            if not calls:
                break
            responses = []
            for c in calls:
                print("  [tool] %s %s" % (c["name"], json.dumps(c["args"])[:120]))
                result = run_tool(c["name"], c["args"])
                if native:
                    messages.append({"role": "tool", "tool_call_id": c["id"], "content": result})
                else:
                    responses.append("<tool_response>\n%s\n</tool_response>" % result)
            if not native:
                messages.append({"role": "user", "content": "\n".join(responses)})
        else:
            print("  (stopped after %d tool rounds)" % MAX_ROUNDS)


if __name__ == "__main__":
    main()
