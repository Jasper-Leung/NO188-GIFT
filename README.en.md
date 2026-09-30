# 188号礼物 — Gift No.188

**Pack the landscape into your bag.**

A short, gentle 3D cycling journey built around Su Dongpo's "joys of the heart."
Ride an invented figure-8 loop, complete five fictional stations, and compose
them into a giftable postcard.

Built for **Tripothon S1**, the "world building" AI hackathon. Theme:
*A Gift for ______*. Ours: **A Gift for No.188**.

> This is a fictional narrative demo. The route is a purely mathematical
> figure-8 pattern that does not reference or reproduce any real road. Station
> names, and scene layout are artistically invented. It does not claim to
> represent any real tourism road, official station brand, or real scenic-area
> operation. The theme draws on public-domain poetry by Su Dongpo (1037–1101).

---

## What kind of game is this?

**An atmospheric / emotional journey with a collect-and-compose payoff.**
Not a puzzle game. Not a story game.

- **No puzzles.** The main action is: ride, stop near a station, check in.
- **No plot, no dialogue, no branching.** The narrative is thematic, not
  dramatic — five poetic joys, not a story with a beginning and an end.
- **No combat, no timer, no difficulty curve.** Deliberately gentle.

The closest reference is a short-form pilgrimage in the spirit of *Journey*:
the feeling comes from arriving, not from beating anything. One run is
5–8 minutes, with no failure state.

---

## The idea: "188" is three things at once

| "188" means | In the game |
| :--- | :--- |
| A **188 km** loop motif | the distance the player rides |
| A **figure-8** route built from a mathematical curve | the road geometry you ride |
| **No.188** | the gift's serial number and final postcard |

One number, three layers — the road becomes the gift, and the gift leaves with you.

Su Dongpo (苏东坡, 1037–1101) is one of the greatest poets in Chinese history.
His essay *Sixteen Joys of the Heart* (赏心十六乐事) lists the small pleasures
of a literati's life. This demo keeps five of those joys as public cultural
motifs, then expresses them through fictional stations and procedural 3D scenes.

---

## The five fictional stations

| # | Station | English name | The joy | Fragment |
| :-: | :--- | :--- | :--- | :-: |
| 1 | 云影台 | Cloudshadow Terrace | Rain stops; watch clouds and mountains soften | 云 **Cloud** |
| 2 | 茶烟小筑 | Tea Smoke Cottage | A guest arrives; draw water and brew tea | 茶 **Tea** |
| 3 | 琴音林 | Zither Grove | Listen to wind as if it were a zither | 琴 **Zither** |
| 4 | 竹雨庭 | Bamboo Rain Courtyard | Night rain talks through the bamboo window | 竹 **Bamboo** |
| 5 | 禽语湖湾 | Birdsong Cove | A bird answers the lake in its own language | 禽 **Bird** |

Eleven additional decorative markers are placed along the route for distance,
map detail, and pacing. They are not collection goals.

---

## Play

| Platform | Controls |
| :--- | :--- |
| Desktop | `W` `A` `S` `D` / arrows to ride, `Space` / `Enter` to check in |
| Touch | Left virtual joystick to ride; tap **Complete Joy** near a station |
| Pause | `Esc` or top-right pause button |
| Mute | `M` or top-right sound buttons |

All five fragment stations must be checked in. There is no way to fail, and
no timer.

---

## What you get out

Finish the five stations and the fragments fly together into a **procedurally
drawn 16:9 postcard** — cloud, tea, zither, bamboo, bird, and a `No.188`
road sign. Export it as a PNG and keep it, or copy the share text.
That exportable postcard is the second half of the loop: the game is the gift,
and the gift leaves with you.

---

## Build

- **Engine:** Godot 4.6.2, Forward+
- **Export targets:** Web first, Windows desktop backup, Android/touch fallback
- **Play anywhere:** `188号礼物.html` — no install, no account, opens in a browser
- **Road geometry:** a figure-8 lemniscate curve generated analytically in code;
  no external map, GPS trace, or real-road data is used
- **World:** 3D low-poly, procedurally generated terrain, roads, vegetation,
  station landmarks, and boundary warnings
- **Stations:** five GLB landmarks load near the player; eleven decorative markers
  complete the 8-route
- **Audio:** ambient wind / birdsong / water with 3D distance falloff;
  separate BGM / SFX mute controls
- **Language:** Chinese and English UI, persisted locally
- **Font:** open-source LXGW WenKai, subset to the characters actually used
- **Progress:** autosaved locally after every check-in

The Web export must be tested in a real browser before submission, especially
the PNG download path.

---

## Honest scope notes

Shipped: full loop, PNG export, ambient audio, save, language switching,
mobile joystick, mobile check-in button, landscape lock, Web export preset,
Windows export preset, and touch fallback.

Not in this build yet: the planned Boruo-candy roadside easter egg, full
multi-station Hakka song variations, and a formal visual asset board for judges.

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
