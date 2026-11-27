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

        ; TileEffects : probe 6 points of Mario's hit box for coins / flag pole
TileEffects:
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
        mov     si,[mh]
        shr     si,1
        mov     bx,[mx]
        add     bx,2
        mov     cx,2
.xl:    push    bx
        mov     ax,[my]
        inc     ax
        push    ax
        push    ds
        call    TileProbe
        push    bx
        mov     ax,[my]
        add     ax,si
        push    ax
        push    ds
        call    TileProbe
        push    bx
        mov     ax,[my]
        add     ax,[mh]
        sub     ax,2
        push    ax
        push    ds
        call    TileProbe
        add     bx,11
        loop    $+4
        jmp     short $+5
        jmp     near .xl
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; Grow : Small -> Super, feet stay fixed (top moves up 16)
Grow:
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

        mov     byte [form],1
        mov     byte [hp],2
        mov     byte [growpending],1
        push    ds
        call    TryGrow
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; TryGrow(context): expand only when the added upper 16 pixels are clear.
; Under a low ceiling Super Mario keeps a short/crouched hitbox until clear.
; Feet never move; no solid tile is crossed. No register result.
TryGrow:
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
        cmp     byte [growpending],0
        jne     short $+5
        jmp     near .done
        mov     dx,[my]
        sub     dx,16
        mov     ax,[mx]
        add     ax,2
        push    ax
        push    dx
        PUSHI   16
        push    ds
        call    ColSolid
        test    ax,ax
        jz     short $+5
        jmp     near .done
        mov     ax,[mx]
        add     ax,13
        push    ax
        push    dx
        PUSHI   16
        push    ds
        call    ColSolid
        test    ax,ax
        jz     short $+5
        jmp     near .done
        mov     [my],dx
        mov     word [mh],32
        mov     byte [growpending],0
.done:  pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; Hurt : enemy contact.  Super -> Small (+2 s invulnerability), Small dies
Hurt:
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

        cmp     byte [form],0
        jne     short $+5
        jmp     near .die
        mov     byte [form],0
        mov     byte [hp],1
        mov     ax,[mh]
        sub     ax,16
        add     [my],ax                 ; crouched Super already has height 16
        mov     word [mh],16
        mov     byte [growpending],0
        mov     word [invuln],INVULN
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2
.die:   mov     byte [deathreq],1
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
;  MODULE 11 : enemies, shells, mushrooms
; =====================================================================
; EntBlocked(ptr) -> AX=1 if another walking enemy / still shell is in
; the way (used for "turns around at other enemies").            ret 4
EntBlocked:
        ; Last stack input: context segment. Callee removes it and other inputs.
        push    ds
        push    bp
        mov     bp,sp
        mov     ds,[bp+6]
        pop     bp

        push    bp
        mov     bp,sp
        push    bx
        push    cx
        push    si
        mov     si,[bp+8]
        mov     bx,ents
        mov     cx,ENTN
.l:     cmp     bx,si
        jne     short $+5
        jmp     near .n
        mov     al,[bx+E_TYPE]
        cmp     al,ET_GOOMBA
        jae     short $+5
        jmp     near .n
        cmp     al,ET_KOOPA
        jbe     short $+5
        jmp     near .n
        mov     al,[bx+E_STATE]
        cmp     al,ES_WALK
        jne     short $+5
        jmp     near .chk
        cmp     al,ES_SHELL
        je     short $+5
        jmp     near .n
.chk:   mov     ax,[bx+E_X]
        sub     ax,[si+E_X]
        js     short $+5
        jmp     near .a1
        neg     ax
.a1:    cmp     ax,14
        jl     short $+5
        jmp     near .n
        mov     ax,[bx+E_Y]
        sub     ax,[si+E_Y]
        js     short $+5
        jmp     near .a2
        neg     ax
.a2:    cmp     ax,12
        jl     short $+5
        jmp     near .n
        mov     ax,1
        jmp     .out
.n:     add     bx,ESIZE
        loop    $+4
        jmp     short $+5
        jmp     near .l
        xor     ax,ax
.out:   pop     si
        pop     cx
        pop     bx
        pop     bp
        pop     ds
        ret     4

; ShellKill(ptr) : a sliding shell removes every enemy it touches (+500)
ShellKill:
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
        mov     si,[bp+8]
        mov     bx,ents
        mov     cx,ENTN
