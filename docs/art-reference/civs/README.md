# Civ unit reference boards

Concept reference for the six fantasy civs of
`decisions/D-20260823-fantasy-civs-on-a-four-epoch-ladder.md`, one board per
civ: a 4 x 6 grid, rows are the four epochs (medieval, imperial, modern,
futuristic), columns the six roles (worker, line foot, spear/defensive,
missile, cavalry/mobile, general). They are **reference, not assets**:
nothing in the game reads them, and an authored `.blend` under
`art/source/` is checked against the board for its civ and epoch, not the
other way round.

| file | civ | axis |
|---|---|---|
| `dominion.jpg` | Dominion (humans) | quality |
| `warhost.jpg` | Warhost (orcs) | quantity |
| `centaurs.jpg` | Centaurs | mobility |
| `deepholds.jpg` | Deepholds (dwarves) | fortification & siege |
| `gilded.jpg` | Gilded (goblin trade-compact) | economy & flexibility |
| `sylvans.jpg` | Sylvans (elves) | ranged attrition |
| `northmen-as-shipped.jpg` | the SHIPPED Northmen roster (`civs/northmen.tres`), single row, pre-rework | — |

Generated 2026-08-23 with Google Gemini image generation ("Nano Banana"),
one generation per civ, no editing. The exact prompts are below so a board
can be regenerated, or a seventh civ drawn to match. Paste the shared
header, then one civ block.

## Known drift from the prompt

Worth knowing before treating a board as authoritative:

- **Dominion and Northmen** carry small front-view insets the other boards
  dropped; the grid header never asks for them, they were inherited from
  the earlier single-row prompt. Ignore them.
- **Gilded, medieval "Hired Pikeman"** was briefed as ogre-ish and came out
  as a large human. Either reads.
- **Northmen** came back with five figures for six asked — the LEVY is
  missing.
- **Warhost** uses a different label font from the rest. Cosmetic.

## Shared header

```
Create a single character-design reference board (one image, 16:9, clean grid layout) for one faction of a stylised low-poly real-time strategy game that spans four epochs.

ART STYLE: polished low-poly 3D game art, flat-shaded faceted geometry, clean readable silhouettes, chunky proportions, simple solid colours with subtle gradients, soft studio lighting, no photorealism, no fine textures. Think modern stylised RTS unit renders. Identical style across every figure.

LAYOUT: a 4-row by 6-column grid of full-body figures on small hexagonal ground tiles, three-quarter pose, plain neutral grey-green studio background. ROWS are the four epochs top to bottom, labelled on the left edge: MEDIEVAL, IMPERIAL, MODERN, FUTURISTIC. COLUMNS are the six roles left to right, labelled along the top: WORKER, LINE FOOT, SPEAR / DEFENSIVE, MISSILE, CAVALRY / MOBILE, GENERAL. Under each figure a small clean label with its unit name only. All figures at consistent scale so size differences read. The worker in every row is the humblest figure and the general the grandest. Each row must read as the SAME culture one era later: keep the faction colour, emblem, shield/armour motifs and body type constant while the technology changes. No text other than the labels, no watermark.
```

## Dominion

```
FACTION: the DOMINION — a disciplined, centralised human empire. Square-jawed soldiers, close-cropped hair, upright parade bearing, everything issued and uniform. Faction colour is imperial blue (#2C4A8A) with white trim and a gold eagle emblem on every banner, shield and shoulder; secondary tones are polished steel and black leather. Clean lines, symmetry, nothing scavenged.

MEDIEVAL row: Serf (hoe and grain sack), Man-at-Arms (sword, kite shield, mail and tabard), Halberdier (halberd, breastplate), Longbowman (longbow, quiver, leather jack), Knight (barded warhorse, lance, full plate), Marshal (ornate plate, great helm, eagle standard).
IMPERIAL row: Labourer (pick, powder barrel), Redcoat Musketeer (musket, tricorne, blue coat white facings), Grenadier (tall mitre cap, grenade pouch, short sword), Field Gun crew (cannon with two gunners), Cuirassier (breastplate, plumed helm, sabre, heavy horse), General (bicorne, epaulettes, sash, spyglass).
MODERN row: Engineer (wrench, tool bag, hard cap), Rifleman (bolt rifle, greatcoat, steel helmet), Machine-Gun team (tripod gun, two crew), Field Artillery (howitzer, crew), Tank (riveted steel tank with eagle on turret), Commander (peaked cap, greatcoat, map case, binoculars).
FUTURISTIC row: Fabricator drone-tender (hover toolkit), Iron Legionnaire (sleek power armour, rail rifle), Bulwark (heavy power armour, energy shield, pike-lance), Rail Gunner (shoulder rail cannon), Walker Tank (two-legged mech with eagle crest), Lord-Marshal (ornate gold-and-blue command armour, energy standard).
```

