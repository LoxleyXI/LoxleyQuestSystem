#!/usr/bin/env python3
"""
Migrate LQS 2.x quest files to the LQS 3.0 API.

    python3 tools/migrate_v3.py <file or folder> ...      rewrite in place
    python3 tools/migrate_v3.py --check <file or folder>  list what would change, write nothing

What it changes (quest vars and step numbers are never touched, so saved
progress carries over):

  Builders
    LQS.dialog  quest = X  ->  complete = X with a reward, accept = X without
                beginQuest = X  ->  accept = X
    LQS.trade   quest = X  ->  complete = X
    LQS.menu    quest = X  ->  complete = X with finish (finish removed), else accept = X
    dialog / trade  spawn = "Name" (a string)  ->  as = "Name"
    any builder name = ""  ->  object = true
    LQS.defeat  func = function(player, prev)  ->  after = function(ctx)

  Event commands
    emotion -> narrate, fmt -> say, { animation = N, ..., duration } -> pose,
    { noturn = true } rows removed

  Hand-written handlers take ctx:
    onTrigger = function(player, npc)          -> function(ctx) local player, npc = ctx.player, ctx.npc
    onTrade   = function(player, npc, trade)   -> ... ctx.trade
    onMobDeath / mob step functions (mob, player) -> ctx.mob, ctx.player
    default   = function(player, npc)          -> unchanged (an event: ctx is added third)
    after     = function(player)               -> ctx
  including local functions used as handlers by name.

Everything else is left alone. Read the diff; then run the tests.
"""
import os
import re
import sys

BUILDERS = ("LQS.dialog", "LQS.trade", "LQS.menu", "LQS.defeat")


# ---------------------------------------------------------------------------
# A small Lua scanner: positions that are code (not strings or comments)
# ---------------------------------------------------------------------------
def code_mask(src):
    """mask[i] is True where src[i] is code."""
    mask = [True] * len(src)
    i, n = 0, len(src)

    def long_bracket(at):
        m = re.match(r"\[(=*)\[", src[at:])
        if not m:
            return None
        close = "]" + m.group(1) + "]"
        end = src.find(close, at + len(m.group(0)))
        return len(src) if end < 0 else end + len(close)

    while i < n:
        c = src[i]
        if src.startswith("--", i):
            end = long_bracket(i + 2)
            if end is None:
                end = src.find("\n", i)
                end = n if end < 0 else end
            for k in range(i, end):
                mask[k] = False
            i = end
        elif c in "'\"":
            j = i + 1
            while j < n and src[j] != c:
                j += 2 if src[j] == "\\" else 1
            for k in range(i, min(j + 1, n)):
                mask[k] = False
            i = j + 1
        elif c == "[" and long_bracket(i):
            end = long_bracket(i)
            for k in range(i, end):
                mask[k] = False
            i = end
        else:
            i += 1
    return mask


def match_close(src, mask, open_at):
    """Index of the bracket closing the one at open_at."""
    pairs = {"(": ")", "{": "}", "[": "]"}
    stack = []
    for i in range(open_at, len(src)):
        if not mask[i]:
            continue
        c = src[i]
        if c in pairs:
            stack.append(pairs[c])
        elif c in ")}]":
            if not stack or stack.pop() != c:
                return -1
            if not stack:
                return i
    return -1


def top_level_keys(src, mask, start, end):
    """(key, key_start, value_start, value_end) for keys at depth 1 of the table src[start:end]."""
    keys = []
    depth = 0
    i = start
    while i < end:
        if not mask[i]:
            i += 1
            continue
        c = src[i]
        if c in "({[":
            depth += 1
        elif c in ")}]":
            depth -= 1
        elif depth == 1:
            m = re.compile(r"([A-Za-z_]\w*)\s*=(?!=)").match(src, i)
            if m and (i == 0 or not (src[i - 1].isalnum() or src[i - 1] in "_.:")):
                vstart = m.end()
                # the value runs to the next comma or closing bracket at depth 1
                d, j = 0, vstart
                while j < end:
                    if mask[j]:
                        ch = src[j]
                        if ch in "({[":
                            d += 1
                        elif ch in ")}]":
                            if d == 0:
                                break
                            d -= 1
                        elif ch == "," and d == 0:
                            break
                    j += 1
                keys.append((m.group(1), i, vstart, j))
                i = j
                continue
        i += 1
    return keys


