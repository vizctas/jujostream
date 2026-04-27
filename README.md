<p align="center">
  <img src="assets/images/app_icon.png" width="120" alt="JUJO Stream"/>
</p>

<h1 align="center">JUJO Stream</h1>

<p align="center">
  Game streaming client with a console feel for Android, Android TV, macOS, and more
</p>

<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/GET_IT_ON-Google_Play-34A853?style=for-the-badge&logo=google-play&logoColor=white" alt="Get it on Google Play"/></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/license-GPL--3.0-blue?style=flat-square" alt="License GPL-3.0"/>
  <img src="https://img.shields.io/badge/free-100%25-brightgreen?style=flat-square" alt="Free"/>
  <img src="https://img.shields.io/badge/built_with-Flutter-54C5F8?style=flat-square&logo=flutter&logoColor=white" alt="Flutter"/>
</p>

---

## What is JUJO Stream?

**IMPORTANT**
>Since multiple bugfixes and features are being implemented, these changes will hit the Play Store first. Alternatively, you can clone the repository and build your own APK if you prefer not to join the Play Store beta.


JUJO Stream is a game streaming client that gives your library a proper console feel. Connect it to a Sunshine, Apollo any sunshine server running on your PC, and you can browse and launch games from your phone, TV, or desktop  entirely with a gamepad if you want.

---

## Platforms

<p align="center">
  <img src="https://img.shields.io/badge/Android-Stable-4CAF50?style=flat-square&logo=android&logoColor=white" alt="Android"/>
  <img src="https://img.shields.io/badge/macOS-Stable-4CAF50?style=flat-square&logo=apple&logoColor=white" alt="macOS"/>
  <img src="https://img.shields.io/badge/Android_TV-Stable-4CAF50?style=flat-square&logo=androidtv&logoColor=white" alt="Android TV"/>
  <img src="https://img.shields.io/badge/Windows-Unstable-FFC107?style=flat-square&logo=windows&logoColor=white" alt="Windows"/>
  <img src="https://img.shields.io/badge/Linux-Pending-9E9E9E?style=flat-square&logo=linux&logoColor=white" alt="Linux"/>
</p>

**\* Android TV**  Works well on most devices, but TV hardware varies a lot. Low-end sticks and boxes can hit performance limits, so your mileage may vary. More testing across different devices is still in progress.

**macOS**  Tested with keyboard and mouse with good stability. Gamepad testing is limited due to hardware constraints on my end.

---

## Compatible Servers

JUJO Stream connects to any of these streaming backends:

