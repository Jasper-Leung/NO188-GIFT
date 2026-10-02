# 188号礼物 — Gift No.188

**Pack the landscape into your bag.**

A short, gentle 3D cycling journey built around Su Dongpo's "joys of the heart."
Ride an invented figure-8 loop, make three visits to each of five fictional
stations, and compose fifteen moments into a giftable postcard you can write on
and export.

Built for **Tripothon S1**, the "world building" AI hackathon. Theme:
*A Gift for _______. Ours: **A Gift for No.188**.

> This is a fictional narrative demo. The route is a purely mathematical
> figure-8 pattern that does not reference or reproduce any real road. Station
> names and scene layout are artistically invented. It does not claim to
> represent any real tourism road, official station brand, or real scenic-area
> operation. The theme draws on public-domain poetry by Su Dongpo (1037–1101).

---

## What kind of game is this?

**An atmospheric journey with a collect-and-compose payoff.**

Not a platformer, not a racing game, not a roguelike. There is no combat and no
fail-state screen that ends your run.

- **You ride a fixed loop** and stop at stations. The riding is the connective
  tissue, not the challenge.
- **There is dialogue.** Every fragment station introduces itself on your first
  visit, and a recurring character (郑铎 / Zheng Duo) interrupts you three times
  as you get further around the loop. His lines are about a life spent measuring
  the road instead of riding it.