## Warhost

```
FACTION: the WARHOST — brutal orc clans, strength over discipline. Big, heavy-shouldered green-grey orcs with tusks and scarred hide, hunched aggressive postures. Gear is scavenged, crude, dented and heavy; bone and tooth trophies, spiked shoulder guards. Faction colour is blood red (#9E2A2A) as war paint, cloth wraps and skull-totem banners; secondary tones are rust iron, bone white and mud-brown leather. No symmetry, no polish, ever.

MEDIEVAL row: Drudge (runt hauling logs, pickaxe), Grunt (cleaver, plank shield), Pike-Brute (jagged pike, crude tower shield), Hunter (bone bow, hide), Wolf Rider (dire wolf, spear), Warchief (spiked pauldrons, skull helm, huge cleaver, bone banner).
IMPERIAL row: Drudge with powder kegs, Blunderbuss Mob (oversized blunderbuss, bandolier), Pike-Brute with iron plates, Scrap Cannon (bolted-together cannon, two crew), War-Boar Rider (armoured giant boar, lance), Warlord (red coat stolen from a general, too small, over scrap plate).
MODERN row: Drudge with welding torch, Shoota (belt-fed crude machine gun carried by hand), Iron-Brute (boiler-plate armour, hydraulic claw), Rokkit Brute (shoulder rocket tubes), Scrap Half-Track (fume-belching rust vehicle, spikes), Big Boss (goggles, huge wrench, exhaust pipes on back).
FUTURISTIC row: Drudge with looted energy cell, Burna (looted plasma gun held wrong), Mega-Brute (bolted-on energy shield and crackling fist), Zapper (looted laser cannon on a cart), Burner-Jet Rider (rocket-bike, flames), Doom Engine (walking scrap war-machine with a warchief throne on top, skull banner).
```

## Centaurs

```
FACTION: the CENTAURS — herds of the open steppe, half horse half warrior, never still. Lean muscular bodies, braided manes, wind-worn faces, feathered and beaded tack. Faction colour is steppe gold (#C9A227) with teal accents on feathers, tack and banners; secondary tones are bay and dun hides, tan leather and bronze. Everything is light, strapped on, built to move. They never build walls.

MEDIEVAL row: Forager (herd-hand with panniers of roots and a sling), Lancer (long spear, round hide shield), Pike-Guard (braced long pike, the only heavy one), Horse-Archer (composite bow, firing at full gallop), Outrider (no extra mount needed: a lighter, faster scout with javelins and no armour), Khan (feathered crown, bronze scale barding, gold banner spear).
IMPERIAL row: Forager with satchels and a pistol, Carbineer (short carbine fired from the canter, bandolier), Pike-Guard with breastplate, Dragoon (paired pistols, sabre), Light Gun team (two centaurs towing a small field gun), Khan with plumed shako and sash.
MODERN row: Mechanic (tool harness, oil can), Trooper (bolt rifle, goggles, flat cap), Shield-Guard (steel plate, riot shield), Sharpshooter (scoped rifle, bandana), Iron Herd Armoured Car (open-topped scout car with a centaur gunner), Field Marshal (leather greatcoat over the horse-body, binoculars).
FUTURISTIC row: Tender (hover drone tools), Skimmer (hover harness over the legs, pulse carbine), Shield-Guard (energy barrier projector), Rail Lancer (shoulder-mounted rail lance), Gravity Cavalry (fully hovering, legs tucked, wing-fins), Sky-Khan (golden hover armour, energy pennant).
```

## Deepholds

