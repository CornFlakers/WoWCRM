# WoW CRM — design spec

Status: **approved; version 0.1.0 built. In-game checks (section 8) still to run.**

## Decisions made at review

- One click per channel: accepted.
- Name: **WoW CRM** (folder and saved-data name `WoWCRM`).
- Lead capture happens **only while contact tracking is switched on, and only after a post**. A "Turn on contact tracking" button sits at the top of the window. A whisper from a new player creates a contact and a lead; a whisper from an existing contact creates a lead on that contact. Tracking switches itself off 30 minutes after the last post (adjustable, 0 = never) and survives a reload.
- The chat limit is 255 **bytes**, not letters. The editor counts bytes; the probe has a button that tests this on the live client.
- Saving: the game only writes add-on data at logout or interface reload, so after any meaningful change a "Save N changes" button appears; clicking it reloads the interface.
- Publishing: github.com/CornFlakers, then CurseForge. No author line.

## Not in 0.1.0 (deferred)

- Key binding for "post next" (the quick-post bar covers the same need with a click).
- The step-through follow-up mailing list (single letters work).
- Minimap button (use `/crm` or the add-on menu entry).
- Automated release packaging (to be set up and tested once the repository exists).

The sections below are the original draft, kept for reference; where they differ from the decisions above, the decisions win.
Target client: `_forever_` (product `wowf`, client 1.60.1, `## Interface: 16001`).
Author field: none. Not affiliated with any company.

## 1. What it does

A seller's notebook inside the game:

1. **Posts** — save reusable adverts and post them to Say, Yell, General, Trade, Party and Guild.
2. **Leads** — people who whisper you after a post land in an inbox, tagged with the post that brought them.
3. **Contacts** — promote a lead to a contact with one click; keep notes, tags and who referred them.
4. **Orders** — record what each contact bought (crafted items, raw goods, services), price and status.
5. **Mail** — at a mailbox, open a pre-filled letter to a contact from a template.
6. **Numbers** — lifetime value per customer, referral counts, revenue per post.

## 2. Hard limits set by the game (these shape the design)

| Limit | Consequence for the design |
|---|---|
| Modern clients only let an add-on send to Say, Yell and public channels (General, Trade) from a real key press or mouse click. Party, Guild and Whisper are unrestricted. | **Every post is one click per channel.** No timers, no auto-repeat, no "post to all six at once". A post to 4 channels is 4 clicks on the same button. |
| Chat messages are capped at 255 bytes. | The editor shows a live byte counter and refuses to save over the limit. |
| General and Trade are numbered per character, and Trade only exists in cities. | Channels are looked up by name at click time; unavailable ones are greyed out with the reason. |
| Mail can only be sent with a mailbox open, costs postage, and may be limited across realms or factions. | The add-on **fills in** the Send Mail window; you press Send. No bulk mailing. |
| Whisper text can be hidden from add-ons in some combat situations ("secret values"; this client has them). | Hidden whispers are still logged as a lead with the text shown as "(hidden during combat)". |
| Saved data is written to disk only on logout or `/reload`. | A crash loses the session's changes. Stated in the README; export button provided. |
| Blizzard's add-on policy: free, readable code, no in-game promotion of the add-on itself. Advert spam is reportable by other players. | Free and open source. A built-in minimum gap per channel (default 60 s, adjustable upward only to 30 s minimum) stops accidental spam. |

**Not yet verified on this client** (first thing checked in game, see §8): that the click rule applies exactly as on retail, the exact Trade channel name, and the mail function signatures. The design is safe whichever way these turn out.

## 3. Features

### 3.1 Posts
- Fields: name, message text, target channels (any of Say, Yell, General, Trade, Party, Guild), notes.
- Tokens in text: `{me}` (your character), `{zone}`.
- **Post** button: sends to the next eligible target each click, showing "2 of 4 — next: Trade". Skips targets that are unavailable or still inside their gap.
- Optional key binding for "post next" (a key press also counts as a real input).
- Every send is logged: post, channel, time, zone.

### 3.2 Leads
- Any incoming whisper from someone who is not already a contact creates or updates a lead.
- Attribution: the most recent post sent within the last 15 minutes (configurable); otherwise "unattributed".
- Lead row shows name, first message, time, source post. Actions: **Add to contacts**, **Whisper back**, **Dismiss**, **Ignore forever**.
- Manual add: `/crm add Name` or "Add target" button.

### 3.3 Contacts
- Key: `Name-Realm`.
- Fields: status (lead, customer, repeat, VIP, do-not-contact), tags, free notes, first seen, last contact, source post, **referred by** (another contact), alternate characters.
- Search and sort by name, last contact, lifetime value.