- **There is a choice at the end**, and it is not cosmetic — see
  [The last thing you decide](#the-last-thing-you-decide).
- **There are five minigames**, one per joy. You can fail them; failing costs
  you that visit's reward and nothing else.
- **There is an economy.** You earn 旅币 (road coins) for riding and checking in,
  and spend them at three roadside shops (an inn, a tea stall, a lantern shop).
  A mood meter (心神) darkens the screen during the heavier story beats and
  recovers while you ride.

The closest reference is a short-form pilgrimage in the spirit of *Journey*:
the feeling comes from arriving, not from beating anything.

---

## The idea: "188" is two things, not three

| "188" means | In the game |
| :--- | :--- |
| **No.188** | the gift's serial number, printed on the postcard |
| **16 stations** | the "驿" (post-stations) you pass; the HUD counts `n/16 驿` |

**It is not a distance.** An earlier version of this README called it a "188 km
loop", and that was simply wrong in a way players would catch in the first ten
seconds: the actual loop is **1,228.8 m**, which at the 15 m/s top speed takes
**82 seconds** — about 7,200 km/h if you scale it to 188 km. The number was
always a serial, and the in-game text now says so everywhere (distance is an
internal currency unit only, never shown to the player).

---

## The five fragment stations

| # | Station | English name | The joy | Fragment |
| :-: | :--- | :--- | :--- | :-: |
| 1 | 云影台 | Cloudshadow Terrace | Rain stops; watch clouds and mountains soften | 云 **Cloud** |
| 2 | 茶烟小筑 | Tea Smoke Cottage | A guest arrives; draw water and brew tea | 茶 **Tea** |
| 3 | 琴音林 | Zither Grove | Listen to wind as if it were a zither | 琴 **Music** |
| 4 | 竹雨庭 | Bamboo Rain Courtyard | Night rain talks through the bamboo window | 竹 **Bamboo** |
| 5 | 花房·禽语湖湾 | Birdsong Cove Flower House | A bird answers the lake in its own language | 禽 **Bird** |

Eleven additional post-stations line the route. They cannot be checked in, but
riding through one floats a single line of its own text.

---

## Three visits, five joys

Each fragment station must be visited **three times** to max out. Collecting a
fragment is the *first* visit, not the last — "already collected" and "no longer
worth going" are different states, and the game treats them that way everywhere:
the top bar, the minimap highlight, and the ring at your feet all keep pointing
at a station until it is genuinely done.

Each visit plays one of the five minigames, rotating:

| | 1st visit | 2nd visit | 3rd visit |
| :--- | :--- | :--- | :--- |
| 云影台 | 云 trace the cloud | 茶 pour the tea | 琴 repeat the notes |
| 茶烟小筑 | 茶 pour the tea | 琴 repeat the notes | 竹 cut the bamboo |
| 琴音林 | 琴 repeat the notes | 竹 cut the bamboo | 禽 name the bird |
| 竹雨庭 | 竹 cut the bamboo | 禽 name the bird | 云 trace the cloud |
| 花房·禽语湖湾 | 禽 name the bird | 云 trace the cloud | 茶 pour the tea |

Your **first** visit to each station is still its own joy, so the thematic
pairing (the cloud terrace has you trace a cloud) is unchanged from the first
version. Across 15 check-ins each minigame appears exactly three times, and no
station ever shows you the same one twice in a row.

Station dialogue, by contrast, is **first visit only** — it is the station
introducing itself, and replaying it would flatten the sense of progress that
the three visits are supposed to build.

---

## The five minigames

| Joy | Mechanic | Failure |
| :--- | :--- | :--- |
| 云 Cloud | Trace a cloud outline with the mouse (or arrow keys + space) | Let go below 75% traced |
| 茶 Tea | Hold to fill the pot for 3 seconds | Releasing resets to zero (it cannot be failed) |
| 琴 Zither | Repeat a 4-note sequence | Wrong note, or 2.5 s of silence |
| 竹 Bamboo | Press on each bamboo as it appears (5 stalks) | Press too early or too late |
| 禽 Bird | Watch a bird, then pick it out of four | — (timed, not judged) |

Failing is not fatal: you get a short panel saying so, and the station is
immediately re-enterable once you ride off and come back.

Every minigame is fully keyboard-playable, and `Esc` cancels any of them — the
cancel button on screen is drawn, not a real widget, so without `Esc` a keyboard
player would be stranded.

---

## The last thing you decide

When all fifteen visits are done you get to choose how the gift ends:

- **留门 / Leave the Door** — the back of the postcard is pre-written, and the
  wax seal stays closed.
- **放手 / Let Go** — the back is left blank for you to write, and the seal on
  the front is broken open.

Both differences land on the **front** of the exported PNG, not just on a menu.
Then you can write on the back yourself, and the game shows you a live preview
of exactly what will be exported.

The postcard is graded four ways depending on how far you got: **初旅 /
探索者 / 朝圣者 / 大师** (First Journey / Explorer / Pilgrim / Master).

If you would rather stop early, the pause panel has **"finish this run"** — it
is hidden until you hold at least one fragment, because an empty card has
nothing to say.

---

## How long it takes

One full run to the postcard is **roughly 20–30 minutes**, and that is an
estimate built from the real constants, not a measured average:

- **Riding** — three laps of a 1,228.8 m loop (the five fragment stations are
  spread so that one lap passes all five). At the 15 m/s top speed that is
  ~4 minutes of pure pedalling; a real player spends considerably more.
- **Check-ins** — 15 of them. Each has a fixed 1.0 s camera move + 1.5 s hold
  + 0.4 s tail = **~3 s of scripted beats** each, before the minigame.
- **Minigames** — 15 of them, from 3 s (tea) to ~9 s (bamboo) plus your own
  reaction time.
- **Story** — 5 first-visit dialogues and 3 antagonist scenes.

Riding one lap and collecting the five fragments once is about **8–10 minutes**,
and the game will let you stop there via the pause panel.

---

## Play

| Platform | Controls |
| :--- | :--- |
| Desktop | `W` `A` `S` `D` to ride, `Space` to check in / advance dialogue |
| Touch | Left virtual joystick to ride; on-screen check-in button |
| Pause | `Esc` or the top-right pause button |
| Mute | The top-right sound buttons |
| Cancel a minigame | `Esc` |

---

## Build

- **Engine:** Godot 4.6.2, Forward+
- **Export targets:** Web (primary), Windows desktop, Android/touch
- **Zero texture assets** — road, terrain, and grass are all procedural
  shaders, which is what lets the Web build stay small
- **Road geometry:** a figure-8 lemniscate sampled analytically in code; no
  external map, GPS trace, or real-road data is used
- **Vegetation:** instanced `MultiMesh` scatter in concentric streaming rings,
  with deterministic per-cell placement
- **Stations:** hand-made GLB landmarks, tinted at runtime
- **Audio:** procedurally synthesized ambience and minigame SFX (no sample
  files); separate BGM / SFX mute
- **Language:** Chinese and English UI, switchable
- **Font:** open-source LXGW WenKai, subset to the characters actually used
- **Progress:** autosaved locally after every check-in

---

## Honest scope notes

**Shipped:** full loop, three-visit progression, 15 rotating minigames, PNG
export of both postcard faces, ambient + SFX audio, local save, language
switching, mobile joystick, mobile check-in, day/night cycle that shifts on the
third lap, Web and Windows export presets.

**Not in this build:** the planned roadside easter eggs, any per-station music
variation, and a formal visual asset board. The antagonist exists but has one
arc, not a branching one.

---

## Legal / naming note

The game uses no real official station names, and the route is a mathematical
figure-8 pattern that does not reproduce any real road. Public cultural motifs
are freely usable and are the thematic basis of the work, including Dongpo's
sixteen joys and the idea of a scenic cycling journey.

Use wording like:

- fictional narrative demo
- invented route geometry
- public-domain poetry (Su Dongpo, 1037–1101)
- tribute to public cultural motifs

Avoid wording like:

- inspired by / based on a real road
- artistic rearrangement of real route data
- official partnership
- official authorization
- real scenic-area reproduction
- official station brand
- official route recreation

---

*Tripothon S1 · `#Tripothon` · @TripoAI*
