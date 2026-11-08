# Multiplayer Tournament Organiser

Host tournaments for [Balatro Multiplayer PvP](https://github.com/Balatro-Multiplayer/BalatroMultiplayerPvP) from inside the game: create them, then run them (players, seeding, results, the timetable, messages to players).

**Players don't need this mod.** Browsing, joining, checking in, playing and the bracket are all part of the PvP mod's TOURNAMENTS tab. This mod only adds the organiser's side: the **ORGANISE** page in that tab, with a **NEW TOURNAMENT** wizard and a **MANAGE** page for every tournament you run or help run. Without the mod, ORGANISE doesn't show.

## Installation

Requirements:

- [Steamodded](https://github.com/Steamodded/smods) and [Lovely Injector](https://github.com/ethangreen-dev/lovely-injector)
- [MultiplayerAPI](https://github.com/Balatro-Multiplayer/BalatroMultiplayerAPI) (>= 1.0.2)
- [MultiplayerPvP](https://github.com/Balatro-Multiplayer/BalatroMultiplayerPvP) (>= 1.0.5)

Extract the mod into its own folder in your Balatro `Mods` directory, next to MultiplayerAPI and MultiplayerPvP, then open **PvP > TOURNAMENTS > ORGANISE**.

## Creating a tournament

**NEW TOURNAMENT** opens a wizard. Every setting has a **?** that explains it, and the wizard won't go on while a step has a problem (it says what).

| Step | What you set |
|---|---|
| **BASICS** | Name, description, public (listed in Browse) or private (invite code only), start date and time (your local time), player limit, check-in before the start, whether players must be on their ranked profile, and OFFICIAL (only with the official privilege, below). |
| **FORMAT** | Single or double elimination (grand final reset on or off), round robin (group size) or Swiss (number of rounds), and seeding: by rating, random, or your own order. |
| **GAMES** | Game mode, ruleset, series length (Bo1, Bo3...), and the decks: one deck and stake for everyone, or a ban-and-pick pool of decks, stakes and Cocktails (mixed decks). |
| **ROUNDS** | Different games for some rounds, say Bo5 and a locked deck for the final. Rounds are numbered in playing order or named (Final, Semifinals, Winners/Losers final). |
| **SCHEDULE** | The timetable: a live event (players ready up when their match opens), rounds you start by hand, or a league (play each round by a deadline). Then round by round: a break before a round, a round you start by hand, a round that continues at a date and time (with its own check-in), or a different way of playing. A preview shows the bracket for any number of players. |
| **REVIEW** | Everything on one page. **CREATE** saves it as a draft or opens it for sign-ups straight away. |

**SAVE TEMPLATE** and **LOAD TEMPLATE** keep a wizard's settings for next time. Templates are JSON files in `%AppData%/Balatro/mp_tournament_templates`, so they can be shared by copying the file (**OPEN FOLDER** shows them).

Before a tournament starts, **EDIT** on its MANAGE page reopens the wizard with everything as it was. Once it's running, only the name, description and round settings can change.

### Rounds at a date and time

A round set to continue at a date and time (for example the final the next evening):

- has to be after the tournament's start, and timed rounds have to be in round order;
- never starts early. If earlier rounds run late, each of its matches opens as soon as both players are known, with the normal ready-up;
- can have its own check-in (the **Check in** setting: 10 to 60 minutes before, opening no earlier than the tournament's start). Every player still in is told when it opens. A player whose match is ready when the round starts and who didn't check in forfeits that match; if neither player checked in, the timetable's rule for unplayed matches decides it. Players still finishing an earlier round when it starts don't need to check in. If you start the round early by hand, its check-in is dropped.

## Running a tournament

**MANAGE** lists the tournaments you organise or co-organise (finished ones are hidden until **SHOW FINISHED**). Open one to:

- **Before the start:** open or close sign-ups, see who joined and checked in, remove players, move players up from the waitlist, set the seeding order (manual seeding), and start early.
- **While it runs:** see every match and its state, set a result (one game or the whole match) or clear one, give a match more time, start a round you start by hand, pause and resume the whole timetable, and cancel.
- **Talk to players:** a **NOTICE BOARD** shown above every player's tournament screen (set or clear it at any time), and **MESSAGE PLAYERS**, a short message into the lobby chat of one match or every live match, also shown to those players as a banner.
- **Co-organisers:** the organiser shares a **co-organiser code**; anyone who enters it (with this mod) can help run the tournament. Co-organisers handle the running side: players, the waitlist, results, more time, starting rounds, pausing, the notice board and messages. The organiser alone edits the settings, opens and closes sign-ups, sets the seeding order, starts the tournament, cancels it, and manages co-organisers.

On a Dev server, MANAGE can also fill a tournament with bots for testing.

## Limits

Set by the server:

- For now, only players with the `tournament_create` (or `tournament_official`) privilege can create tournaments. Admins can lift this on the website's admin panel. Without the privilege, NEW TOURNAMENT says so. Running a tournament you already organise or co-organise never needs it.
- You can create at most 10 tournaments a day and run at most 5 at once.
- **OFFICIAL** tournaments (listed first in Browse, with a gold badge) need the `tournament_official` privilege, which admins grant on the website's admin panel.
- Moderators can close any tournament from the website's admin panel; its players see the reason.

## Languages

All text is in `localization/en-us.lua` (keys `k_tom_...`). A translation adds `localization/<language>.lua` with the same keys; any key it leaves out shows in English.

## Development

The mod uses PvP's tournament client (`PVP.Tournaments`, `PVP.TUI`) and the server's `tournament_*` RPCs (in BalatroMultiplayerServer, `nakama/src/tournament/`). `lib/` is plain Lua (the wizard's form, templates, text) and is unit tested; `ui/` builds the pages.

Run the tests from the repository root with Lua 5.4:

```sh
for f in tests/*_test.lua; do lua5.4 "$f" || echo "FAILED $f"; done
```

`tests/text_test.lua` checks that every `k_tom_...` key the code uses exists in the English file.

## License

[GPL-3.0](LICENSE.md)
