; The start and the end of a program for a 68000 Macintosh (the macplus target of
; p8p8): an application, with its text in a window.

%option no_symbol_prefixing, ignore_unused

p8_sys_startup {
    %option force_output

    ; The Segment Loader starts the program with a5 set (QuickDraw's variables are below
    ; it, the jump table above), and the program has put its addresses right already
    ; (the code generator's first lines).  Here the stack gets its room, the heap the
    ; rest, the Toolbox is started as every application does it, and the window that the
    ; text goes to is opened.  a5 stays what it is for as long as the program runs.
    sub init_system() {
        %option noframe
        %asm {{
            move.l  $908.w,a0               ; CurStackBase
            sub.l   #macos.STACK_SIZE,a0
            dc.w    $a02d                   ; _SetApplLimit
            dc.w    $a063                   ; _MaxApplZone
            pea     -4(a5)
            dc.w    $a86e                   ; _InitGraf
            dc.w    $a8fe                   ; _InitFonts
            move.l  #$0000ffff,d0
            dc.w    $a032                   ; _FlushEvents
            dc.w    $a912                   ; _InitWindows
            dc.w    $a930                   ; _InitMenus
            dc.w    $a9cc                   ; _TEInit
            clr.l   -(sp)
            dc.w    $a97b                   ; _InitDialogs
            dc.w    $a850                   ; _InitCursor
            clr.l   -(sp)
            dc.w    $a8d8                   ; _NewRgn
            move.l  (sp)+,macos.region
            ; the window, in the middle of the screen's width (QuickDraw's variables: the
            ; screen's rectangle is 116 bytes below thePort, its right edge 110)
            move.l  (a5),a0
            move.w  -110(a0),d0
            move.w  -112(a0),d1
            lea     macos.limits,a0           ; (where the window may be dragged to)
            move.w  #24,(a0)
            move.w  #4,2(a0)
            subq.w  #4,d1
            move.w  d1,4(a0)
            subq.w  #4,d0
            move.w  d0,6(a0)
            addq.w  #4,d0
            sub.w   #macos.WIDTH,d0
            asr.w   #1,d0
            lea     macos.rect,a0
            move.w  #40,(a0)
            move.w  d0,2(a0)
            move.w  #40+macos.HEIGHT,4(a0)
            add.w   #macos.WIDTH,d0
            move.w  d0,6(a0)
            clr.l   -(sp)                   ; (the result)
            clr.l   -(sp)                   ; its record: the system's memory
            pea     macos.rect
            pea     $910.w                  ; CurApName: the title is the program's name
            move.w  #$0100,-(sp)            ; visible
            move.w  #4,-(sp)                ; a document window without a grow box
            moveq   #-1,d0
            move.l  d0,-(sp)                ; in front
            clr.w   -(sp)                   ; no close box
            clr.l   -(sp)
            dc.w    $a913                   ; _NewWindow
            move.l  (sp),macos.window
            dc.w    $a873                   ; _SetPort
            move.w  #4,-(sp)
            dc.w    $a887                   ; _TextFont: Monaco,
            move.w  #9,-(sp)
            dc.w    $a88a                   ; _TextSize: 9 points: every character 6 by 11
            clr.w   -(sp)
            dc.w    $a889                   ; _TextMode: a character replaces what was there
            lea     macos.screen,a0
            move.w  #macos.CELLS-1,d0
.fill:
            move.b  #' ',(a0)+
            dbra    d0,.fill
            jsr     macos.echo_open
            rts
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
        }}
    }

    sub cleanup_at_exit() {
        %option noframe
        %asm {{
            jmp     macos.finish
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