- [**Sunshine**](https://github.com/LizardByte/Sunshine)  open source, actively maintained, recommended
- [**Apollo / VibeApollo/ Any sunshine server**](https://github.com/ClassicOldSong/Apollo)  Sunshine fork with Playnite integration built in

For game library detection: [Playnite](https://playnite.link/) with the Playnite App Export plugin works well alongside Apollo.

---

## Features

Everything is free. No purchases, no tiers, no subscriptions. GPL v3.0 Licence.

### Focus Mode

A dedicated screen built for a calmer, more focused streaming experience. Each server can have its own background image and ambient audio  it strips away the noise and gives you a quiet space to settle into before a session. Think of it as the difference between a busy dashboard and a clean TV interface.

It's not the main screen. You have to activated it, by going to app options (three dots at top bar). Once you activate it, you will be redirect to this screen everytime you open the app. (Can disabled it to return to classic view).

 <img src="https://github.com/vizctas/jujostream/blob/feature/r1/assets/ss/focus_mode.jpg"  alt="filters common"/>

 More interesting functions and personalization will be added in future updates.

### Launcher Styles

Four launcher layouts to choose from: **Classic**, **Backbone**, **Hero**, and **PS5-style**. Each one changes the layout, card style, and overall feel of the main library screen. Pick what fits your setup.

 <img src="https://github.com/vizctas/jujostream/blob/feature/r1/assets/ss/ps5_theme.jpg"  alt="PS5 theme"/>

### *Disclaimer for Android TV* 

The design is very heavy for android tv. Tried to do my best and with the support with claude + gemini tried to reduce as many lag issues with the navigation. This doesn't happens with powerful android devices or MAC OS. 

First boot will probably cause problem with the streaming. Give around 1 minute depending your internet connection, to fully load all posters, metadata and more. 

### Color Schemes

5+ Color schemes tailored for the launcher best fit. You'll make me happy if you choose to use "Debossy", "ShioryPan" or "Lazy Ankui". Based on my cats colors. 

 <img src="https://github.com/vizctas/jujostream/blob/feature/r1/assets/ss/color_schemes.jpg"  alt="colours"/>

### Session Metrics

After each session you get a summary of how the stream performed: frame data, bitrate, latency, and decoder info. Handy for fine-tuning your setup over time.

 <img src="https://github.com/vizctas/jujostream/blob/feature/r1/assets/ss/metrics_card.jpg"  alt="Metrics card"/>

### Custom Combos

Map button combinations of most used shorcuts while streaming. Some client limits you to just SELECT + START + R1 + R2 to call menu. Now you can configure that and the hold time. 

 <img src="https://github.com/vizctas/jujostream/blob/feature/r1/assets/ss/cfg_combos.jpg"  alt="combos cfg"/>

### Everything Else

- Full gamepad navigation across every screen  built from the ground up for TV and mobile
- Live Steam trailers as backgrounds while you browse
- Game metadata from Steam and RAWG (descriptions, ratings, posters)
- Per-game stream profiles with custom bitrate, FPS, and codec
- Screensaver with Ken Burns effect using your game art
- Collections and smart filters
- PiP mode to minimize the stream into a floating window
- *Companion app via QR code for remote configuration*

 Some more features:

 <img src="https://github.com/vizctas/jujostream/blob/feature/r1/assets/ss/ragio_autofilters.jpg"  alt="auto filters"/>

 Need fix - No EN Location added yet. 

 <img src="https://github.com/vizctas/jujostream/blob/feature/r1/assets/ss/common_filters.jpg"  alt="common filters"/>

---

## License

Licensed under the **GNU General Public License v3.0**.

You can use it, modify it, fork it, and redistribute it  as long as the same license applies. See [LICENCE.md](LICENCE.md).

JUJO Stream is a fork of [Artemis](https://github.com/ClassicOldSong/moonlight-android) by ClassicOldSong, which is itself based on [Moonlight Android](https://github.com/moonlight-stream/moonlight-android) by the moonlight-stream team. Both upstream projects are GPL-3.0.

---

## Credits

| Project | Author |
|---|---|
| [Artemis](https://github.com/ClassicOldSong/moonlight-android) | ClassicOldSong |
| [Moonlight Android](https://github.com/moonlight-stream/moonlight-android) | moonlight-stream |

---

## Build from Source

```bash
git clone https://github.com/vizctas/jujo.stream.client.git
cd jujo.stream.client
flutter pub get
flutter run
```

Requires Flutter SDK.

---

## Bugs

The project has bugs, and some will show up over time. I'm working through them and pushing updates to the Play Store as they get fixed. macOS updates will be published as GitHub releases.

If you run into something, [open an issue](https://github.com/vizctas/jujo.stream.client/issues) with:
- What happened vs. what you expected
- Device model and OS version

**Forks are welcome.** If you want to fix something or add a feature, go for it  that's the point of the GPL license. I'm doing this solo, but my goal is to keep the repo reasonably active.

**iPhone** is not in the plans right now. I don't own an iOS device, which makes real testing impossible, and App Store distribution adds constraints I haven't taken on. Maybe in the future, but no promises.

---

## Keep JUJO Alive

If the app has been useful and you want to show some support, there's a Ko-fi page.

Full disclosure: contributions here go toward my future wedding.🙌 Hope happens this year.

<p align="center">
  <a href="https://ko-fi.com/jujodev">
    <img src="https://ko-fi.com/img/githubbutton_sm.svg" alt="Support on Ko-fi"/>
  </a>
</p>


---

## Future 

If everything goes well, and I have time and incentivation to keep the work alive, I will continue bringing to more platforms, 

fixing bugs and introduce more features. I'm limited now with my time, and future weeding. I will do my best. 