.l:     cmp     bx,si
        jne     short $+5
        jmp     near .n
        mov     al,[bx+E_TYPE]
        cmp     al,ET_GOOMBA
        jae     short $+5
        jmp     near .n
        cmp     al,ET_KOOPA
        jbe     short $+5
        jmp     near .n
        cmp     byte [bx+E_STATE],ES_WAIT
        jne     short $+5
        jmp     near .n
        cmp     byte [bx+E_STATE],ES_FLAT
        jne     short $+5
        jmp     near .n
        push word [si+E_X]
        push word [si+E_Y]
        PUSHI   16
        PUSHI   16
        push word [bx+E_X]
        push word [bx+E_Y]
        PUSHI   16
        PUSHI   16
        push    ds
        call    RectOverlap
        test    ax,ax
        jnz     short $+5
        jmp     near .n
        mov     byte [bx+E_TYPE],0
        PUSHI   500
        push    ds
        call    AddScore
.n:     add     bx,ESIZE
        dec     cx
        jz     short $+5
        jmp     near .l
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     bp
        pop     ds
        ret     4

; EntStep(ptr) : one frame of gravity + walking for one record    ret 4
EntStep:
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
        mov     bx,[bp+8]
        cmp     byte [bx+E_STATE],ES_FLAT
        je     short $+5
        jmp     near .nf
        dec     word [bx+E_TIMER]       ; flat Goomba disappears after ~1 s
        jz     short $+5
        jmp     near .ret
        mov     byte [bx+E_TYPE],0
        jmp     .ret
.nf:    cmp     word [bx+E_TIMER],0
        jne     short $+5
        jmp     near .t0
        dec     word [bx+E_TIMER]       ; kick grace counter
.t0:    ; ---- gravity
        mov     ax,[bx+E_VY]
        add     ax,GRAV
        cmp     ax,MAXFALL
        jg     short $+5
        jmp     near .gok
        mov     ax,MAXFALL
.gok:   mov     [bx+E_VY],ax
        mov     al,[bx+E_VY]
        add     [bx+E_YF],al
        mov     al,[bx+E_VY+1]
        cbw
        adc     [bx+E_Y],ax
        cmp     word [bx+E_Y],200       ; fell out of the map
        jge     short $+5
        jmp     near .inmap
        mov     byte [bx+E_TYPE],0
        jmp     .ret
.inmap: mov     ax,[bx+E_VY]
        test    ax,ax
        jns     short $+5
        jmp     near .vend
        mov     dx,[bx+E_Y]
        add     dx,16
        mov     ax,[bx+E_X]
        add     ax,3
        push    ax
        push    dx
        push    ds
        call    SolidAt
        test    ax,ax
        jz     short $+5
        jmp     near .land
        mov     ax,[bx+E_X]
        add     ax,12
        push    ax
        push    dx
        push    ds
        call    SolidAt
        test    ax,ax
        jnz     short $+5
        jmp     near .vend
.land:  mov     ax,dx
        shr     ax,1
        shr     ax,1
        shr     ax,1
        shr     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        shl     ax,1
        sub     ax,16
        mov     [bx+E_Y],ax
        mov     byte [bx+E_YF],0
        mov     word [bx+E_VY],0
.vend:  cmp     byte [bx+E_STATE],ES_SHELL
        jne     short $+5
        jmp     near .ret                    ; a still shell does not walk
        ; ---- horizontal speed by kind
        mov     dx,SPD_GOOMBA
        mov     al,[bx+E_TYPE]
        cmp     al,ET_KOOPA
        je     short $+5
        jmp     near .t1
        mov     dx,SPD_KOOPA
        cmp     byte [bx+E_STATE],ES_SLIDE
        je     short $+5
        jmp     near .spd
        mov     dx,SPD_SHELL
        jmp     .spd
.t1:    cmp     al,ET_MUSH
        je     short $+5
        jmp     near .spd
        mov     dx,SPD_MUSH
.spd:   cmp     byte [bx+E_DIR],0
        jne     short $+5
        jmp     near .dok
        neg     dx
