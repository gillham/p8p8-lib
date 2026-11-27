; GameTank gamepads.
;
; Prog8 version of the GameTank SDK's src/gt/input.c and input.h, and of
; src/gt/feature/paddleInput, with the names of the C SDK.  Call update_inputs() once per frame, then test the
; button variables with the INPUT_MASK_ constants:
;
;   gametank.update_inputs()
;   if gametank.player1_buttons & gametank.INPUT_MASK_LEFT != 0  ...   ; held down
;   if gametank.player1_new_buttons & gametank.INPUT_MASK_A != 0  ...  ; pressed this frame
;
; A gamepad is read as two bytes: the first read is the low byte of the value,
; the second read the high byte.  A set bit is a button that is down.

%import gametank

gametank {
%option merge

    const uword INPUT_MASK_UP       = 2056      ; $0808: in both reads
    const uword INPUT_MASK_DOWN     = 1028      ; $0404: in both reads
    const uword INPUT_MASK_LEFT     = 512
    const uword INPUT_MASK_RIGHT    = 256
    const uword INPUT_MASK_A        = 16
    const uword INPUT_MASK_B        = 4096
    const uword INPUT_MASK_C        = 8192
    const uword INPUT_MASK_START    = 32
    const uword INPUT_MASK_ALL_KEYS = INPUT_MASK_UP|INPUT_MASK_DOWN|INPUT_MASK_LEFT|INPUT_MASK_RIGHT|INPUT_MASK_A|INPUT_MASK_B|INPUT_MASK_C|INPUT_MASK_START
    const uword INPUT_MASK_ANY_DIRECTION = INPUT_MASK_UP|INPUT_MASK_DOWN|INPUT_MASK_LEFT|INPUT_MASK_RIGHT

    uword player1_buttons           ; down now
    uword player1_old_buttons       ; down at the previous update_inputs()
    uword player1_new_buttons       ; down now, and not at the previous one
    uword player2_buttons
    uword player2_old_buttons
    uword player2_new_buttons

    ; read both gamepads into the variables above
    sub update_inputs() {
        player1_old_buttons = player1_buttons
        player1_buttons = ~read_gamepad1() & INPUT_MASK_ALL_KEYS
        player1_new_buttons = player1_buttons & ~player1_old_buttons

        player2_old_buttons = player2_buttons
        player2_buttons = ~read_gamepad2() & INPUT_MASK_ALL_KEYS
        player2_new_buttons = player2_buttons & ~player2_old_buttons
    }

    ; ---- paddle controllers (the C SDK's src/gt/feature/paddleInput) ----

    const uword INPUT_MASK_PADDLE_UP    = 2048
    const uword INPUT_MASK_PADDLE_DOWN  = 1024
    const uword INPUT_MASK_PADDLE_LEFT  = 512
    const uword INPUT_MASK_PADDLE_RIGHT = 256
    const uword INPUT_MASK_PADDLE_A     = 16
    const uword INPUT_MASK_PADDLE_B     = 4096
    const uword INPUT_MASK_PADDLE_C     = 8192
    const uword INPUT_MASK_PADDLE_START = 32
    const uword INPUT_MASK_PADDLE_MODE  = 1
    const uword INPUT_MASK_PADDLE_X     = 2
    const uword INPUT_MASK_PADDLE_Y     = 4
    const uword INPUT_MASK_PADDLE_Z     = 8
    const uword INPUT_MASK_PADDLE_ALL_KEYS = INPUT_MASK_PADDLE_UP|INPUT_MASK_PADDLE_DOWN|INPUT_MASK_PADDLE_LEFT|INPUT_MASK_PADDLE_RIGHT|INPUT_MASK_PADDLE_A|INPUT_MASK_PADDLE_B|INPUT_MASK_PADDLE_C|INPUT_MASK_PADDLE_START|INPUT_MASK_PADDLE_MODE|INPUT_MASK_PADDLE_X|INPUT_MASK_PADDLE_Y|INPUT_MASK_PADDLE_Z

    ; update_inputs() for paddles and touch interfaces: use this one in its
    ; place, and test the button variables with the INPUT_MASK_PADDLE_ constants.
    sub update_paddle_inputs() {
        player1_old_buttons = player1_buttons
        player1_buttons = ~read_gamepad1() & INPUT_MASK_PADDLE_ALL_KEYS
        player1_new_buttons = player1_buttons & ~player1_old_buttons

        player2_old_buttons = player2_buttons
        player2_buttons = ~read_gamepad2() & INPUT_MASK_PADDLE_ALL_KEYS
        player2_new_buttons = player2_buttons & ~player2_old_buttons
    }

    ; The position of the paddle of a port (0: player 1, 1: player 2), from
    ; what update_paddle_inputs() read.
    sub get_paddle_rotation(ubyte port) -> ubyte {
        uword buttons = player1_buttons
        ubyte result = 0
        if port == 1
            buttons = player2_buttons
        if buttons & INPUT_MASK_PADDLE_UP != 0     result |= 1
        if buttons & INPUT_MASK_PADDLE_DOWN != 0   result |= 2
        if buttons & INPUT_MASK_PADDLE_LEFT != 0   result |= 4
        if buttons & INPUT_MASK_PADDLE_RIGHT != 0  result |= 8
        if buttons & INPUT_MASK_PADDLE_X != 0      result |= 16
        if buttons & INPUT_MASK_PADDLE_Y != 0      result |= 32
        if buttons & INPUT_MASK_PADDLE_Z != 0      result |= 64
        if buttons & INPUT_MASK_PADDLE_MODE != 0   result |= 128
        return ~result
    }

    ; The two bytes of a gamepad as the hardware gives them: a clear bit is a
    ; button that is down, and no mask is applied.
    ; Reading the other port first puts this port's select line back, so that
    ; the two reads that follow are the first and the second set of buttons.
    asmsub read_gamepad1() -> uword @AY {
        %asm {{
            php
            sei
            lda  gametank.GAMEPAD2
            lda  gametank.GAMEPAD1
            ldy  gametank.GAMEPAD1
            plp
            rts
        }}
    }

    asmsub read_gamepad2() -> uword @AY {
        %asm {{
            php
            sei
            lda  gametank.GAMEPAD1
            lda  gametank.GAMEPAD2
            ldy  gametank.GAMEPAD2
            plp
            rts
        }}
    }
}