# ---------------------------------------------------------------------------
# Builders
# ---------------------------------------------------------------------------
def migrate_builders(src, notes):
    edits = []  # (start, end, replacement)
    mask = code_mask(src)

    for builder in BUILDERS:
        for m in re.finditer(re.escape(builder) + r"\s*\(\s*\{", src):
            if not mask[m.start()]:
                continue
            brace = m.end() - 1
            close = match_close(src, mask, brace)
            if close < 0:
                continue
            keys = top_level_keys(src, mask, brace, close + 1)
            names = {k[0] for k in keys}
            kind = builder.split(".")[1]

            for key, kstart, vstart, vend in keys:
                value = src[vstart:vend].strip()
                new = None

                if key == "quest":
                    if kind == "dialog":
                        new = "complete" if "reward" in names else "accept"
                    elif kind == "trade":
                        new = "complete"
                    elif kind == "menu":
                        new = "complete" if "finish" in names else "accept"
                elif key == "beginQuest":
                    new = "accept"
                elif key == "spawn" and kind in ("dialog", "trade") and re.match(r'^("|\'|[A-Za-z_][\w.]*$)', value) and not value.startswith("{"):
                    # a string (or a constant naming one): the NPC swap
                    new = "as"
                elif key == "func" and kind == "defeat":
                    new = "after"
                elif key == "spawner" and kind == "menu":
                    # never read by LQS.menu: drop it
                    stop = vend
                    while stop < close and src[stop] in " \t":
                        stop += 1
                    if stop < close and src[stop] == ",":
                        stop += 1
                    line_start = src.rfind("\n", 0, kstart) + 1
                    if src[line_start:kstart].strip() == "":
                        kstart = line_start
                        if stop < len(src) and src[stop] == "\n":
                            stop += 1
                    edits.append((kstart, stop, ""))
                    notes.append("menu: spawner removed (LQS.menu never used it)")
                    continue
                elif key == "name" and value in ('""', "''"):
                    edits.append((kstart, vend, "object = true"))
                    notes.append(f"{kind}: name = \"\" -> object = true")
                    continue
                elif key == "finish" and kind == "menu" and "quest" in names:
                    # finish only chose the message; drop it with its separator
                    stop = vend
                    while stop < close and src[stop] in " \t":
                        stop += 1
                    if stop < close and src[stop] == ",":
                        stop += 1
                    line_start = src.rfind("\n", 0, kstart) + 1
                    if src[line_start:kstart].strip() == "":
                        kstart = line_start
                        if stop < len(src) and src[stop] == "\n":
                            stop += 1
                    edits.append((kstart, stop, ""))
                    notes.append("menu: finish removed")
                    continue

                if new:
                    # keep alignment: pad the new key to the old key's width when shorter
                    old_head = src[kstart:vstart]
                    pad = max(0, len(key) - len(new))
                    head = old_head.replace(key, new + " " * pad, 1) if pad else old_head.replace(key, new, 1)
                    edits.append((kstart, vstart, head))
                    notes.append(f"{kind}: {key} -> {new}")

    return apply_edits(src, edits)


# ---------------------------------------------------------------------------
# Hand-written handlers
# ---------------------------------------------------------------------------
ROLES = {
    "onTrigger":  ["ctx.player", "ctx.npc"],
    "onTrade":    ["ctx.player", "ctx.npc", "ctx.trade"],
    "onMobDeath": ["ctx.mob", "ctx.player"],
    "default":    ["ctx.player", "ctx.npc"],
    "after":      ["ctx.player"],
}


