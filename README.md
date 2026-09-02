# Mixing Mysteries Helper

This retail World of Warcraft addon turns the **Mixing Mysteries** farm into a
single-key sequence while preserving Blizzard's protected-action rules. Every
target or interaction still requires one physical key press.

The addon has no default key. Bind **Chain Actions** in the game's key-binding
settings, then keep pressing your chosen key to cycle through:

1. Target **Ofi the Sly**.
2. Use WoW's protected **Interact With Target** binding.
3. Select an offered ingredient automatically, prioritizing recipes needed for
   **Mysterious Mix Master**, then a balanced mix of one of each reagent, then
   any available ingredient.
4. Target **Mysterious Offering**.
5. Use **Interact With Target** on the offering.
6. Return to the first step after the quest/loot event.

The helper pools all ten combination-specific Offering containers into one
generic icon on the right side of the panel. Its count is the total across all
variants. Each click opens an available variant, automatically switching to
another variant when needed. The tooltip lists the variants currently in the
character's bags, and the button disappears when none remain.

The addon also accepts quest `97016` and completes its no-choice turn-in when
those standard quest frames appear.

The main panel shows the current bag counts for Clouded Blood-Pearls, Ancient
Knucklebones, and Serpent's Feathers. Hover the reagent line for the full item
names. Click it to open a preselected Auctionator shopping-list import; press
**Ctrl+C** and paste it in Auctionator's Import window. It warns in chat when
fewer than the required remaining reagents are available and pauses the gossip
sequence until enough reagents are in the bags. Adding the missing reagents
resumes an open Ofi dialog automatically. The panel is visible by default.

## Language support

Targeting is locale-aware. The helper identifies Ofi and the Mysterious
Offering by their NPC IDs, learns the localized names from the active WoW
client, and uses those names for its protected target macros. This works with
every game client locale without maintaining translated NPC-name tables.

Reagent selection uses the ingredient picker's stable game-defined option order
(Pearl, Bone, Feather) to map each choice to its item ID. It does not depend on
the translated gossip label, so achievement and balanced-mix priorities work in
every client language. The helper uses localized item names only as a fallback
when recovering an already-open picker it did not open itself.
In the addon settings, you can show or hide it manually and optionally show it
automatically when you are near Ofi the Sly.

Configure **Chain Actions** in **Options > Key Bindings**. The game’s normal
binding UI shows conflicts and lets you change or unbind the helper key. The
helper panel opens the addon settings, where **Key bindings** opens that game page.

## Commands

- `/mmh help` to show available commands
- `/mmh enable` or `/mmh disable`
- `/mmh reset` to reset the sequence
- `/mmh settings`
- `/mmh show` or `/mmh hide`

The status panel can be dragged with the left mouse button.

## Important limitation

The addon cannot legally collapse the sequence into one key press. Targeting and
interaction are protected actions, so the implementation changes what the same
key does between presses. Binding updates deferred during combat are applied as
soon as combat ends.
