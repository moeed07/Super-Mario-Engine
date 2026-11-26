; OWNER: 25F-0030 - interrupts, timer, input, movement and scrolling.
; Includes shared collision helpers. Included by mario.asm; no ORG/BITS here.
; Uses the shared constants/data and context-on-stack calling convention.


; RestoreHardware(context): restore saved vectors and the BIOS PIT rate.
; Inputs: context segment at [BP+6]. Outputs: none. All registers preserved.
; Only call after HookInts. Separated from DOS exit so cleanup can be tested.
RestoreHardware:
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp
        push    ax
        push    dx
        pushf
        cli
        mov     al,36h                  ; PIT channel 0 back to 18.2 Hz
        out     43h,al
        xor     al,al
        out     40h,al
        out     40h,al
        push    ds
        lds     dx,[old08]
        mov     ax,2508h
        int     21h
        pop     ds
        push    ds
        lds     dx,[old09]
        mov     ax,2509h
        int     21h
        pop     ds
        popf
        pop     dx
        pop     ax
        pop     ds
        ret     2

; ---------------------------------------------------------------------
; HookInts : save and replace INT 09h (keyboard) and INT 08h (timer),
;            then speed the PIT up to FPS Hz.
; ---------------------------------------------------------------------
HookInts:
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
        mov     ax,3509h
        int     21h
        mov     [old09],bx
        mov     [old09+2],es
        mov     ax,3508h
        int     21h
        mov     [old08],bx
        mov     [old08+2],es
        pop     es
        mov     ax,2509h
        mov     dx,KbdISR
        int     21h
        mov     ax,2508h
        mov     dx,TimerISR
        int     21h
        cli
        mov     al,36h
        out     43h,al
        mov     ax,TIMER_DIV
        out     40h,al
        mov     al,ah
        out     40h,al
        sti
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
;  MODULE 7 : keyboard interrupt handler (INT 09h)
;  keys[]  : 1 while a scan code is held     hits[] : set on a fresh press
; =====================================================================
KbdISR:
        push    ax
        push    bx
        push    ds
        push    cs
        pop     ds
        in      al,60h
        cmp     al,0E0h
        je     short $+5
        jmp     near .not_e0
        mov     byte [e0flag],1         ; extended prefix: ignore it
        jmp     .eoi
.not_e0:
        cmp     byte [e0flag],0
        jne     short $+5
        jmp     near .proc
        mov     byte [e0flag],0
        mov     ah,al
        and     ah,7Fh
        cmp     ah,2Ah                  ; fake shift sent with arrow keys
        jne     short $+5
        jmp     near .eoi
        cmp     ah,36h
        jne     short $+5
        jmp     near .eoi
.proc:  mov     bl,al
        and     bl,7Fh
        xor     bh,bh
        test    al,80h                  ; bit 7 = key release
        jz     short $+5
        jmp     near .rel
        cmp     byte [keys+bx],0
        je     short $+5
        jmp     near .held
        mov     byte [hits+bx],1        ; new press (not auto-repeat)
        cmp     bl,K_LEFT
        je     short $+5
        jmp     near .rightpress
        mov     byte [lastdir],1
        jmp     .held
.rightpress:
        cmp     bl,K_RIGHT
        je     short $+5
        jmp     near .held
        mov     byte [lastdir],0
.held:  mov     byte [keys+bx],1
        jmp     .eoi
.rel:   mov     byte [keys+bx],0
.eoi:   mov     al,20h                  ; end of interrupt
        out     20h,al
        pop     ds
        pop     bx
        pop     ax
        iret
; =====================================================================
;  MODULE 8 : timer interrupt handler (INT 08h), 30 Hz
;  Counts ticks, and chains to the old BIOS handler at 18.2 Hz so the
;  DOS clock keeps correct time.
; =====================================================================
TimerISR:
        push    ax
        push    ds
        push    cs
        pop     ds
        inc     word [ticks]
        add     word [acc],TIMER_DIV
        jnc     short $+5
        jmp     near .chain
        mov     al,20h
        out     20h,al
        pop     ds
        pop     ax
        iret
.chain: pop     ds
        pop     ax
        jmp     far [cs:old08]

; ---------------------------------------------------------------------
; WaitTick : block until the tick counter changes (frame pacing)
; ---------------------------------------------------------------------
WaitTick:
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

        pushf
        push    ax
        cli
.check: mov     ax,[ticks]
        cmp     ax,[lasttick]
        je     short $+5
        jmp     near .ready
        sti
        hlt                            ; STI/HLT closes the check-to-sleep race
        cli
        jmp     .check
.ready: inc     word [lasttick]         ; consume ONE tick, retain backlog
        pop     ax
        popf
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
; ClearHits : forget pending key presses (used on state changes)
; ---------------------------------------------------------------------
ClearHits:
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

        pushf
        cli
        push    es
        push    ds
        pop     es
        push    ax
        push    cx
        push    di
        mov     al,[keys+K_SPACE]
        mov     [jlatch],al             ; held jump requires release after transition
        mov     di,hits
        mov     cx,64
        xor     ax,ax
        rep     stosw
        pop     di
        pop     cx
        pop     ax
        pop     es
        popf
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; SolidAt(px, py) -> AX = 1 when the tile is solid (codes 1..10)  ret 6
SolidAt:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp

        push    bp
        mov     bp,sp
        push word [bp+10]
        push word [bp+8]
        push    ds
        call    GetTile
        cmp     al,1
        jae     short $+5
        jmp     near .no
        cmp     al,10
        jbe     short $+5
        jmp     near .no
        mov     ax,1
        jmp     .o