.dok:   mov     si,[bx+E_X]             ; remember old position
        mov     al,[bx+E_XF]
        xor     ah,ah
        mov     di,ax
        add     [bx+E_XF],dl
        mov     al,dh
        cbw
        adc     [bx+E_X],ax
        ; wall in front?
        mov     ax,[bx+E_X]
        cmp     byte [bx+E_DIR],0
        je     short $+5
        jmp     near .wl
        add     ax,15
.wl:    push    ax
        push word [bx+E_Y]
        PUSHI   16
        push    ds
        call    ColSolid
        test    ax,ax
        jz     short $+5
        jmp     near .blocked
        ; Koopa walking: turn at platform edges
        cmp     byte [bx+E_TYPE],ET_KOOPA
        je     short $+5
        jmp     near .noledge
        cmp     byte [bx+E_STATE],ES_WALK
        je     short $+5
        jmp     near .noledge
        cmp     word [bx+E_VY],0
        je     short $+5
        jmp     near .noledge
        mov     ax,[bx+E_X]
        cmp     byte [bx+E_DIR],0
        je     short $+5
        jmp     near .el
        add     ax,15
.el:    mov     dx,[bx+E_Y]
        add     dx,16
        push    ax
        push    dx
        push    ds
        call    SolidAt
        test    ax,ax
        jnz     short $+5
        jmp     near .blocked
.noledge:
        cmp     byte [bx+E_STATE],ES_SLIDE
        jne     short $+5
        jmp     near .slide
        cmp     byte [bx+E_TYPE],ET_MUSH
        jne     short $+5
        jmp     near .ret
        push    bx
        push    ds
        call    EntBlocked
        test    ax,ax
        jz     short $+5
        jmp     near .blocked
        jmp     .ret
.slide: push    bx
        push    ds
        call    ShellKill
        jmp     .ret
.blocked:
        mov     [bx+E_X],si             ; undo the step and turn around
        mov     ax,di
        mov     [bx+E_XF],al
        xor     byte [bx+E_DIR],1
.ret:   pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     bp
        pop     ds
        ret     4

; UpdateEnts : walk the whole entity table (activation, removal, step)
UpdateEnts:
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
        mov     bx,ents
        mov     cx,ENTN
.loop:  mov     al,[bx+E_TYPE]
        test    al,al
        jnz     short $+5
        jmp     near .next
        cmp     al,ET_POP
        jne     short $+5
        jmp     near .pop
        cmp     byte [bx+E_STATE],ES_WAIT
        je     short $+5
        jmp     near .active
        mov     ax,[camx]               ; wake up within one tile of the screen
        add     ax,SCRW+TILE
        cmp     [bx+E_X],ax
        jl     short $+5
        jmp     near .next
        mov     byte [bx+E_STATE],ES_WALK
        mov     byte [bx+E_DIR],1
.active:
        mov     ax,[camx]
        sub     ax,32
        cmp     [bx+E_X],ax             ; left behind: remove
        jge     short $+5
        jmp     near .remove
        push    bx
        push    ds
        call    EntStep
        jmp     .next
.pop:   dec     word [bx+E_TIMER]
        jnz     short $+5
        jmp     near .remove
        cmp     word [bx+E_TIMER],12
        ja     short $+5
        jmp     near .dn
        sub     word [bx+E_Y],3
        jmp     .next
.dn:    add     word [bx+E_Y],3
        jmp     .next
.remove:
        mov     byte [bx+E_TYPE],0
.next:  add     bx,ESIZE
        dec     cx
        jz     short $+5
        jmp     near .loop
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; ResolveEnts : Mario against enemies, shells and mushrooms (5.6 order)
ResolveEnts:
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
        mov     bx,ents
        mov     cx,ENTN
.loop:  mov     al,[bx+E_TYPE]
        cmp     al,ET_GOOMBA
        jae     short $+5
        jmp     near .next
        cmp     al,ET_MUSH
        jbe     short $+5
        jmp     near .next
        cmp     byte [bx+E_STATE],ES_WAIT
        jne     short $+5
        jmp     near .next
        cmp     byte [bx+E_STATE],ES_FLAT
        jne     short $+5
        jmp     near .next
        mov     ax,[mx]
        add     ax,2
        push    ax
        push word [my]
        PUSHI   12
        push word [mh]
        push word [bx+E_X]
        push word [bx+E_Y]
        PUSHI   16
        PUSHI   16
        push    ds
        call    RectOverlap
        test    ax,ax
        jnz     short $+5
        jmp     near .next
        cmp     byte [bx+E_TYPE],ET_MUSH
        jne     short $+5
        jmp     near .mush
        cmp     byte [bx+E_STATE],ES_SHELL
        jne     short $+5
        jmp     near .shell
        cmp     byte [bx+E_STATE],ES_SLIDE
        je     short $+5
        jmp     near .stomp?
        cmp     word [bx+E_TIMER],0     ; kick grace: ignore Mario
        je     short $+5
        jmp     near .next