### 3.4 Orders
- Fields: contact, type (crafted, goods, service), description, item link (optional), quantity, price in gold/silver/copper, status (quoted, in progress, delivered, paid, cancelled), dates, notes.
- **Assisted capture**: when a trade completes or you send a cash-on-delivery mail to a contact, a small prompt offers "Record as order?" with the items and gold pre-filled. Nothing is recorded without your click.
- Lifetime value = sum of **paid** orders. Shown per contact.

### 3.5 Referrals
- Setting "referred by" on a contact credits the referrer.
- Per contact: number of referrals and total revenue from the people they referred.

### 3.6 Mail
- Templates with tokens: `{name}`, `{item}`, `{total}`, `{me}`.
- "Mail" button on a contact (enabled only at a mailbox) fills recipient, subject and body. You review and press Send.
- "Follow-up list": a filtered contact list you step through one letter at a time.
- Sent mail is logged against the contact.

### 3.7 Dashboard
- Total revenue, orders, customers; top customers by lifetime value; top referrers; leads and revenue per post.

### 3.8 Data
- Stored account-wide in `WoWCRMDB`, split per realm, with a schema version for migrations.
- Export and import contacts and orders as text (copy/paste box).
- "Delete all data" with confirmation.
- Everything stays on your computer. The add-on sends nothing anywhere.

## 4. Interface

- One window, opened with `/crm` or a minimap button, with tabs: **Posts · Leads · Contacts · Orders · Mail · Dashboard**.
- Built with the game's stock frame templates. No third-party libraries, so nothing to keep in sync.

## 5. Out of scope

- Timed or automatic posting; automatic whisper replies; bulk mail.
- Real-money sales of any kind (against the game's terms).
- Sharing data between accounts or players.
- Other clients (`_retail_`, `_classic_beta_`) — possible later via extra interface numbers.

## 6. Code layout

```
WoWCRM/
  WoWCRM.toc        Interface 16001, SavedVariables: WoWCRMDB, no Author line
  Core.lua          startup, events, slash commands
  DB.lua            schema, migrations, export/import      (pure logic, testable offline)
  Model.lua         contacts, orders, value, referrals     (pure logic, testable offline)
  Chat.lua          channel lookup, click-driven post queue, whisper capture
  Capture.lua       trade and mail detection, order prompt
  Mail.lua          templates, Send Mail pre-fill
  UI/*.lua          window and tabs
  tests/            offline tests with a stubbed game API
```

## 7. Publishing without affiliation

- GitHub: public repo under a **personal or throwaway account you control** (I cannot create accounts; you sign in). Commits authored as `WoWCRM dev` with a GitHub no-reply address. Your work email is never used; this machine's git identity is currently blank, which keeps it clean.
- Licence: MIT, "Copyright (c) WoWCRM contributors".
- CurseForge: project under the same pseudonym. Release zips built by a GitHub Action from a version tag. You create the project and the upload token.
- Pre-publish check: search the repo and its history for your name, email, company name and machine user name.

## 8. Testing and verification

| Stage | How | Pass means |
|---|---|---|
| Static | Lua syntax check and lint over every file | No errors, no accidental globals |
| Offline unit tests | `DB.lua` and `Model.lua` run under Lua 5.1 with a stub API | Value, referral, attribution, byte limit, migration and import/export tests pass |
| **In-game probe** (first build) | `/crm probe` prints channel list, tries one click-driven Say and one Party/Guild send, opens a mail pre-fill | Confirms the three unverified items in §2 |
| In-game checklist | You run a scripted list: post to each of 6 targets, receive a whisper from an alt or friend, promote, record an order from a real trade, send one letter | Every row ticked, no Lua errors |
| Publish check | Packaged zip installed into a clean AddOns folder; identity scan of the repo | Loads cleanly; no affiliation strings |

I can do the static and offline stages myself. The in-game stages need you at the keyboard; I will read the results from your screen or saved-variables file.

## 9. Build order

1. Skeleton + data layer + offline tests.
2. Posts and the in-game probe (settles §2 unknowns early).
3. Leads and contacts.
4. Orders, value, referrals, dashboard.
5. Mail.
6. Export/import, polish, in-game checklist.
7. Repo, packaging, release.

## 10. Decisions I need from you

1. Is one click per channel acceptable? (It is not optional for Say, Yell, General and Trade.)
2. Keep the name **WoWCRM**, or pick something else before the repo exists?
3. Lead capture: every whisper from a non-contact, or only whispers within the window after a post?
4. Anything missing from contacts or orders that you track today?
