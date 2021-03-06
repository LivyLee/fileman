#include "kernel.inc"
#include "corelib.inc"
#include "config.inc"
    .db "KEXC"
    .db KEXC_ENTRY_POINT
    .dw start
    .db KEXC_STACK_SIZE
    .dw 100
    .db KEXC_KERNEL_VER
    .db 0, 6
    .db KEXC_NAME
    .dw window_title
    .db KEXC_HEADER_END
window_title:
    .db "File Manager", 0
start:
    pcall(getLcdLock)
    pcall(getKeypadLock)

    kld(de, corelibPath)
    pcall(loadLibrary)
    kld(de, configlibPath)
    pcall(loadLibrary)

    kcall(loadConfiguration)

    pcall(allocScreenBuffer)
    pcall(clearBuffer)

    ; Set current path
    ld bc, 512
    pcall(malloc)
    push ix \ pop de
    push de
        kld(hl, (config_initialPath))
        pcall(strlen)
        inc bc
        ldir
        dec de \ dec de
        ex de, hl
        ld a, '/'
        cp (hl)
        jr z, _
        inc hl
        ld (hl), a
        xor a
        inc hl
        ld (hl), a
_:      ex de, hl
    pop de
    ex de, hl
    kld((currentPath), hl)
    ex de, hl
    pcall(directoryExists)
    jr z, _
    ; Move us back to / cause this doesn't exist
    ex de, hl
    ld a, '/'
    ld (hl), a
    inc hl
    xor a
    ld (hl), a
    dec hl
    push hl
    push de
        xor a
        ld b, a
        kld(hl, startNotFound)
        kld(de, openFailOptions)
        corelib(showMessage)
    pop de
    pop hl

_:  ; Allocate space for fileList and directoryList
    ld bc, 512 ; Max 256 subdirectories and 256 files per directory
    pcall(malloc)
    corelib(showErrorAndQuit)
    push ix \ pop hl
    kld((clipboard), hl)
    pcall(malloc)
    corelib(showErrorAndQuit)
    push ix \ pop hl
    kld((fileList), hl)
    pcall(malloc)
    corelib(showErrorAndQuit)
    push ix \ pop hl
    kld((directoryList), hl)

browse_loop:
    kcall(doListing)
browse_loop_draw:
    kcall(drawList)
    xor a
    kld(hl, tabs)
    corelib(drawTabs)
    ; Save list length
    push bc
        ld a, b
        add c
        ld b, 0
        ld c, a
        jr nc, $+3
        inc b
        push bc ; Save total length (dirs+files)
            ld hl, 0
            pcall(cpHLBC)
            jr z, browse_idle

            kcall(drawChrome)

            kld(a, (scrollOffset))
            ld d, a ; Index

browse_idle:
            pcall(fastCopy)
            pcall(flushKeys)
            corelib(appWaitKey)
            jr nz, browse_idle

            cp kMode
            kjp(z, .exit)
            ld hl, 0
            pcall(cpHLBC)
            jr z, browse_idle

            cp kDown
            kjp(z, .handleDown)
            cp kUp
            kjp(z, .handleUp)
            cp kLeft
            kjp(z, .handleParent)
            cp kClear
            kjp(z, .handleParent)
            cp kEnter
            kjp(z, .handleEnter)
            cp k2nd
            kjp(z, .handleEnter)
            cp kRight
            kjp(z, .handleDetails)
            cp kSTAT
            kjp(z, .handleDetails)
            cp kDel
            kjp(z, .handleDelete)
            cp kF3
            kjp(z, .handleMenu)
            jr browse_idle
.handleDetails:
        pop bc
    pop bc \ push bc
        kcall(details_loop)
    pop bc
    kjp(browse_loop_draw)
.handleDown:
        pop bc
        ld a, d
        inc a
        cp c
        push bc
            ld c, 87
            ld b, 7
            jr nc, browse_idle
            ld a, d
            push hl
                kld(hl, scrollTop)
                sub (hl)
            pop hl
            cp 6
            jr z, .tryScrollDown
            push de
                ld d, a
                add a, a
                add a, a
                add a, d
                add a, d ; A *= 6
                add a, 14
            pop de
            ld l, a
            dec b
            pcall(rectXOR)
            add a, 6
            ld l, a
            pcall(rectXOR)
            inc d
            ld a, d
            kld((scrollOffset), a)
            kjp(browse_idle)