.stomp?:
        mov     ax,[vy]                 ; stomp test: moving down and the
        test    ax,ax                   ; previous feet above upper half
        jg     short $+5
        jmp     near .side
        mov     ax,[bx+E_Y]
        add     ax,8
        cmp     [pfeet],ax
        jle     short $+5
        jmp     near .side
        cmp     byte [bx+E_TYPE],ET_GOOMBA
        je     short $+5
        jmp     near .kstomp
        mov     byte [bx+E_STATE],ES_FLAT
        mov     word [bx+E_TIMER],FPS
        jmp     .sdone
.kstomp:
        mov     byte [bx+E_STATE],ES_SHELL
        mov     word [bx+E_TIMER],0
.sdone: push    ds
        call    StompScore
        mov     word [vy],STOMPV
        cmp     byte [keys+K_SPACE],0
        jne     short $+5
        jmp     near .nb
        mov     word [vy],STOMPVH
.nb:    mov     ax,[bx+E_Y]
        sub     ax,[mh]
        mov     [my],ax
        mov     byte [myf],0
        mov     byte [onground],0
        jmp     .next
.side:  cmp     word [invuln],0
        je     short $+5
        jmp     near .next
        push    ds
        call    Hurt
        jmp     .next
.shell: cmp     word [bx+E_TIMER],0
        je     short $+5
        jmp     near .next
        mov     byte [bx+E_STATE],ES_SLIDE      ; kick
        mov     word [bx+E_TIMER],8
        mov     byte [bx+E_DIR],0
        mov     ax,[mx]
        add     ax,8
        mov     dx,[bx+E_X]
        add     dx,8
        cmp     ax,dx
        jge     short $+5
        jmp     near .kd
        mov     byte [bx+E_DIR],1
.kd:    PUSHI   400
        push    ds
        call    AddScore
        jmp     .next
.mush:  mov     byte [bx+E_TYPE],0
        PUSHI   1000
        push    ds
        call    AddScore
        cmp     byte [form],0
        je     short $+5
        jmp     near .next
        push    ds
        call    Grow
.next:  add     bx,ESIZE
        dec     cx
        jz     short $+5
        jmp     near .loop
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

; DrawHUD : top 16-pixel strip, fixed on screen
DrawHUD:
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
        FILL    0,0,320,16,0
        FILL    0,192,320,8,0
        TEXT    8,0,s_score,8,1
        TEXT    72,0,s_coins,8,1
        TEXT    128,0,s_world,8,1
        TEXT    184,0,s_time,8,1
        TEXT    224,0,s_lives,8,1
        TEXT    272,0,s_health,8,1
        NUM     8,8,word [score],word [score+2],6,10,1
        TEXT    72,8,s_x,10,1
        NUM     80,8,word [coins],0,2,10,1
        TEXT    128,8,s_11,10,1
        NUM     184,8,word [timeleft],0,3,10,1
        TEXT    224,8,s_x,10,1
        mov     ax,1
        cmp     word [lives],10
        jae     short $+5
        jmp     near .d1
        mov     ax,2
.d1:    NUM     232,8,word [lives],0,ax,10,1
        mov     ax,2                    ; heart 1: always red (HP>=1)
        PUSHI   272
        PUSHI   8
        PUSHI   3
        push    ax
        PUSHI   1
        push    ds
        call    DrawChar
        mov     ax,2                    ; heart 2: red if HP = 2 else grey
        cmp     byte [hp],2
        jb     short $+5
        jmp     near .h2
        mov     ax,14
.h2:    PUSHI   284
        PUSHI   8
        PUSHI   3
        push    ax
        PUSHI   1
        push    ds
        call    DrawChar
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

