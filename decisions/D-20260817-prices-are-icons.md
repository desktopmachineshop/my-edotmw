# D-20260817-prices-are-icons · 2026-08-17 · Accepted

**A resource is a colour and a number. The word is a tooltip.**

## Decision

Everywhere the HUD states a resource — the top bar's wallet, a build
button's price, a train tile's price — it draws the resource's **swatch**
and the number, and never the word:

- **the top bar** reads `[pink] 92  [orange] 70  [yellow] 40  [grey] 0`.
  `RESOURCE_PITCH` drops 168 → 96 as a direct consequence, giving the top
  bar roughly 300 design units back;
- **a build button** carries its price as swatch-and-number pairs at its
  right end, with the button's own text inset (via the stylebox's content
  margin) so a long name ellipsises where the price starts rather than
  running through it;
- **a train tile** does the same on the row its `5/5` occupies for a
  composition chip — a tile states one or the other, never both.

The swatch is not a new icon set: it is `Client._node_colour`, the same
four colours the top bar, the minimap and the world's resource markers
already use, so the icon needs no legend beyond the game. Hovering a top
bar readout names its resource; a train tile's tooltip carries its whole
price in words.

## Rationale

Asked for directly, during the same playtest, as "save space by using
resource icons instead of text" — and it is the cheapest space left in the
HUD, because the words were never carrying anything the colours did not.
Measured on the shipping layout:

| readout | as words | as icons |
|---|---|---|
| top bar, four resources | 672 units (`RESOURCE_PITCH` 168 × 4) | 384 |
| a one-resource price | "150 wood" ≈ 70 units | 30 |
| a two-resource price | "40 wood · 45 stone" ≈ 150 units | 66 |

That matters most on the 26-unit one-line build buttons the short bar
(D-20260817-selection-bar-three-columns) left: at 1080p a button is 151
units wide, and a two-resource price in words did not leave room for the
name it belonged to.

## Consequences

- **A price that does not fit is now a silent truncation** rather than a
  clipped sentence, which is a worse failure mode. `COST_SLOTS` is 4 —
  every resource can appear — and a test walks the shipped unit and
  building defs asserting none names more kinds than a button can draw.
  A chip has two slots against a shipped worst case of three, and carries
  the whole price on its tooltip.
- Cost entries are built by `_cost_entries`, the list-shaped sibling of
  `_cost_text`, kept beside it so the icons and the words cannot disagree
  about which resources a thing costs.
- Build buttons align their label LEFT (they have a price at the right);
  the orders column, which never has one, stays centred.
- The icon metrics are deliberately tight (8-unit swatch, 20-unit number):
  a generously spaced icon price gives back the room it just saved, and
  20 units is three digits at `CAPTION_SIZE`, which every shipped cost is.

## Rejected alternatives

- **Abbreviating the words** ("150w · 45s"). Saves most of the same room
  with none of the work, but it is a second vocabulary to learn beside the
  colours the game already uses everywhere else — and it reads as a
  compromise rather than a design.
- **Textured icons per resource.** The swatch already is this game's
  resource vocabulary (D-087's node colours), and a new icon set would be
  a second source of truth for "what colour is stone".
- **Keeping the word in the top bar and only shrinking prices.** The bar's
  four words were the single largest block of redundant text in the HUD;
  leaving them would have kept `RESOURCE_PITCH` at 168 for nothing.

## Revisit trigger

A player unable to tell the four colours apart in play — the answer then
is a textured icon set, not the words back, because the words cost the
room this decision exists to save. Also worth revisiting if a resource is
ever added: four swatches read as four things, eight would not.
