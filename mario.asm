; OWNER: 25F-0037 - graphics, video memory, sprites, map drawing and build.
; Build THIS file: nasm -f bin mario.asm -o MARIO.COM
; Shared constants/macros/data live here. Coordinate shared-data edits as a team.
; player.asm and gameplay.asm are included below, not assembled separately.

; =====================================================================
;  SUPER MARIO ENGINE  -  EL2003 COAL Semester Project
;  Target : MARIO.COM  (NASM -f bin, 16-bit real mode, ORG 100h)
;  Video  : VGA mode 13h (320x200x256), off-screen frame buffer
;  Build  : nasm -f bin mario.asm -o MARIO.COM        (see build.bat)
;
;  CONVENTIONS
;   * Procedures take their inputs on the STACK (pushed left to right,
;     followed by a context-segment word; callee removes all with RET n) and preserve every register they
;     do not return (results come back in AX).
;   * DS = ES = CS everywhere except inside drawing routines, which
;     load ES with the frame-buffer segment and restore it.
;   * Positions use an extended whole word + fraction byte (16.8):
;     this spans 960 world pixels; velocity is a signed 8.8 word.
;
;  MODULE MAP (see manual section 6)
;   1 skeleton   : start / Shutdown            2 video : SetPalette, PutPixel, FillRect
;   3 map        : GetTile, DrawTiles, ResetLevel   4 sprites : DrawSprite
;   5 frame buf  : ClearFB, Present            6 camera : UpdateCamera
;   7 keyboard   : KbdISR                      8 timer  : TimerISR, WaitTick
;   9 physics    : UpdateMario                10 collision : ColSolid, RectOverlap
;  11 enemies    : UpdateEnts, EntStep        12 blocks : HitBlock, Spawn, TileEffects
;  13 HUD/score  : AddScore, DrawNum, DrawHUD 14 states : St* handlers + statetab
;  15 win/lose   : StartDeath, StartWin, NewGame, Shutdown
; =====================================================================
        cpu     8086
        bits    16
        org     100h
%ifdef AUDIT_TEST
        jmp     TestMain               ; test builds only; absent from MARIO.COM
%endif

; ------------------------------------------------------------ constants
SCRW        equ 320
SCRH        equ 200
TILE        equ 16
LVLW        equ 60                      ; level width  in tiles
LVLH        equ 12                      ; level height in tiles
CAM_MAX     equ (LVLW*TILE-SCRW)        ; 640 : last camera position
MARIO_MAXX  equ (LVLW*TILE-TILE)        ; 944 : right end of the level
FPS         equ 30
TIMER_DIV   equ 39772                   ; 1193182 / 30 Hz
SPRN        equ 26                      ; number of 16x16 sprites
PALN        equ 18                      ; palette entries we program

; scan codes (Appendix A.3)
K_ESC   equ 01h
K_T     equ 14h
K_P     equ 19h
K_ENTER equ 1Ch
K_SHIFT equ 2Ah
K_SPACE equ 39h
K_UP    equ 48h
K_LEFT  equ 4Bh
K_RIGHT equ 4Dh
K_DOWN  equ 50h

; physics (8.8 fixed point, Appendix A.5)
ACC     equ 0020h                       ; walk acceleration
BRAKE   equ 0040h                       ; braking against the motion
FRIC    equ 0010h
MAXWALK equ 0180h
MAXRUN  equ 0280h
GRAV    equ 0040h
JUMPV   equ 0FA80h                      ; -5.5
JUMPCUT equ 0FE00h                      ; -2.0
MAXFALL equ 0400h
STOMPV  equ 0FD00h                      ; -3.0
STOMPVH equ 0FC00h                      ; -4.0  (jump key held)
DEATHV  equ 0FB00h                      ; -5.0  (death hop, ~50 px)
SPD_GOOMBA equ 0080h
SPD_KOOPA  equ 00C0h
SPD_SHELL  equ 0300h
SPD_MUSH   equ 0100h
INVULN     equ 60                       ; 2 s of frames
DEATH_FRAMES equ 45                     ; 1.5 s
LIFELOST_FRAMES equ 60                  ; 2 s

; game states
ST_TITLE equ 0
ST_PLAY  equ 1
ST_PAUSE equ 2
ST_DYING equ 3
ST_LIFE  equ 4
ST_WIN   equ 5
ST_DONE  equ 6
ST_OVER  equ 7
ST_EXIT  equ 8

