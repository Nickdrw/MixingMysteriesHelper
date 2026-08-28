# Mixing Mysteries Helper

This retail World of Warcraft addon turns the **Mixing Mysteries** farm into a
single-key sequence while preserving Blizzard's protected-action rules. Every
target or interaction still requires one physical key press.

The default key is **F12**. Keep pressing it and the addon cycles through:

1. Target **Ofi the Sly**.
2. Use WoW's protected **Interact With Target** binding.
3. Select one of each offered ingredient automatically by default, falling
   back to the first available ingredient if three different types are not present.
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
resumes an open Ofi dialog automatically. The panel only appears while the
player is near Ofi the Sly and hides again after leaving her area.

Configure **Advance Mixing Mysteries** in **Options > Key Bindings > AddOns**.
The game’s normal binding UI shows conflicts and lets you change or unbind the
helper key. The **Key bindings** button on the helper panel opens that game page.
There is no controls panel or action-bar macro.

## Commands

- `/mmh on` or `/mmh off`
- `/mmh reset`
- `/mmh sync` to rebuild the helper step from the current quest-log status
- `/mmh show` to enable the proximity-based panel or `/mmh hide` to keep it hidden
- `/mmh status`
- `/mmh mix balanced` to prefer one of each offered ingredient
- `/mmh mix first` to repeat the first ingredient option
- `/mmh debug on` or `/mmh debug off`
- `/mmh ofi <localized NPC name>`
- `/mmh offering <localized NPC name>`

The status panel can be dragged with the left mouse button. Target names default
to the English client names and can be changed with the commands above.

On login, reload, enable, target changes, and quest-log updates, the helper
checks whether Mixing Mysteries is absent, active, or ready for turn-in. It
also uses a currently selected Ofi, a visible Ofi gossip window, or a selected
Mysterious Offering to resume at the matching interaction step. This lets it
recover when the quest was accepted or advanced before the addon was enabled.

## Important limitation

The addon cannot legally collapse the sequence into one key press. Targeting and
interaction are protected actions, so the implementation changes what the same
key does between presses. Binding updates deferred during combat are applied as
soon as combat ends.