```
FACTION: the DEEPHOLDS — dwarven mountain-holds of stone and forge. Short, wide, immovable figures with braided beards, heavy boots, rune-cut armour. Everything is thick, engineered, riveted, over-built. Faction colour is forge orange (#D2691E) on runes, beards' rings and banners against slate grey (#4A4E57) iron and granite; secondary tones are brass and dark oak. Squat silhouettes; their "cavalry" is always a machine, never an animal.

MEDIEVAL row: Miner (pick, lantern helm, ore sack), Shieldwarden (huge round shield, hand axe, heavy mail), Hearthguard (long glaive, tower shield, full plate), Crossbowman (heavy crossbow, pavise), Siege Ram cart (two crew pushing a wheeled ram), Thane (runic plate, great axe, stone-and-iron banner).
IMPERIAL row: Sapper (powder kegs, fuse), Grenadier (short blunderbuss, grenades, bearskin cap), Ironwall (thick plate, tower shield with firing slit), Bombard crew (fat squat mortar, two crew), Steam-Cart (brass steam wagon with a swivel gun), Lord-Engineer (goggles, brass plate, blueprint scroll, banner).
MODERN row: Engineer (welding mask, rivet gun), Steam-Armour trooper (boiler-backed powered suit, rifle), Bulwark (huge shield-suit with pistons), Heavy Howitzer (massive gun, tracked carriage, crew), Tunnelling Engine (drill-nosed tracked vehicle), Forge-Marshal (brass command suit, smokestacks, banner).
FUTURISTIC row: Tender (hover forge-drone tools), Sealed Bulwark Suit (heavy sealed armour, energy hammer), Aegis-Warden (walking shield generator), Siege Beam team (tripod beam cannon, two crew), Fortress Crawler (tracked mobile bastion with turrets), High Thane (rune-lit mega-armour, energy banner).
```

## Gilded

```
FACTION: the GILDED — a goblin trade-compact of bankers, brokers and hired muscle. Small, sharp-faced, quick-eyed goblins in fine coats that are always slightly too grand, surrounded by mercenaries of other races they have paid for. Faction colour is gold (#E0B020) on coin emblems, buttons, sashes and banners against deep purple (#4B2A6E) cloth; secondary tones are brass, velvet red and ledger-paper cream. Everything is bought, branded with the coin emblem, and slightly mismatched because it came from six different suppliers.

MEDIEVAL row: Clerk-Porter (ledger, coin chest, abacus), Hired Blade (human sellsword in compact livery, sword and buckler), Hired Pikeman (ogre-ish big mercenary with a pike), Hired Crossbowman (crossbow, purple tabard with coin), Hired Horse (mercenary light horseman), Factor (goblin in fur-trimmed velvet, gold chain, a contract scroll as a banner).
IMPERIAL row: Clerk with strongbox and pistol, Mercenary Musketeer (regimental coat, purple facings), Pike-Regiment (mercenary with pike and breastplate), Privateer Gunner (small naval swivel gun on a cart), Hussar-for-Hire (fancy braided uniform, sabre), Director (goblin in top hat, cane, gold-embroidered coat).
MODERN row: Clerk with typewriter case and revolver, Contract Rifleman (khaki, purple armband, rifle), Shield-Contractor (riot shield, baton, body armour), Hired Gunner (light machine gun), Armoured Train car (turreted rail car with coin livery), Chairman (goblin in pinstripes, cigar, brass-plated limousine door as backdrop).
FUTURISTIC row: Clerk with holo-ledger tablet, Drone Trooper (cheap mass-produced combat drone, gold-and-purple), Shield Drone (floating barrier emitter), Gun Drone Swarm (cluster of small flying guns), Hover-Courier (sleek goblin hover-bike with cargo pods), The Broker (goblin on a hovering golden throne-chair, holographic stock tickers, coin banner).
```

## Sylvans