; entity record (16 bytes)
E_TYPE  equ 0
E_STATE equ 1
E_X     equ 2                           ; word, world pixels
E_Y     equ 4                           ; word, top pixel
E_VY    equ 6                           ; word, 8.8
E_DIR   equ 8                           ; 0 = right, 1 = left
E_XF    equ 9                           ; x fraction
E_TIMER equ 10                          ; word
E_YF    equ 12                          ; y fraction
ESIZE   equ 16
ENTN    equ 16                          ; 8 level enemies + 8 dynamic slots
ENTDYN  equ 8                           ; first dynamic record

ET_GOOMBA equ 1
ET_KOOPA  equ 2
ET_MUSH   equ 3
ET_POP    equ 4                         ; coin popping out of a "?" block

ES_WAIT  equ 0
ES_WALK  equ 1
ES_FLAT  equ 2
ES_SHELL equ 3
ES_SLIDE equ 4

; ------------------------------------------------------------ macros
; PUSHI(value): 8086-safe stack argument; preserves AX, BP and FLAGS.
; Used for constants and drawing macro arguments (never BP-relative operands).
%macro PUSHI 1
        push    ax
        push    bp
        mov     bp,sp
        mov     ax,%1
        xchg    ax,[bp+2]
        pop     bp
%endmacro

%macro IFHIT 2                          ; IFHIT scancode,label : key was pressed
        cmp     byte [hits+%1],0
        jne     short $+5
        jmp     near %%no
        mov     byte [hits+%1],0
        jmp     %2
%%no:
%endmacro

%macro FILL 5                           ; x,y,w,h,colour
        PUSHI   %1
        PUSHI   %2
        PUSHI   %3
        PUSHI   %4
        PUSHI   %5
        push    ds
        call    FillRect
%endmacro
%macro TEXT 5                           ; x,y,string,colour,scale
        PUSHI   %1
        PUSHI   %2
        PUSHI   %3
        PUSHI   %4
        PUSHI   %5
        push    ds
        call    DrawString
%endmacro
%macro NUM 7                            ; x,y,lo,hi,digits,colour,scale
        PUSHI   %1
        PUSHI   %2
        PUSHI   %3
        PUSHI   %4
        PUSHI   %5
        PUSHI   %6
        PUSHI   %7
        push    ds
        call    DrawNum
%endmacro
%macro BOX 6                            ; x,y,w,h,border,fill
        PUSHI   %1
        PUSHI   %2
        PUSHI   %3
        PUSHI   %4
        PUSHI   %5
        PUSHI   %6
        push    ds
        call    DrawBox
%endmacro

; =====================================================================
;  MODULE 1 : program entry
; =====================================================================
start:
        cld
        mov     ah,4Ah                  ; shrink our block to 64 KB ...
        mov     bx,1000h
        int     21h
        jnc     short $+5
        jmp     near fail_mem
        mov     ah,48h                  ; ... and allocate the frame buffer
        mov     bx,0FA0h                ; 0FA0h paragraphs = 64000 bytes
        int     21h
        jnc     short $+5
        jmp     near fail_mem
        mov     [fbseg],ax
        push    ds
        call    InitData
        mov     ax,0013h                ; VGA mode 13h
        int     10h
        push    ds
        call    SetPalette
        push    ds
        call    HookInts
        push    ds
        call    GoTitle
mainloop:
        push    ds
        call    WaitTick                ; 1. wait for the next timer tick
        mov     bl,[state]
        xor     bh,bh
        shl     bx,1
        push    ds
        call    word [statetab+bx]      ; jump table indexed by state
        cmp     byte [state],ST_EXIT
        jne     short $+5
        jmp     near Shutdown
        mov     ax,[ticks]
        cmp     ax,[lasttick]
        je     short $+5
        jmp     near mainloop          ; consume every pending simulation tick
        push    ds
        call    RenderState            ; draw once after catching up
        jmp     mainloop

fail_mem:
        mov     dx,s_memfail
        mov     ah,9
        int     21h
        mov     ax,4C01h
        int     21h

; ---------------------------------------------------------------------
; Shutdown : restore timer rate, both vectors, text mode, return to DOS.
; Single exit path used by every way of leaving the game.
; ---------------------------------------------------------------------
Shutdown:
        push    ds
        call    RestoreHardware
        mov     ax,0003h                ; text mode
        int     10h
        mov     ax,4C00h
        int     21h

; ---------------------------------------------------------------------
; InitData : convert text sprites/map to palette indices / tile codes,
;            copy the BIOS 8x8 font into our data, build working map.
; ---------------------------------------------------------------------
InitData:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp

        push    ax
        push    cx
        push    dx
        push    bx
        push    bp
        push    si
        push    di
        push    es
        ; sprites: letters -> palette index (in place)
        mov     si,Sprites
        mov     cx,SPRN*256
