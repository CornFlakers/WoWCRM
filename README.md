# WoW CRM

A seller's notebook for World of Warcraft. Post your adverts with one click, catch the people who whisper back, and keep track of what each customer bought.

- **Posts** — save adverts and send them to Say, Yell, General, Trade, Party or Guild. One click sends one message to one channel.
- **Contact tracking** — posting switches it on; everyone who whispers you afterwards becomes a lead and a contact, with the whole conversation kept.
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
| `/crm reagents` | Turn double-click help in the profession window on or off |
| `/crm reagents check` | Say which profession window this client has and whether WoW CRM is hooked into it |
| `/crm probe` | Check how this client handles chat and mail |

A typical session:

1. `/crm`, write a post on the **Posts** tab, tick its channels, **Save post**.
2. Post from the quick-post bar (`/crm bar`) or the Posts tab. Contact tracking switches on by itself; the top of the bar shows it and counts down until it switches off again.
3. Replies appear on the **Leads** tab with the conversation. Whisper back, then **Make it an order** when they buy.
4. Trade with them. The trade fills in that order.

## What a post is for

Every post has a purpose, set with the **For:** button beside its name on the Posts tab:

- **Selling**: goods and services you provide ("WTS bags, bring your cloth").
- **Looking for**: things you want to buy or have made ("WTB Linen Cloth").
- **Group**: dungeons, quests and groups ("Tank LFG for Wailing Caverns, whisper me").

Whoever whispers you after a post is filed under its purpose. The **Leads** tab has a button for each (All, Selling, Looking for, Group) with a count. Each lead shows which post it answered, even if that post is deleted later. The contact is tagged with the purpose too (`sell`, `buy` or `group`), so searching `group` on the Contacts tab lists everyone you have grouped with. Posts saved before purposes existed count as Selling, and so do bag offers.

## Posting without spamming

- **One pause for every public channel.** After any post to Say, Yell, General or Trade, all of them wait 2 minutes (Options tab; 0 turns it off). One advert can no longer land in Yell, General and Trade within seconds.
- **The quick-post bar's big button** (`/crm bar`, or right-click the minimap button) takes turns: next post, next channel. General, then Trade, then General again. Outside a city, where there is no Trade, it uses General. Tick Yell on the bar to include it. While it waits, the button counts down.
- **Or choose exactly where:** pick a channel on the bar (Say, Yell, Gen, Trade, Party, Guild), then click a post. It goes to that channel only, whatever the post is ticked for. The bar shows when the picked channel is ready.
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

### Bag offers (out in the world)

For players you meet while questing, who carry cloth but not much gold. The quick-post bar has two buttons at the top: **Open WoW CRM** (the window, on the page you left it) and **Products** (straight to the bag offers). On the Products tab, **Bag offers** / **All recipes** switch between the two views.

The offers are the biggest plain bag of each cloth: Red Linen Bag, Red and Green Woolen Bag, Black and Green Silk Pack, Red Mageweave Bag, then Runecloth and Mooncloth Bag once you have them. Bags you mark as products are offered as well. Target a player and the bags that suit their level are marked.

Click a bag, then **Post to chat box**. A line like this goes into the chat box, on whatever channel it is set to (Say, usually), and is **not sent**. Change it if you like, then press Enter yourself:

> Tailoring: Red Linen Bag makes [Red Linen Bag] (10 slot). Bring 8 Linen Cloth + 1s for Coarse Thread and Red Dye and a tip, and I'll make it right here!

- The cloth is the raw cloth: bolts are broken down using your own bolt recipes, so they bring 8 Linen Cloth rather than 4 bolts.
- The fee is what thread and dye cost at the vendor plus a tip (20% unless you change **Tip %**), rounded up to a whole silver. Vendor prices are read whenever you open a vendor window. Until then they are estimates, marked with \*.
- The recipe and the bag are links when the game has them ready and they fit in 255 bytes; otherwise their names are used.
- Change the wording in **Message**. `{recipe}`, `{item}`, `{size}`, `{mats}`, `{fee}` and `{vendor}` are filled in.
- Placing an offer counts as a post for contact tracking: whoever whispers you afterwards becomes a lead, tagged with the bag you offered.

