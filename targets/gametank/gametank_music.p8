; GameTank music and sound effects: the SDK's "tracker FM" player.
;
; Prog8 version of the GameTank SDK's src/gt/audio/backends/tracker_fm (music.c and
; tracker.s).  The names are those of the C SDK as much as possible.
;
;   init_music()                        once, after init_audio_coprocessor()
;   play_song(song, bank, repeat)       start a song (the data the SDK's tracker writes)
;   tick_music()                        once every frame
;   stop_music()  pause_music()  unpause_music()
;   play_sound_effect(sfx, bank, channel)
;
; What is different from the C SDK:
; - A song or sound effect is given as its address and the cartridge bank it is in.
;   The C SDK makes that pair with its ASSET__ macros and looks sound effects up in a
;   table by number; here there is no such table.  Data in the fixed bank ($c000 and
;   up) can be given bank 255.
; - The program is in ROM, so the envelopes are read through pointers in ram and not
;   by code that changes itself.
; - The song that was playing is kept on a stack (REPEAT_RESUME, pause_music), as in
;   C.  When there is nothing to go back to the music stops.

%import gametank
%import gametank_audio

gametank {
%option merge

    ; ---- play_song: what happens when the song ends ----
    const ubyte REPEAT_NONE     = 0         ; the music stops
    const ubyte REPEAT_LOOP     = 1         ; the song starts again
    const ubyte REPEAT_RESUME   = 2         ; the song that played before goes on

    const ubyte MUSIC_STACK_SIZE        = 8

    const ubyte MUSIC_FLAG_POP_AT_END   = 1
    const ubyte MUSIC_FLAG_REPEAT       = 2
    const ubyte MUSIC_FLAG_STOPPED      = 4

    ; ---- the song data (track_header_t in C); addresses in it count from its start ----
    ;   0     format version
    ;   1     step_frames: frames for one step
    ;   2     pattern_length: steps in one pattern
    ;   3-6   reserved
    ;   7-14  4 addresses of the channels' data (channel_header_t):
    ;             0   number of patterns
    ;             1   sequence length
    ;             2   address of the sequence: a pattern number for every position
    ;             4.. address of every pattern: 2 bytes a step, the note (255 = none)
    ;                 and the instrument
    ;   15    number of instruments
    ;   16..  address of every instrument (instrument_header_t):
    ;             0-3 transpose of the 4 operators
    ;             4.. 4 addresses of the operators' envelopes: 17 bytes, 1-16 are used
    const ubyte TRACK_STEP_FRAMES       = 1
    const ubyte TRACK_PATTERN_LENGTH    = 2
    const ubyte TRACK_CHANNEL_DATAS     = 7
    const ubyte TRACK_INSTRUMENTS       = 16

    ; ---- the song that plays (music_state in C) ----
    uword music_song_base
    ubyte music_bank
    ubyte music_delay
    ubyte music_flags
    ubyte[NUM_FM_CHANNELS] music_instruments_idx
    ubyte music_sequence_idx
    ubyte music_step_idx

    ; ---- the songs that played before it (music_stack in C) ----
    uword[MUSIC_STACK_SIZE] music_stack_song_base
    ubyte[MUSIC_STACK_SIZE] music_stack_bank
    ubyte[MUSIC_STACK_SIZE] music_stack_delay
    ubyte[MUSIC_STACK_SIZE] music_stack_flags
    ubyte[MUSIC_STACK_SIZE * NUM_FM_CHANNELS] music_stack_instruments_idx
    ubyte[MUSIC_STACK_SIZE] music_stack_sequence_idx
    ubyte[MUSIC_STACK_SIZE] music_stack_step_idx
    ubyte music_stack_idx

    ; ---- taken from the song's header ----
    ubyte track_step_frames
    ubyte track_pattern_length
    uword[NUM_FM_CHANNELS] track_channel_datas
    uword[NUM_FM_CHANNELS] channelSequences
    ubyte sequenceLength

    ubyte[NUM_FM_CHANNELS] channelStates            ; step in the envelope (1-16), 255 = none
    ubyte[NUM_FM_CHANNELS] channelCurrentPattern
    ubyte[NUM_FM_CHANNELS] last_note
    uword[NUM_FM_OPS] music_env_ptrs                ; the envelope of every operator
    ubyte[NUM_FM_OPS] op_transpose

    ubyte[] channel_masks = [1, 2, 4, 8]
    ubyte music_channel_mask                        ; bit of a channel clear: a sound effect has it
    ubyte note_held_mask

    ; ---- sound effects ----
    uword[NUM_FM_CHANNELS] sound_effect_ptr
    ubyte[NUM_FM_CHANNELS] sound_effect_bank
    ubyte[NUM_FM_CHANNELS] sound_effect_length
    ubyte[NUM_FM_CHANNELS] saved_feedback_value
    ubyte[NUM_FM_CHANNELS] sound_effect_priority

    ; the cartridge bank of the main program, to put it back with rombank()
    inline asmsub music_getbank() -> ubyte @A {
        %asm {{
            lda  cartbank.p8s_cartbank_value
        }}
    }

    sub init_music() {
        ubyte i
        music_stack_idx = 0
        music_song_base = 0
        music_delay = 0
        music_channel_mask = 255
        note_held_mask = 0
        for i in 0 to NUM_FM_CHANNELS-1 {
            sound_effect_length[i] = 0
            sound_effect_priority[i] = 0
        }
        for i in 0 to NUM_FM_OPS-1 {
            op_transpose[i] = 0
        }
        op_transpose[4] = 28
        op_transpose[5] = 12
        op_transpose[7] = 19
        op_transpose[8] = 36
        stop_music()
    }

    sub push_song_stack() {
        ubyte i
        ubyte slot = music_stack_idx << 2
        music_stack_song_base[music_stack_idx] = music_song_base
        music_stack_bank[music_stack_idx] = music_bank
        music_stack_delay[music_stack_idx] = music_delay
        music_stack_flags[music_stack_idx] = music_flags
        music_stack_sequence_idx[music_stack_idx] = music_sequence_idx
        music_stack_step_idx[music_stack_idx] = music_step_idx
        for i in 0 to NUM_FM_CHANNELS-1 {
            music_stack_instruments_idx[slot] = music_instruments_idx[i]
            slot++
        }
        music_stack_idx++
        if music_stack_idx == MUSIC_STACK_SIZE
            music_stack_idx = 0
    }

    ; go on with the song that played before.  The cartridge bank is that song's after
    ; this, when there is one.
    sub pop_song_stack() {
        ubyte i
        ubyte slot
        if music_stack_idx == 0
            music_stack_idx = MUSIC_STACK_SIZE-1
        else
            music_stack_idx--
        music_song_base = music_stack_song_base[music_stack_idx]
        music_bank = music_stack_bank[music_stack_idx]
        music_delay = music_stack_delay[music_stack_idx]
        music_flags = music_stack_flags[music_stack_idx]
        music_sequence_idx = music_stack_sequence_idx[music_stack_idx]
        music_step_idx = music_stack_step_idx[music_stack_idx]
        slot = music_stack_idx << 2
        for i in 0 to NUM_FM_CHANNELS-1 {
            music_instruments_idx[i] = music_stack_instruments_idx[slot]
            slot++
        }

        music_reset_channels()
        if music_song_base == 0 {
            ; no song played before
            music_flags |= MUSIC_FLAG_STOPPED
            return
        }
        rombank(music_bank)
        music_load_header()
        init_song_data()
    }

    ; no notes, all operators silent
    sub music_reset_channels() {
        ubyte i
        for i in 0 to NUM_FM_CHANNELS-1 {
            last_note[i] = 0
            channelStates[i] = 255
        }
        for i in 0 to NUM_FM_OPS-1 {
            aram[AMPLITUDE + i] = 128
        }
    }

    ; (the song's bank must be the cartridge bank)
    sub music_load_header() {
        track_step_frames = @(music_song_base + TRACK_STEP_FRAMES)
        track_pattern_length = @(music_song_base + TRACK_PATTERN_LENGTH)
    }

    ; give a channel another instrument of the song (the song's bank must be the cartridge bank)
    sub load_instrument(ubyte channel, ubyte instrumentIdx) {
        ubyte i
        ubyte op = channel << 2
        uword instrument = music_song_base + TRACK_INSTRUMENTS + (instrumentIdx as uword) * 2
        instrument = music_song_base + peekw(instrument)
        music_instruments_idx[channel] = instrumentIdx
        for i in 0 to OPS_PER_CHANNEL-1 {
            op_transpose[op] = @(instrument + i)
            music_env_ptrs[op] = music_song_base + peekw(instrument + 4 + i * 2)
            op++
        }
    }

    ; the pitch of a channel's 4 operators, for note number n
    sub set_note(ubyte ch, ubyte n) {
        ubyte op = ch << 2
        ubyte n_mul
        repeat OPS_PER_CHANNEL {
            n_mul = (op_transpose[op] + n) << 1
            aram[PITCH_MSB + op] = pitch_table[n_mul]
            aram[PITCH_LSB + op] = pitch_table[n_mul + 1]
            op++
        }
    }

    ; (the song's bank must be the cartridge bank)
    sub init_song_data() {
        ubyte n
        for n in 0 to NUM_FM_CHANNELS-1 {
            track_channel_datas[n] = music_song_base + peekw(music_song_base + TRACK_CHANNEL_DATAS + n * 2)
            channelSequences[n] = music_song_base + peekw(track_channel_datas[n] + 2)
            channelCurrentPattern[n] = @(channelSequences[n] + music_sequence_idx)
            load_instrument(n, music_instruments_idx[n])
        }
        sequenceLength = @(track_channel_datas[0] + 1)
    }

    ; start the notes of the current step; their envelopes begin at envelope_start
    sub music_play_step(ubyte envelope_start) {
        ubyte n
        ubyte evt
        ubyte ins
        uword step
        for n in 0 to NUM_FM_CHANNELS-1 {
            step = track_channel_datas[n] + 4 + (channelCurrentPattern[n] as uword) * 2
            step = music_song_base + peekw(step) + (music_step_idx as uword) * 2
            evt = @(step)
            ins = @(step + 1)
            if evt != 255 {
                if ins != music_instruments_idx[n]
                    load_instrument(n, ins)
                last_note[n] = evt
                if (music_channel_mask & channel_masks[n]) != 0
                    set_note(n, evt)
                channelStates[n] = envelope_start
            }
        }
    }

    ; the amplitudes of the operators, from their envelopes (fetchEnvelopes in tracker.s)
    sub fetchEnvelopes() {
        ubyte ch
        ubyte op
        ubyte state
        for ch in 0 to NUM_FM_CHANNELS-1 {
            state = channelStates[ch]
            if state < 128 and (music_channel_mask & channel_masks[ch]) != 0 {
                op = ch << 2
                repeat OPS_PER_CHANNEL {
                    aram[AMPLITUDE + op] = @(music_env_ptrs[op] + state)
                    op++
                }
            }
        }
    }

    ; start a song.  loop is REPEAT_NONE, REPEAT_LOOP or REPEAT_RESUME.
    sub play_song(uword song, ubyte bank_num, ubyte loop) {
        ubyte oldbank = music_getbank()
        push_song_stack()
        music_bank = bank_num
        rombank(music_bank)
        music_song_base = song
        music_load_header()
        music_sequence_idx = 0
        music_delay = track_step_frames
        music_step_idx = 0
        music_reset_channels()

        when loop {
            REPEAT_LOOP -> music_flags = MUSIC_FLAG_REPEAT
            REPEAT_RESUME -> music_flags = MUSIC_FLAG_POP_AT_END
            else -> music_flags = 0
        }

        init_song_data()
        music_play_step(1)
        fetchEnvelopes()
        rombank(oldbank)
    }

    ; keep the song for unpause_music().  (As in C it plays on until stop_music()
    ; or another play_song().)
    sub pause_music() {
        push_song_stack()
        note_held_mask = 0
    }

    sub unpause_music() {
        ubyte oldbank = music_getbank()
        pop_song_stack()
        rombank(oldbank)
    }

    ; call this once every frame
    sub tick_music() {
        ubyte n
        ubyte i
        ubyte note      ; (not "a": p8c's assembly has "inc a", which would then be this variable)
        ubyte op
        uword sfx
        ubyte oldbank = music_getbank()

        for n in 0 to NUM_FM_CHANNELS-1 {
            if sound_effect_length[n] != 0 {
                sound_effect_length[n]--
                op = n << 2
                if sound_effect_length[n] != 0 {
                    ; a frame of the effect: 4 amplitudes, then 4 note numbers
                    rombank(sound_effect_bank[n])
                    sfx = sound_effect_ptr[n]
                    for i in 0 to OPS_PER_CHANNEL-1 {
                        aram[AMPLITUDE + op] = (@(sfx + i) << 3) + 128
                        note = @(sfx + 4 + i) << 1
                        aram[PITCH_MSB + op] = pitch_table[note]
                        aram[PITCH_LSB + op] = pitch_table[note + 1]
                        op++
                    }
                    sound_effect_ptr[n] = sfx + 8
                } else {
                    ; the effect is over: the channel is the music's again
                    aram[AMPLITUDE + op + 3] = 128
                    aram[FEEDBACK_AMT + n] = 128    ; (C: not saved_feedback_value either)
                    music_channel_mask |= channel_masks[n]
                    sound_effect_priority[n] = 0
                    if channelStates[n] != 255
                        set_note(n, last_note[n])
                }
            }
        }

        if music_song_base != 0
            rombank(music_bank)

        if (music_flags & MUSIC_FLAG_STOPPED) == 0 {
            music_delay--
            if music_delay == 0 {
                music_delay = track_step_frames
                music_step_idx++
                if music_step_idx == track_pattern_length {
                    music_step_idx = 0
                    music_sequence_idx++
                    if music_sequence_idx == sequenceLength {
                        if (music_flags & MUSIC_FLAG_REPEAT) != 0
                            music_sequence_idx = 0
                        else if (music_flags & MUSIC_FLAG_POP_AT_END) != 0
                            pop_song_stack()
                        else
                            music_flags |= MUSIC_FLAG_STOPPED
                    }
                    if (music_flags & MUSIC_FLAG_STOPPED) == 0 {
                        for n in 0 to NUM_FM_CHANNELS-1 {
                            channelCurrentPattern[n] = @(channelSequences[n] + music_sequence_idx)
                        }
                    }
                }
                if (music_flags & MUSIC_FLAG_STOPPED) == 0
                    music_play_step(0)
            }
        }

        for n in 0 to NUM_FM_CHANNELS-1 {
            if channelStates[n] < 16
                channelStates[n]++
            else
                channelStates[n] = 255
        }
        fetchEnvelopes()

        flush_audio_params()
        rombank(oldbank)
    }

    sub silence_all_channels() {
        ubyte n
        for n in 0 to NUM_FM_OPS-1 {
            aram[AMPLITUDE + n] = 128
        }
        note_held_mask = 0
    }

    sub stop_music() {
        ubyte n
        music_flags |= MUSIC_FLAG_STOPPED
        silence_all_channels()
        for n in 0 to NUM_FM_CHANNELS-1 {
            channelStates[n] = 255
        }
    }

    ; start a sound effect, at address sfx in cartridge bank bank_num.  It takes the
    ; channel (0-3) from the music until it is over.  A priority (0-15) can be added
    ; to the channel as  channel | priority << 4  (SFX_PRIORITY in C): an effect of
    ; lower priority than the one that plays on the channel is not started.
    ; The data: the number of frames, the channel's feedback amount, and then 8 bytes
    ; for every frame: the amplitudes of the 4 operators and their note numbers.
    sub play_sound_effect(uword sfx, ubyte bank_num, ubyte channel) {
        ubyte oldbank
        ubyte priority = channel & $f0
        channel &= $03
        if priority < sound_effect_priority[channel]
            return
        sound_effect_priority[channel] = priority
        oldbank = music_getbank()
        rombank(bank_num)
        sound_effect_bank[channel] = bank_num
        sound_effect_length[channel] = @(sfx) + 1
        saved_feedback_value[channel] = aram[FEEDBACK_AMT + channel]
        aram[FEEDBACK_AMT + channel] = @(sfx + 1)
        sound_effect_ptr[channel] = sfx + 2
        music_channel_mask &= ~channel_masks[channel]
        rombank(oldbank)
    }

    ; the SDK's jingle, which is in the fixed bank
    sub play_boot_jingle() {
        play_song(assets.jingle, 255, REPEAT_NONE)
    }
}

assets {
%option merge

jingle:
    %asmbinary "jingle.bin"
}