.s:     lodsb
        mov     di,sprchars
        push    cx
        mov     cx,PALN
        repne   scasb
        mov     al,PALN-1
        sub     al,cl                   ; index = PALN-1-cx
        pop     cx
        mov     [si-1],al
        loop    $+4
        jmp     short $+5
        jmp     near .s
        ; map: letters -> tile codes (in place)
        mov     si,orgmap
        mov     cx,LVLW*LVLH
.m:     lodsb
        mov     di,mapchars
        push    cx
        mov     cx,16
        repne   scasb
        mov     al,15
        sub     al,cl
        pop     cx
        mov     [si-1],al
        loop    $+4
        jmp     short $+5
        jmp     near .m
        ; BIOS 8x8 font (chars 0..127) -> fontbuf
        mov     ax,1130h
        mov     bh,3
        int     10h                     ; ES:BP -> font
        push    ds
        push    es
        pop     ds
        mov     si,bp
        push    cs
        pop     es
        mov     di,fontbuf
        mov     cx,512
        rep     movsw
        pop     ds
        pop     es
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; ---------------------------------------------------------------------
; SetPalette : program DAC registers 0..PALN-1 (INT 10h AX=1012h)
; ---------------------------------------------------------------------
SetPalette:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp

        push    ax
        push    cx
        push    dx
        push    bx
        push    bp
        push    si
        push    di
        mov     ax,1012h
        xor     bx,bx
        mov     cx,PALN
        mov     dx,palette
        int     10h
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; =====================================================================
;  MODULE 5 : frame buffer operations
; =====================================================================
; ClearFB : block-fill the frame buffer with the sky colour (REP STOSW)
ClearFB:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp
        push    ax
        push    cx
        push    dx
        push    bx
        push    bp
        push    si
        push    di

        push    es
        push    di
        push    cx
        push    ax
        mov     es,[fbseg]
        xor     di,di
        mov     ax,0101h
        mov     cx,32000
        rep     stosw
        pop     ax
        pop     cx
        pop     di
        pop     es
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; Present : block-move the frame buffer to video memory (REP MOVSW)
Present:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp
        push    ax
        push    cx
        push    dx
        push    bx
        push    bp
        push    si
        push    di

        push    ax
        push    ds
        push    es
        push    si
        push    di
        push    cx
        mov     ds,[fbseg]
        mov     ax,0A000h
        mov     es,ax
        xor     si,si
        xor     di,di
        mov     cx,32000
        rep     movsw
        pop     cx
        pop     di
        pop     si
        pop     es
        pop     ds
        pop     ax
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; =====================================================================
;  MODULE 2 : drawing primitives (all draw into the frame buffer)
; =====================================================================
; PutPixel(x, y, colour)           stack: x,y,colour       ret 8
PutPixel:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp

        push    bp
        mov     bp,sp
        push    ax
        push    bx
        push    di
        push    es
        mov     ax,[bp+12]
        cmp     ax,SCRW
        jb     short $+5
        jmp     near .o
        mov     bx,[bp+10]
        cmp     bx,SCRH
        jb     short $+5
        jmp     near .o
        mov     di,bx
        shl     di,1
        shl     di,1
        shl     di,1
        shl     di,1
        shl     di,1
        shl     di,1                    ; y*64
        shl     bx,1
        shl     bx,1
        shl     bx,1
        shl     bx,1
        shl     bx,1
        shl     bx,1
        shl     bx,1
        shl     bx,1                    ; y*256
        add     di,bx                   ; y*320
        add     di,ax
        mov     es,[fbseg]
        mov     al,[bp+8]
        mov     [es:di],al
.o:     pop     es
        pop     di
        pop     bx
        pop     ax
        pop     bp
        pop     ds
        ret     8

; FillRect(x, y, w, h, colour)     clips on every edge       ret 12
FillRect:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp

        push    bp
        mov     bp,sp
        push    ax
        push    cx
        push    dx
        push    bx
        push    bp
        push    si
        push    di
        push    es
        mov     es,[fbseg]
        mov     ax,[bp+16]              ; x
        mov     bx,[bp+12]               ; w
        test    ax,ax
        js     short $+5
        jmp     near .xl
        add     bx,ax
        xor     ax,ax
.xl:    mov     dx,ax
        add     dx,bx
        cmp     dx,SCRW
        jg     short $+5
        jmp     near .xr
        mov     bx,SCRW
        sub     bx,ax
.xr:    test    bx,bx
        jg     short $+5
        jmp     near .done
        mov     dx,[bp+14]              ; y
        mov     cx,[bp+10]               ; h
        test    dx,dx
        js     short $+5
        jmp     near .yt
        add     cx,dx
        xor     dx,dx
