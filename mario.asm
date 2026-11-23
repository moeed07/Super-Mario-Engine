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