.tryScrollDown:
            inc d
            ld a, d
            kld((scrollOffset), a)
            kld(hl, scrollTop)
            inc (hl)
        pop bc
    pop bc
    kjp(browse_loop_draw)
.handleUp:
            ld a, d
            or a
            kjp(z, browse_idle)
            push hl
                kld(hl, scrollTop)
                sub (hl)
            pop hl
            or a ; cp 0
            jr z, .tryScrollUp
            push de
                ld d, a
                add a, a
                add a, a
                add a, d
                add a, d ; A *= 6
                add a, 14
            pop de
            ld l, a
            ld b, 6
            pcall(rectXOR)
            sub a, 6
            ld l, a
            pcall(rectXOR)
            dec d
            ld a, d
            kld((scrollOffset), a)
            kjp(browse_idle)
.tryScrollUp:
            dec d
            ld a, d
            kld((scrollOffset), a)
            kld(hl, scrollTop)
            dec (hl)
        pop bc
    pop bc
    kjp(browse_loop_draw)
.handleEnter:
        pop bc
    pop bc
    ; Determine if it's a file or a directory
    ld a, d
    cp b
    kjp(nc, action_open)
    ; Handle directory
    add a, a
    kld(hl, (directoryList))
    add l
    ld l, a
    jr nc, $+3
    inc h
    ld e, (hl)
    inc hl
    ld d, (hl)
    inc de \ inc de ; Skip icon
    ld a, (de)
    cp '.'
    kjp(z, .handleParent_noPop)
    kld(hl, (currentPath))
    xor a
    ld bc, 0
    cpir
    dec hl
    ex de, hl
    pcall(strlen)
    inc bc
    ldir
    ex de, hl
    dec hl
    ld a, '/' ; Add trailing slash
    ld (hl), a
    inc hl
    xor a
    ld (hl), a
    kjp(freeAndLoopBack)
.handleDelete:
        pop bc
    pop bc
    kjp(action_delete)
.exit:
        pop bc
    pop bc
    ret
.handleMenu:
        pop bc
    pop bc
    kjp(action_menu)
.handleParent:
        pop bc
    pop bc
.handleParent_noPop:
    kld(hl, (currentPath))
    push hl \ pop de
    pcall(strlen)
    add hl, bc
    ld a, '/'
    ld bc, 0
    cpdr \ cpdr
    inc hl \ inc hl
    pcall(cpHLDE)
    jr nz, _
    inc hl
_:  xor a
    ld (hl), a
    ;jr freeAndLoopBack

freeAndLoopBack:
    xor a
    kld((scrollTop), a)
    kld((scrollOffset), a)

    kld(a, (totalDirectories))
    or a
    jr z, +_
    ld b, a
    kld(hl, (directoryList))
.freeDirs:
    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl
    push de \ pop ix
    ld a, (ix)
    cp '.'
    pcall(nz, free)
    djnz .freeDirs
_:  kld(a, (totalFiles))
    or a
    kjp(z, browse_loop)
    ld b, a
    kld(hl, (fileList))
.freeFiles:
    ld e, (hl)
    inc hl
    ld d, (hl)
    inc hl
    push de \ pop ix
    pcall(free)
    djnz .freeFiles
    kjp(browse_loop)

; Variables
currentPath:
    .dw 0
fileList:
    .dw 0
directoryList:
    .dw 0
totalFiles:
    .db 0
totalDirectories:
    .db 0
scrollOffset:
    .db 0
scrollTop:
    .db 0
clipboard:
    .dw 0
tabs:
    .db 2
    .db "Browse", 0
    .db "Details", 0

#include "src/listing.asm"
#include "src/details.asm"
#include "src/draw.asm"
#include "src/actions.asm"
#include "src/settings.asm"
#include "src/constants.asm"