def preamble(params, roles, indent):
    names, values = [], []
    for name, value in zip(params, roles):
        if name and name != "_":
            names.append(name)
            values.append(value)
    if len(params) > len(roles):
        # an extra parameter we can't map (a defeat func's previous step)
        for name in params[len(roles):]:
            if name == "_":
                continue
            names.append(name)
            values.append("ctx.step - 1")
    if not names:
        return ""
    return f"\n{indent}local {', '.join(names)} = {', '.join(values)}"


def body_indent(src, func_end):
    """Indent of the first line of the function body."""
    nl = src.find("\n", func_end)
    if nl < 0:
        return "    "
    line = src[nl + 1:src.find("\n", nl + 1)]
    return line[: len(line) - len(line.lstrip())] or "    "


def convert_function(src, mask, fstart, params_open, roles, notes, label):
    close = match_close(src, mask, params_open)
    params = [p.strip() for p in src[params_open + 1:close].split(",") if p.strip()]
    if params == ["ctx"]:
        return None
    indent = body_indent(src, close)
    pre = preamble(params, roles, indent)
    notes.append(f"{label}: function({', '.join(params)}) -> function(ctx)")
    return (params_open, close + 1, "(ctx)" + pre)


def migrate_handlers(src, notes):
    mask = code_mask(src)
    edits = []
    named = {}  # local function name -> roles

    # Inline: key = function(...)
    # (onMobDeath = function on an entity is a raw LSB callback; step mob handlers
    # are bare functions, handled below)
    # (default = function is an event: it keeps (player, npc), with ctx added third)
    for m in re.finditer(r"\b(onTrigger|onTrade|after|func)\s*=\s*function\s*\(", src):
        if not mask[m.start()]:
            continue
        key = m.group(1)
        roles = ROLES.get(key, ROLES["after"])
        if key == "func":
            roles = ["ctx.player"]
        params_open = m.end() - 1
        first = src[params_open + 1:match_close(src, mask, params_open)].split(",")[0].strip()
        if key == "after" and first == "mob":
            continue  # an entity's own after(mob, player): unchanged in 3.0
        e = convert_function(src, mask, m.start(), params_open, roles, notes, key)
        if e:
            edits.append(e)

    # By name: key = someLocal
    # (not after or onMobDeath: by name those are usually an entity's own callbacks)
    for m in re.finditer(r"\b(onTrigger|onTrade)\s*=\s*([A-Za-z_]\w*)\s*[,}\n]", src):
        if not mask[m.start()] or m.group(2) in ("nil", "true", "false"):
            continue
        named.setdefault(m.group(2), ROLES[m.group(1)])

    for name, roles in named.items():
        for d in re.finditer(r"local\s+function\s+" + re.escape(name) + r"\s*\(|local\s+" + re.escape(name) + r"\s*=\s*function\s*\(", src):
            if not mask[d.start()]:
                continue
            e = convert_function(src, mask, d.start(), d.end() - 1, roles, notes, name)
            if e:
                edits.append(e)

    # Menu onChoice: function(player, npc, choice) -> function(ctx, choice)
    for m in re.finditer(r"\bonChoice\s*=\s*function\s*\(([^)]*)\)", src):
        if not mask[m.start()]:
            continue
        params = [p.strip() for p in m.group(1).split(",") if p.strip()]
        if params and params[0] == "ctx":
            continue
        params_open = src.index("(", m.start() + m.group(0).index("function"))
        close = match_close(src, mask, params_open)
        indent = body_indent(src, close)
        pre = preamble(params[:2], ROLES["onTrigger"], indent)
        rest = ", " + ", ".join(params[2:]) if len(params) > 2 else ""
        edits.append((params_open, close + 1, "(ctx" + rest + ")" + pre))
        notes.append("menu onChoice -> function(ctx, index)")

    # Handler factories: return function(player, npc[, trade])
    for m in re.finditer(r"\breturn\s+function\s*\(\s*player\s*,\s*npc\s*(,\s*trade\s*)?\)", src):
        if not mask[m.start()]:
            continue
        roles = ROLES["onTrade"] if m.group(1) else ROLES["onTrigger"]
        params_open = src.index("(", m.start())
        e = convert_function(src, mask, m.start(), params_open, roles, notes, "handler factory")
        if e:
            edits.append(e)

    # Bare step functions: [Name] = function(player, npc) / (mob, player)
    for m in re.finditer(r"\[\s*[^\]]+\]\s*=\s*function\s*\(([^)]*)\)", src):
        if not mask[m.start()]:
            continue
        params = [p.strip() for p in m.group(1).split(",") if p.strip()]
        roles = ROLES["onMobDeath"] if params and params[0] == "mob" else ROLES["onTrigger"]
        params_open = src.index("(", m.start() + m.group(0).index("function"))
        e = convert_function(src, mask, m.start(), params_open, roles, notes, "step function")
        if e:
            edits.append(e)

    return apply_edits(src, edits)


