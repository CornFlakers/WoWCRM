"""Bundles the WoW Utils buff tool into WoW CRM.

Copies the add-on's Lua files from the WoW Utils project into WoWCRM/Buffs/, adapting them so
they live inside WoW CRM without clashing with the standalone add-on:
  * each file keeps its own namespace (ns.BuffTool inside WoW CRM's namespace);
  * saved data, frame names and the scan tooltip are renamed WoWCRMBuffs*;
  * /wu becomes /crm buffs, and the add-on menu entry is left to WoW CRM;
  * nothing starts unless WoW CRM's "Buff reminders" option is on (BuffBridge.lua).
Run it again after WoW Utils changes:   python tools/sync_buffs.py [path to WoWUtils]
It stops with an error, changing nothing, if WoW Utils no longer looks the way this script expects.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CRM = os.path.dirname(HERE)
SRC = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(CRM), "WoWUtils")
DEST = os.path.join(CRM, "Buffs")

HEADER = "-- Bundled from WoW Utils by tools/sync_buffs.py. Edit WoW Utils, then sync; changes made here are overwritten.\n"
NS_LINE = re.compile(r"^local (_|ADDON), ns = \.\.\.$", re.M)


def toc_files():
    with open(os.path.join(SRC, "WoWUtils.toc"), encoding="utf-8") as f:
        return [l.strip() for l in f if l.strip() and not l.startswith("#")]


def must(text, old, new, name, count=1):
    if text.count(old) != count:
        raise SystemExit(f"{name}: expected {count} of {old[:60]!r}, found {text.count(old)}. WoW Utils changed; update tools/sync_buffs.py.")
    return text.replace(old, new)


def adapt(name, text):
    if len(NS_LINE.findall(text)) != 1:
        raise SystemExit(f"{name}: no 'local _, ns = ...' line found.")
    text = NS_LINE.sub(lambda m: f"local {m.group(1)}, crm = ...\nlocal ns = crm.BuffTool or {{ crm = crm }}\ncrm.BuffTool = ns", text, count=1)
    if name == "Core.lua":
        # the add-on menu entry and /wu belong to the standalone add-on
        text = re.sub(r"\nSLASH_WOWUTILS1 = .*?\nend\n", "\n", text, flags=re.S)
        if "SLASH_WOWUTILS" in text or "OnCompartmentClick" in text:
            raise SystemExit("Core.lua: the slash command block was not where expected.")
        # start only when WoW CRM says the buff tool is on
        text = must(text, 'on("PLAYER_LOGIN", function()\n\tWoWUtilsDB = ', "function ns.Start()\n\tif ns.ready then return end\n\tWoWUtilsDB = ", name)
        text = must(text, "\tns.Refresh()\nend)\n\nlocal function aura",
                    "\tns.Refresh()\nend\non(\"PLAYER_LOGIN\", function() if ns.crm.BuffToolEnabled() then ns.Start() end end)\n\nlocal function aura", name)
        # while it is off, no event does anything
        text = must(text, "\tif f then ns.Safe(event, f, ...) end", "\tif f and (ns.ready or event == \"PLAYER_LOGIN\") then ns.Safe(event, f, ...) end", name)
        text = must(text, 'DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffWoW Utils:|r "', 'DEFAULT_CHAT_FRAME:AddMessage("|cff33ccffWoW CRM buffs:|r "', name)
    text = text.replace("WoWUtilsDB", "WoWCRMBuffsDB").replace("WoWUtils", "WoWCRMBuffs")
    text = re.sub(r"/wu\b", "/crm buffs", text)
    text = text.replace("WoW Utils", "WoW CRM's buff reminders")
    return HEADER + text


def main():
    files = toc_files()
    if not files:
        raise SystemExit("WoWUtils.toc lists no files.")
    out = {}
    for name in files:
        with open(os.path.join(SRC, name), encoding="utf-8") as f:
            out[name] = adapt(name, f.read())
    os.makedirs(DEST, exist_ok=True)
    for old in os.listdir(DEST):
        if old.endswith(".lua") and old not in out:
            os.remove(os.path.join(DEST, old))
    for name, text in out.items():
        with open(os.path.join(DEST, name), "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
    # keep WoW CRM's TOC listing the bundled files, in WoW Utils' order, before BuffBridge.lua
    toc_path = os.path.join(CRM, "WoWCRM.toc")
    with open(toc_path, encoding="utf-8") as f:
        lines = [l.rstrip("\r\n") for l in f]
    lines = [l for l in lines if not l.startswith("Buffs\\")]
    lines = [("## SavedVariables: WoWCRMDB, WoWCRMBuffsDB" if l.startswith("## SavedVariables:") and "WoWCRMBuffsDB" not in l else l) for l in lines]
    at = lines.index("BuffBridge.lua") if "BuffBridge.lua" in lines else len(lines)
    lines[at:at] = ["Buffs\\" + n for n in files]
    if "BuffBridge.lua" not in lines:
        lines.append("BuffBridge.lua")
    with open(toc_path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    print(f"bundled {len(files)} files from {SRC} into {DEST}")


main()