DrawTitle:
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
        cmp     byte [keys+K_T],0
        jne     short $+5
        jmp     near .norm
        push    ds
        call    DrawColorTest
        jmp     .done
.norm:  push    ds
        call    ClearFB
        FILL    16,152,288,8,6
        FILL    16,160,288,24,4
        xor     bx,bx
.bt:    PUSHI   2
        push    bx
        PUSHI   0
        push    ds
        call    DrawTileCode
        PUSHI   2
        push    bx
        PUSHI   184
        push    ds
        call    DrawTileCode
        add     bx,16
        cmp     bx,SCRW
        jae     short $+5
        jmp     near .bt
        mov     bx,16
.bs:    PUSHI   2
        PUSHI   0
        push    bx
        push    ds
        call    DrawTileCode
        PUSHI   2
        PUSHI   304
        push    bx
        push    ds
        call    DrawTileCode
        add     bx,16
        cmp     bx,176
        ja     short $+5
        jmp     near .bs
        PUSHI   40
        PUSHI   136
        PUSHI   Sprites
        PUSHI   0
        push    ds
        call    DrawSprite
        PUSHI   260
        PUSHI   136
        PUSHI   Sprites+7*256
        PUSHI   0
        push    ds
        call    DrawSprite
        TEXT    30,22,s_title1,5,3      ; drop shadow
        TEXT    28,20,s_title1,2,3
        TEXT    72,52,s_title2,10,2
        TEXT    24,74,s_hint,10,1
        BOX     60,88,200,56,10,0
        mov     ax,10
        mov     dx,10
        cmp     byte [menusel],0
        je     short $+5
        jmp     near .s1
        mov     ax,8
        jmp     .go
.s1:    mov     dx,8
.go:    TEXT    86,96,s_start,ax,2
        TEXT    86,120,s_exit,dx,2
        mov     ax,96
        cmp     byte [menusel],0
        jne     short $+5
        jmp     near .cu
        mov     ax,120
.cu:    TEXT    68,ax,s_cursor,8,2
        TEXT    40,168,s_team,8,1
.done:  pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

DrawLifeLost:
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
        FILL    0,0,320,200,0
        TEXT    52,36,s_world11,10,3
        PUSHI   100
        PUSHI   90
        PUSHI   Sprites
        PUSHI   0
        push    ds
        call    DrawSprite
        TEXT    140,92,s_x,10,3
        NUM     170,92,word [lives],0,1,10,3
        TEXT    80,140,s_liveslft,8,2
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

DrawGameOver:
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
        FILL    0,0,320,200,0
        BOX     24,16,272,168,2,0
        TEXT    52,56,s_over,2,3
        TEXT    72,104,s_final,10,1
        NUM     176,104,word [score],word [score+2],6,10,1
        TEXT    88,128,s_coinsc,8,1
        NUM     144,128,word [coins],0,2,8,1
        TEXT    176,128,s_timec,8,1
        NUM     224,128,word [timeleft],0,3,8,1
        TEXT    60,156,s_pressT,6,1
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

DrawDone:
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
        FILL    0,0,320,200,16
        BOX     16,12,288,150,8,16
        TEXT    40,28,s_lvl,8,2
        TEXT    48,64,s_score,10,1
        NUM     150,64,word [prescore],word [prescore+2],6,10,1
        TEXT    48,80,s_coins,10,1
        TEXT    150,80,s_x,10,1
        NUM     166,80,word [coins],0,2,10,1
        TEXT    48,96,s_tl,10,1
        NUM     150,96,word [timeleft],0,3,10,1
        TEXT    182,96,s_x50,10,1
        NUM     238,96,word [bonus],0,5,10,1
        TEXT    48,112,s_tb,10,1
        TEXT    150,112,s_plus,10,1
        NUM     166,112,word [bonus],0,5,10,1
        TEXT    48,132,s_fs,8,1
        NUM     150,132,word [score],word [score+2],6,8,1
        TEXT    48,164,s_cont,6,1
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2

DrawPauseBox:
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
        BOX     80,76,160,48,10,0
        TEXT    112,84,s_paused,8,2
        TEXT    92,108,s_resume,10,1
        pop     di
        pop     si
        pop     bp
        pop     bx
        pop     dx
        pop     cx
        pop     ax
        pop     ds
        ret     2
