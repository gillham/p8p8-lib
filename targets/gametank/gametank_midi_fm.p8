; The older music player of the GameTank SDK: songs converted from MIDI files.
;
; MOST PROGRAMS SHOULD NOT USE THIS MODULE, but the tracker player that is in
; gametank_music.p8 (gametank.play_song and so on): it is the one that the
; GameTank SDK uses now, and the one that gametank.sdk_init() plays its jingle
; with.  This one is for a program converted from C that has songs in the
; older format (.gtm2, what the SDK's midiconvert makes of a MIDI file).
;
; Prog8 version of the GameTank SDK's src/gt/audio/backends/legacy_midi_fm
; (music.c, instruments.c, note_numbers.h), with the names of the C SDK.  In C
; this player and the tracker player have the same names, and a program has one
; of them; here this one is in its own block, midi_fm, and a program can have
; both.  They use the same 4 channels: play with one at a time.
;
;   midi_fm.init_music()                        ; after gametank.init_audio_coprocessor()
;   midi_fm.play_song(&mysong, bank, midi_fm.REPEAT_LOOP)
;   ...
;   midi_fm.tick_music()                        ; once per frame
;
; A song: a byte of flags (1: every note has a velocity byte), the numbers of
; the instruments of the 4 channels (0: percussion), the first delay, and then
; for each event: a mask of channels, for each of them a note (0: note off) and
; with flag 1 a velocity, and the delay in frames to the next event (0: the end).
;
; An instrument is 18 bytes: for each of the 4 operators the first amplitude,
; the decay, the sustain and the transposition, then the feedback, and the
; transposition of the channel (signed).  get_instrument_ptr() has the 7 of the
; SDK; load_instrument() takes any, in ram or in the fixed bank.
;
; Different from C:
;   - A sound effect is a number in C, from a table that the SDK's asset import
;     generates.  Here a program fills that table: set_sound_effect().  The
;     notes of a percussion channel play these too: note n is effect n-1.
;   - A song that is taken up again (REPEAT_RESUME, unpause_music) gets the
;     instruments of all 4 channels back.  In C all four go to channel 0.

%import gametank
%import gametank_audio
%import gametank_banking

midi_fm {
    const ubyte REPEAT_NONE = 0
    const ubyte REPEAT_LOOP = 1
    const ubyte REPEAT_RESUME = 2

    ; the instruments of the SDK, for get_instrument_ptr()
    const ubyte INSTR_IDX_PIANO = 1
    const ubyte INSTR_IDX_GUITAR = 2
    const ubyte INSTR_IDX_DISTGUITAR = 3
    const ubyte INSTR_IDX_SLAPBASS = 4
    const ubyte INSTR_IDX_SNARE = 5
    const ubyte INSTR_IDX_SITAR = 6
    const ubyte INSTR_IDX_HORN = 7

    const uword INSTR_PERCUSSION = $ffff    ; not an instrument: the channel plays sound effects
    const ubyte INSTR_SIZE = 18
    const ubyte INSTR_ENV_INITIAL = 0       ; 4 bytes each
    const ubyte INSTR_ENV_DECAY = 4
    const ubyte INSTR_ENV_SUSTAIN = 8
    const ubyte INSTR_OP_TRANSPOSE = 12
    const ubyte INSTR_FEEDBACK = 16
    const ubyte INSTR_TRANSPOSE = 17

    ; note numbers (note_numbers.h): 12 for each octave, Cn1 = 24 to Bn7 = 107
    const ubyte RST = 0                     ; a rest: note off
    const ubyte NUP = 128
    const ubyte Cn1 = 24
    const ubyte Cn2 = 36
    const ubyte Cn3 = 48
    const ubyte Cn4 = 60
    const ubyte Cn5 = 72
    const ubyte Cn6 = 84
    const ubyte Cn7 = 96

    const ubyte MUSIC_STACK_SIZE = 8
    const ubyte MUSIC_CFG_VELOCITY = 1
    const ubyte MUSIC_CFG_PROGCHANGE = 2
    const ubyte MUSIC_FLAG_POP_AT_END = 1
    const ubyte SFX_TABLE_SIZE = 32

    ubyte[] instrument_data = [
        ; piano
        $30, $40, $40, $5f,   $04, $02, $10, $02,   $04, $02, $10, $30,   0, 0, 0, 0,     0, 0,
        ; guitar
        $6f, $40, $68, $5f,   $00, $ff, $02, $08,   $00, $00, $40, $08,   12, 36, 0, 24,  8, 256-12,
        ; guitar2 (distorted)
        $60, $40, $88, $4f,   $00, $ff, $02, $01,   $00, $00, $40, $30,   12, 36, 0, 24,  8, 256-12,
        ; slapbass
        $58, $88, $58, $5f,   $18, $08, $04, $02,   $18, $08, $04, $02,   28, 12, 0, 12,  0, 256-24,
        ; snare
        $88, $8f, $8f, $38,   $18, $02, $04, $04,   $18, $08, $08, $04,   36, 0, 0, 0,    8, 256-8,
        ; sitar
        $60, $40, $01, $10,   $00, $ff, $f8, $ff,   $00, $60, $60, $30,   12, 36, 12, 24, 4, 256-24,
        ; horn
        $00, $00, $01, $10,   $00, $00, $fc, $fc,   $00, $00, $30, $50,   12, 36, 12, 24, 0, 256-12]

    ubyte[] op_transpose_start = [0, 0, 0, 0, 28, 12, 0, 19, 36, 0, 0, 0, 0, 0, 0, 0]
    ubyte[] channel_masks = [1, 2, 4, 8]

    ; the song that plays (music_state in C)
    uword music_cursor              ; 0: none
    ubyte music_bank
    ubyte music_cfg
    ubyte music_delay
    uword music_repeat_ptr
    ubyte music_flags
    uword[gametank.NUM_FM_CHANNELS] music_instruments

    ; the songs that wait (music_stack in C)
    uword[MUSIC_STACK_SIZE] stack_cursor
    ubyte[MUSIC_STACK_SIZE] stack_bank
    ubyte[MUSIC_STACK_SIZE] stack_cfg
    ubyte[MUSIC_STACK_SIZE] stack_delay
    uword[MUSIC_STACK_SIZE] stack_repeat_ptr
    ubyte[MUSIC_STACK_SIZE] stack_flags
    uword[MUSIC_STACK_SIZE * gametank.NUM_FM_CHANNELS] stack_instruments
    ubyte music_stack_idx

    ubyte[gametank.NUM_FM_CHANNELS] channel_note_offset
    ubyte[gametank.NUM_FM_OPS] audio_amplitudes
    ubyte[gametank.NUM_FM_OPS] env_initial
    ubyte[gametank.NUM_FM_OPS] env_decay
    ubyte[gametank.NUM_FM_OPS] env_sustain
    ubyte[gametank.NUM_FM_OPS] op_transpose

    ubyte music_mode
    ubyte music_channel_mask
    ubyte percussion_channel_mask
    ubyte note_held_mask
    uword[gametank.NUM_FM_CHANNELS] sound_effect_ptr
    ubyte[gametank.NUM_FM_CHANNELS] sound_effect_bank
    ubyte[gametank.NUM_FM_CHANNELS] sound_effect_length
    ubyte[gametank.NUM_FM_CHANNELS] saved_feedback_value
    ubyte[gametank.NUM_FM_CHANNELS] sound_effect_priority

    ; the sound effects, by number (the asset index of the C SDK)
    uword[SFX_TABLE_SIZE] sfx_ptr_table
    ubyte[SFX_TABLE_SIZE] sfx_bank_table

    sub init_music() {
        ubyte i
        music_stack_idx = 0
        music_cursor = 0
        music_delay = 0
        music_channel_mask = 255
        note_held_mask = 0
        for i in 0 to gametank.NUM_FM_CHANNELS-1 {
            sound_effect_length[i] = 0
            sound_effect_priority[i] = 0
            channel_note_offset[i] = 0
        }
        for i in 0 to gametank.NUM_FM_OPS-1 {
            env_initial[i] = 0
            env_decay[i] = 0
            env_sustain[i] = 0
            op_transpose[i] = op_transpose_start[i]
        }
        stop_music()
    }

    ; the address of one of the SDK's instruments (an INSTR_IDX_ constant);
    ; 0 gives INSTR_PERCUSSION
    sub get_instrument_ptr(ubyte idx) -> uword {
        if idx == 0 or idx > INSTR_IDX_HORN
            return INSTR_PERCUSSION
        return &instrument_data + (idx - 1) * (INSTR_SIZE as uword)
    }

    ; Say which sound effect a number is: its address and its ROM bank.
    sub set_sound_effect(ubyte sfx_id, uword sfx, ubyte bank_num) {
        if sfx_id < SFX_TABLE_SIZE {
            sfx_ptr_table[sfx_id] = sfx
            sfx_bank_table[sfx_id] = bank_num
        }
    }

    sub push_song_stack() {
        ubyte i
        ubyte base = music_stack_idx * gametank.NUM_FM_CHANNELS
        stack_cursor[music_stack_idx] = music_cursor
        stack_bank[music_stack_idx] = music_bank
        stack_cfg[music_stack_idx] = music_cfg
        stack_delay[music_stack_idx] = music_delay
        stack_repeat_ptr[music_stack_idx] = music_repeat_ptr
        stack_flags[music_stack_idx] = music_flags
        for i in 0 to gametank.NUM_FM_CHANNELS-1
            stack_instruments[base + i] = music_instruments[i]
        music_stack_idx++
        if music_stack_idx == MUSIC_STACK_SIZE
            music_stack_idx = 0
    }

    sub pop_song_stack() {
        ubyte i
        ubyte base
        if music_stack_idx == 0
            music_stack_idx = MUSIC_STACK_SIZE-1
        else
            music_stack_idx--
        base = music_stack_idx * gametank.NUM_FM_CHANNELS
        music_cursor = stack_cursor[music_stack_idx]
        music_bank = stack_bank[music_stack_idx]
        music_cfg = stack_cfg[music_stack_idx]
        music_delay = stack_delay[music_stack_idx]
        music_repeat_ptr = stack_repeat_ptr[music_stack_idx]
        music_flags = stack_flags[music_stack_idx]
        for i in 0 to gametank.NUM_FM_CHANNELS-1 {
            music_instruments[i] = stack_instruments[base + i]
            if music_instruments[i] != 0
                load_instrument(i, music_instruments[i])
        }
    }

    ; Give a channel (0-3) an instrument: the address of its 18 bytes, in ram
    ; or in the fixed bank.  INSTR_PERCUSSION: the channel plays sound effects.
    sub load_instrument(ubyte channel, uword instr) {
        ubyte op
        ubyte i
        if instr == INSTR_PERCUSSION {
            percussion_channel_mask |= channel_masks[channel]
            return
        }
        percussion_channel_mask &= ~channel_masks[channel]
        music_instruments[channel] = instr
        channel_note_offset[channel] = instr[INSTR_TRANSPOSE]
        gametank.aram[gametank.FEEDBACK_AMT + channel] = (instr[INSTR_FEEDBACK] << 3) + 128
        op = channel << 2
        for i in 0 to gametank.OPS_PER_CHANNEL-1 {
            env_initial[op] = instr[INSTR_ENV_INITIAL + i]
            env_decay[op] = instr[INSTR_ENV_DECAY + i]
            env_sustain[op] = instr[INSTR_ENV_SUSTAIN + i]
            op_transpose[op] = instr[INSTR_OP_TRANSPOSE + i]
            op++
        }
    }

    ; Set the pitch of the 4 operators of a channel: op is the first of them
    ; (the channel * 4), n the note number.
    sub set_note(ubyte op, ubyte n) {
        ubyte n_mul
        repeat gametank.OPS_PER_CHANNEL {
            n_mul = op_transpose[op] + n
            n_mul += n_mul
            gametank.aram[gametank.PITCH_MSB + op] = gametank.pitch_table[n_mul]
            n_mul++
            gametank.aram[gametank.PITCH_LSB + op] = gametank.pitch_table[n_mul]
            op++
        }
    }

    ; Play a song: its address, its ROM bank (255 = the fixed bank), and a
    ; REPEAT_ constant.  REPEAT_RESUME: the song that plays now goes on
    ; afterwards.
    sub play_song(uword song, ubyte bank_num, ubyte loop) {
        ubyte n
        push_song_stack()
        music_bank = bank_num
        gametank.push_rom_bank()
        gametank.change_rom_bank(music_bank)
        music_cursor = song

        for n in 0 to gametank.NUM_FM_OPS-1 {
            audio_amplitudes[n] = 0
            gametank.aram[gametank.AMPLITUDE + n] = 128
        }

        when loop {
            REPEAT_NONE -> {
                music_repeat_ptr = 0
                music_mode = REPEAT_NONE
                music_flags = 0
            }
            REPEAT_LOOP -> {
                music_repeat_ptr = music_cursor
                music_mode = REPEAT_LOOP
                music_flags = 0
            }
            REPEAT_RESUME -> music_flags = MUSIC_FLAG_POP_AT_END
        }

        if music_cursor != 0 {
            percussion_channel_mask = 0
            music_cfg = next_byte()
            for n in 0 to gametank.NUM_FM_CHANNELS-1
                load_instrument(n, get_instrument_ptr(next_byte()))
            music_delay = next_byte()
        }

        gametank.pop_rom_bank()
    }

    ; the next byte of the song (its bank must be there)
    sub next_byte() -> ubyte {
        ubyte value = @(music_cursor)
        music_cursor++
        return value
    }

    sub pause_music() {
        push_song_stack()
        music_cursor = 0
        note_held_mask = 0
    }

    sub unpause_music() {
        pop_song_stack()
    }

    ; Call once per frame: the sound effects, the envelopes and the song.
    sub tick_music() {
        ubyte n
        ubyte noteMask
        ubyte ch
        ubyte op
        ubyte i
        ubyte note
        ubyte velocity
        uword @zp sfx

        gametank.push_rom_bank()
        for n in 0 to gametank.NUM_FM_CHANNELS-1 {
            if sound_effect_length[n] != 0 {
                sound_effect_length[n]--
                op = n << 2
                if sound_effect_length[n] != 0 {
                    gametank.change_rom_bank(sound_effect_bank[n])
                    sfx = sound_effect_ptr[n]
                    for i in 0 to gametank.OPS_PER_CHANNEL-1 {
                        gametank.aram[gametank.AMPLITUDE + op] = (sfx[i] << 3) + 128
                        note = sfx[i + 4] << 1
                        gametank.aram[gametank.PITCH_MSB + op] = gametank.pitch_table[note]
                        note++
                        gametank.aram[gametank.PITCH_LSB + op] = gametank.pitch_table[note]
                        op++
                    }
                    sound_effect_ptr[n] += 8
                } else {
                    gametank.aram[gametank.AMPLITUDE + op + 3] = 128
                    gametank.aram[gametank.FEEDBACK_AMT + n] = saved_feedback_value[n]
                    music_channel_mask |= channel_masks[n]
                    sound_effect_priority[n] = 0
                }
            }
        }

        gametank.change_rom_bank(music_bank)

        ; the envelopes of the channels that hold a note
        op = 0
        for ch in 0 to gametank.NUM_FM_CHANNELS-1 {
            if channel_masks[ch] & music_channel_mask & note_held_mask == 0 {
                op += 4
                continue
            }
            repeat gametank.OPS_PER_CHANNEL {
                if ((env_sustain[op] - audio_amplitudes[op]) ^ env_decay[op]) & $80 != 0
                    audio_amplitudes[op] -= env_decay[op]
                else
                    audio_amplitudes[op] = env_sustain[op]
                gametank.aram[gametank.AMPLITUDE + op] = (audio_amplitudes[op] >> 1) + 128
                op++
            }
        }

        if music_cursor != 0 {
            repeat {
                if music_delay > 0 {
                    music_delay--
                    break
                }
                noteMask = next_byte()
                for ch in 0 to gametank.NUM_FM_CHANNELS-1 {
                    if channel_masks[ch] & noteMask != 0 {
                        n = next_byte()
                        if music_cfg & MUSIC_CFG_VELOCITY != 0
                            velocity = next_byte()
                        if channel_masks[ch] & percussion_channel_mask != 0 {
                            if n > 0
                                play_sound_effect(n - 1, ch)
                        } else if channel_masks[ch] & music_channel_mask != 0 {
                            op = ch << 2
                            if n > 0 {
                                set_note(op, n + channel_note_offset[ch])
                                repeat 3 {
                                    audio_amplitudes[op] = env_initial[op]
                                    gametank.aram[gametank.AMPLITUDE + op] = (audio_amplitudes[op] >> 1) + 128
                                    op++
                                }
                                if music_cfg & MUSIC_CFG_VELOCITY != 0
                                    audio_amplitudes[op] = velocity
                                else
                                    audio_amplitudes[op] = env_initial[op]
                                gametank.aram[gametank.AMPLITUDE + op] = (audio_amplitudes[op] >> 1) + 128
                            } else {
                                op += 3
                                audio_amplitudes[op] = 0
                                gametank.aram[gametank.AMPLITUDE + op] = 128
                            }
                        }
                        if n != 0
                            note_held_mask |= channel_masks[ch]
                        else
                            note_held_mask &= ~channel_masks[ch]
                    }
                }
                music_delay = next_byte()
                if music_delay != 0 {
                    music_delay--
                    break
                }
                ; the end of the song
                if music_flags & MUSIC_FLAG_POP_AT_END != 0 {
                    pop_song_stack()
                    break
                }
                music_cursor = music_repeat_ptr
                if music_cursor == 0 {
                    silence_all_channels()
                    break
                }
                music_cursor += 5       ; over the flags and the instruments
                music_delay = next_byte()
            }
        }

        gametank.flush_audio_params()
        gametank.pop_rom_bank()
    }

    sub silence_all_channels() {
        ubyte n
        for n in 0 to gametank.NUM_FM_OPS-1 {
            audio_amplitudes[n] = 0
            gametank.aram[gametank.AMPLITUDE + n] = 128
        }
        note_held_mask = 0
    }

    sub stop_music() {
        music_cursor = 0
        silence_all_channels()
    }

    ; Play the sound effect with a number (set_sound_effect) on a channel
    ; (0-3).  A priority can be added to the channel, 16 for each step: an
    ; effect with a lower one than the effect that plays there is not played.
    ; A sound effect: its length in frames, the feedback, and for each frame 4
    ; amplitudes and 4 notes.
    sub play_sound_effect(ubyte sfx_id, ubyte channel) {
        ubyte priority = channel & $f0
        uword @zp sfx
        channel &= $03
        if sfx_id >= SFX_TABLE_SIZE or priority < sound_effect_priority[channel]
            return
        sound_effect_priority[channel] = priority
        gametank.push_rom_bank()
        sound_effect_bank[channel] = sfx_bank_table[sfx_id]
        sfx = sfx_ptr_table[sfx_id]
        gametank.change_rom_bank(sound_effect_bank[channel])
        sound_effect_length[channel] = sfx[0] + 1
        saved_feedback_value[channel] = gametank.aram[gametank.FEEDBACK_AMT + channel]
        gametank.aram[gametank.FEEDBACK_AMT + channel] = sfx[1]
        sound_effect_ptr[channel] = sfx + 2
        music_channel_mask &= ~channel_masks[channel]
        gametank.pop_rom_bank()
    }

    ; the SDK's jingle, in this player's format
    sub play_boot_jingle() {
        play_song(&jingle, 255, REPEAT_NONE)
    }

jingle:
    %asmbinary "jingle.gtm2"
}