```
FACTION: the SYLVANS — an elven forest realm; long lives, long bows, longer memory. Tall, slender, graceful figures with long hair, angular faces, quiet poise. Gear is grown or shaped from living wood, leaf-steel and silver; flowing lines, never riveted. Faction colour is forest green (#2E6B3A) with silver (#C8D0D8) leaf emblems and pale cream cloth; secondary tones are bark brown and moonlit blue. Even their modern and futuristic technology looks grown, not built — curved, organic, glowing at the seams.

MEDIEVAL row: Tender (basket of fruit, pruning blade), Glaive-Dancer (long glaive, light scale, flowing cloak), Warden (tall leaf-shaped shield, spear), Longbow (tall recurve longbow, hood), Stag Rider (great antlered stag, bow), Lord of the Glade (silver circlet, leaf-steel plate, living-branch standard).
IMPERIAL row: Tender with seed pouches, Long-Gun (slim rifled long musket with carved stock, green coat), Warden with silver breastplate, Ranger Corps marksman (long-gun, cloak of leaves, kneeling), Stag Dragoon (stag, paired pistols), Warden-Captain (silver officer's coat, sabre, banner).
MODERN row: Tender with grafting tools, Sharpshooter (scoped long rifle, ghillie cloak of leaves), Bulwark Warden (grown-wood riot shield, carbine), Grown Artillery (a living-wood gun-tree on roots, crew), Canopy Glider (winged glider-rider, wooden wings, rifle), Marshal of the Wood (long coat of leaf-scale, binoculars, banner).
FUTURISTIC row: Tender with a floating seed-drone, Lightline Archer (bow that fires beams of light, glowing quiver), Spirit-Shield Warden (projecting a shimmering green barrier), Beam Ranger (long rail of living crystal), Wind-Rider (hovering grown-wood skimmer with silver fins), Voice of the Worldtree (robed figure lit from within, branches of light as a banner).
```

## Northmen, as shipped (single row, earlier prompt)

The pre-rework board of the roster that is in `units/northmen_*.tres` and
`units/gatherers.tres` today. Different header — a single row of six, with
front-view insets — kept because it is the only picture of the shipped
roster's intended look.

```
Create a single character-design reference board (one image, 16:9, clean layout) for the "Northmen" faction of a stylised low-poly real-time strategy game.

ART STYLE: polished low-poly 3D game art, flat-shaded faceted geometry, clean readable silhouettes, chunky proportions, simple solid colours with subtle gradients, soft studio lighting, no photorealism, no fine textures, no text-heavy detail. Think modern stylised RTS unit renders. Consistent style across every figure.

FACTION IDENTITY: a cold-country raiding culture — numbers over quality. Cheap, fast-mustered troops: rough furs, wool, leather, round wooden shields, iron caps, braided hair and beards, axes and spears. Nothing is heavy plate; no knights, no heavy foot. Faction colour is rust-orange (#C76B47) used on cloth, shield faces and banners; secondary tones are dark brown leather, bone white, and cold grey-blue iron.

LAYOUT: six full-body units standing on small hexagonal ground tiles, arranged left to right, each in a three-quarter pose with a small neutral front-view inset above it. Plain neutral grey-green studio background. Under each figure a small clean label with its name only. Keep all six at consistent scale so size differences read.

THE UNITS (left to right):
1. GATHERERS — the civilian worker. Unarmed villager in a plain wool tunic, apron and hood, carrying a woodcutter's axe over one shoulder and a wicker basket or bundle of logs; a small sack of grain at the belt. Slightly stooped, hard-working, clearly non-combat. Same rust-orange trim on the hood so they read as Northmen.
2. LEVY — the cheap mass infantry. Lean farmer-warrior, simple tunic and fur vest, hand axe and small round shield, no helmet or a plain leather cap. Looks numerous and expendable.
3. HEARTH SPEARS — defensive spearmen. Long ash spear, larger round shield with rust-orange face, padded wool coat, iron cap. Sturdier stance, braced.
4. SKIRMISHERS — light ranged troops. Javelins in a bundle, sling or throwing arm raised, almost no armour, bare arms, light cloak, very fast-looking and lightly built.
5. RAIDERS — light cavalry. Shaggy hardy pony, rider with spear and axe, fur-trimmed cloak, light kit; built for speed and hit-and-run, not a charge.
6. WARLORD — the faction general, the one unit that looks rich. Taller and broader, bear-fur mantle, ornate iron helm with cheek guards, large decorated axe, rust-orange war banner on his back, gold arm rings. Commanding pose.

Make the group read instantly as one culture: shared shield designs, shared colour palette, shared silhouette language. The gatherer should be visibly the humblest figure and the warlord the grandest. No modern elements, no photoreal, no watermark.
```
