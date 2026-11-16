# WoW CRM

A seller's notebook for World of Warcraft. Post your adverts with one click, catch the people who whisper back, and keep track of what each customer bought.

- **Posts** — save adverts and send them to Say, Yell, General, Trade, Party or Guild. One click sends one message to one channel.
- **Contact tracking** — switch it on, make your posts, and everyone who whispers you becomes a lead and a contact.
- **Contacts** — status, tags, notes, and who referred them.
- **Orders** — what was sold, for how much, and whether it is paid. Completed trades and cash-on-delivery mail offer to fill the order in for you.
- **Lifetime value and referrals** — per customer, plus revenue per post on the dashboard.
- **Mail** — at a mailbox, fill in a letter to a contact from a template. You press Send.

Built for the `_forever_` client (interface 16001).

## Install

Copy this folder into `World of Warcraft\_forever_\Interface\AddOns\` as `WoWCRM`, then restart the game.

## Use

| Command | What it does |
|---|---|
| `/crm` | Open or close the window |
| `/crm bar` | Show or hide the quick-post bar |
| `/crm track` | Turn contact tracking on or off |
| `/crm add Name` | Add a contact |
| `/crm probe` | Check how this client handles chat and mail |

A typical session:

1. `/crm`, write a post on the **Posts** tab, tick its channels, **Save post**.
2. Press **Turn on contact tracking**.
3. Click **Post to …** once per channel (or use the quick-post bar).
4. Replies appear on the **Leads** tab. Whisper back, then **New order** when they buy.

## Orders, materials and tips

An order has three parts:

- **I gave them** — each item you handed over, as its own line.
- **They gave me** — each item they handed you, with a value. Every line is either **materials** (supplied for the job, not income) or **payment** (a tip or payment in goods, counted as income at its value).
- **Gold** — gold received.

A job often takes several trades: the customer hands over cloth, comes back for the bags, then tips in gold or more cloth. After each trade the add-on offers to add it to that customer's current order (for 60 minutes after the last trade; adjustable), so the whole job stays on one order.

- Goods received **before** you have delivered anything are recorded as materials.
- Goods received **with or after** the delivery are recorded as payment.
- If it guessed wrong, open the order, click the line and press **Flip kind**.

Values come from TradeSkillMaster or Auctionator if you have either, otherwise the vendor price, at the moment of the trade. Click a line to change its value.

Lifetime value and the dashboard show gold and goods separately, and the dashboard lists what each post sold. Open a contact to see all their orders; click one to open it.

## Things to know

- **Chat messages are limited to 255 bytes, not 255 letters.** Accented letters count as 2 and an item link counts as its full hidden text. The editor shows the count as you type.
- **One click, one message.** The game does not let add-ons post to public channels on a timer, and this add-on does not try. There is a minimum gap between posts to the same public channel (60 seconds by default).
- **Saving.** The game writes add-on data to disk only when you log out or reload the interface. After a change, a **Save** button appears; clicking it reloads the interface, which takes a couple of seconds. If the game crashes before that, changes since the last save are lost. Use **Dashboard → Export** for a backup you can paste elsewhere.
- **Tracking** only captures whispers after you have made a post, and switches itself off 30 minutes after your last post (adjustable).
- **Mail** is filled in for you one letter at a time. There is no bulk mail.
- Everything stays on your computer. The add-on sends nothing anywhere, and in-game gold is the only currency it understands.

## Tests

The rules (value, referrals, tracking, limits, import/export) and a simulated selling session are tested outside the game:

```
cd tests
npm install
npm test
```

## Licence

MIT. See `LICENSE`.