## In the profession window

WoW CRM adds to the game's own profession window (the Professions window on the Forever client; the older trade skill and Enchanting windows elsewhere):

- **Double-click a material** under the recipe. If a recipe in this window makes it, for example the Coarse Grinding Stone that Patterned Bronze Bracers need, that recipe opens. Craft it, then press **Back to Patterned Bronze Bracers** beside the window. The button says *(ready)* once you hold enough. You can go several levels deep; Back retraces your steps.
- **Materials you cannot make here** open a panel that says where they come from: the mining node or creature type, the vendor, or the profession that makes them (from Mastercraft's scan of your other characters). If Questie is installed, its database adds the named creatures, nodes and vendors. **Wowhead** gives you the item's Wowhead page, which lists every source with drop chances.
- **Craft first.** When the chosen recipe needs parts you can make here but do not hold, a note beside the window lists them in order, for example *Craft first: 2x Coarse Grinding Stone*, and what you are still short of.

Hover over a material to see which of the two a double-click will do. WoW CRM never crafts for you; the game's Create button stays yours. The built-in notes cover common ores, stone, bars, cloth, leather, herbs, elementals, enchanting materials and vendor supplies. The add-on cannot reach Wowhead from inside the game, so anything else is a click away on Wowhead.

## Opty: what people need, before there is an order

An **opportunity** is a need written down: *Skotor Ironmark needs 5 silver*, *Claire Paige needs more Waylaid Crates for merchant favor*, *Rosa Vell wants a Red Mageweave Bag next week*. Orders record what happened; opportunities are for planning what should happen.

- **Start one** on the **Opty** tab (type who it is for, or press **Me** or **Target**), from a lead (**Opportunity** on the Leads tab), or from a contact (**+ Opportunity**).
- **Your own characters count.** It's your address book, so requests to and from your alts sit next to everyone else's. Mark your alts as **my character** on the Contacts tab and they show in blue.
- **Request:** write it out over as many lines as you need: what they want, how many, who brings what.
- **Conversation:** every whisper with them is shown under the request (the lead's conversation when the Opty came from a lead), so nothing has to be copied over.
- **Which way:** *They need it* (from you), or *I need it from them*.
- **Price:** gold (`2g 50s`) or words (`their mats + 50s tip`). Gold becomes the order's agreed price; words go in the order's notes.
- **Work it:** a stage (New, Working, Quoted, then Won or Lost), a next step, and **Follow up in N days**. Open ones are listed with the most overdue first, and due ones are marked. **Alert me when online** uses the same online alert as follow-ups.
- **Won: make it an order** starts an order with the request's first line as the item still to hand over. The full request goes in the order's notes. Your next trade with them fills it in, as with any order.

## From lead to order

**One person, one lead.** A whisper joins the person's open lead whatever post it was about, so answering two of your posts, or chatting on after you posted again, no longer makes a second lead. Whispers within 12 hours of their last one also join it, even after it became an order. Leads split by older versions are folded into one at login.

**The conversation.** Click a lead to see the post they answered, then every whisper both ways, with times. Whispers you send are kept for anyone already in your contacts (the last 200 per person, on your computer only).

**Make it an order.** Pick one of your products (marked on the Products tab). The order starts as *quoted* with that item still to hand over and your price as the agreed price, for example a Red Mageweave Bag at 1g 90s. Or start an empty order and fill it in.

**The trade completes it.** When you trade with them, the add-on offers to add the trade to that open order, however long ago it was made. Handing over the bag delivers the planned bag rather than adding a second one, and the gold received is recorded as received, not added to the agreed price. Nothing is counted twice. If you deliver another way, click the line on the Orders tab and press **Given**. **Mark paid** with no gold typed uses the agreed price.

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
- **Tracking** only captures whispers after you have made a post, switches on when you post (you can turn that off on the Options tab), and switches itself off 30 minutes after your last post (adjustable).
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
