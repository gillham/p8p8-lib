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
- `gametank_input.p8`, `gametank_banking.p8` and `gametank_draw.p8` are
  Prog8 versions of the SDK's `src/gt/input.c`, `src/gt/banking.c` and
  `src/gt/gfx/draw_direct.c` (with their headers).
- `gametank_sprites.p8` is a Prog8 version of the SDK's
  `src/gt/gfx/sprites.c`.
- `gametank_drawqueue.p8` is a Prog8 version of the SDK's
  `src/gt/gfx/draw_queue.c` and `draw_util.s`.
- `gametank_text.p8` and `gametank_random.p8` are Prog8 versions of the
  SDK's `src/gt/feature/text/text.c` and `src/gt/feature/random/random.c`;
  the paddle routines in `gametank_input.p8` are one of
  `src/gt/feature/paddleInput/paddleInput.c`.
- `gametank_persist.p8` is a Prog8 version of the SDK's
  `src/gt/feature/persist/persist.c`.
- `gametank_midi_fm.p8` is a Prog8 version of the SDK's
  `src/gt/audio/backends/legacy_midi_fm/` (`music.c`, `instruments.c`,
  `note_numbers.h`), and `gametank_util.p8` one of small things of
  `src/gt/gametank.h` and `src/gt/wait.s`.
- `jingle.gtm2` is the SDK's `assets/sdk_default/jingle.mid`, as the SDK's
  asset import converts it (taken from a ROM that the SDK built).
- `bios8.gtg.deflate` is the SDK's font, `assets/sdk_default/bios8.bmp`,
  as the SDK's asset import converts it (taken from a ROM that the SDK
  built).

The firmware was included here with the author's permission (given
2026-11-13), when the SDK had no license yet.  The SDK is now under the
MIT license (its `LICENCE` file, Copyright (c) 2023 Clyde Shaffer), and
that is the license of what is listed above.

# What comes from zlib6502

`zlib6502_inflate.asm` is `inflate.asx` of zlib6502 by Piotr Fusik
(<https://github.com/pfusik/zlib6502>).  It is an altered version: it was
converted from xasm to 64tass syntax, and it says so itself.  `zlib.p8`,
which includes it, is part of this library.  zlib6502 is under the zlib
license:

    Copyright (C) 2000-2017 Piotr Fusik

    This software is provided 'as-is', without any express or implied
    warranty.  In no event will the authors be held liable for any damages
    arising from the use of this software.

    Permission is granted to anyone to use this software for any purpose,
    including commercial applications, and to alter it and redistribute it
    freely, subject to the following restrictions:

    1. The origin of this software must not be misrepresented; you must not
       claim that you wrote the original software. If you use this software
       in a product, an acknowledgment in the product documentation would be
       appreciated but is not required.

    2. Altered source versions must be plainly marked as such, and must not be
       misrepresented as being the original software.

    3. This notice may not be removed or altered from any source distribution.

Everything else in this directory, the fonts included, is part of this
library and under its license.
