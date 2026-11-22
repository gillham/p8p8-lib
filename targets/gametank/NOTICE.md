# What comes from the GameTank SDK

These files are from the GameTank SDK by Clyde Shaffer
(<https://github.com/clydeshaffer/gametank_sdk>).  They are not part of
Prog8 or of p8p8.

- `audio_fw.bin.rle` is the audio firmware of the GameTank, built from the
  SDK's `src/gt/audio/sdk_default_fm.acp.asm`.
- `jingle.bin` is the SDK's boot jingle, `assets/sdk_default/jingle.bin`.
- `gametank_audio.p8` and `gametank_music.p8` are Prog8 versions of the
  SDK's C and assembly sources in `src/gt/audio/` (`audio_coprocessor.c`
  and the `tracker_fm` backend).

The firmware was included here with the author's permission (given
2026-11-13), when the SDK had no license yet.  The SDK is now under the
MIT license (its `LICENCE` file, Copyright (c) 2023 Clyde Shaffer), and
that is the license of what is listed above.

Everything else in this directory, the fonts included, is part of this
library and under its license.