.no:    xor     ax,ax
.o:     pop     bp
        pop     ds
        ret     6

; ColSolid(px, ytop, height) -> AX = 1 if any of three sample points on
; the vertical line x=px (top+1, middle, bottom-2) is solid.     ret 8
ColSolid:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp

        push    bp
        mov     bp,sp
        push    bx
        mov     bx,[bp+10]
        inc     bx
        push word [bp+12]
        push    bx
        push    ds
        call    SolidAt
        test    ax,ax
        jz     short $+5
        jmp     near .out
        mov     bx,[bp+8]
        shr     bx,1
        add     bx,[bp+10]
        push word [bp+12]
        push    bx
        push    ds
        call    SolidAt
        test    ax,ax
        jz     short $+5
        jmp     near .out
        mov     bx,[bp+10]
        add     bx,[bp+8]
        sub     bx,2
        push word [bp+12]
        push    bx
        push    ds
        call    SolidAt
.out:   pop     bx
        pop     bp
        pop     ds
        ret     8

; RectOverlap(x1,y1,w1,h1, x2,y2,w2,h2) -> AX = 1 if they overlap  ret 18
RectOverlap:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp

        push    bp
        mov     bp,sp
        push    bx
        xor     ax,ax
        mov     bx,[bp+22]
        add     bx,[bp+18]
        cmp     [bp+14],bx
        jl     short $+5
        jmp     near .no
        mov     bx,[bp+14]
        add     bx,[bp+10]
        cmp     [bp+22],bx
        jl     short $+5
        jmp     near .no
        mov     bx,[bp+20]
        add     bx,[bp+16]
        cmp     [bp+12],bx
        jl     short $+5
        jmp     near .no
        mov     bx,[bp+12]
        add     bx,[bp+8]
        cmp     [bp+20],bx
        jl     short $+5
        jmp     near .no
        inc     ax
.no:    pop     bx
        pop     bp
        pop     ds
        ret     18

; =====================================================================
;  MODULE 9 : player movement and physics   (+ MODULE 10 tile collision)
; =====================================================================
UpdateMario:
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
        push    ds
        call    TryGrow
        mov     ax,[my]
        add     ax,[mh]
        mov     [pfeet],ax              ; feet of the previous frame (stomp test)
        ; ---- horizontal acceleration / friction / braking
        xor     bx,bx
        cmp     byte [keys+K_LEFT],0
        jne     short $+5
        jmp     near .nl
        dec     bx
.nl:    cmp     byte [keys+K_RIGHT],0
        jne     short $+5
        jmp     near .nr
        inc     bx
.nr:    cmp     byte [keys+K_LEFT],0
        jne     short $+5
        jmp     near .direction
        cmp     byte [keys+K_RIGHT],0
        jne     short $+5
        jmp     near .direction
        mov     bx,1
        cmp     byte [lastdir],0
        jne     short $+5
        jmp     near .direction
        mov     bx,-1
.direction:
        mov     cx,MAXWALK
        cmp     byte [keys+K_SHIFT],0
        jne     short $+5
        jmp     near .ms
        mov     cx,MAXRUN
.ms:    mov     ax,[vx]
        test    bx,bx
        jnz     short $+5
        jmp     near .fric
        jns     short $+5
        jmp     near .left
        mov     byte [face],0
        test    ax,ax
        jns     short $+5
        jmp     near .brkr
        add     ax,ACC
        cmp     ax,cx
        jg     short $+5
        jmp     near .store
        mov     ax,cx
        jmp     .store
.brkr:  add     ax,BRAKE
        jmp     .store
.left:  mov     byte [face],1
        neg     cx
        test    ax,ax
        jle     short $+5
        jmp     near .brkl
        sub     ax,ACC
        cmp     ax,cx
        jl     short $+5
        jmp     near .store
        mov     ax,cx
        jmp     .store
.brkl:  sub     ax,BRAKE
        jmp     .store
.fric:  test    ax,ax
        jnz     short $+5
        jmp     near .store
        jns     short $+5
        jmp     near .fneg
        sub     ax,FRIC
        js     short $+5
        jmp     near .store
        xor     ax,ax
        jmp     .store
.fneg:  add     ax,FRIC
        jns     short $+5
        jmp     near .store
        xor     ax,ax
.store: mov     [vx],ax
        ; ---- jump (ground only, no auto-repeat) / variable jump height
        cmp     byte [keys+K_SPACE],0
        je     short $+5
        jmp     near .sp
        mov     byte [jlatch],0
        cmp     word [vy],JUMPCUT
        jl     short $+5
        jmp     near .grav
        mov     word [vy],JUMPCUT       ; key released while rising fast
        jmp     .grav
.sp:    cmp     byte [jlatch],0
        je     short $+5
        jmp     near .grav
        cmp     byte [onground],0
        jne     short $+5
        jmp     near .grav
        mov     word [vy],JUMPV
        mov     byte [onground],0
        mov     byte [jlatch],1
.grav:  mov     ax,[vy]
        add     ax,GRAV
        cmp     ax,MAXFALL
        jg     short $+5
        jmp     near .gs
        mov     ax,MAXFALL
.gs:    mov     [vy],ax