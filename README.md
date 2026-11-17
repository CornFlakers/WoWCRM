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

## Posting without spamming

- **One pause for every public channel.** After any post to Say, Yell, General or Trade, all of them wait 2 minutes (Options tab; 0 turns it off). One advert can no longer land in Yell, General and Trade within seconds.
- **The quick-post bar's big button** (`/crm bar`, or right-click the minimap button) takes turns: next post, next channel. General, then Trade, then General again. Outside a city, where there is no Trade, it uses General. Tick Yell on the bar to include it. While it waits, the button counts down.
- **Whispers are not held back.** Whispering a post to someone is private and has no pause.

## Posting from more than one character

Each post belongs to the character whose voice it is written in, or to any character. Buttons only offer the current character's posts, and a post written for someone else is never sent. "Copy this post for me" on the Posts tab starts a copy you can reword for the character you are on.

## Follow-ups when someone comes online

Press **Follow up when online** on a lead, or **Follow up** on a contact. WoW CRM adds them to the friends list of the character you are playing (they are not told), and alerts you with a sound and a raid-warning message when they log in, or when they speak in a channel or near you. `/crm follow` lists everyone you owe a reply; **Done** takes them off the list and off the friends list again. On another character, type `/crm watch` once to put the same people on its friends list.

## Getting to WoW CRM

`/crm`, the minimap button (drag it around the edge; hide it on the Options tab), or the game's Settings > AddOns > WoW CRM. Drag the window's bottom-right corner to make it bigger or smaller.

## Campaigns

A campaign is a selling session: the posts you want to run, how long to run for, and how long to wait between posts to the same channel (5 minutes unless you change it).

1. **Campaigns** tab: tick the posts, set the length and the wait, press **Start campaign**. Contact tracking switches on.
2. A small campaign bar shows what is due. When a post is due it plays a sound and the button reads "Post name > Channel". One click sends that one message.
3. Between posts the button counts down. With several posts in a campaign, they take turns.

The add-on never posts on its own; the game only allows posts that come from your click. A campaign tells you when, so you are not guessing or spamming.

Each campaign keeps its own results, per post: times posted, leads, orders, gold and goods, leads per post, and the share of leads who ordered. The **Dashboard** adds the same per post for all time, and a table by hour of day so you can see when posting works.

## Products

The **Products** tab lists your recipes by profession and category with materials cost, sale value, margin and how many you have sold through WoW CRM. Sort by any of those, search by name, and mark the things you sell as "my products". Click a recipe to see its materials; materials another scanned profession can craft are flagged.

Recipes are read from the Mastercraft add-on's scan of your professions, and prices from TradeSkillMaster or Auctionator (vendor price otherwise). Without Mastercraft the tab is empty; everything else works.

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

## Follow-up letters

For people who whispered once and went quiet, or customers you'd like to see again. The aim is a friendly reminder with an easy way to reply, not a chase.

1. Open a mailbox, then `/crm` and the **Mail** tab.
2. Under **Who to write to**, choose leads, customers or everyone, and click a name. People you have never written to are at the top; anyone written to in the last 3 days (adjustable) is greyed out at the bottom.
3. Click a template, then **Fill in letter**. The recipient, subject and body are filled in.
4. Read it, change anything you like, and press **Send** in the mail window.

When the game confirms the letter was sent, it is counted. The Mail tab and the contact page show how many follow-ups each person has had and when the last one was. Contacts marked "do not contact" or "ignored" never appear in the list. Three follow-up templates are included; edit them or write your own.

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
