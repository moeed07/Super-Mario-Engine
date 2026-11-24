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
