; OWNER: 25F-0051 - enemies, items, score/health/HUD, menus and restart.
; Included by mario.asm; no ORG/BITS here. Rendering primitives are in mario.asm.
; Uses the shared constants/data and context-on-stack calling convention.
; =====================================================================
;  Score / coins / lives  (MODULE 13)
; =====================================================================
; AddScore(points) : 32-bit ADD/ADC, clamped to 999,999        ret 4
AddScore:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp
        push    bp
        mov     bp,sp
        push    ax
        mov     ax,[bp+8]
        add     [score],ax
        adc     word [score+2],0
        cmp     word [score+2],0Fh
        jae     short $+5
        jmp     near .ok
        jbe     short $+5
        jmp     near .clamp
        cmp     word [score],423Fh
        ja     short $+5
        jmp     near .ok
.clamp: mov     word [score+2],0Fh
        mov     word [score],423Fh
.ok:    pop     ax
        pop     bp
        pop     ds
        ret     4
; AddLife : lives + 1 (max 99)
AddLife:
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

        cmp     word [lives],99
        jb     short $+5
        jmp     near .r
        inc     word [lives]
.r:     pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; AddCoin : coins + 1, every 100 coins = extra life, counter back to 0
AddCoin:
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
        inc     word [coins]
        cmp     word [coins],100
        jae     short $+5
        jmp     near .r
        mov     word [coins],0
        push    ds
        call    AddLife
.r:     pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; StompScore : points for the next stomp of the current jump
;              (chain table of section 5.4, 11th stomp = 1-UP)
StompScore:
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
        push    bx
        xor     bx,bx
        mov     bl,[chain]
        cmp     bl,10
        jb     short $+5
        jmp     near .up
        shl     bx,1
        push word [stomptab+bx]
        push    ds
        call    AddScore
        jmp     .inc
.up:    push    ds
        call    AddLife
.inc:   cmp     byte [chain],11
        jb     short $+5
        jmp     near .r
        inc     byte [chain]
.r:     pop     bx
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2
