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
; =====================================================================
;  MODULE 12 : blocks, coins, power-ups
; =====================================================================
; Spawn(type, x, y) : create a dynamic entity in a free slot      ret 8
Spawn:
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
        mov     bx,ents+ENTDYN*ESIZE
        mov     cx,ENTN-ENTDYN
.f:     cmp     byte [bx+E_TYPE],0
        jne     short $+5
        jmp     near .got
        add     bx,ESIZE
        loop    $+4
        jmp     short $+5
        jmp     near .f
        jmp     .out
.got:   mov     di,bx
        xor     ax,ax
        mov     cx,ESIZE/2
        rep     stosw
        mov     al,[bp+12]
        mov     [bx+E_TYPE],al
        mov     byte [bx+E_STATE],ES_WALK
        mov     ax,[bp+10]
        mov     [bx+E_X],ax
        mov     ax,[bp+8]
        mov     [bx+E_Y],ax
        mov     word [bx+E_TIMER],24    ; (coin pop lifetime)
.out:   pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     bp
        pop     ds
        ret     8

; HitBlock(px, py) : Mario's head hit the tile under (px,py)      ret 6
HitBlock:
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
        mov     di,[bp+8]
        shr     di,1
        shr     di,1
        shr     di,1
        shr     di,1                    ; row
        mov     cx,[bp+10]
        shr     cx,1
        shr     cx,1
        shr     cx,1
        shr     cx,1                    ; column
        mov     ax,di
        mov     bx,LVLW
        mul     bx
        add     ax,cx
        mov     si,ax                   ; map index
        mov     al,[wrkmap+si]
        cmp     al,2
        jne     short $+5
        jmp     near .brick
        cmp     al,3
        jne     short $+5
        jmp     near .qcoin
        cmp     al,4
        jne     short $+5
        jmp     near .qmush
        jmp     .end
.brick: cmp     byte [form],0           ; Small Mario only bumps it
        jne     short $+5
        jmp     near .end
        mov     byte [wrkmap+si],0
        PUSHI   50
        push    ds
        call    AddScore
        jmp     .end
.qcoin: mov     byte [wrkmap+si],5
        PUSHI   200
        push    ds
        call    AddScore
        push    ds
        call    AddCoin
        PUSHI   ET_POP
        mov     ax,cx
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        push    ax
        mov     ax,di
        dec     ax
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        push    ax
        push    ds
        call    Spawn
        jmp     .end
.qmush: mov     byte [wrkmap+si],5
        PUSHI   ET_MUSH
        mov     ax,cx
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        push    ax
        mov     ax,di
        dec     ax
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        push    ax
        push    ds
        call    Spawn
.end:   pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     bp
        pop     ds
        ret     6

; TileProbe(x, y) : coin tiles are collected, flag tiles set flagfound ret 6
TileProbe:
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
        push word [bp+10]
        push word [bp+8]
        push    ds
        call    GetTile
        cmp     al,11
        jne     short $+5
        jmp     near .coin
        cmp     al,12
        jne     short $+5
        jmp     near .flag
        cmp     al,13
        jne     short $+5
        jmp     near .flag
        jmp     .end
.coin:  mov     ax,[bp+8]
        shr     ax,1
        shr     ax,1
        shr     ax,1
        shr     ax,1
        mov     bx,LVLW
        mul     bx
        mov     bx,[bp+10]
        shr     bx,1
        shr     bx,1
        shr     bx,1
        shr     bx,1
        add     bx,ax
        mov     byte [wrkmap+bx],0
        PUSHI   200
        push    ds
        call    AddScore
        push    ds
        call    AddCoin
        jmp     .end
.flag:  mov     byte [flagfound],1
        mov     ax,[bp+10]
        shr     ax,1
        shr     ax,1
        shr     ax,1
        shr     ax,1
        mov     [flagcol],ax
.end:   pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     bp
        pop     ds
        ret     6