.yt:    mov     si,dx
        add     si,cx
        cmp     si,SCRH
        jg     short $+5
        jmp     near .yb
        mov     cx,SCRH
        sub     cx,dx
.yb:    test    cx,cx
        jg     short $+5
        jmp     near .done
        mov     di,dx
        shl     di,1
        shl     di,1
        shl     di,1
        shl     di,1
        shl     di,1
        shl     di,1
        mov     si,dx
        shl     si,1
        shl     si,1
        shl     si,1
        shl     si,1
        shl     si,1
        shl     si,1
        shl     si,1
        shl     si,1
        add     di,si
        add     di,ax
        mov     al,[bp+8]
.row:   push    cx
        push    di
        mov     cx,bx
        rep     stosb
        pop     di
        add     di,SCRW
        pop     cx
        loop    $+4
        jmp     short $+5
        jmp     near .row
.done:  pop     es
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     bp
        pop     ds
        ret     12

; DrawBox(x, y, w, h, border, fill)   2-pixel border              ret 14
DrawBox:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp

        push    bp
        mov     bp,sp
        push    ax
        push word [bp+18]
        push word [bp+16]
        push word [bp+14]
        push word [bp+12]
        push word [bp+10]
        push    ds
        call    FillRect
        mov     ax,[bp+18]
        add     ax,2
        push    ax
        mov     ax,[bp+16]
        add     ax,2
        push    ax
        mov     ax,[bp+14]
        sub     ax,4
        push    ax
        mov     ax,[bp+12]
        sub     ax,4
        push    ax
        push word [bp+8]
        push    ds
        call    FillRect
        pop     ax
        pop     bp
        pop     ds
        ret     14

; =====================================================================
;  MODULE 4 : sprites
;  DrawSprite(x, y, address, flags)                              ret 10
;   flags bit0 = mirror horizontally, bit1 = opaque (fast REP MOVSB)
;   colour 0 is transparent otherwise.  Clips at all four edges.
; =====================================================================
DrawSprite:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp

        push    bp
        mov     bp,sp
        sub     sp,10                   ; locals: -2 cstart -4 count -6 sx -8 rowptr -10 rows
        push    ax
        push    cx
        push    dx
        push    bx
        push    bp
        push    si
        push    di
        push    es
        mov     es,[fbseg]
        mov     ax,[bp+14]              ; x
        xor     cx,cx                   ; first visible column
        test    ax,ax
        js     short $+5
        jmp     near .xp
        mov     cx,ax
        neg     cx
.xp:    mov     dx,SCRW
        sub     dx,ax
        cmp     dx,16
        jg     short $+5
        jmp     near .ce
        mov     dx,16
.ce:    sub     dx,cx                   ; visible column count
        jg     short $+5
        jmp     near .done
        mov     [bp-2],cx
        mov     [bp-4],dx
        add     ax,cx
        mov     [bp-6],ax               ; first screen x
        mov     ax,[bp+10]
        mov     [bp-8],ax
        mov     word [bp-10],16
        mov     bx,[bp+12]               ; y
.row:   test    bx,bx
        jns     short $+5
        jmp     near .nextrow
        cmp     bx,SCRH
        jl     short $+5
        jmp     near .done
        mov     di,bx
        shl     di,1
        shl     di,1
        shl     di,1
        shl     di,1
        shl     di,1
        shl     di,1
        mov     ax,bx
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        add     di,ax
        add     di,[bp-6]
        mov     si,[bp-8]
        mov     cx,[bp-4]
        test    word [bp+8],1
        jz     short $+5
        jmp     near .mir
        add     si,[bp-2]
        test    word [bp+8],2
        jnz     short $+5
        jmp     near .trn
        rep     movsb
        jmp     .nextrow
.trn:   lodsb
        test    al,al
        jnz     short $+5
        jmp     near .t1
        mov     [es:di],al
.t1:    inc     di
        loop    $+4
        jmp     short $+5
        jmp     near .trn
        jmp     .nextrow
.mir:   add     si,15
        sub     si,[bp-2]
.m1:    mov     al,[si]
        dec     si
        test    al,al
        jnz     short $+5
        jmp     near .m2
        mov     [es:di],al
.m2:    inc     di
        loop    $+4
        jmp     short $+5
        jmp     near .m1
.nextrow:
        add     word [bp-8],16
        inc     bx
        dec     word [bp-10]
        jz     short $+5
        jmp     near .row
.done:  pop     es
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        mov     sp,bp
        pop     bp
        pop     ds
        ret     10