def apply_edits(src, edits):
    seen = set()
    for start, end, text in sorted(edits, key=lambda e: e[0], reverse=True):
        if (start, end) in seen:
            continue
        seen.add((start, end))
        src = src[:start] + text + src[end:]
    return src


# Event commands renamed in 3.0 (only as the first key of a row: `{ emotion = ...`)
EVENT_RENAMES = [
    (r"\{(\s*)emotion(\s*)=", r"{\1narrate\2=", "event: emotion -> narrate"),
    (r"\{(\s*)fmt(\s*)=", r"{\1say\2=", "event: fmt -> say"),
]


def migrate_events(src, notes):
    mask = code_mask(src)
    for pattern, repl, note in EVENT_RENAMES:
        out, last = [], 0
        for m in re.finditer(pattern, src):
            if not mask[m.start()]:
                continue
            out.append(src[last:m.start()])
            out.append(m.expand(repl))
            last = m.end()
            notes.append(note)
        out.append(src[last:])
        src = "".join(out)
        mask = code_mask(src)

    # { animation = N, target = "player", duration = ms }: a pose (not an entity's animation field)
    out, last = [], 0
    for m in re.finditer(r"\{(\s*)animation(\s*)=([^{}]*\bduration\b[^{}]*)\}", src):
        if not mask[m.start()]:
            continue
        out.append(src[last:m.start()])
        out.append("{" + m.group(1) + "pose     " + m.group(2) + "=" + m.group(3) + "}")
        last = m.end()
        notes.append("event: animation -> pose")
    out.append(src[last:])
    src = "".join(out)

    # { noturn = true }, rows: did nothing
    src2 = re.sub(r"[ \t]*\{\s*noturn\s*=\s*true\s*\},[ \t]*\n", "", src)
    # and as an extra key on another row: { object = true, noturn = true }
    src2 = re.sub(r",\s*noturn\s*=\s*true(\s*\})", r"\1", src2)
    src2 = re.sub(r"(\{\s*)noturn\s*=\s*true\s*,\s*", r"\1", src2)
    if src2 != src:
        notes.append("event: noturn rows removed")
    return src2


def migrate(src):
    notes = []
    src = migrate_events(src, notes)
    src = migrate_builders(src, notes)
    src = migrate_handlers(src, notes)
    return src, notes


def files_in(paths):
    for path in paths:
        if os.path.isdir(path):
            for root, _, names in os.walk(path):
                for name in sorted(names):
                    if name.endswith(".lua"):
                        yield os.path.join(root, name)
        else:
            yield path


def main(argv):
    check = "--check" in argv
    paths = [a for a in argv if a != "--check"]
    if not paths:
        print(__doc__)
        return 2

    changed = 0
    for path in files_in(paths):
        src = open(path, encoding="utf-8", errors="surrogateescape").read()
        if "LQS." not in src:
            continue
        out, notes = migrate(src)
        if out != src:
            changed += 1
            print(f"{path}: {len(notes)} change(s)")
            for note in notes:
                print(f"    {note}")
            if not check:
                open(path, "w", encoding="utf-8", errors="surrogateescape").write(out)
    print(f"{changed} file(s) {'would change' if check else 'changed'}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
