# Full screen (20:9) in every game

Research of 2026-10-27. The OnePlus 8 panel is 2400x1080: a 20:9 aspect ratio (2.22:1). Most
games are made for 16:9 (1.78:1), and 20:9 is close to the "21:9 ultrawide" PC monitors
(2.33:1), so the ultrawide fixes written for PC monitors mostly fit this screen too.

Terms used below:

- *pillarbox* = black bars left and right of a picture narrower than the screen;
- *Hor+* = on a wider screen the game shows more on the sides (good); *Vert-* = it keeps the width
  of the view and cuts the top and bottom instead, so the picture looks zoomed in (bad);
- *ASI loader* = a small DLL with the name of a system DLL (`dinput8.dll`, `winmm.dll`,
  `version.dll`, ...) placed next to the game's .exe; the game loads it by itself, and it loads
  the fix (a `.asi` file) into the game. Under Proton it needs a DLL override (below) so that Wine
  takes the file from the game folder instead of its own copy.

## What already works

gamescope patch `9001` (since 2026-10-04): every resolution Steam asks for keeps its height and
gets the panel's 20:9 shape (1920x1080 becomes 2400x1080, Steam's "Maximum game resolution"
1280x720 becomes 1600x720). A game that supports any aspect ratio sees a 20:9 screen and fills it.

## Why a game can still show bars

1. **The game picked a 16:9 resolution.** Wine also offers standard 16:9 sizes (1920x1080,
   1280x720, ...), and a settings file synced by Steam Cloud from the PC brings the PC's
   resolution along. Fix: in the game's settings choose 2400x1080 or 1600x720 (or "desktop
   resolution" / borderless). 1600x720 also costs the GPU 2.25 times fewer pixels than 2400x1080
   (performance-scan.md 3.1).
2. **The game fills 20:9 but looks zoomed in** (Vert-). Fix: a field of view setting if the game
   has one; for Unreal Engine games the Engine.ini line in section B.
3. **The game only draws a 16:9 picture** (its own bars, or a 16:9-only resolution list). Fix: a
   per-game fix (A); without one, zoom or stretch with gamescope (C), or accept the bars.
4. **Cutscenes and videos** made in 16:9 keep their bars, also with most fixes. Normal.

## A. Per-game fixes (the best result: real widescreen)

Where to look: the game's page on [PCGamingWiki](https://www.pcgamingwiki.com/), rows
"Widescreen resolution" and "Ultra-widescreen", which link the known fixes.

- **[Lyall's fixes](https://github.com/Lyall)** (about 60 games, mostly Japanese games and
  console ports: Metaphor, Persona 3 Reload, Final Fantasy VII Remake/Rebirth and XVI, Clair
  Obscur, Granblue Fantasy Relink, Resident Evil 5, ...). Each README has a "Steam Deck/Linux"
  section with the launch option, for example `WINEDLLOVERRIDES="winmm=n,b" %command%`
  (MetaphorFix).
- **[ThirteenAG's WidescreenFixesPack](https://github.com/ThirteenAG/WidescreenFixesPack)**
  (hundreds of older games, the 2000s and early 2010s: the games the Adreno 650 runs best). They
  use the [Ultimate ASI Loader](https://github.com/ThirteenAG/Ultimate-ASI-Loader), whose README
  points to a [Proton/Wine guide](https://silentsblog.com/setup-instructions/#proton-wine): the
  same `WINEDLLOVERRIDES="<loader name>=n,b" %command%` launch option.
- **Flawless Widescreen** (a Windows program that patches the game in memory while it runs): it
  would have to run inside the game's Proton prefix, next to the game, under FEX. Not tried; a
  last resort.

Installing on the phone: the fix's files go into the game's folder,
`~/.local/share/Steam/steamapps/common/<Game>/` in the Steam container (or the games partition
it points to, see `bind-steamapps.sh`), copied over SSH from the PC. The launch option is added
in Steam (the game > Properties > Launch Options) and combines with others in front of
`%command%`, for example `WINEDLLOVERRIDES="dinput8=n,b" FEX_TSOENABLED=0 %command%`.

Under FEX: the fix is x86 code like the game, and FEX runs it the same way. Fixes that patch the
game's code in memory depend on FEX noticing the changed code, which it checks for. Not tried on
the phone yet: the first test below.

## B. Unreal Engine 4/5 games that look zoomed in

UE4's default keeps the horizontal field of view (Vert- on 20:9). One line makes it keep the
vertical one (Hor+), as described for ultrawide monitors by the
[WSGF](https://www.wsgf.org/node/29773). In the game's Proton prefix, file
`~/.local/share/Steam/steamapps/compatdata/<appid>/pfx/drive_c/users/steamuser/AppData/Local/<Game>/Saved/Config/WindowsNoEditor/Engine.ini`
(UE5: `.../Saved/Config/Windows/Engine.ini`), add:

```ini
[/Script/Engine.LocalPlayer]
AspectRatioAxisConstraint=AspectRatio_MaintainYFOV
```

Some games rewrite the file at start; then make it read-only (`chmod 444`). Reports differ by
game: in some it works, in some it reverts after cutscenes. It does not remove bars a game draws
on purpose (a camera with a fixed aspect ratio): that needs a fix from A.

## C. No fix: let gamescope zoom or stretch

For a game that only makes a 16:9 picture:

1. In the game, set **windowed** (or borderless) at a 16:9 size, for example 1280x720 or
   1920x1080.
2. In Quick Access > Performance, set **Scaling Mode**:
   - **Fill**: zooms until the screen is full, no distortion, but cuts about 10% at the top and
     10% at the bottom (16:9 scaled to 2400 wide is 1350 tall, 270 rows more than the panel);
   - **Stretch**: nothing cut, everything 25% wider.

gamescope scales the window it shows (the game's own size, not the screen's): Fill takes the
larger of the two scale factors and Stretch scales each axis on its own
(`calc_scale_factor_scaler()` in `steamcompmgr.cpp`, 3.16.29); Steam sets the mode through the
`GAMESCOPE_NEW_SCALING_SCALER` property. The same method is what Steam Deck users use for 16:9
games on the Deck's 16:10 screen, also in windowed mode
([SteamDeckHQ](https://steamdeckhq.com/news/steamos-3-5-best-feature-for-720p-resolutions/)).
In exclusive fullscreen at 16:9, Wine likely scales the picture into the 20:9 screen itself and
adds the bars before gamescope sees it, so Fill would change nothing there (to check, below).

## Order of attempts for a game with bars

1. The game's own settings: native resolution (2400x1080 or 1600x720), borderless or fullscreen,
   the field of view slider if there is one.
2. PCGamingWiki: a fix (A), or the Engine.ini line for Unreal games (B).
3. Otherwise windowed 16:9 + Fill (C), or keep the bars.

## To check on the phone (first session with a game)

- That Quick Access > Performance shows Scaling Mode in our session, and that Fill and Stretch
  change the picture of a 16:9 window.
- Exclusive fullscreen at 1920x1080 in a Proton game: are the bars drawn by Wine (Fill has no
  effect) or not.
- One ASI fix under FEX: a ThirteenAG or Lyall fix for a game the maintainer owns.

The list of games that still show bars comes from the maintainer's library; each one gets a line
here with what worked.
