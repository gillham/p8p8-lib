; The start and the end of a program for the Atari ST (the atarist target of p8p8):
; a GEMDOS program, a .TOS file.

%option no_symbol_prefixing, ignore_unused

p8_sys_startup {
    %option force_output

    ; GEMDOS starts a program with all of the free memory as its own, the stack at the
    ; end of it, and the address of the program's base page at 4(sp).  The program
    ; keeps what it is long (the base page's lengths of text, data and BSS, which GEMDOS
    ; has cleared) and tos.STACK_SIZE bytes of stack after that, and gives the rest
    ; back (Mshrink), so that there is memory for what else the machine runs.
    sub init_system() {
        %option noframe
        %asm {{
            move.l  (sp)+,a3                ; (where this returns to: the stack moves)
            move.l  4(sp),a5
            move.l  a5,tos.basepage
            move.l  $c(a5),d3
            add.l   $14(a5),d3
            add.l   $1c(a5),d3
            add.l   #$100,d3
            addq.l  #1,d3
            bclr    #0,d3
            move.l  a5,d4
            add.l   d3,d4
            move.l  d4,tos.stack_low
            add.l   #tos.STACK_SIZE,d3
            add.l   #tos.STACK_SIZE,d4
            cmp.l   4(a5),d4                ; (the end of the memory that the program has)
            bhi.s   .keep
            move.l  d4,sp
            move.l  d3,-(sp)
            move.l  a5,-(sp)
            clr.w   -(sp)
            move.w  #$4a,-(sp)              ; Mshrink
            trap    #1
            lea     12(sp),sp
.keep:
            move.w  #4,-(sp)                ; Getrez
            trap    #14
            addq.l  #2,sp
            move.b  d0,tos.rez
            ; a line that reaches the right edge goes on in the next one, as on the other
            ; machines (the console's own way is to stay in the last column): VT-52's ESC v
            pea     .wrap(pc)
            move.w  #9,-(sp)                ; Cconws
            trap    #1
            addq.l  #6,sp
            jmp     (a3)
.wrap:      dc.b    27,'v',0,0
            ; !notreached!
        }}
    }

    sub init_system_phase2() {
        %option noframe
        %asm {{
            moveq   #0,d0
            moveq   #0,d1
            moveq   #0,d2
            moveq   #0,d3
            moveq   #0,d4
            moveq   #0,d5
            moveq   #0,d6
            moveq   #0,d7
            move.w  d0,ccr
            suba.l  a0,a0
            suba.l  a1,a1
            suba.l  a2,a2
            suba.l  a3,a3
            suba.l  a4,a4
            suba.l  a5,a5
            suba.l  a6,a6
        }}
    }

    sub cleanup_at_exit() {
        %option noframe
        %asm {{
            move.w  d0,-(sp)
            move.w  #$4c,-(sp)              ; Pterm
            trap    #1
        }}
    }
}

prog8_lib {
    asmsub strcmp(str st1 @D0, str st2 @D1) -> byte @D0 {
        ; Compares two strings for sorting, case-sensitively.
        ; Returns -1 (255 as byte), 0 or 1.
        %asm {{
            movea.l  d0,a0
            movea.l  d1,a1
.loop:
            move.b   (a0)+,d0
            move.b   (a1)+,d1
            cmp.b    d1,d0
            bne      .diff
            tst.b    d0
            bne      .loop
            moveq    #0,d0
            rts
.diff:
            blo      .less
            moveq    #1,d0
            rts
.less:
            moveq    #-1,d0
            rts
        }}
    }
}
