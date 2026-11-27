; GameTank audio coprocessor (ACP) support.
;
; Prog8 version of the GameTank SDK's src/gt/audio/audio_coprocessor.c, for the
; SDK's default FM firmware (sdk_default_fm.acp.asm): 4 channels of 4 operators.
; The names are those of the C SDK as much as possible.
;
; The firmware runs in the 4KB of audio ram at $3000, which the main cpu sees too.
; Its zero page holds the parameters of the 16 operators, so they are set in two ways:
;   set directly:   aram[PITCH_MSB + op] = value          (set_audio_param in C)
;   queued:         push_audio_param(PITCH_MSB + op, value), then flush_audio_params()
;                   lets the firmware copy them all in one go, in its NMI.
;
; The music player that uses this is in gametank_music.p8.

%import gametank
%import shared_compression

gametank {
%option merge

    ; ---- parameters of the FM firmware: offsets in its zero page ----
    const ubyte FEEDBACK_AMT    = $04       ; + channel (0-3)
    const ubyte PITCH_MSB       = $10       ; + operator (0-15)
    const ubyte PITCH_LSB       = $20       ; + operator (0-15)
    const ubyte AMPLITUDE       = $30       ; + operator (0-15), 128 = silent

    const ubyte NUM_FM_CHANNELS = 4
    const ubyte OPS_PER_CHANNEL = 4
    const ubyte NUM_FM_OPS      = 16

    ; the first page of the audio ram: the firmware's zero page
    &ubyte[256] aram = $3000
    &uword WAVE_TABLE_LOCATION = $3002
    const uword AUDIO_PARAM_INPUT_BUFFER = $3070

    ; pitch of every note number (0-107), 2 bytes each: msb then lsb
    ubyte[216] pitch_table = [
        $00, $4D, $00, $51, $00, $56, $00, $5B, $00, $61, $00, $66, $00, $6C, $00, $73, $00, $7A, $00, $81, $00, $89, $00, $91,
        $00, $99, $00, $A2, $00, $AC, $00, $B6, $00, $C1, $00, $CD, $00, $D9, $00, $E6, $00, $F3, $01, $02, $01, $11, $01, $21,
        $01, $33, $01, $45, $01, $58, $01, $6D, $01, $82, $01, $99, $01, $B2, $01, $CB, $01, $E7, $02, $04, $02, $22, $02, $43,
        $02, $65, $02, $8A, $02, $B0, $02, $D9, $03, $04, $03, $32, $03, $63, $03, $97, $03, $CD, $04, $07, $04, $44, $04, $85,
        $04, $CA, $05, $13, $05, $60, $05, $B2, $06, $09, $06, $65, $06, $C6, $07, $2D, $07, $9A, $08, $0E, $08, $89, $09, $0B,
        $09, $94, $0A, $26, $0A, $C1, $0B, $64, $0C, $12, $0C, $CA, $0D, $8C, $0E, $5B, $0F, $35, $10, $1D, $11, $12, $12, $16,
        $13, $29, $14, $4D, $15, $82, $16, $C9, $18, $24, $19, $93, $1B, $19, $1C, $B5, $1E, $6A, $20, $39, $22, $24, $24, $2B,
        $26, $52, $28, $99, $2B, $03, $2D, $92, $30, $48, $33, $27, $36, $31, $39, $6A, $3C, $D4, $40, $72, $44, $47, $48, $57,
        $4C, $A4, $51, $32, $56, $06, $5B, $24, $60, $8F, $66, $4D, $6C, $62, $72, $D4, $79, $A8, $80, $E4, $88, $8E, $90, $AD]

    ubyte audio_params_index
    uword wavetable_page
    ubyte sine_offset

    ; load the firmware into the audio ram and start the coprocessor
    sub init_audio_coprocessor() {
        audio_rate = $7f
        void compression.decode_rle(assets.audio, audio_ram, 4096)
        audio_params_index = 0
        @(AUDIO_PARAM_INPUT_BUFFER) = 0
        audio_reset = 0
        audio_rate = 255
        while WAVE_TABLE_LOCATION == 0 {
            ; wait for the firmware to come up
        }
        wavetable_page = $3000 + WAVE_TABLE_LOCATION
        sine_offset = @($3003)
    }

    ; queue one parameter for the firmware; flush_audio_params() sends the queue.
    ; (the queue holds 7 of them: it is the 16 bytes at AUDIO_PARAM_INPUT_BUFFER)
    sub push_audio_param(ubyte param, ubyte value) {
        @(AUDIO_PARAM_INPUT_BUFFER + audio_params_index) = param
        audio_params_index++
        @(AUDIO_PARAM_INPUT_BUFFER + audio_params_index) = value
        audio_params_index++
    }

    ; let the firmware take the queued parameters
    sub flush_audio_params() {
        @(AUDIO_PARAM_INPUT_BUFFER + audio_params_index) = 0
        audio_nmi = 1
        audio_params_index = 0
    }
}

; the SDK's assets that are in the library (other modules add to this block)
assets {
audio:
    %asmbinary "audio_fw.bin.rle", 0, 4096
}
