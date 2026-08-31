; Disassembly of "Metroid2.gb"
; This file was created with:
; mgbdis v1.4 - Game Boy ROM disassembler by Matt Currie and contributors.
; https://github.com/mattcurrie/mgbdis

SECTION "ROM Bank $003", ROMX[$4000], BANK[$3]

handleEnemyLoading: ;{ 03:4000
    call loadEnemies
    ; Update scroll history
    ; y2 <= y1
    ld hl, scrollHistory_B.y1
    ld a, [hl-]
    ld [hl+], a
    ; y1 <= y0
    ld a, [scrollY]
    ld [hl+], a
    ; x2 <= x1
    inc l
    ld a, [hl-]
    ld [hl+], a
    ; x1 <= x0
    ld a, [scrollX]
    ld [hl], a
ret ;}

; Handles loading enemies from the map
;  Alternates between vertical and horizontal checks
;  Has some weird optimizations that make certain assumptions of the underlying order of the data
loadEnemies: ;{ 03:4014
    ; Load y pixel to L
    ld de, hCameraYPixel
    ld a, [de]
    ld l, a
    ; Load y screen to H
    inc e
    ld a, [de]
    ld h, a
    push hl
        ; Get bottom edge of the visible screen, rounded to the nearest block
        ld bc, SCREEN_HEIGHT_PX/2 + $10 + OAM_Y_OFS ;$0068
        add hl, bc
        ld a, l
        and $100 - OAM_Y_OFS
        ld [bottomEdge_pixel], a
        ld a, h
        ld [bottomEdge_screen], a
    pop hl
    ; Get top edge of visible screen, rounded to the nearest block
    ld bc, -SCREEN_HEIGHT_PX/2 - $10 ;$ffa8
    add hl, bc
    ld a, l
    and $100 - OAM_Y_OFS
    ld [topEdge_pixel], a
    ld a, h
    ld [topEdge_screen], a
    
    ; Load x pixel to L
    inc e
    ld a, [de]
    ld l, a
    ; Load x screen to H
    inc e
    ld a, [de]
    ld h, a
    push hl
        ; Get right edge of the visible screen, rounded to the nearest tile
        ld bc, SCREEN_WIDTH_PX/2 + $10 + OAM_X_OFS ;$0068
        add hl, bc
        ld a, l
        and $100 - OAM_X_OFS
        ld [rightEdge_pixel], a
        ld a, h
        ld [rightEdge_screen], a
    pop hl
    ; Get left edge of the visible screen, rounded to the nearest tile
    ld bc, -SCREEN_WIDTH_PX/2 - $10 ;$ffa0
    add hl, bc
    ld a, l
    and $100 - OAM_X_OFS
    ld [leftEdge_pixel], a
    ld a, h
    ld [leftEdge_screen], a
    
    ld d, $ff
    ; Prevent enemies from loading via vertical wraparound of the map
    ld a, [bottomEdge_screen]
    ld b, a
    and $0f
    jr nz, .endIf_A
        ld a, [topEdge_screen]
        ld c, a
        and $0f
        cp $0f
        jr nz, .endIf_A
            ; We get to this point if the bottom edge of the camera is on the top map screen
            ;  and the top edge of the camera on the bottom map screen.
            
            ; Check if the center of the camera is above or below the seam
            ld a, [hCameraYScreen]
            cp b
            jr z, .else_B
                ; Clamp bottom edge of camera to the bottom edge of the map
                ld a, c ; C = topEdge_screen
                ld [bottomEdge_screen], a
                ld a, d ; D is $FF
                ld [bottomEdge_pixel], a
                jr .endIf_A
            .else_B:
                ; Clamp top edge of camera to the top edge of the map
                ld a, b ; B = bottomEdge_screen
                ld [topEdge_screen], a
                xor a
                ld [topEdge_pixel], a
    .endIf_A:

    ; Prevent enemies from loading via horizontal wraparound of the map
    ld a, [rightEdge_screen]
    ld b, a
    and $0f
    jr nz, .endIf_C
        ld a, [leftEdge_screen]
        ld c, a
        and $0f
        cp $0f
        jr nz, .endIf_C
            ; We get to this point if the right edge of the camera is on the leftmost map screen
            ;  and the left edge of the camera on the rightmost map screen.
        
            ; Check if the center of the camera is to the left or right of the seam
            ld a, [hCameraXScreen]
            cp b
            jr z, .else_D
                ; Clamp right edge of camera to the right edge of the map
                ld a, c ; C = leftEdge_screen
                ld [rightEdge_screen], a
                ld a, d ; D is $FF
                ld [rightEdge_pixel], a
                jr .endIf_C
            .else_D:
                ; Clamp left edge of the camera to the left edge of the map
                ld a, b ; B = rightEdge_screen
                ld [leftEdge_screen], a
                xor a
                ld [leftEdge_pixel], a
    .endIf_C:

    ; Switch between loading enemies horizontally and vertically every frame
    ld hl, loadEnemies_oscillator
    ld a, [hl]
    xor $01
    ld [hl], a
jp z, loadEnemies_horizontal ;}

; Vertical case to the above function
loadEnemies_vertical: ;{ 03:40BE
    ; Compare scroll value between now and two frames ago, exit if equal
    ld hl, scrollHistory_B.y2
    ld a, [scrollY]
    sub [hl]
        ret z

    jr c, .else_A
        ; Get bottom left corner
        ld a, $01
        ld [loadEnemies_unusedVar], a
        ld a, [bottomEdge_screen]
        ld b, a
        ld a, [leftEdge_screen]
        ld c, a
        ld a, [bottomEdge_pixel]
        ld [hTemp.a], a
        call loadEnemy_getBankOffset
        call loadEnemy_getPointer.screen
        jr .endIf_A
    .else_A:
        ; Get top-left corner
        ld a, $03
        ld [loadEnemies_unusedVar], a
        ld a, [topEdge_screen]
        ld b, a
        ld a, [leftEdge_screen]
        ld c, a
        ld a, [topEdge_pixel]
        ld [hTemp.a], a
        call loadEnemy_getBankOffset
        call loadEnemy_getPointer.screen
    .endIf_A:

; Check left screen {
    .left_nextEnemy:
        ; Load sprite number, move on to next screen if $FF
        ld a, [hl]
        cp $ff
            jr z, .checkRightScreen
        ; Load sprite number (again, this time incrementing HL to sprite type)
        ld a, [hl+]
        ld e, a
        ; Check if spawn flag is active or dead
        ld d, HIGH(enemySpawnFlags)
        ld a, [de]
        cp $fe
            jr nc, .left_loadEnemy
        inc hl ; Set HL to xpos
      .left_skipY:
        inc hl ; Set HL to ypos
      .left_skipToNext:
        inc hl ; Set HL to next enemy
    jr .left_nextEnemy

.left_loadEnemy:
    ; Load x
    inc hl
    ld a, [hl]
    and $100 - OAM_X_OFS ; Clamp to nearest tile
    ld e, a
    ; Compare with left edge of screen
    ld a, [leftEdge_pixel]
    cp e ; Skip to next enemy if it is not to the right side of the seam
        jr nc, .left_skipY
    ld d, a
    
    ; If the right edge pixel value has a greater value than the left edge pixel value
    ;  (i.e. the camera does not cross a screen boundary)
    ; AND the enemy x pixel is to the right of the right edge of the screen
    ;  then exit
    ld a, [rightEdge_pixel]
    cp d
    jr c, .endIf_B
        cp e
        ret c
    .endIf_B:
    
    ; Load y
    inc hl
    ld a, [hl]
    and $100 - OAM_Y_OFS ; Clamp to nearest block
    ld e, a
    ; If the clamped enemy Y equals the clamped camera Y
    ;  then load the enemy
    ld a, [hTemp.a]
    cp e
    jr z, .endIf_C
        jr .left_skipToNext
    .endIf_C:
    
    call loadOneEnemy
jr .left_skipToNext ;}

.checkRightScreen: ;{
    ; Iterate to next screen lazily, by assuming its enemy data is contiguous with the previous
    inc hl
    ; Compare left screen to right screen
    ld a, [rightEdge_screen]
    cp c
        ret z ; Exit if they are equal
        ret c ; Exit if there is wraparound

    .right_nextEnemy:
        ; Load sprite number, move on to next screen if $FF
        ld a, [hl]
        cp $ff
            ret z
        ; Load sprite number (again, this time incrementing HL to sprite type)
        ld a, [hl+]
        ld e, a
        ; Check if spawn flag is active or dead
        ld d, HIGH(enemySpawnFlags)
        ld a, [de]
        cp $fe
            jr nc, .right_loadEnemy
        inc hl ; Set HL to xpos
        inc hl ; Set HL to ypos
      .right_skipToNext:
        inc hl ; Set HL to next enemy
    jr .right_nextEnemy

.right_loadEnemy:
    ; Load x pos
    inc hl
    ld a, [hl]
    and $100 - OAM_X_OFS ; Clamp to nearest tile
    ld e, a
    ld a, [rightEdge_pixel]
    cp e ; Exit if enemy is not to the left side of the right edge
        ret c ; Why does this not go to .right_skipY like the previous case?
    
    ; Load y pos
    inc hl
    ld a, [hl]
    and $100 - OAM_Y_OFS ; Clamp to nearest block
    ld e, a
    ; If the clamped enemy Y equals the clamped camera Y
    ;  then load the enemy
    ld a, [hTemp.a]
    cp e
    jr z, .endIf_D
        jr .right_skipToNext
    .endIf_D:
    
    call loadOneEnemy
jr .right_skipToNext ;}
;} End vertical case

; Horizontal case to the above function
loadEnemies_horizontal: ;{ 03:416A
    ld hl, scrollHistory_B.x2
    ld a, [scrollX]
    sub [hl]
        ret z

    jr c, .else_A
        ; Get top-right corner
        ld a, $00
        ld [loadEnemies_unusedVar], a
        ld a, [topEdge_screen]
        ld b, a
        ld a, [rightEdge_screen]
        ld c, a
        ld [loadEnemy_unusedVar_B], a
        ld a, [rightEdge_pixel]
        ld [hTemp.a], a
        call loadEnemy_getBankOffset
        call loadEnemy_getPointer.screen
        jr .endIf_A
    .else_A:
        ; Get top-left corner
        ld a, $01
        ld [loadEnemies_unusedVar], a
        ld a, [topEdge_screen]
        ld b, a
        ld a, [leftEdge_screen]
        ld c, a
        ld a, [leftEdge_pixel]
        ld [hTemp.a], a
        call loadEnemy_getBankOffset
        call loadEnemy_getPointer.screen
    .endIf_A:

; Check top screen {
    .top_nextEnemy:
        ; Load sprite number, move on to next screen if $FF
        ld a, [hl]
        cp $ff
            jr z, .checkBottomScreen
        ; Load sprite number (again, this time incrementing HL to sprite type)
        ld a, [hl+]
        ld e, a
        ; Check if spawn flag is active or dead
        ld d, HIGH(enemySpawnFlags)
        ld a, [de]
        cp $fe
            jr nc, .top_loadEnemy
        inc hl ; Set HL to xpos
      .top_skipY:
        inc hl ; Set HL to ypos
      .top_skipToNext:
        inc hl ; Set HL to next enemy
    jr .top_nextEnemy

.top_loadEnemy:
    ; Load x pos
    inc hl
    ld a, [hl]
    and $100 - OAM_X_OFS ; Clamp to nearest tile
    ld e, a
    ; Compare enemy x to seam
    ld a, [hTemp.a]
    cp e
    jr z, .endIf_B ; If equal, try loading
        jr nc, .top_skipY ; If enemy is to the left of the seam, skip to next enemy
        jr .checkBottomScreen ; else (implicitly to the right), skip to the next screen
        ; (...that's a weird optimization that implies a certain spatial structuring to the data)
    .endIf_B:

    ; Load y pos
    inc hl
    ld a, [hl]
    and $100 - OAM_Y_OFS ; Clamp to nearest block
    ld e, a
    ; If y pos does not equal top edge, skip to next enemy
    ld a, [topEdge_pixel]
    cp e
    jr z, .endIf_C
        jr nc, .top_skipToNext
    .endIf_C:
    ld d, a
    
    ; If the bottom edge pixel value is greater than the top edge pixel value
    ;  (i.e a screen boundary is not being crossed)
    ; AND the enemy is below the bottom edge of the camera
    ;  then skip to the next enemy
    ld a, [bottomEdge_pixel]
    cp d
    jr c, .endIf_D
        cp e
        jr c, .top_skipToNext
    .endIf_D:

    ; Load enemy
    call loadOneEnemy
jr .top_skipToNext ;}

.checkBottomScreen: ;{
    ; Check if the bottom and top screen are the same, exit if so
    ld a, [topEdge_screen]
    ld b, a
    inc b
    ld a, [bottomEdge_screen]
    cp b
        ret nz
    ; Iterate to the bottom screen (properly)
    ld a, c
    ld [loadEnemy_unusedVar_A], a
    call loadEnemy_getBankOffset
    call loadEnemy_getPointer.screen

    .bottom_nextEnemy:
        ; Load sprite number, move on to next screen if $FF
        ld a, [hl]
        cp $ff
            ret z
        ; Load sprite number (again, this time incrementing HL to sprite type)
        ld a, [hl+]
        ld e, a
        ; Check if spawn flag is active or dead
        ld d, HIGH(enemySpawnFlags)
        ld a, [de]
        cp $fe
            jr nc, .bottom_loadEnemy
        inc hl ; Set HL to xpos
      .bottom_skipY:
        inc hl ; Set HL to ypos
      .bottom_skipToNext:
        inc hl ; Set HL to next enemy
    jr .bottom_nextEnemy

.bottom_loadEnemy:
    ; Load x pos
    inc hl
    ld a, [hl]
    and $100 - OAM_X_OFS ; Clamp to nearest tile
    ld e, a
    ; Compare camera x to enemy x
    ld a, [hTemp.a]
    cp e ; Exit if enemy is to the right of the seam
        ret c
    ; Skip to next enemy if positions aren't equal
    jr z, .endIf_E
        jr .bottom_skipY
    .endIf_E:
    
    ; Load y pos
    inc hl
    ld a, [hl]
    and $100 - OAM_Y_OFS ; Clamp to nearest block
    ld e, a
    ; Compare enemy y to camera y
    ld a, [bottomEdge_pixel]
    cp e
    ; Skip to next enemy if it is below the camera edge
    jr nc, .endIf_F
        jr .bottom_skipToNext
    .endIf_F:

    call loadOneEnemy
jr .bottom_skipToNext ;}
;} End horizontal case

; Load one enemy
loadOneEnemy: ;{ 03:422F
    push bc ; Save local vars from caller
    ; Transfer the enemy map data pointer to DE
    ld d, h
    ld e, l
    
    ; Get base address of enemy
    call loadEnemy_getFirstEmptySlot
    ld a, l
    ld [enemy_pWramLow], a
    ld a, h
    ld [enemy_pWramHigh], a
    ; Set status to active
    xor a
    ld [hl+], a
    
    push de ; Save the enemy map data pointer from caller

    ; Set enemy Y position, adjusting for camera position
    ld a, [scrollY]
    ld b, a
    ld a, [de] ; Load enemy y
    add OAM_Y_OFS
    sub b
    ld [hl+], a

    ; Set enemy X position, adjusting for camera position
    ld a, [scrollX]
    ld b, a
    dec de
    ld a, [de] ; Load enemy x
    add OAM_X_OFS
    sub b
    ld [hl+], a
    
    ; Load enemy sprite type
    dec de
    ld a, [de]
    ld [hl], a
    
    ; Load enemy spawn number
    ld a, l
    add $1a
    ld l, a
    dec de
    ld a, [de]
    ld [hl], a ; Write enemy spawn number to enemy entry in RAM

    ; Load enemy spawn flag
    ld hl, enemySpawnFlags
    ld l, a
    ld a, [hl]
    cp $ff ; Check if it has been seen before
    jr z, .else
        ; If flag was $FE, mark it as active and seen before
        ld a, $04
        ld [hl], a
        ld [loadEnemy_spawnFlagTemp], a
        jr .endIf
    .else:
        ; If flag was $FF, mark it as active and new
        ld a, $01
        ld [hl], a
        ld [loadEnemy_spawnFlagTemp], a
    .endIf:

    ; Reload enemy WRAM address (at the sprite type)
    ld a, [enemy_pWramLow]
    add $03
    ld l, a
    ld a, [enemy_pWramHigh]
    ld h, a
    ; Load sprite type
    ld a, [hl+]
    push hl
        ; Get pointer to header
        ld hl, enemyHeaderPointers
        call loadEnemy_getPointer.header
    pop hl

    ; Read enemy header (first 9 bytes)
    ld b, $09
    .loadLoop:
        ld a, [de]
        ld [hl+], a
        inc de
        dec b
    jr nz, .loadLoop
    ld c, a ; Save initial health to C
    
    ; Clear next 4 bytes (drop type, explosion flag, x/y screen coordinates)
    xor a
    ld b, $04
    .clearLoop:
        ld [hl+], a
        dec b
    jr nz, .clearLoop

    ; Load initial health to WRAM
    ld [hl], c

    ; Load enemy spawn flag
    ld a, [enemy_pWramLow]
    add $1c
    ld l, a
    ld a, [loadEnemy_spawnFlagTemp]
    ld [hl], a
    
    ; Load enemy AI pointer
    inc l
    inc l
    ld a, [de]
    ld [hl+], a
    inc de
    ld a, [de]
    ld [hl], a

    ; Increment number of enemies (total/active)
    ld hl, numEnemies.total
    inc [hl]
    inc l
    inc [hl]
    
    ; Restore the enemy map data pointer from the caller
    pop de
    ld l, e
    ld h, d
    pop bc ; Restore local variables from the caller
ret ;}

; returns pointer to first unused enemy slot in HL
; WARNING: Does not perform any bounds check
loadEnemy_getFirstEmptySlot: ;{ 03:42B4
    ld hl, enemyDataSlots
    ld bc, enemyDataSlotSize ; $0020
    .findLoop:
        ld a, [hl]
        cp $ff ; Exit with address if enemy is inactive
            ret z
        add hl, bc
    jr .findLoop
;}

; Returns the base offset for a bank's enemy data pointer in HL
loadEnemy_getBankOffset: ;{ 03:42C1
    ; HL = (levelBank-9)*$200
    ld hl, enemyDataPointers
    ld a, [currentLevelBank]
    sub $09 ; Adjust pointer to account for $9 being the first level bank
    add a
    ld d, a
    ld e, $00
    add hl, de
ret ;}

; Multiple entry points for loading an enemy map data pointer and and an enemy header pointer
;  Value is returned in both HL and DE
loadEnemy_getPointer:
  .screen: ;{ 03:42CF
    ; Get index from YX coordinate
    ;  B - y coordinate
    ;  C - x coordinate
    ld a, b
    swap a
    add c
; Given a base offset in hl and a pointer index in a, returns a pointer in hl
  .header: ; 03:42D3
    ; HL =+ A*2
    ld d, $00
    add a
    rl d
    ld e, a
    add hl, de
    ; HL = [HL]
    ld e, [hl]
    inc hl
    ld d, [hl]
    ld h, d
    ld l, e
ret ;}

; Enemy Data starts here
enemyDataPointers:
    include "maps/enemyData.asm"
; 03:6244 -- Enemy Data ends here
; Freespace filled with $00 (NOP)
DS $BC ;This fills freespace
enemyData_end: ;Label used by the LAMP Editor

SECTION "ROM Bank $003 Part 2", ROMX[$6300], BANK[$3]
enemyHeaderPointers: ; 03:6300 - Enemy headers
    include "data/enemy_headerPointers.asm"
    include "data/enemyHeaders.asm"
enemyDamageTable: ; 03:673A - Enemy damage values
    include "data/enemy_damageValues.asm"
enemyHitboxPointers: ; 03:6839 - Enemy hitboxes
    include "data/enemy_hitboxPointers.asm"
    include "data/enemyHitboxes.asm"

; Enemy AI stuff

; Deletes the enemy currently loaded in HRAM
enemy_deleteSelf: ;{ 03:6AE7
    ld hl, hEnemyWorkingHram ; $FFE0
    ; Save hEnemy.status to C
    ld c, [hl]
    ; Clear first 15 bytes of enemy data in HRAM
    ld a, $ff
    ld b, $0f
    .clearLoop:
        ld [hl+], a
        dec b
    jr nz, .clearLoop

    ; Read hEnemy.spawnFlag to see if enemy has a parent
    ld a, [hl]
    and $0f
    jr nz, .endIf_A
        ; Get address of parent object from link in hEnemy.spawnFlag
        ld a, [hl]
        ld h, HIGH(enemyDataSlots)
        bit 4, a
        jr nz, .else_B
            add $1c
            ld l, a
            jr .endIf_B
        .else_B:
            add $0c
            ld l, a
            inc h ; $C700 address
        .endIf_B:

        ; Check the enemy spawn flag of the parent
        ; If 3, set to 1
        ; If 5, set to 4
        ; Do this so their projectile-firing status is not saved
        ld a, [hl]
        cp $03 ; Has a child object
        jr z, .else_C
            cp $05 ; Has been seen before and has a child object
                jr nz, .endIf_A
            ld a, $04 ; Has been seen before
            jr .endIf_C
        .else_C:
            ld a, $01 ; Active
        .endIf_C:
        ld [hl+], a
        
        ld b, a
        ld a, [hl]
        ld hl, enemySpawnFlags
        ld l, a
        ld [hl], b
    .endIf_A:

    ; Clear enemy AI pointer, and screen coordinates
    ld hl, hEnemy.pAI_low
    ld a, $ff
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl], a
    ; Decrement number of total enemies and number of active enemies
    ld hl, numEnemies.total
    dec [hl]
    inc l
    dec [hl]
    ; Check if [enSprCollision.pEnemyHigh] = [$FFFD]
    ld hl, enSprCollision.pEnemyHigh
    ld de, hEnemyWramAddrHigh
    ld a, [de]
    cp [hl]
        ret nz
    ; Check if [enSprCollision.pEnemyLow] = [$FFFE]
    dec e
    dec l
    ld a, [de]
    cp [hl]
        ret nz
    ; Clear enSprCollision.weaponType, etc. ($C466, $C467, $C468, $C469)
    dec l
    ld a, $ff
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl], a
ret ;}

; Used for seeking towards Samus
; takes B, D, and E as arguements
; $E9 and $EA form a directional vector (centered at $10, $10)
;
; Caller arguments
;        B   D   E
; Zeta  $02 $20 $00
; Omega $02 $20 $00
; Larva $01 $1E $02
; Baby  $02 $20 $00
; D is the maximum for $E9/$EA
; E is the minimum for $E9/$EA
; B is the movement step in the table (acceleration, basically)
;
; Caller functions should validate the movement afterwards to make sure it doesn't clip into anything.
enemy_seekSamus: ;{ 03:6B44
    ; Load Samus/Enemy positions to adjusted temp variables
    ld hl, seekSamusTemp.samusX
    ld a, [samus_onscreenXPos]
    add $10
    ld [hl-], a
    ld a, [samus_onscreenYPos]
    add $10
    ld [hl-], a
    ldh a, [hEnemy.xPos]
    add $10
    ld [hl-], a
    ldh a, [hEnemy.yPos]
    add $10
    ld [hl], a
    
    ; Compare Y positions to modify Y component of vector
    ld a, [seekSamusTemp.samusY]
    sub [hl] ; HL = seekSamusTemp.enemyY
    jr z, .endIf_A
        jr c, .else_B
            ; Samus below
            ldh a, [hEnemy.counter]
            cp d ; Clamp vector Y to max value
            jr z, .endIf_A
                add b
                ldh [hEnemy.counter], a
                jr .endIf_A
        .else_B:
            ; Samus above
            ldh a, [hEnemy.counter]
            cp e ; Clamp vector Y to min value
            jr z, .endIf_A
                sub b
                ldh [hEnemy.counter], a
    .endIf_A:

    ; Compare X positions to modify X component of vector
    inc l
    ld a, [seekSamusTemp.samusX]
    sub [hl] ; HL = seekSamusTemp.enemyX
    jr z, .endIf_C
        jr c, .else_D
            ; Samus right
            ldh a, [hEnemy.state]
            cp d ; Clamp vector x to max value
            jr z, .endIf_C
                add b
                ldh [hEnemy.state], a
                jr .endIf_C
        .else_D:
            ; Samus left
            ldh a, [hEnemy.state]
            cp e ; Clamp vector x to min value
            jr z, .endIf_C
                sub b
                ldh [hEnemy.state], a
    .endIf_C:

    ; Adjust y position
    ldh a, [hEnemy.counter]
    ld e, a
    ld d, $00
    ld hl, .speedTable
    add hl, de
    ld a, [hl]
    ld hl, hEnemy.yPos
    add [hl]
    ld [hl], a
    ; Adjust x position
    ldh a, [hEnemy.state]
    ld e, a
    ld d, $00
    ld hl, .speedTable
    add hl, de
    ld a, [hl]
    ld hl, hEnemy.xPos
    add [hl]
    ld [hl], a
ret

.speedTable: ; 03:6BB1
    db $FB, $FB, $FC, $FC, $FD, $FE, $FD, $FD, $FD, $FF, $FE, $FE, $FE, $FF, $FF, $00
    db $00, $00, $01, $01, $02, $02, $02, $01, $03, $03, $03, $02, $03, $04, $04, $05
    db $05
;}

; Adjust enemy positions (which are in camera-space) due to scrolling
scrollEnemies: ;{ 03:6BD2
    ; Compare current scroll y to the scroll y from one frame ago
    ld hl, scrollHistory_A.y1
    ld de, scrollY
    ld a, [de]
    sub [hl]
    ld b, a ; B now has delta_y
    ; Compare current scroll x to the scroll x from one frame ago
    inc l
    inc e
    ld a, [de]
    sub [hl]
    ld c, a ; C now has delta_x
    ; Return both scroll distance is zero
    or b
        ret z
    ; Exit if no enemies
    ld a, [numEnemies.total]
    and a
        ret z
    ; Save number of enemies to process
    ld [scrollEnemies_numEnemiesLeft], a

    ; Iterate through enemy slots to find the first enemy
    ld hl, enemyDataSlots - enemyDataSlotSize ;$c5e0
    ld de, enemyDataSlotSize ; $0020
.findNextEnemy: ; Jump back here from the end to find next
    .findLoop:
        add hl, de
        ld a, [hl]
        inc a ; Continue until a non-$FF status is found
    jr z, .findLoop

    push hl
        call scrollEnemies_loadToHram ; Load enemy positions to HRAM
        ld hl, hEnemy.yPos
        ; Check if we moved up or down
        bit 7, b
        jr z, .else_A
            ; We moved up, so move the enemy down in camera-space
            ld a, b
            cpl ; Negate the negative number to get a positive number
            inc a
            add [hl] ; Thus adding a positive number moves it down
            ld [hl+], a
            ; If value carries and the enemy is offscreen, move it down a screen
            jr nc, .endIf_A
                ldh a, [hEnemy.status]
                cp $01
                jr nz, .endIf_A
                    ldh a, [hEnemy.yScreen]
                    inc a
                    ldh [hEnemy.yScreen], a
                    jr .endIf_A
        .else_A:
            ; We moved down, so move the enemy up in camera-space
            ld a, [hl]
            sub b
            ld [hl+], a
            ; If value carries and the enemy is offscreen, move it up a screen
            jr nc, .endIf_A
                ldh a, [hEnemy.status]
                cp $01
                jr nz, .endIf_A
                    ldh a, [hEnemy.yScreen]
                    dec a
                    ldh [hEnemy.yScreen], a
        .endIf_A:
    
        ; Check if we moved left or right
        bit 7, c
        jr z, .else_B
            ; We moved left, so move the enemy right in camera-space
            ld a, c
            cpl ; Negate the negative number to get a positive number
            inc a
            add [hl] ; Thus adding a positive number moves it right
            ld [hl], a
            ; If value carries and the enemy is offscreen, move it right a screen
            jr nc, .endIf_B
                ldh a, [hEnemy.status]
                cp $01
                jr nz, .endIf_B
                    ld hl, hEnemy.xScreen
                    inc [hl]
                    jr .endIf_B
        .else_B:
            ; We moved right, so move the enemy left in camera-space
            ld a, [hl]
            sub c
            ld [hl], a
            ; If value carries and the enemy is offscreen, move it left a screen
            jr nc, .endIf_B
                ldh a, [hEnemy.status]
                cp $01
                jr nz, .endIf_B
                    ld hl, hEnemy.xScreen
                    dec [hl]
        .endIf_B:
    
        call scrollEnemies_saveToWram ; Save enemy positions to WRAM
    pop hl
    ; Check if there's another enemy to process
    ld a, [scrollEnemies_numEnemiesLeft]
    dec a
    ld [scrollEnemies_numEnemiesLeft], a
        ret z
jr .findNextEnemy ;}

; Helper function to the above
scrollEnemies_loadToHram: ;{ 03:6C58
    ; Save base address to temp
    ld a, l
    ld [enemy_pWramLow], a
    ld a, h
    ld [enemy_pWramHigh], a
    ; Load status and pixel position
    ld a, [hl+]
    ldh [hEnemy.status], a
    ld a, [hl+]
    ldh [hEnemy.yPos], a
    ld a, [hl]
    ldh [hEnemy.xPos], a
    ; Load screen position
    ld a, l
    add $0d
    ld l, a
    ld a, [hl+]
    ldh [hEnemy.yScreen], a
    ld a, [hl]
    ldh [hEnemy.xScreen], a
ret ;}

; Helper function as well
scrollEnemies_saveToWram: ;{ 03:6C74
    ; Save base address to temp
    ld a, [enemy_pWramLow]
    ld l, a
    ld a, [enemy_pWramHigh]
    ld h, a
    ; Don't bother saving status
    inc l
    ; Save pixel position
    ldh a, [hEnemy.yPos]
    ld [hl+], a
    ldh a, [hEnemy.xPos]
    ld [hl], a
    ; Save screen position
    ld a, l
    add $0d
    ld l, a
    ldh a, [hEnemy.yScreen]
    ld [hl+], a
    ldh a, [hEnemy.xScreen]
    ld [hl], a
ret ;}

;------------------------------------------------------------------------------
; Start of queen code

; Neck swoop patterns
queen_neckPatternPointers: ;{ 03:6C8E - Indexed by queen_neckPattern
    dw .down_A ; 0 - Down 1 (curving up)
    dw .up_A ; 1 - Up 1
    dw .down_B ; 2 - Down 2 (curving down)
    dw .up_B ; 3 - Up 2
    dw .vomiting ; 4 - Up, steep (being spat out)
    dw .dying ; 5 - Down, steep, clips through floor (used during death)
    dw .forward ; 6 - Straight ahead (slight U shape)

; These movement strings are traversed forwards when extending the neck
;  and backwards when retracting the neck
;
; $80 tells the neck to stop extending
; $81 tells the neck to stop retracting
;
; The movement vectors are YX nybble pairs, with the Y component being signed
;  and the X component being unsigned

.down_A: ; 03:6C9C - 0
    db $81, $33, $33, $32, $32, $32, $32, $33, $23, $23, $24, $23, $23, $23, $24, $13
    db $13, $13, $13, $13, $00, $80
.up_A: ; 03:6CB2 - 1
    db $81, $E3, $E3, $E3, $E3, $E3, $E2, $E2, $E2, $E2, $E2, $E2, $D2, $D2, $D2, $D2
    db $D2, $D2, $00, $00, $00, $80
.up_B: ; 03:6CC8 - 3
    db $81, $01, $01, $01, $01, $F1, $01, $F1, $F1, $F1, $F1, $F1, $F1, $F2, $F2, $E2
    db $E2, $E2, $E2, $E2, $E2, $E2, $D2, $D2, $D2, $D2, $D2, $00, $00, $00, $80
.forward: ; 03:6CE7 - 6
    db $81, $01, $02, $12, $02, $12, $12, $12, $12, $13, $13, $13, $F3, $03, $03, $F3
    db $03, $F3, $F3, $F3, $00, $00, $00, $00, $80
.down_B: ; 03:6D00 - 2
    db $81, $01, $01, $01, $01, $01, $01, $02, $02, $12, $02, $12, $02, $12, $12, $12
    db $12, $12, $22, $22, $22, $23, $23, $33, $33, $33, $00, $00, $00, $80
.vomiting: ; 03:6D1E - 4
    db $81, $93, $93, $93, $D3, $00, $00, $00, $80
.dying: ; 03:6D27 - 5
    db $81, $10, $20, $20, $20, $20, $20, $21, $21, $20, $20, $20, $20, $20, $20, $21
    db $21, $20, $20, $20, $20, $20, $21, $21, $21, $20, $20, $20, $20, $20, $21, $21
    db $21, $00, $80
;}

; Initialize Queen AI
queen_initialize: ;{ 03:6D4A
    ; Clear the entire page
    ld hl, oamScratchpad
    xor a
    ld b, a
    .clearLoop:
        ld [hl+], a
        dec b
    jr nz, .clearLoop
    
    ; Initial raster split locations
    ld a, queenInRoom_bodyYTop
    ld [queen_bodyY], a
    ld a, queenInRoom_bodyHeight
    ld [queen_bodyHeight], a
    
    ; Enable interrupt
    ld a, STAT_LYC | STAT_LYCF ; $44
    ld [rSTAT], a
    
    ; Set initial position values
    ld a, $5c
    ld [queen_bodyXScroll], a
    ld a, [scrollX]
    ld [queen_cameraX], a
    
    ld a, $03
    ld [rWX], a
    ld [queen_headX], a
    
    ld a, [scrollY]
    ld [queen_cameraY], a
    
    ld a, $70
    ld [rWY], a
    ld [queen_headY], a
    
    ; Initialize interrupt list
    ld hl, queen_interruptList
    ld [hl], $ff
    ld a, l
    ld [queen_pInterruptListLow], a
    ld a, h
    ld [queen_pInterruptListHigh], a
    
    ; Initialize the neck movement sums (why not with zero?)
    ld a, $09
    ld [queen_neckYMovementSum], a
    ld [queen_neckXMovementSum], a
    
    ; Initialize OAM scratchpad pointers
    ld hl, oamScratchpad
    ld a, l
    ld [queen_pOamScratchpadLow], a
    ld a, h
    ld [queen_pOamScratchpadHigh], a
    
    ; Initialize wall sprites
    ld hl, queen_wallOAM ; $C338
    ld b, $0c
    ld a, $78
    .wallLoop:
        ; Set Y pos
        ld [hl+], a
        ; Set X pos
        ld [hl], $a2
        ; Set tile
        inc l
        ld [hl], $b0
        ; Set attributes
        inc l
        ld [hl], $00
        ; Iterate to next sprite
        inc l
        add $08
        dec b
    jr nz, .wallLoop
    call queen_adjustWallSpriteToHead
    
    ; Initialize Queen's state to Init fight pt 1 (wait to scream)
    ld hl, queen_stateList
    ld a, l
    ld [queen_pNextStateLow], a
    ld a, h
    ld [queen_pNextStateHigh], a
    ld a, queenState_startA
    ld [queen_state], a
    
    ; Clear enemy slots
    ld hl, enemyDataSlots ; $C600
    ld bc, enemyDataSlotSize * $0D ; $01a0
    .enemyLoop:
        xor a
        ld [hl+], a
        dec bc
        ld a, b
        or c
    jr nz, .enemyLoop

    ; Set initial health
    ld a, $96 ; 150
    ld [queen_health], a
    
    call queen_setActorPositions
    
    ; Set sprite types
    ld hl, queenActor_body + 3 ; $C603
    ld [hl], QUEEN_ACTOR_BODY ; $F3
    ld l, LOW(queenActor_mouth + 3) ; $23
    ld [hl], QUEEN_ACTOR_MOUTH_CLOSED ; $F5
    ld l, LOW(queenActor_headL + 3) ; $43
    ld [hl], QUEEN_ACTOR_HEAD_LEFT ; $F1
    ld l, LOW(queenActor_headR + 3) ; $63
    ld [hl], QUEEN_ACTOR_HEAD_RIGHT ; $F2
    
    ; Set sprite types for neck
    ld hl, queenActor_neckA + 3 ; $C683
    ld de, enemyDataSlotSize
    ld b, $06
    ld a, QUEEN_ACTOR_NECK ; $F0
    .neckLoop:
        ld [hl], a
        add hl, de
        dec b
    jr nz, .neckLoop

    call queen_deactivateActors.neck
    
    ; Initialize head frame
    ld a, $01
    ld [queen_headFrameNext], a
    ld [queen_headFrame], a
    
    ; Set initial delay
    ld a, $8c
    ld [queen_delayTimer], a
ret ;}

; Deactivate actors - two entrances (one for neck, one for arbitrary sets)
queen_deactivateActors: ;{ 03:6E12
    .neck:
        ; Deactivate neck parts
        ld hl, queenActor_neckA ; $C680
        ld b, $06
    .arbitrary: ; 03:6E17
    
    ; Set incrementation value
    ld de, enemyDataSlotSize
    ; Set status to $FF (inactive)
    ld a, $ff
    .clearLoop:
        ld [hl], a
        add hl, de
        dec b
    jr nz, .clearLoop
ret ;}

; Adjust the wall sprites pertaining to the head to match y position
queen_adjustWallSpriteToHead: ;{ 03:6E22
    ; Get base address of OAM scratchpad for wall sprites pertaining to the head
    ld hl, queen_wallOAM_head ; $C354
    ; Set loop counter
    ld b, $05
    ; Get Y position and adjust
    ld a, [queen_headY]
    add $10
    .loop:
        ; Set Y position
        ld [hl+], a
        ; Skip X position, tile, and attributes
        inc l
        inc l
        inc l
        ; Increment Y position
        add $08
        ; Exit once loop is done
        dec b
    jr nz, .loop
ret ;}

queenHandler: ;{ 03:6E36
    ; Limit actions if Samus is dying
    ld a, [deathFlag]
    and a
    jr z, .endIf_A
        xor a
        ld [queen_footFrame], a
        ld [queen_headFrameNext], a
        ld [queen_deathBitmask], a
        call queen_writeOam
        ret
    .endIf_A:

    ; Change palette of neck sprites when hurt
    ld a, [frameCounter]
    and $03
    jr nz, .endIf_B
        ld a, [queen_bodyPalette]
        and a
        jr z, .endIf_B
            xor $90
            ld [queen_bodyPalette], a
            
            ld b, $0c
            ld hl, queen_objectOAM ; $c308
            .loop:
                inc l
                inc l
                inc l
                ld a, $10
                xor [hl]
                ld [hl+], a
                dec b
            jr nz, .loop
    .endIf_B:

    ; Set aggression flags
    ; Skip if health is zero
    ld a, [queen_health]
    and a
    jr z, .endIf_C
        ; Check if health is below 100
        cp $64 ; 100
        jr nc, .endIf_C
            ; Set middle health flag
            ld b, a
            ld a, $01
            ld [queen_midHealthFlag], a
            ; Check if health is below 50
            ld a, b
            cp $32 ; 50
            jr nc, .endIf_C
                ; Set low health flag
                ld a, $01
                ld [queen_lowHealthFlag], a
    .endIf_C:

    call queen_handleState
    call queen_walk
    call queen_moveNeck
    call queen_drawNeck
    call queen_getCameraDelta
    call queen_adjustBodyForCamera
    call queen_adjustSpritesForCamera
    call queen_setActorPositions ; For collision detection
    call queen_adjustWallSpriteToHead
    call queen_writeOam ; Copy sprites from C600 area to OAM buffer
    call queen_headCollision ; Check if head got hit by a missile
ret ;}

queen_headCollision: ;{ 03:6EA7
    ; Skip ahead if timer is zero
    ld a, [queen_flashTimer]
    and a
    jr z, .endIf_A
        ; Decrement the timer, and reset the palette if it hit zero
        dec a
        ld [queen_flashTimer], a
        jr nz, .endIf_A
            xor a
            ld [queen_bodyPalette], a
            call queen_setDefaultNeckAttributes
    .endIf_A:

    ; Load collision type
    ld a, [collision_weaponType]
    ld b, a
    ; Clear collision type
    ld a, $ff
    ld [collision_weaponType], a
    
    ; Exit if collision type is none
    ld a, b
    cp $ff
        ret z
    ; Exit if collision type is not missiles
    cp $08
        ret nz
    
; Check if it hit the mouth or head
    ld a, [collision_pEnemyHigh]
    cp HIGH(queenActor_mouth) ; $C6
        ret nz
    ld h, a
    ; Check if it hit the hed or not
    ld a, [collision_pEnemyLow]
    cp LOW(queenActor_mouth) ; $20
        jr nz, .checkHead

; A mouth collision happened
    ; Exit if it hit the mouth when it was not open
    ld l, LOW(queenActor_mouth + 3) ; $23
    ld a, [hl]
    cp $f6
        ret z
.hurt:
    ; Hurt the queen
    call queen_missileHurt
    
    ; Set the flash timer
    ld a, $08
    ld [queen_flashTimer], a
    ; Exit if the palette is non-zero
    ld a, [queen_bodyPalette]
    and a
        ret nz
    ; Set palette
    ld a, $93
    ld [queen_bodyPalette], a
    
    ; Play screaming sound
    ld a, [queen_lowHealthFlag]
    and a
    ld a, sfx_noise_metroidQueenCry ; Normal sound
    jr z, .endIf_B
        ld a, sfx_noise_metroidQueenHurtCry ; Low health sound
    .endIf_B:
    ld [sfxRequest_noise], a
ret

.checkHead:
    ; Check if it hit one of the head objects
    cp LOW(queenActor_headL) ; $40
        jr z, .hurt
    cp LOW(queenActor_headR) ; $60
        jr z, .hurt
ret
;}

; Set actor positions from these various variables
queen_setActorPositions: ;{ 03:6F07
    ; Queen body
    ld hl, queenActor_body + 1 ; $C601
    ; Y + $18
    ld a, [queen_bodyY]
    add $18
    ld [hl+], a
    ; $30 - X
    ld a, [queen_bodyXScroll]
    cpl
    inc a
    add $30
    ld [hl], a
    
    ; Queen head left half
    ld l, LOW(queenActor_headL + 1) ; $41
    ; Y + $10
    ld a, [queen_headY]
    add $10
    ld [hl+], a
    ; X
    ld a, [queen_headX]
    ld [hl], a
    
    ; Queen head right half
    ld l, LOW(queenActor_headR + 1) ; $61
    ; Y + $10
    ld a, [queen_headY]
    add $10
    ld [hl+], a
    ; X + $20
    ld a, [queen_headX]
    add $20
    ld [hl], a

    ; Queen mouth
    ld l, LOW(queenActor_mouth+3) ; $23
    ld b, $12
    ld c, $0e
    ; Check if mouth is stunned
    ld a, [hl-]
    cp QUEEN_ACTOR_MOUTH_STUNNED ; $F7
    jr nz, .endIf_A
        ; If so, adjust position forward
        ld b, $15
        ld c, $12
    .endIf_A:
    ; X + B ($12, or $15 when stunned)
    ld a, [queen_headX]
    add b
    ld [hl-], a
    ; Y + C ($0E, or $12 when stunned)
    ld a, [queen_headY]
    add c
    ld [hl], a
    
    ; Deactivate neck actors every frame
    call queen_deactivateActors.neck
    
    ; Exit if health is zero
    ld a, [queen_health]
    and a
        ret z
        
    ; Check if the Queen is dealing with her stomach being bombed (when her neck is bent upwards)
    ld a, [queen_stomachBombedFlag]
    and a
    jr nz, .else_B
        ; Exit if projectiles are active
        ld a, [queen_projectilesActiveFlag]
        and a
            ret nz
        ; Exit if OAM scratchpad is being unused
        ld a, [queen_pOamScratchpadLow]
        cp $00
            ret z
        ; Read X/Y positions from OAM scratchpad to enemy RAM !?
        ; Set source pounter
        ; HL = X position of the last sprite
        inc a
        ld l, a
        ld a, [queen_pOamScratchpadHigh]
        ld h, a
        
        ; Setup destination pointer
        ; Set sprite type to neck
        ld de, queenActor_neckA + 3 ; $c683
        ld a, QUEEN_ACTOR_NECK ; $F0
        ld [de], a
        dec e
        .loop:
            ; Transfer sprite X to actor X
            ld a, [hl-]
            ld [de], a
            
            ; Transfer sprite Y to actor Y
            dec e
            ld a, [hl]
            ld [de], a
            
            ; Set actor status to active ($00)
            dec e
            xor a
            ld [de], a
            
            ; Iterate to the x position of the next sprite
            push de
                ld de, -7 ; $fff9
                add hl, de
            pop de
            ; Iterate to the x position of the next actor
            push hl
                ld hl, $0022
                add hl, de
                ld e, l
                ld d, h
            pop hl
            ; Exit loop if OAM scratchpad pointer has reached the end
            ld a, l
            cp $01
        jr nz, .loop
        ret
    .else_B:
        ; Read X/Y positions from OAM scratchpad to enemy RAM !?
        ld de, queen_objectOAM ; $C308
        ld hl, queenActor_neckA ; $C680
        ; Set status to active
        ld [hl], $00
        ; Set Y position
        inc l
        ld a, [de]
        add $10
        ld [hl+], a
        ; Set X position
        inc e
        ld a, [de]
        add $10
        ld [hl+], a
        ; Set enemy type
        ld [hl], QUEEN_ACTOR_BENT_NECK ; $82
        ret
;}

; Queen head tilemaps
queen_headFrameA: ; 03:6FA2
    db $BB, $B1, $B2, $B3, $B4, $FF
    db $C0, $C1, $C2, $C3, $C4, $FF
    db $D0, $D1, $D2, $D3, $D4, $D5
    db $FF, $FF, $E2, $E3, $E4, $E5
    db $FF, $FF, $FF, $FF, $FF, $FF
    db $FF, $FF, $FF, $FF, $FF, $FF
queen_headFrameB: ; 03:6FC6
    db $BB, $B1, $F5, $B8, $B9, $BA
    db $C0, $C1, $C7, $C8, $C9, $CA
    db $D0, $E6, $D7, $D8, $FF, $FF
    db $FF, $F6, $E7, $E8, $FF, $FF
    db $FF, $FF, $F7, $F8, $FF, $FF
    db $FF, $FF, $FF, $FF, $FF, $FF
queen_headFrameC: ; 03:6FEA
    db $FF, $BC, $BD, $BE, $FF, $FF
    db $FF, $CB, $CC, $CD, $FF, $FF
    db $DA, $DB, $DC, $DD, $FF, $FF
    db $EA, $EB, $EC, $ED, $DE, $FF
    db $FA, $FB, $FC, $FD, $EE, $D9
    db $FF, $FF, $FF, $FF, $FF, $FF

queen_drawHead: ;{
    .resume_A: ; 03:700E
        ld a, [queen_headDest]
        ld l, a
        ld a, [queen_headSrcHigh]
        ld d, a
        ld a, [queen_headSrcLow]
        ld e, a
        ld h, $9c
        jr .resume_B
.entry: ; 03:701E - Entry point
    ld a, [queen_headFrameNext]
    and a
        ret z
    cp $ff
        jr z, .resume_A

    ld de, queen_headFrameA
    cp $01
    jr z, .endIf
        ld de, queen_headFrameB
        cp $02
        jr z, .endIf
            ld de, queen_headFrameC
    .endIf:

    ld hl, $9c00
  .resume_B:
    ld c, $03 ; Draw only 3 rows per frame (split update into two frames)

    .drawLoop:
        ld b, $06
        .rowLoop:
            ld a, [de]
            ld [hl+], a
            inc de
            dec b
        jr nz, .rowLoop
    
        ld a, $1a
        add l
        ld l, a
        dec c
    jr nz, .drawLoop

    ld a, [queen_headFrameNext]
    cp $ff
    jr nz, .else
        ; Finished rendering
        xor a
        ld [queen_headFrameNext], a
        ret
    .else:
        ; Continue rendering next frame
        ld a, l
        ld [queen_headDest], a
        ld a, d
        ld [queen_headSrcHigh], a
        ld a, e
        ld [queen_headSrcLow], a
        ld a, $ff
        ld [queen_headFrameNext], a
        ret
;} end proc

; 03:706A - Rendering the Queen's feet
queen_drawFeet: ;{
    ; Try drawing the head if the next frame is zero
    ld a, [queen_footFrame]
    and a
        jr z, queen_drawHead.entry
    ; Save frame to B
    ld b, a
    ; Try drawing the head if the animation delay is non-zero
    ld a, [queen_footAnimCounter]
    and a
    jr z, .endIf_A
        dec a
        ld [queen_footAnimCounter], a
            jr queen_drawHead.entry
    .endIf_A:

    ; Reload the animation counter
    ld a, $01
    ld [queen_footAnimCounter], a
    ; Select the front or back feet depending on the LSB of the animation frame
    ld a, b
    bit 7, a ; Bit 7 == 0 -> do the front foot, else do the rear foot
    ld hl, queen_frontFootPointers
    ld de, queen_frontFootOffsets
    ld b, $0c ; Number of tiles to update
    jr z, .endIf_B
        ld hl, queen_rearFootPointers
        ld de, queen_rearFootOffsets
        ld b, $10 ; Number of tiles to update
    .endIf_B:
    
    ; Get the foot tilemap/tile-offset pointers
    push de
        and $7f ; Mask out the bit determining which foot to render
        dec a   ; Adjusting because the value zero earlier meant "skip rendering"
        sla a
        ld e, a
        ld d, $00
        add hl, de
        ld e, [hl]
        inc hl
        ld d, [hl]
    pop hl
    ; HL now points to the offset table
    ; DE now points to the tilemap

    .vramUpdateLoop:
        push bc ; push the loop counter (b) on to the stack
            ; VRAM Offset: BC = $9A00 + [HL]
            ld b, $9a
            ld c, [hl]
            ; DE points to the current tile number to render
            ld a, [de]
            ld [bc], a ; Write to VRAM
            inc hl
            inc de
        pop bc ; pop the loop counter from the stack
        dec b
    jr nz, .vramUpdateLoop

    ; Don't increment the frame counter if we rendered the front foot
    ld a, [queen_footFrame]
    bit 7, a
    jr z, .endIf_C
        inc a
    .endIf_C:
    
    xor $80 ; Swap which foot to render next frame
    and $83 ; Mask frame numbers greater than 3
    ; inc if zero so we don't stop animating the feet
    jr nz, .endIf_D
        inc a
    .endIf_D:
    ld [queen_footFrame], a
ret

; Pointers, tile numbers, and tilemap offsets for the rear and front feet.
queen_rearFootPointers:
    dw queen_rearFoot1, queen_rearFoot2, queen_rearFoot3
queen_frontFootPointers:
    dw queen_frontFoot1, queen_frontFoot2, queen_frontFoot3
    
; 03:70D0
queen_rearFoot1:
    db     $21,$22,$23,$24
    db $30,$31,$32,$33
    db $40,$41,$42,    $44
    db $50,$51,$52,$53
queen_rearFoot2:
    db     $2c,$2d,$2e,$2f
    db $3b,$3c,$3d,$3e
    db $4b,$4c,$4d,    $4f
    db $7f,$f2,$ef,$df
queen_rearFoot3:
    db     $2c,$2d,$2e,$2f
    db $3b,$3c,$3d,$3e
    db $4b,$4c,$4d,    $4f
    db $10,$11,$12,$df

; 03:7100
queen_frontFoot1:
    db $28,$29,$2a
    db $38,$39,$3a
    db $48,$49,$4a
    db $fe,$f9,$f4
queen_frontFoot2:
    db $1b,$1c,$1d
    db $03,$04,$05
    db $0e,$0f,$1f
    db $ff,$ff,$ff
queen_frontFoot3:
    db $1b,$1c,$1d
    db $03,$04,$05
    db $0e,$0f,$1f
    db $00,$01,$02
    
; 03:7124
queen_rearFootOffsets:
    db     $01,$02,$03,$04
    db $20,$21,$22,$23
    db $40,$41,$42,    $44
    db $60,$61,$62,$63
queen_frontFootOffsets:
    db $08,$09,$0a
    db $28,$29,$2a
    db $48,$49,$4a
    db $68,$69,$6a

;} No more code about the Queen's feet, please.

; Copy sprites to OAM buffer
queen_writeOam: ;{ 03:7140
    ; Copy the 6 segments of the neck (or the spit projectiles)
    ; Set source pointer
    ld hl, queen_objectOAM ; $c308
    ; Set destination pointer
    ld a, [hOamBufferIndex]
    ld e, a
    ld d, HIGH(wram_oamBuffer)
    ; Load 6 pairs of sprites
    ld c, $06
    .loop_A:
        ; Break if at the last sprite
        ld a, [queen_pOamScratchpadLow]
        add $08
        cp l
            jr z, .break
        
        ; Load a pair of sprites to the OAM buffer
        ld b, $08
        .loop_B:
            ld a, [hl+]
            ld [de], a
            inc de
            dec b
        jr nz, .loop_B
        
        ; Decrement loop counter
        dec c
    jr nz, .loop_A
    .break:

    ; Copy the wall segments
    ld hl, queen_wallOAM ; $C338
    ld b, $0C*4 ;$30
    .loop_C:
        ld a, [hl+]
        ld [de], a
        inc de
        dec b
    jr nz, .loop_C
    
    ; Update the OAM index
    ld a, e
    ld [hOamBufferIndex], a
ret ;}

; Compute the change in camera position
queen_getCameraDelta: ;{ 03:716E
    ; Load previous Y camera value
    ld a, [queen_cameraY]
    ld b, a
    ; Clamp minimum value of camera to zero
    ld a, [scrollY]
    cp $f8
    jr c, .endIf
        xor a
    .endIf:
    ; Update to current X camera value
    ld [queen_cameraY], a
    ; delta = cur - prev
    sub b
    ld [queen_cameraDeltaY], a
    
    ; Load previous X camera value
    ld a, [queen_cameraX]
    ld b, a
    ; Update to current X camera value
    ld a, [scrollX]
    ld [queen_cameraX], a
    ; delta = cur - prev
    sub b
    ld [queen_cameraDeltaX], a
ret ;}

queen_adjustBodyForCamera: ;{ 03:7190
; Adjust X positions
    ; Get delta X
    ld a, [queen_cameraDeltaX]
    ld b, a
    
    ; Adjust body position
    ld a, [queen_bodyXScroll]
    add b ; Add due to how the raster split works
    ld [queen_bodyXScroll], a
    ; Adjust head position
    ld a, [queen_headX]
    sub b
    ld [queen_headX], a

; Adjust Y positions
    ; Get delta Y
    ld a, [queen_cameraDeltaY]
    ld b, a
    
    ; Adjust body position
    ld a, [queen_headY]
    sub b
    ld [queen_headY], a
    
; Get the scanline numbers for the queen's raster splits (using queen body/height)
    ; Clamp minimum value of camera to zero
    ld a, [scrollY]
    cp $f8
    jr c, .endIf
        xor a
    .endIf:
    ld c, a
    
    ld a, queenInRoom_bodyYTop ; Pixels between the top of the BG map to the top of the queen (minus 1)
    sub c
    jr c, .else
        ; If the top of the camera is above the top of the queen's body
        ; bodyY = $67 - ScrollY
        ld [queen_bodyY], a
        ; height = standard
        ld a, queenInRoom_bodyHeight
        ld [queen_bodyHeight], a
        ret
    .else:
        ; If the top of the camera is below the top of the queen's body (normally impossible)
        ; height = $67 - ScrollY + $37 (bottom of body relative to scroll y)
        ld d, queenInRoom_bodyHeight
        add d
        ld [queen_bodyHeight], a
        ; Set top of queen's body to top of the screen
        xor a
        ld [queen_bodyY], a
        ret
;}

; Camera adjustment
queen_adjustSpritesForCamera: ;{ 03:71CF
    ; Set offset for OAM scratchpad pointer
    ld a, [queen_stomachBombedFlag]
    ld d, $05
    and a
    jr z, .endIf_A
        ld d, $01
    .endIf_A:

    ; Load camera deltas to B and C
    ld a, [queen_cameraDeltaX]
    ld b, a
    ld a, [queen_cameraDeltaY]
    ld c, a
    
    ; Skip ahead if OAM scratchpad is being unused (low byte of pointer is $00)
    ld a, [queen_pOamScratchpadLow]
    cp $00
    jr z, .endIf_B
        ; Set OAM scratchpad pointer (should be pointing at an X value)
        add d
        ld l, a
        ld a, [queen_pOamScratchpadHigh]
        ld h, a
        ; Iterate backwards through the OAM scratchpad
        .loop_A:
            ; Adjust X position
            ld a, [hl]
            sub b
            ld [hl-], a
            ; Adjust Y position
            ld a, [hl]
            sub c
            ld [hl-], a
            ; Skip attributes and tile of previous sprite
            dec l
            dec l
            ; Exit loop if below the end of the OAM scratchpad
            ld a, $05
            cp l
        jr nz, .loop_A
        
        ; Adjust positions of projectiles
        ld hl, queenActor_spitA + 1 ; $C741
        ld d, $03
        .loop_B:
            call queen_singleCameraAdjustment
            ; Iterate to next actor
            ld a, l
            add $1e
            ld l, a
            dec d
        jr nz, .loop_B
    
        ; Adjust Samus targets for the projectiles
        ld hl, queen_samusTargetPoints
        ld d, $03
        .loop_C:
            call queen_singleCameraAdjustment
            dec d
        jr nz, .loop_C
    .endIf_B:

    ; Adjust positions of the wall sprites to match the camera
    ld hl, queen_wallOAM ; $C338
    ld d, $0c
    .loop_D:
        ld a, [hl]
        sub c
        ld [hl+], a
        ld a, [hl]
        sub b
        ld [hl+], a
        inc l
        inc l
        dec d
    jr nz, .loop_D

    ; Adjust the wall sprites to match the queen's head
    call queen_adjustWallSpriteToHead
ret ;}

; Single camera adjustment
queen_singleCameraAdjustment: ;{
    ; Adjust Y position
    ld a, [hl]
    sub c
    ld [hl+], a
    ; Adjust X position
    ld a, [hl]
    sub b
    ld [hl+], a
ret ;}

; Neck extension related (draw neck?)
queen_drawNeck: ;{ 03:7230
    ld a, [queen_pOamScratchpadLow]
    ld l, a
    ld a, [queen_pOamScratchpadHigh]
    ld h, a
    
    ; Exit if state 0
    ld a, [queen_neckDrawingState]
    and a
        ret z
    ; Jump ahead if state 2 (retracting)
    cp $01
        jr nz, .retractionCase
    
    ; State 1 (extending)
    ; Continue and draw sprite...
    ; ...if the head has moved for than 8 pixels horizontally
    ld a, [queen_neckXMovementSum]
    cp $08
    jr nc, .endIf_A
        ; ...or if the head has moved more than 12 pixels vertically
        ld a, [queen_neckYMovementSum]
        cp $0c
        ret c
    .endIf_A:
    ; Clear counters
    xor a
    ld [queen_neckXMovementSum], a
    ld [queen_neckYMovementSum], a
    ld a, $30
    cp l
        ret z

    ; Get OAM scratchpad position of the next sprite
    ld de, $0008
    add hl, de
    push hl
        ; Get Y offset depending on Queen's head frame
        ld a, [queen_headFrame]
        ld b, $15
        cp $03
        jr nz, .endIf_B
            ld b, $27
        .endIf_B:
        
        ; Render first neck sprite
        ; Write Y position
        ld a, [queen_headY]
        add b
        ld [hl+], a
        ; Save Y position
        ld b, a
        ; Write X position
        ld a, [queen_headX]
        sub $00 ; ??
        ld [hl+], a
        ; Save X position
        ld c, a
        ; Write tile
        ld [hl], $b5
        ; Write attributes
        inc l
        ld [hl], OAM_PRIO ; $80
        
        ; Render second neck sprite
        ; Write Y position
        inc l
        ld a, b
        add $08
        ld [hl+], a
        ; Write X position
        ld [hl], c
        ; Write tile
        inc l
        ld [hl], $c5
        ; Write attributes
        inc l
        ld [hl], OAM_PRIO ; $80
    pop hl
    ; Save the scratchpad pointer at the beginning of the latest sprite-pair
    
.saveScratchpadPointer:
    ld a, l
    ld [queen_pOamScratchpadLow], a
    ld a, h
    ld [queen_pOamScratchpadHigh], a
ret

.retractionCase:
    ; Continue and erase sprite...
    ; ...if the head has moved for than 8 pixels horizontally
    ld a, [queen_neckXMovementSum]
    cp $08
    jr nc, .endIf_C
        ; ...or if the head has moved more than 12 pixels vertically
        ld a, [queen_neckYMovementSum]
        cp $0c
        ret c
    .endIf_C:
    ; Set counters to 7 (TODO: Figure out why this is not zero
    ld a, $07
    ld [queen_neckXMovementSum], a
    ld [queen_neckYMovementSum], a
    
    ; Set Y position of one sprite to be offscreen
    ld [hl], $ff
    ; Set Y position of next sprite to be offscreen
    ld de, 4 ; $0004
    add hl, de
    ld [hl], $ff
    
    ; Save scratchpad OAM pointer to the beginning of the previous displayed sprite
    ld de, -12 ;$fff4 ; Don't think this is hEnemy.xScreen
    add hl, de
    ld a, $00
    cp l ; Comparison for special underflow case...
        ret z
    jr .saveScratchpadPointer
;}

; Move the neck
queen_moveNeck: ;{ 03:72B8
    ld a, [queen_neckControl]
    and a ; Case 0 - Do nothing
        ret z
    cp $03 ; Case 3 - Follow body walking
        jp z, .walk
    ld b, a
    ; Load pointer
    ld a, [queen_pNeckPatternLow]
    ld l, a
    ld a, [queen_pNeckPatternHigh]
    ld h, a
    
    ; Check if extending or retracting
    ld a, b
    cp $01
        jp nz, .retract ; Retracting case
; Extending case

    ; Check if paralyzed
    ld a, [queen_eatingState]
    cp $10
    jr nz, .endIf_A
        ld hl, queenActor_mouth + 3 ; $C623
        ld a, [hl]
        cp QUEEN_ACTOR_MOUTH_OPEN ; $F6
        jr z, .else_B
            ld a, [queen_stunTimer]
            and a
            jr z, .else_C
                dec a
                ld [queen_stunTimer], a
                cp $58
                    ret nz
                xor a
                ld [queen_bodyPalette], a
                call queen_setDefaultNeckAttributes
                ret
            .else_C:
                xor a
                ld [queen_eatingState], a
                ld hl, queenActor_mouth + 3 ; $C623
                ld [hl], QUEEN_ACTOR_MOUTH_OPEN ; $F6
                ret
        .else_B:
            ; Set stun timer
            ld a, $60
            ld [queen_stunTimer], a
            ; Change palette
            ld a, $93
            ld [queen_bodyPalette], a
            ; Play noise
            ld a, sfx_noise_metroidQueenHurtCry
            ld [sfxRequest_noise], a
            ; Change actor type
            ld hl, queenActor_mouth + 3 ; $C623
            ld [hl], QUEEN_ACTOR_MOUTH_STUNNED ; $F7
            ret
    .endIf_A:

    ; Exit is Samus is entering mouth
    cp $01
        ret z
    cp $02
        jr nz, .extend
    
    ; Mouth closing with Samus in it
    xor a
    ld [queen_bodyPalette], a
    call queen_setDefaultNeckAttributes
    ; Prep Samus in mouth
    ld a, queenState_prepEatingSamus
    ld [queen_state], a
ret

.extend: ;{ Extension logic
    ; Branch ahead if done extending
    ld a, [hl]
    cp $80
        jr z, .doneExtending
    
    ; Save Y position to C
    ld a, [queen_headY]
    ld c, a
    
    ; Load Y velocity (signed value)
    ld a, [hl]
    and $f0
    
    ; Sign-extend (if necessary) and swap nybbles
    bit 7, a
    jr z, .endIf_D
        or $0f
    .endIf_D:
    swap a
    
    ; A = Velocity + Position
    add c
    
    ; Check if Queen's head is below $D0 (nearly impossible in a normal fight?)
    cp $d0
    jr c, .endIf_E
        ; If so, check if the queen's stomach was just bombed or not
        ld a, [queen_stomachBombedFlag]
        and a
        jr nz, .else_F
            ; If not, just immediately retract the neck
            ld a, queenState_prepRetractingNeck
            ld [queen_state], a
            ; Clear variables
            xor a
            ld [queen_walkStatus], a
            ld [queen_neckStatus], a
            jr .saveNeckPointer
        .else_F:
            ; If so, just spit Samus out
            ld a, queenState_vomitingSamus
            ld [queen_state], a
            jr .saveNeckPointer
    .endIf_E:

    ; Save new Y position
    ld [queen_headY], a
    
    ; Reload Y velocity and save to B
    ld a, [hl]
    and $f0
    swap a
    ld b, a
    ; Check if it was negative
    bit 3, a
    jr z, .endIf_G
        ; If so, sign-extend it
        or $f0
        ; Then negate it so we have the absolute value and save it to B
        cpl
        inc a
        ld b, a
    .endIf_G:
    ; Add the Y speed to the running tally of Y movement (for rendering)
    ld a, [queen_neckYMovementSum]
    add b
    ld [queen_neckYMovementSum], a
    
    ; Load the X position (unsigned)
    ld a, [hl]
    and $0f
    ld c, a
    ld a, [queen_headX]
    add c
    ld [queen_headX], a
    ; Add the X speed to the running tally of X movement (for rendering)
    ld a, [queen_neckXMovementSum]
    add c
    ld [queen_neckXMovementSum], a
    
    ; Increment pointer to next value
    inc hl
    
    ; Exit if low-health flag is zero
    ld a, [queen_lowHealthFlag]
    and a
        jr z, .saveNeckPointer
    
    ; Else, clear the low-health flag (just for this frame)
    dec a
    ld [queen_lowHealthFlag], a
    ; And then draw the neck preemptively and run through this loop again as well
    ; So the neck extends twice as fast during the queen's desperation mode
    push hl
        call queen_drawNeck
    pop hl
jr .extend
;}

.saveNeckPointer:
    ; Save neck pattern and exit
    ld a, l
    ld [queen_pNeckPatternLow], a
    ld a, h
    ld [queen_pNeckPatternHigh], a
ret

.doneExtending:
    ; Stop drawing/moving neck
    xor a
    ld [queen_neckControl], a
    ld [queen_neckDrawingState], a
    ; Set status to "done"
    ld a, $81
    ld [queen_neckStatus], a
    ; Decrement pointer so it isn't sitting on the "stop extending" byte
    dec hl
jr .saveNeckPointer ; Save Neck Pattern and Exit

.retract: ; Retracting case {
    ; Only act every other frame
    ld a, [frameCounter]
    and $01
        ret z
    
    ; Check if the neck is done retracting
    ld a, [hl]
    cp $81
    jr z, .else_H
        ; If not, move it back
        
        ; Load Y velocity from upper nybble
        ld a, [hl]
        and $f0
        swap a
        ; Check if it's positive or negative
        bit 3, a
        jr z, .else_I
            ; If negative, then sign-extend it
            or $f0
            ; And make it positive instead
            cpl
            inc a
            ld b, a
            jr .endIf_I
        .else_I:
            ; If positive, make it negative instead
            cpl
            inc a
            ld b, a
        .endIf_I:
        ; Add the inverted Y velocity to the Y position
        ld a, [queen_headY]
        add b
        ld [queen_headY], a
        
        ; Check if the inverted velocity was negative
        bit 7, b
        jr nz, .endIf_J
            ; If it was negative, make it positive
            ld a, b
            cpl
            inc a
            ld b, a
        .endIf_J:
        ; Add it to the running Y movement sum (for un-rendering the neck)
        ld a, [queen_neckYMovementSum]
        add b
        ld [queen_neckYMovementSum], a
        
        ; Load the X speed from the lower nybble
        ld a, [hl]
        and $0f
        ; Negate it
        cpl
        inc a
        ld b, a
        ; Add it to the head's X position
        ld a, [queen_headX]
        add b
        ld [queen_headX], a
        ; And to the running X movement sum
        ld a, [queen_neckXMovementSum]
        add b
        ld [queen_neckXMovementSum], a
        
        ; Iterate to previous byte in the movement string
        dec hl
        jr .saveNeckPointer
    .else_H:
        ; Stop updating neck
        xor a
        ld [queen_neckControl], a
        ld [queen_neckDrawingState], a
        ; Signal that the neck is done retracting
        ld a, $82
        ld [queen_neckStatus], a
        
        ; Clear eating state (just in case)
        xor a
        ld [queen_eatingState], a
        ; Close mouth
        ld hl, queenActor_mouth + 3 ; $C623
        ld [hl], QUEEN_ACTOR_MOUTH_CLOSED ; $F5
        
        ; Clear OAM scratchpad pointer
        ld hl, oamScratchpad
        ld a, l
        ld [queen_pOamScratchpadLow], a
        ld a, h
        ld [queen_pOamScratchpadHigh], a
        
        ; Reset movement sum (?)
        ld a, $09
        ld [queen_neckXMovementSum], a
        ld [queen_neckYMovementSum], a
        
        ; Save neck pointer where it's at
        call queen_loadNeckBasePointer
        jp queen_moveNeck.saveNeckPointer
;}

.walk:
    ; Add walk speed to head position
    ld a, [queen_walkSpeed]
    ld b, a
    ld a, [queen_headX]
    add b
    ld [queen_headX], a
ret ;}

; Called when Queen's head is hit by a missile
queen_missileHurt: ;{ 03:7436
    ; Exit if health is zero
    ld a, [queen_health]
    and a
        ret z
    ; Hurt for one damage, and exit if it was not fatal
    dec a
    ld [queen_health], a
        ret nz
    
; Do this is the hit was fatal
    ; Set status to "done extending"
    ld a, $81
    ld [queen_neckStatus], a
    ; Set state to prep death
    ld a, queenState_prepDeath
    ld [queen_state], a
    
    ; Clear flags
    xor a
    ld [queen_neckControl], a
    ld [queen_walkControl], a
    ld [queen_footFrame], a
    ld [queen_headFrameNext], a
    
    call queen_deactivateActors.neck
    
    ; Deactivate body, mouth, and head (left and right)
    ld b, $04
    ld hl, queenActor_body
    call queen_deactivateActors.arbitrary
    
    ; Close the bottom exit
    call queen_closeFloor
ret ;}

; Load pointer to HL
queen_loadNeckBasePointer: ;{ 03:7466
    ld a, [queen_pNeckPatternBaseLow]
    ld l, a
    ld a, [queen_pNeckPatternBaseHigh]
    ld h, a
ret ;}

; Sets base pointer given the current index
queen_setNeckBasePointer: ;{ 03:746F
    ; HL = base offset + 2*index
    ld a, [queen_neckPattern]
    sla a
    ld e, a
    ld d, $00
    ld hl, queen_neckPatternPointers
    add hl, de
    ; Load pointer
    ld a, [hl+]
    ld [queen_pNeckPatternBaseLow], a
    ld a, [hl]
    ld [queen_pNeckPatternBaseHigh], a
ret ;}

; Queen state table
queen_stateList: ;{ 03:7484
    db queenState_prepForwardWalk ; Walk forward
    db queenState_prepExtendingNeck, queenState_prepRetractingNeck ; Shove head forward and retract
    db queenState_prepExtendingNeck, queenState_prepRetractingNeck ; Shove head forward and retract
    db queenState_prepBackwardWalk ; Walk back
    db queenState_prepProjectiles ; Spit blobs
    db $ff ; Repeat
;}

queen_handleState: ; 03:748C
    ld a, [queen_state] ; Queen's state!
    rst LOW(RST_28)
        dw queenStateFunc_prepForwardWalk    ; $00 - 03:7821 - Prep forward walk
        dw queenStateFunc_forwardWalk        ; $01 - 03:783C - Walking forward
        dw queenStateFunc_prepExtendingNeck  ; $02 - 03:7864 - Prep neck extension
        dw queenStateFunc_extendingNeck      ; $03 - 03:78EE - Extending neck
        dw queenStateFunc_prepRetractingNeck ; $04 - 03:78F7 - Prep retraction
        dw queenStateFunc_retractingNeck     ; $05 - 03:7932 - Retracting neck
        dw queenStateFunc_prepBackwardWalk   ; $06 - 03:793B - Prep backwards walking
        dw queenStateFunc_backwardWalk       ; $07 - 03:7954 - Walking backward
        dw queenStateFunc_stomachBombed      ; $08 - 03:7970 - Stomach just bombed
        dw queenStateFunc_prepVomitingSamus  ; $09 - 03:79D0 - Prep spitting Samus out of stomach
        dw queenStateFunc_vomitingSamus      ; $0A - 03:79E1 - Spitting Samus out of stomach
        dw queenStateFunc_doneVomitingSamus  ; $0B - 03:7A1D - Done spitting Samus out of stomach
        dw queenStateFunc_pickNextState      ; $0C - 03:7846 - Init fight pt 3 (choose next state)
        dw queenStateFunc_prepEatingSamus    ; $0D - 03:772B - Prep Samus in mouth
        dw queenStateFunc_retractNeckEating  ; $0E - 03:776F - Samus in mouth (head retracting)
        dw queenStateFunc_samusEaten         ; $0F - 03:7785 - Samus in mouth/stomach (head retracted)
        dw queenStateFunc_vomitingOutMouth   ; $10 - 03:77DD - Spitting Samus out of mouth
        dw queenStateFunc_prepDeath          ; $11 - 03:7ABF - Prep death
        dw queenStateFunc_disintegrate       ; $12 - 03:7B05 - Dying pt 1 (disintegrating)
        dw queenStateFunc_deleteBody         ; $13 - 03:7B9D - Dying pt 2
        dw queenStateFunc_prepProjectiles    ; $14 - 03:7519 - Prepping blob spit
        dw queenStateFunc_projectilesActive  ; $15 - 03:757B - Blobs out
        dw queenStateFunc_allDone            ; $16 - 03:7BE7 - Dying pt 3
        dw queenStateFunc_startA             ; $17 - 03:74C4 - Start Fight A (wait to scream)
        dw queenStateFunc_startB             ; $18 - 03:74EA - Start Fight B (wait to move)
        dw enAI_NULL ; $19 - Wrong bank, you silly programmer!

queenStateFunc_startA: ;{ 03:74C4 - Queen State $17: Start Fight A (wait to scream)
    ; Wait until timer expires
    ld a, [queen_delayTimer]
    and a
    jr z, .else_A
      .decTimer:
        dec a
      .setTimer:
        ld [queen_delayTimer], a
        ret
    .else_A:
        ; Open mouth
        ld a, $02
        ld [queen_headFrameNext], a
        ; Set state to Start B
        ld a, queenState_startB
        ld [queen_state], a
        ; Make different noises based on aggression flag?
        ld a, [queen_lowHealthFlag]
        and a
        ld a, sfx_noise_metroidQueenCry
        jr z, .endIf_B
            ld a, sfx_noise_metroidQueenHurtCry
        .endIf_B:
        ld [sfxRequest_noise], a
        ; Set timer for next state
        ld a, $32
        jr .setTimer
;}

queenStateFunc_startB: ;{ 03:74EA - Queen State $18: Start Fight B (wait to move)
    ; Wait for timer to expire
    ld a, [queen_delayTimer]
    and a
        jr nz, queenStateFunc_startA.decTimer
    ; Close mouth
    ld a, $01
    ld [queen_headFrameNext], a
    ; Set state to Pick Next State
    ld a, queenState_pickNextState
    ld [queen_state], a
ret ;}

queen_getSamusTargets: ;{ 03:74FB
    ; Set source pointer
    ld de, samus_onscreenYPos
    ; Set destination pointer
    ld hl, queen_samusTargetPoints
    
    ; Samus Y
    ld a, [de]
    ld b, a
    ld [hl+], a
    ; Samus X
    inc de
    ld a, [de]
    ld c, a
    ld [hl+], a
    
    ; Samus Y - $10
    ld a, -$10 ; $F0
    add b
    ld [hl+], a
    ; Samus X - $10
    ld a, -$10 ; $F0
    add c
    ld [hl+], a
    
    ; Samus Y + $10
    ld a, $10
    add b
    ld [hl+], a
    ; Samus X + $10
    ld a, $10
    add c
    ld [hl], a
ret ;}

queenStateFunc_prepProjectiles: ;{ 03:7519 - Queen State $14: Prep spitting projectiles
    ; Get homing targets for projectiles
    call queen_getSamusTargets
    
    ; Get Y offset for projectiles
    ld a, [queen_headY]
    add $20
    ld b, a
    
    ; Get X offset for projectiles
    ld a, [queen_headX]
    add $1c
    ld c, a
    
    ; Spawn first projectile
    ld hl, queenActor_spitA ;$C740
    ld d, $20 ; Directional flag
    call queen_spawnOneProjectile
    ; Spawn second projectile
    ld l, LOW(queenActor_spitB) ; $60
    ld d, $20
    call queen_spawnOneProjectile
    ; Spawn third projectile
    ld l, LOW(queenActor_spitC) ; $80
    ld d, $21
    call queen_spawnOneProjectile
    
    ; Unnecessarily setting these variables
    ld hl, queen_objectOAM ; $C308
    ld de, queenActor_spitA ; $C740
    ld b, $03
    
    ; Draw projectiles
    call queen_drawProjectiles
    
    ; Set number of times the projectiles will switch bearings to chase Samus
    ld a, $0e
    ld [queen_projectileChaseCounter], a
    
    ; Open mouth
    ld a, $02
    ld [queen_headFrameNext], a
    
    ; Set delay timer for next state
    ld a, $20
    ld [queen_delayTimer], a
    
    ; Set timer
    ld a, $10
    ld [queen_projectileChaseTimer], a

    ; Set state to Blobs out
    ld a, queenState_projectilesActive
    ld [queen_state], a

    ; Set flag to indicate projectiles are active
    ld [queen_projectilesActiveFlag], a
    ld de, -8 ; $FFF8
    add hl, de
jp queen_drawNeck.saveScratchpadPointer ;}

; Spawn Queen's spit
queen_spawnOneProjectile: ;{ 03:756C
    ; Set status to active
    ld [hl], $00
    ; Set Y to B
    inc l
    ld [hl], b
    ; Set X to C
    inc l
    ld [hl], c
    ; Set sprite type
    inc l
    ld [hl], QUEEN_ACTOR_PROJECTILE ; $F2
    
    ; Set flip flags to D
    ld a, l
    add $05
    ld l, a
    ld [hl], d
ret ;}

queenStateFunc_projectilesActive: ;{ 03:757B - Queen State $15: Projectiles out
    ; Check delay timer
    ld a, [queen_delayTimer]
    and a
    jr z, .endIf_A
        ; Decrement delay timer, and close mouth once it's expired
        dec a
        ld [queen_delayTimer], a
        jr nz, .endIf_A
            ld a, $01
            ld [queen_headFrameNext], a
    .endIf_A:

    call queen_handleProjectiles ; Handle projectiles
    
    ; Check the collision type
    ld a, [collision_weaponType]
    cp $ff
        jr z, .clearCollision
    cp $20
        jr z, .clearCollision
    ; Only missiles and screw can destroy these projectiles
    cp $08
        jr z, .verifyCollision
    cp $10
        jr nz, .clearCollision

.verifyCollision:
    ; Verify the collision happened in a slot >= $C740
    ld a, [collision_pEnemyHigh]
    cp HIGH(queenActor_spitA) ; $C7
        jr nz, .clearCollision
    ld h, a
    ld a, [collision_pEnemyLow]
    cp LOW(queenActor_spitA) ; $40
        jr c, .clearCollision

    ; If so, deactivate projectile
    ld l, a
    ld [hl], $ff

.clearCollision:
    ; Clear collision type
    ld a, $ff
    ld [collision_weaponType], a
    
    ; Check if any projectiles are active
    ld de, enemyDataSlotSize
    ld hl, queenActor_spitA ; $C740
    ld b, $03
    .loop_A:
        ; Check if active or not (break if active)
        ld a, [hl]
        cp $ff
            jr nz, .break
        ; Iterate to next projectile
        add hl, de
        dec b
    jr nz, .loop_A
    
    ; If all are inactive, end the state and move on to the next
    jr .endState
    
    ; Else, draw the projectiles and keep going
    .break:
    call queen_drawProjectiles
ret

.endState:
    ; Deactivate all projectiles (even though that have to be inactive for us to be here...)
    ld hl, queenActor_spitA ; $C740
    ld de, enemyDataSlotSize
    ld b, $03
    .loop_B:
        ld [hl], $ff
        add hl, de
        dec b
    jr nz, .loop_B
    
    ; Clear OAM scratchpad
    ld hl, queen_objectOAM ; $C308
    ld de, $0004
    ld b, $0c
    ld a, $ff
    .loop_C:
        ld [hl], a
        add hl, de
        dec b
    jr nz, .loop_C
    
    ; Pick the next state
    call queenStateFunc_pickNextState
    
    ; Clear flag to signal projectiles are inactive
    xor a
    ld [queen_projectilesActiveFlag], a
    
    ; Clear the OAM scratchpad pointer
    ld hl, oamScratchpad
jp queen_drawNeck.saveScratchpadPointer
;}

; Draw projectiles
queen_drawProjectiles: ;{ 03:75FA
    ; Destination address (note this assumes the neck is not being drawn)
    ld hl, queen_objectOAM ; $C308
    ; Source actor addresses
    ld de, queenActor_spitA ; $C740

    ld b, $03 ; Number of projectiles
    .loop:
        ; Save loop counter
        push bc
    .loopAfterDeactivation:
        ; Save actor address
        push de
        
        ; Load status
        ld a, [de]
        ; Set default YX position to draw
        ld bc, $f0f0
        ; Skip bounds check if inactive
        cp $ff
            jr z, .skipProjectile
        
        ; Deactivate if Y position is out of range
        inc e
        ld a, [de]
        cp $E0
            jr nc, .deactivate
        ; Save Y postion to B
        ld b, a
        
        ; Deactivate if X position is out of range
        inc e
        ld a, [de]
        cp $E0
            jr nc, .deactivate
        ; Save X position to C
        ld c, a
    
    .skipProjectile:
        ; Draw at the (Y,X) position of (B,C)
        call queen_drawOneProjectileMetasprite
        
        ; Restore actor address
        pop de
        ; Restore loop counter
        pop bc
        
        ; Iterate to next blob
        ld a, e
        add enemyDataSlotSize
        ld e, a
        ; Exit if done
        dec b
    jr nz, .loop
ret

.deactivate:
    ; Reload actor address
    pop de
    ; Set status to inactive
    ld a, $ff
    ld [de], a
    jr .loopAfterDeactivation
;}

; Draw one projectile, given Y,X in B,C
queen_drawOneProjectileMetasprite: ;{ 03:762D
    ; Draw tiles counter-clockwise from bottom-right
    ; Set tile number
    ld d, $f1
    ; Set attribute
    ld e, OAM_PRIO | OAM_YFLIP ; $c0
    call queen_drawOneProjectileSprite
    
    ; Subtract 8 from Y position
    ld a, -8 ; $F8
    add b
    ld b, a
    ; Set attribute
    ld e, OAM_PRIO ; $80
    call queen_drawOneProjectileSprite
    
    ; Subtract 8 from X position
    ld a, -8 ; $F8
    add c
    ld c, a
    ; Change tile to $F0
    dec d
    call queen_drawOneProjectileSprite
    
    ; Add 8 to Y position
    ld a, $08
    add b
    ld b, a
    ; Set attribute
    ld e, OAM_PRIO | OAM_YFLIP ; $C0
    call queen_drawOneProjectileSprite
ret ;}

; Draws one hardware sprite of a projectile
;  B,C,D,E -> Y,X,T,A
queen_drawOneProjectileSprite: ;{ 03:764F
    ; Write Y
    ld [hl], b
    ; Write X
    inc l
    ld [hl], c
    ; Write tile number
    inc l
    ld [hl], d
    ; Write tile attributes
    inc l
    ld [hl], e
    ; Iterate to next sprite
    inc l
ret ;}

; Handle queen's spit
queen_handleProjectiles: ;{ 03:7658
    ; Iterate through projectiles
    ld b, $03
    ld hl, queenActor_spitA ; $C740
    .loop_A:
        push hl
        push bc
            ; Check if projectile is active
            ld a, [hl]
            and a
            jr nz, .endIf_A
                call queen_moveOneProjectile
            .endIf_A:
        pop bc
        pop hl
        ; Iterate to next projectile
        ld de, enemyDataSlotSize
        add hl, de
        dec b
    jr nz, .loop_A

    ; Exit if timer is not zero
    ld a, [queen_projectileChaseTimer]
    and a
    jr z, .endIf_B
        ; Decrement timer
        dec a
        ld [queen_projectileChaseTimer], a
        ret
    .endIf_B:
    ; Reset timer
    ld a, $03
    ld [queen_projectileChaseTimer], a
    
    ; Exit if counter is zero
    ld a, [queen_projectileChaseCounter]
    and a
        ret z
    ; Decrement counter
    dec a
    ld [queen_projectileChaseCounter], a
    
    call queen_getSamusTargets
    
    ; Iterate through projectiles and their corresponding Samus targets
    ld hl, queenActor_spitA + 8 ; $C748
    ld de, queen_samusTargetPoints
    ld b, $03
    .loop_B:
        ; Save registers
        push hl
        push de
        push bc
            call queen_projectileSeek
        pop bc
        pop de
        pop hl
        ; Iterate to next actor
        ld a, l
        add enemyDataSlotSize
        ld l, a
        ; Iterate to next Samus target
        inc de
        inc de
        dec b
    jr nz, .loop_B
ret ;}

; Function for projectile chasing Samus?
queen_projectileSeek: ;{ 03:76A6
    ; Load directional flags to temp
    ld a, [hl]
    ld [queen_projectileTempDirection], a
    ; Set HL to Y position
    ld a, l
    sub $07
    ld l, a
    ; Get lower nybble of direction byte (Y nybble)
    ld a, [queen_projectileTempDirection]
    and $0f
    ld c, a
    ; Adjust Y nybble of direction byte
    call queen_projectileSeekOneAxis

    ; Increment pointer to point to Samus X target and actor X position
    inc de
    inc hl
    ; Save results to B
    ld a, c
    and $0f
    ld b, a
    
    ; Get upper nybble of direction byte
    ld a, [queen_projectileTempDirection]
    and $f0
    ; Swap it to the lower nybble and store in C
    swap a
    ld c, a
    ; Adjust X nybble of direction byte
    call queen_projectileSeekOneAxis
    
    ; Combined both nybbles and save results to B
    ld a, c
    and $0f
    swap a
    or b
    ld b, a
    ; Reset HL to point at direction byte
    ld a, l
    add $06
    ld l, a
    ; Store new direction byte
    ld [hl], b
ret ;}

; Function for projectile chasing Samus
queen_projectileSeekOneAxis: ;{ 03:76D5
; DE points to target
; HL points to position
; Lower nybble of C stores the direction value (E, F, 0, 1, 2)
    ; A = Target - Position
    ld a, [de]
    sub [hl]
        ret z
    
    ; Store difference and processor flags
    push af
    
    ; If projectile is within 6 pixels of target
    ;  then branch ahead and consider doing nothing
    cp $06
        jr c, .considerNoAction
    cp $fa
        jr nc, .considerNoAction

.chooseDirection:
    ; Reload processor flags for (Target - Position)
    pop af
    ; Load direction value
    ld a, c
    ; Branch if Target >= Position
        jr nc, .moveForward

; moveBackward
    ; Clamp to a minimum value of -2 (just looking at the single nybble)
    cp -2 & $0F ; $0e
        ret z
    ; Decrement by 1
    dec a
    ; (unless the result is zero, in which case decrement again)
    and $0f
        jr nz, .exit
    dec a
; jr .exit

.exit:
    ; Save result to C
    ld c, a
ret

.moveForward:
    ; Clamp to a max value of 2
    cp $02
        ret z
    ; Increment by 1
    inc a
    ; (unless the result is zero, in which case increment again)
    and $0f
        jr nz, .exit
    inc a
jr .exit

.considerNoAction:
    ; If the direction value is zero (not moving) then do nothing.
    ;  else, choose a direction to head in
    ld a, c
    and a
        jr nz, .chooseDirection
    ; Clean stack
    pop af
ret
;}

; Move one spitball according to their direction flags (XY)
queen_moveOneProjectile: ;{ 03:7701
    ; Set loop counter (two axes)
    ld b, $02
    ; Increment HL to Y position
    inc hl
    push hl
        ; Store projectile's direction flags in temp
        ld a, l
        add $07
        ld l, a
        ld a, [hl]
        ld [queen_projectileTempDirection], a
    pop hl
    push hl
        ld a, [queen_projectileTempDirection]
        .loop:
            ; Check the lower nybble
            and $0f
            ; Don't move if zero
            jr z, .endIf
                ; Check if bit 3 is set ($x8)
                bit 3, a
                jr nz, .else
                    ; If not set, treat nybble as positive
                    ;  and move forward 2 pixels
                    inc [hl]
                    inc [hl]
                    jr .endIf
                .else:
                    ; If set, treat nybble as negative
                    ;  and move backward 2 pixels
                    dec [hl]
                    dec [hl]
            .endIf:
            ; Increment HL to X position
            inc hl
            ; Swap nybbles and iterate to do the X axis
            ld a, [queen_projectileTempDirection]
            swap a
            dec b
        jr nz, .loop
    pop hl
ret ;}

queenStateFunc_prepEatingSamus: ;{ 03:772B - Queen State $0D: Prep Samus in mouth
    ; Load neck pointer
    ld a, [queen_pNeckPatternLow]
    ld l, a
    ld a, [queen_pNeckPatternHigh]
    ld h, a
    ; Move on to next state if we were at the very end of a neck extension (?)
    ld a, [hl]
    cp $81
        jp z, queenStateFunc_pickNextState
    
    ; Set queen neck to rectract
    ld a, $02
    ld [queen_neckDrawingState], a
    ld [queen_neckControl], a
    
    ; Adjust head downwards if it's in the upward pose
    ld a, [queen_headFrame]
    cp $03
    jr nz, .endIf
        ld a, [queen_headY]
        add $10
        ld [queen_headY], a
    .endIf:
    ; Set head to normal frame
    ld a, $01
    ld [queen_headFrameNext], a
    ld [queen_headFrame], a
    
    ; Clear status
    xor a
    ld [queen_neckStatus], a
    
    ; Deactivate mouth
    ld a, $ff
    ld [queenActor_mouth], a
    ld a, QUEEN_ACTOR_MOUTH_CLOSED ; $F5
    ld [queenActor_mouth + 3], a
    
    ; Set state to Samus in mouth (head retracting)
    ld a, queenState_retractNeckEating
    ld [queen_state], a
    
    ; Decrement neck pointer and save
    dec hl
jp queen_moveNeck.saveNeckPointer ;}

queenStateFunc_retractNeckEating: ;{ 03:776F - Queen State $0E: Samus in mouth (neck retracting)
    ; Wait until neck has fully retracted
    ld a, [queen_neckStatus]
    cp $82
        ret nz
    ; Set eating state to mouth closed and in place
    ld a, $03
    ld [queen_eatingState], a
    ; Set state to Samus in mouth/stomach (head retracted)
    ld a, queenState_samusEaten
    ld [queen_state], a
    ; Animate
    ld a, $01
    ld [queen_footFrame], a
ret ;}

queenStateFunc_samusEaten: ;{ 03:7785 - Queen State $0F: Samus in mouth/stomach
    ; Check if the mouth was just bombed
    ld a, [queen_eatingState]
    cp $04
    jr nz, .else_A
        ; Mouth was just bombed
        ; Hurt queen for 10 damage, kill if necessary
        ld a, [queen_health]
        sub $0A
        ld [queen_health], a
            jr c, .kill
        ; Set eating state to Samus escaping bombed mouth
        ld a, $05
        ld [queen_eatingState], a
        ; Open mouth
        ld a, $02
        ld [queen_headFrameNext], a
        ld [queen_headFrame], a
        ; Set state to Spitting Samus out of mouth
        ld a, queenState_vomitingOutMouth
        ld [queen_state], a
        ; Set timer
        ld a, $3e
        ld [queen_stunTimer], a
        ; Make the queen flash
        ld a, $93
        ld [queen_bodyPalette], a
        ; Make noise
        ld a, sfx_noise_metroidQueenHurtCry
        ld [sfxRequest_noise], a
        ret
    .else_A:
        ; Check if the Queen is swallowing Samus
        cp $06
        jr nz, .else_B
            ; Do nothing if so
            ret
        .else_B:
            ; Check if the Queen's stomach was just bombed (exit if not)
            cp $07
                ret nz
            ; Set eating state to Samus escaping stomach
            ld a, $08
          .killExit:
            ld [queen_eatingState], a
            ; Set state to Queen's stomach just bombed
            ld a, queenState_stomachBombed
            ld [queen_state], a
            ; Have the queen flash
            ld a, $93
            ld [queen_bodyPalette], a
            ; Make noise
            ld a, sfx_noise_metroidQueenHurtCry
            ld [sfxRequest_noise], a
            ret

.kill:
    ; Clear the queen's health
    xor a
    ld [queen_health], a
    ; Set eating state to dying (from mouth bombing)
    ld a, $20
jr .killExit
;}

queenStateFunc_vomitingOutMouth: ;{ 03:77DD -  Queen State $10: Spitting Samus out
    ; Wait for stun timer to expire
    ld a, [queen_stunTimer]
    and a
    jr z, .else
        ; Decrement timer in the meantime
        dec a
        ld [queen_stunTimer], a
        
        ; Restore body/neck palette at a timer value of $2E
        cp $2e
        jr nz, .endIf
            xor a
            ld [queen_bodyPalette], a
            call queen_setDefaultNeckAttributes
        .endIf:
        
        ; Check foot frame
        ld a, [queen_footFrame]
        cp $02
            ret nz
        ; Stop feed
        xor a
        ld [queen_footFrame], a
        ret
    .else:
        ; Clear eating state
        ld [queen_eatingState], a
        ; Set head to default
        ld a, $01
        ld [queen_headFrameNext], a
        ld [queen_headFrame], a
        ; Pointless state assignment given the jump right there
        ld a, queenState_prepBackwardWalk
        ld [queen_state], a
        ld hl, queen_stateList + 6 ;$748a
        jr queenStateFunc_pickNextState.direct ; Set state to queen_stateTable[6]
;}

; Set default sprite attributes for neck
queen_setDefaultNeckAttributes: ;{ 03:7812
    ; Iterate for all 12 sprites
    ld b, $0c
    ld hl, queen_objectOAM ;$c308
    .loop:
        ; Skip Y, X, and tile
        inc l
        inc l
        inc l
        ; Write priority
        ld a, OAM_PRIO ;$80
        ld [hl+], a
        ; Loop until it's done
        dec b
    jr nz, .loop
ret ;}

queenStateFunc_prepForwardWalk: ;{ 03:7821 - Queen State $00: Prep forward walk
    ; Clear forward walk
    xor a
    ld [queen_walkCounter], a
    ; Don't draw the neck
    ld [queen_neckDrawingState], a
    ; Set to 1 (walk forwards)
    inc a
    ld [queen_walkControl], a
    ; Have the neck follow the body (if extended at all)
    ld a, $03
    ld [queen_neckControl], a
    ; Set foot frame
    ld a, $02
    ld [queen_footFrame], a
    ; Set state to Walking forward
    ld a, queenState_forwardWalk
    ld [queen_state], a
ret ;}

queenStateFunc_forwardWalk: ;{ 03:783C - Queen State $01 - Walking forwards
    ; Wait until we're done walking forwards
    ld a, [queen_walkStatus]
    cp $81
        ret nz
    ; End foot animation
    xor a
    ld [queen_footFrame], a
    ; fallthrough to queenStateFunc_pickNextState
;}

; This is commonly jumped to directly
;  also has an entry point for selecting the next state immediately
queenStateFunc_pickNextState: ;{ 03:7846 - Queen State $0C: Pick next state from list
    ; Load pointer
    ld a, [queen_pNextStateLow]
    ld l, a
    ld a, [queen_pNextStateHigh]
    ld h, a
.tryAgain:
    ; Return to start of table if the end is reached
    ld a, [hl+]
    cp $ff
    jr z, .else
        ld [queen_state], a
      .direct: ; Alternate entry for directly setting the state pointer
        ; Save the state pointer
        ld a, l
        ld [queen_pNextStateLow], a
        ld a, h
        ld [queen_pNextStateHigh], a
        ret
    .else:
        ld hl, queen_stateList
        jr .tryAgain
;}

queenStateFunc_prepExtendingNeck: ;{ 03:7864 - Queen State $02 - Prep neck extension
    ; Activate mouth
    ld hl, queenActor_mouth ; $C620
    ld [hl], $00
    ; Set neck controls to extending the neck
    ld a, $01
    ld [queen_neckControl], a
    ld [queen_neckDrawingState], a
    ; Set next state to Extending neck
    ld a, queenState_extendingNeck
    ld [queen_state], a
    
    ; Flip flag every call
    ld a, [queen_neckSelectionFlag]
    xor $01
    ld [queen_neckSelectionFlag], a
    
    ; Default to else branch if below 100 health
    ld a, [queen_midHealthFlag]
    and a
        jr nz, .else_A
    ; Alternate to the else branch every other time
    ld a, [queen_neckSelectionFlag]
    and a
    jr z, .else_A
        ; Select downwards pattern by default
        ld a, [queen_headY]
        ld b, $02 ; downwards neck pattern
        
        ; Select the upwards neck pattern if the head is below $46 pixels onscreen
        cp $46
        jr c, .endIf_B
            ld b, $03
            
            ; Adjust head Y position for upwards frame
            ld a, [queen_headY]
            add -$10 ; $F0
            ld [queen_headY], a
            
            ; Select upwards frame
            ld a, $03
            ld [queen_headFrameNext], a
            ld [queen_headFrame], a
        .endIf_B:
        
        ; Store neck pattern index
        ld a, b
        ld [queen_neckPattern], a
        jp .endIf_A
    .else_A:
        ld a, [queen_headY]
        ; Choose downwards
        ld b, $00 ; downwards neck pattern
        ; Select another neck pattern if the head is below $29 pixels onscreen
        cp $29
        jr c, .endIf_C
            ld b, $06 ; Forwards neck pattern
            ; Select the upwards neck pattern if the head is below $4C pixels onscreen
            cp $4C
            jr c, .endIf_C
                ld b, $01 ; Upwards neck pattern
                ; Adjust head Y position for upwards frame
                ld a, [queen_headY]
                add -$10 ; $F0
                ld [queen_headY], a
        .endIf_C:
        
        ; Save neck pattern
        ld a, b
        ld [queen_neckPattern], a
        
        ; Select head pose
        ; Select upwards head pose by default
        ld b, $03
        ; Select a different pose if the upwards neck pattern was n
        cp $01
        jr z, .endIf_D
            ; Standard head pose
            ld b, $02
            ; Randomly set mouth to open (1/4 chance)
            ld a, [rDIV]
            and $03
            jr z, .endIf_A
                ld hl, queenActor_mouth + 3 ; $C623
                ld [hl], QUEEN_ACTOR_MOUTH_OPEN ; $F6
        .endIf_D:
        
        ; Save head frame
        ld a, b
        ld [queen_headFrameNext], a
        ld [queen_headFrame], a
    .endIf_A:

    ; Set the neck point based on the index
    call queen_setNeckBasePointer
    ; Load pointer to HL
    call queen_loadNeckBasePointer
    ; Skip the first entry of the neck pointer list (the byte that is used to stop it from retracting)
    inc hl
    ; Save the neck pointer
jp queen_moveNeck.saveNeckPointer ;}

queenStateFunc_extendingNeck: ;{ 03:78EE - Queen State $03: Extending neck
    ; Wait until status is $81
    ld a, [queen_neckStatus]
    cp $81
        ret nz
jp queenStateFunc_pickNextState ;}

queenStateFunc_prepRetractingNeck: ;{ 03:78F7 - Queen State $04: Prep neck retraction
    ; Load neck pointer to HL
    ld a, [queen_pNeckPatternLow]
    ld l, a
    ld a, [queen_pNeckPatternHigh]
    ld h, a
    ; If we were fully extended, simply move to the next state
    ld a, [hl]
    cp $81
        jp z, queenStateFunc_pickNextState

    ; Set controls to retract neck
    ld a, $02
    ld [queen_neckDrawingState], a
    ld [queen_neckControl], a
    
    ; If Queen's head was upwards, adjust it down
    ld a, [queen_headFrame]
    cp $03
    jr nz, .endIf
        ld a, [queen_headY]
        add $10
        ld [queen_headY], a
    .endIf:
    ; Set head frame to default
    ld a, $01
    ld [queen_headFrameNext], a
    ld [queen_headFrame], a
    
    ; Close the queen's mouth
    ld a, QUEEN_ACTOR_MOUTH_CLOSED ; $F5
    ld [queenActor_mouth + 3], a
    
    ; Set state manually to Retracting neck
    ld a, queenState_retractingNeck
    ld [queen_state], a
    
    ; Decrement/save neck pointer (in case it was at the end of the list?)
    dec hl
jp queen_moveNeck.saveNeckPointer ;}

queenStateFunc_retractingNeck: ;{ 03:7932 - Queen State $05: Retracting Neck
    ; Wait until status is $82
    ld a, [queen_neckStatus]
    cp $82
        ret nz
jp queenStateFunc_pickNextState ;}

queenStateFunc_prepBackwardWalk: ;{ 03:793B Queen State $06: Prep walking backwards
    ; Walk backwards
    ld a, $02
    ld [queen_walkControl], a
    ; Move neck with head
    ld a, $03
    ld [queen_neckControl], a
    ; Don't update neck rendering
    xor a
    ld [queen_neckDrawingState], a
    ; Set foot frame
    ld a, $82
    ld [queen_footFrame], a
    ; Set state to Walking backward
    ld a, queenState_backwardWalk
    ld [queen_state], a
ret ;}

queenStateFunc_backwardWalk: ;{ 03:7954 - Queen State $07: Walking Backwards
    ; Wait until we are finished walking backwards
    ld a, [queen_walkStatus]
    cp $82
        ret nz
    ; Disable walking animation
    xor a
    ld [queen_footFrame], a
jp queenStateFunc_pickNextState ;}

; Queen's neck sprite while she is vomiting Samus
queen_bentNeckSprite: ; 03:7961
    db $00, $00, $b5
    db $08, $00, $c5
    db $00, $08, $b6
    db $00, $10, $b7
    db $08, $0c, $c6

queenStateFunc_stomachBombed: ;{ 03:7970 - Queen State $08: Stomach Just Bombed
    ; Unnecessary comparisons of the Y position
    ld a, [queen_headY]
    cp $2c
    cp $71

    ; Set next to extend
    ld a, $01
    ld [queen_neckControl], a
    ; Do not perform the standard neck drawing procedure with extending the neck
    ;  because this function will manually draw the bent neck sprite
    xor a
    ld [queen_neckDrawingState], a
    
    ; Set head frame
    ld a, $03
    ld [queen_headFrameNext], a
    ld [queen_headFrame], a
    
    ; Set next state to Prep spitting Samus out of stomach
    ld a, queenState_prepVomitingSamus
    ld [queen_state], a
    
; Write diagonal neck sprite
    ; Set destination pointer
    ld hl, queen_objectOAM ; $C308
    
    ; Get Y offset for sprite
    ld a, [queen_headY]
    add $14
    ld b, a
    ; Get X offset for sprite
    ld a, [queen_headX]
    add $02
    ld c, a
    
    ; Set source pointer
    ld de, queen_bentNeckSprite

    .loop:
        ; Write Y position
        ld a, [de]
        add b
        ld [hl+], a
        ; Write X position
        inc de
        ld a, [de]
        add c
        ld [hl+], a
        ; Write tile number
        inc de
        ld a, [de]
        ld [hl+], a
        ; Write attributes
        ld [hl], $80
        ; Iterate to next sprite
        inc l
        inc de
        ld a, l
        cp LOW(queen_bentNeckOAM_end) ; $1C
    jr nz, .loop

    ; Decrement queen_pOamScratchpadLow by four
    ; (unsure why it does this, but I think it's to make the sprite erasing code work properly)
    dec l
    dec l
    dec l
    dec l
    ld a, l
    ld [queen_pOamScratchpadLow], a
    ld a, h
    ld [queen_pOamScratchpadHigh], a
    
    ; Select neck pattern (vomiting Samus)
    ld a, $04
    ld [queen_neckPattern], a
    ; Set flag
    ld [queen_stomachBombedFlag], a
    ; Set neck pointer based on index
    call queen_setNeckBasePointer
    ; Skip the first byte of the neck speed list (because it tells the Queen to stop retracting the neck)
    call queen_loadNeckBasePointer
    inc hl
jp queen_moveNeck.saveNeckPointer ;}

queenStateFunc_prepVomitingSamus: ;{ 03:79D0 - Queen State $09: Prep spitting Samus out of stomach
    ; Wait until neck is extended
    ld a, [queen_neckStatus]
    cp $81
        ret nz
    ; Set delay timer for next state
    ld a, $50
    ld [queen_delayTimer], a
    ; Set next state to Spitting Samus out
    ld a, queenState_vomitingSamus
    ld [queen_state], a
ret ;}

queenStateFunc_vomitingSamus: ;{ 03:79E1 - Queen State $0A: Spitting Samus out of stomach
    ; Wait for delay timer to expire
    ld a, [queen_delayTimer]
    and a
    jr z, .else
        ; Decrement timer
        dec a
        ld [queen_delayTimer], a
        ; Exit it foot is not on a particular frame
        ld a, [queen_footFrame]
        cp $02
            ret nz
        ; Stop foot animation
        xor a
        ld [queen_footFrame], a
        ret
    .else:
        ; Clear queen's body palette
        xor a
        ld [queen_bodyPalette], a
        
        ; Check if queen is dead
        ld a, [queen_health]
        and a
            jr z, queen_killFromStomach
        ; Apply stomach bomb damage, kill if applicable
        sub $1E ; Hurt for 30 damage with bombs
        ld [queen_health], a
            jr c, queen_killFromStomach
        
        ; Set neck to retract
        ld a, $02
        ld [queen_neckControl], a
        ; Set state to Done spitting Samus out
        ld a, queenState_doneVomitingSamus
        ld [queen_state], a
        
        ; Set neck pattern
        ld a, [queen_pNeckPatternLow]
        ld l, a
        ld a, [queen_pNeckPatternHigh]
        ld h, a
        dec hl
        jp queen_moveNeck.saveNeckPointer
;}

queenStateFunc_doneVomitingSamus: ;{ 03:7A1D - Queen State $0B: Done spitting Samus out of stomach
    ; Wait until neck has finished retracting
    ld a, [queen_neckStatus]
    cp $82
        ret nz
        
    ; Animate head
    ld a, $01
    ld [queen_headFrameNext], a
    ld [queen_headFrame], a
    
    ; Clear flag
    xor a
    ld [queen_stomachBombedFlag], a
    
    ; Clear bent neck sprite
    ld hl, queen_objectOAM ; $C308
    ld b, $05
    .loop:
        ; Set y pos offscreen
        ld [hl], $ff
        inc l
        inc l
        inc l
        ; Set attribute
        ld [hl], $80
        ; Iterate to next sprite, exit if done
        inc l
        dec b
    jr nz, .loop

    ; Reset OAM scratchpad pointer
    ld hl, oamScratchpad
    ld a, l
    ld [queen_pOamScratchpadLow], a
    ld a, h
    ld [queen_pOamScratchpadHigh], a
    ; Pick next state
jp queenStateFunc_pickNextState ;}

queen_killFromStomach: ;{ 03:7A4D Kill Queen from stomach
    ; Deactivate all enemies
    ld b, $0D
    ld hl, enemyDataSlots ; $C600
    call queen_deactivateActors.arbitrary
    
    ; Set neck to extend
    ld a, $01
    ld [queen_neckControl], a
    ld [queen_neckDrawingState], a
    ; Set state to Prep death
    ld a, queenState_prepDeath
    ld [queen_state], a
    
    ; Clear several variables
    xor a
    ld [queen_neckXMovementSum], a
    ld [queen_neckYMovementSum], a
    ld [queen_stomachBombedFlag], a
    ld [queen_health], a
    ld [queen_neckStatus], a
    ld [queen_footFrame], a
    ld [queen_headFrameNext], a
    ld [queen_lowHealthFlag], a
    
    ; Reset OAM scratchpad pointer
    ld hl, queen_objectOAM ; $C308
    ld a, l
    ld [queen_pOamScratchpadLow], a
    ld a, h
    ld [queen_pOamScratchpadHigh], a
    ; Set priority bit of the first two sprites (why?)
    inc l
    inc l
    inc l
    ld [hl], OAM_PRIO ;$80
    inc l
    inc l
    inc l
    inc l
    ld [hl], OAM_PRIO ;$80
    
    ; Close the exit
    call queen_closeFloor
    
    ; Play sound
    ld a, sfx_noise_clearedSaveFile
    ld [sfxRequest_noise], a
    
    ; Drop the head to the ground
    ld a, $05 ; Dying neck pattern
    ld [queen_neckPattern], a
    call queen_setNeckBasePointer
    call queen_loadNeckBasePointer
    inc hl
jp queen_moveNeck.saveNeckPointer ;}

; Seals the bottom exit upon death
queen_closeFloor: ;{ 03:7AA8
    ; Get address to write. (X,Y) = (14,24)
    ld hl, $9800 + $20*24 + 14 ; $9B0E
    
    ; Wait for HBlank
    .waitLoop_A:
        ld a, [rSTAT]
        and $03
    jr nz, .waitLoop_A
    ; Write tile
    ld [hl], $5d
    
    inc l ; Iterate to next tile
    ; Wait for HBlank
    .waitLoop_B:
        ld a, [rSTAT]
        and $03
    jr nz, .waitLoop_B
    ; Write tile
    ld [hl], $5e
ret ;}

queenStateFunc_prepDeath: ;{ 03:7ABF - State $11: Prep Death
    ; Wait for head to finish falling
    ld a, [queen_neckStatus]
    cp $81
        ret nz
    ; Set delay timer for next state
    ld a, $50
    ld [queen_delayTimer], a
    ; Set state to disintegrating (dying part 1)
    ld a, queenState_disintegrate
    ld [queen_state], a
    ; Set animation counter
    ld a, $05
    ld [queen_deathAnimCounter], a
    ; Zero health for good measure
    xor a
    ld [queen_health], a
    ld [queen_deathArrayIndex], a
    
    ; Set table for disintegration animation
    ld hl, queen_deathArray
    ld [hl], $ee
    inc hl
    ld [hl], $bb
    inc hl
    ld [hl], $dd
    inc hl
    ld [hl], $77
    inc hl
    ld [hl], $ee
    inc hl
    ld [hl], $bb
    inc hl
    ld [hl], $dd
    inc hl
    ld [hl], $77

    ; Set earthquake timer
    ld a, $d0
    ld [earthquakeTimer], a
    ; Play earthquake sound
    ld a, $0e
    ld [songRequest], a
    ; Set eating state to "dying"
    ld a, $22
    ld [queen_eatingState], a
ret ;}

queenStateFunc_disintegrate: ;{ 03:7B05 - Queen State $12:  - Dying pt 1 (disintegrating)
    ld a, [queen_delayTimer]
    and a
    jr z, .endIf_A
        ; Decrement timer
        dec a
        ld [queen_delayTimer], a
        ; Wait a few frames before refilling health
        cp $4c
            ret nz
        ; Refill Samus health
        ld a, [samusEnergyTanks]
        ld [samusCurHealthHigh], a
        ld a, $99
        ld [samusCurHealthLow], a
        ret
    .endIf_A:

    ; Exit if bitmask is non-zero
    ld a, [queen_deathBitmask]
    and a
        ret nz
; Find next value for bitmask
    ; Use a loop to access queen_deathArray[queen_deathArrayIndex] (why?)
    ld de, queen_deathArray
    ld b, $00
    ld a, [queen_deathArrayIndex]
    .loop:
        ; Exit when B == queen_deathArrayIndex
        cp b
            jr z, .break
        inc de
        inc b
    jr .loop
    .break:
    ld b, a ; Double check B == A (seems unnecessary)
    ; Note: DE now points to queen_deathArray[queen_deathArrayIndex]
    
    ; Get starting address for next disintegration
    or LOW(queenDeath_firstTile) ;$10
    ld [queen_pDeathChrLow], a
    ; Get next value of index
    ; NOTE: This code relies on the relative primality of 3 and 8
    ;  to ensure every value from 0-7 is iterated through
    ld a, b
    add $03
    and $07
    ld [queen_deathArrayIndex], a

    ; Check if counter is zero
    jr nz, .endIf_B
        ; Decrement counter
        ld a, [queen_deathAnimCounter]
        dec a
        ld [queen_deathAnimCounter], a
            jr z, .nextState
    .endIf_B:

    ; Rotate bitmask value three times to the left
    ;  (again relying on the relative primality of 3 and 8)
    ld a, [de]
    rlca
    rlca
    rlca
    ld [de], a
    ; Load bitmask
    ld [queen_deathBitmask], a
    ; Load high byte of starting address
    ld a, HIGH(queenDeath_firstTile) ; $8B
    ld [queen_pDeathChrHigh], a
ret

.nextState:
    ld a, LOW(queenDeath_bodyStart)
    ld [queen_pDeleteBodyLow], a
    ld a, HIGH(queenDeath_bodyStart)
    ld [queen_pDeleteBodyHigh], a
    ; Set state to "Dying part 2"
    ld a, queenState_deleteBody
    ld [queen_state], a
ret
;}

; VBlank Routine
queen_disintegrate: ;{ 03:7B69
    ; Exit if disintegration bitmask is zero
    ld a, [queen_deathBitmask]
    and a
        ret z
    ld b, a
    ; Load starting address
    ld a, [queen_pDeathChrLow]
    ld l, a
    ld a, [queen_pDeathChrHigh]
    ld h, a
    ld de, $0008 ; Increment value
    ld c, $1a ; Max updates per frame

    ; Loop to clear pixels
    .clearLoop:
        ; AND chr value with bitmask
        ld a, [hl]
        and b
        ld [hl], a
        ; Increment to next pixel row
        add hl, de
        ; Break if on the last row of tiles (though we may re-enter the loop at .nextClear)
        ld a, h
        cp HIGH(queenDeath_lastTile) ;$95
            jr z, .break
      .nextClear:
        dec c
    jr nz, .clearLoop
        
        ; Premature exit
        ; Save pointer to keep clearing pixels next frame
        ld a, h
        ld [queen_pDeathChrHigh], a
        ld a, l
        ld [queen_pDeathChrLow], a
        ret
        
    .break:
        ; Keep clearing things unless we're on the last tile
        ld a, l
        and $f0
        cp LOW(queenDeath_lastTile) ;$70
            jr nz, .nextClear
        ; Clear bitmask to indicate we're done with it
        xor a
        ld [queen_deathBitmask], a
        ret
;}

; Note: Queen State $16 (All Done) is here
queenStateFunc_deleteBody: ;{ 03:7B9D - Queen State $13: Dying Part 2 (delete body)
    ; Get pointer
    ld a, [queen_pDeleteBodyLow]
    ld l, a
    ld a, [queen_pDeleteBodyHigh]
    ld h, a

    ; Delete row (routine runs during active display!!)
    ld b, $0b
    .clearLoop:
        ; Wait for HBlank twice and write, to ensure the write goes through
        .waitLoop_A:
            ld a, [rSTAT]
            and $03
        jr nz, .waitLoop_A
        ld [hl], $ff
    
        .waitLoop_B:
            ld a, [rSTAT]
            and $03
        jr nz, .waitLoop_B
        ld [hl], $ff

        ; Iterate to next tile
        inc hl
        dec b
    jr nz, .clearLoop

    ; Iterate to next row
    ld de, $0020 - $0b
    add hl, de

    ; Check if we're at the end
    ;  Note: this check relies on the fact that the queen's body is less than 128 pixels tall (i.e. contained in a range of less than 256 tiles from top to bottom)
    ld a, l
    cp LOW(queenDeath_bodyEnd)
    jr z, .else
        ; Save pointer for next frame
        ld [queen_pDeleteBodyLow], a
        ld a, h
        ld [queen_pDeleteBodyHigh], a
        ret
    .else:
        ; Clear variables
        xor a
        ld [queen_eatingState], a
        ; Zero out metroid counters
        ld [metroidCountDisplayed], a
        ld [metroidCountReal], a
        ; Set state to that stub right down there
        ld a, queenState_allDone
        ld [queen_state], a
        ; Shuffle counter and play noise
        ld a, $80
        ld [metroidCountShuffleTimer], a
        ld a, sfx_noise_babyMetroidCry
        ld [sfxRequest_noise], a
    queenStateFunc_allDone: ; 03:7BE7 - Queen State $16: All Done
        ret
;}

queen_walk: ;{ 03:7BE8
    ; Clear walking speed
    xor a
    ld [queen_walkSpeed], a
    ; Exit if not walking
    ld a, [queen_walkControl]
    and a
        ret z
    ld b, a
    
    ; Wait for wait timer to expire (never used?)
    ld a, [queen_walkWaitTimer]
    and a
    jr z, .else_A
        ; Decrement wait timer
        dec a
        ld [queen_walkWaitTimer], a
        ret
    .else_A:
        ; Index into walk-speed table and then increment counter
        ld a, [queen_walkCounter]
        ld l, a
        inc a
        ld [queen_walkCounter], a
        ld h, $00
        ld de, .walkSpeedTable
        add hl, de
        ; Check walking direction
        ld a, b
        cp $01
        jr nz, .else_B
            ; Walk forwards until $81 is encountered
            ld a, [hl]
            cp $81
                jr nz, .move
            ; Done walking backwards
            ; Set status to $81
            ld [queen_walkStatus], a
            ; Stop walking
            xor a
            ld [queen_walkControl], a
            ret
                
            .move: ; Common case between the above and below branches
                ; Negate value and store as speed
                cpl
                inc a
                ld [queen_walkSpeed], a
                ; Reload value and add to x position
                ld a, [hl]
                ld hl, queen_bodyXScroll
                add [hl]
                ld [hl], a
                ret
        
        .else_B:
            ; Walk backwards until $82 is encountered
            ld a, [hl]
            cp $82
                jr nz, .move
            ld [queen_walkStatus], a
            xor a
            ld [queen_walkControl], a
            ld [queen_walkCounter], a
            ret
; end proc

; Values are negated due to how the raster split works
;  $81 means "done walking forward"
;  $82 means "done walking backward"
.walkSpeedTable: ; 03:7C39
    db $ff, $ff, $ff, $ff, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe
    db $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $fe, $ff, $ff, $ff
    db $ff, $ff, $81, $01, $01, $01, $01, $02, $02, $02, $02, $02, $02, $02, $02, $02
    db $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02, $02
    db $01, $01, $01, $01, $01, $82
;}

; Interrupt handler only used by queen
LCDCInterruptHandler: ;{ 03:7C7F
    push af ; Caller function already pushed af, so this may be unnecessary
    push bc
    push de
    push hl
    ld a, [queen_pInterruptListLow]
    ld l, a
    ld a, [queen_pInterruptListHigh]
    ld h, a

    .loop:
        ; If token is FF, do nothing and don't set up another interrupt
        ld a, [hl]
        cp $ff
            jr z, .exitLastInterrupt
        and $7f
        cp $01
            jr z, .case_1 ; Set scroll X and palette to queen's
        cp $02
            jr z, .case_2 ; Set scroll X and palette to room's
        cp $03
            jr z, .case_3 ; Disable window (queen's head)
    
        ; case 4 (default) ; Draw status bar
            push hl
                ld hl, rLCDC
                res 5, [hl] ; Disable window
            pop hl
            ; Set scroll for status bar
            xor a
            ld [rSCX], a
            ld a, $70
            ld [rSCY], a
            inc l
        jr .exitLastInterrupt
        
        .case_3: ; Disable window
            push hl
            ld hl, rLCDC
            res 5, [hl]
            pop hl
        jr .nextToken
        
        .case_1: ; Set scroll X and palette to queen's
            ld a, [queen_bodyXScroll]
            ld [rSCX], a
            ; Skip writing palette if zero
            ld a, [queen_bodyPalette]
            and a
                jr z, .nextToken
            ld [rBGP], a
        jr .nextToken
        
        .case_2: ; Set scroll X and palette to room's
            ld a, [scrollX]
            ld [rSCX], a
            ld a, $93 ; FIXME: Causes palette issues if pausing is enabled
            ld [rBGP], a
        ; end case
    
    .nextToken:
        bit 7, [hl]
            jr z, .exitAndPrepNextInterrupt
        inc l
        inc l
    jr .loop

.exitAndPrepNextInterrupt:
    ; Load Y position for next interrupt
    inc l
    ld a, [hl+]
    ld [rLYC], a
.exitLastInterrupt:
    ; Save interrupt instruction pointer
    ld a, l
    ld [queen_pInterruptListLow], a
    ld a, h
    ld [queen_pInterruptListHigh], a
    pop hl
    pop de
    pop bc
    pop af
ret ;}


VBlank_drawQueen: ;{ 03:7CF0
    call queen_drawFeet ; Also draws head if no foot animation is ready
    call queen_disintegrate ; Disintegration effect?
    ; Set scroll position
    ld a, [scrollX]
    ld [rSCX], a
    ld a, [scrollY]
    ld [rSCY], a
    ; Set head X position (prevent rWX from being 166 due to hardware bug)
    ld a, [queen_headX]
    cp $a6
    jr nz, .endIf_A
        ld a, $a7
    .endIf_A:
    ld [rWX], a
; Start preparing the interrupt list
    ; Set head Y position
    ld a, [queen_headY]
    ld [rWY], a
    add queenInRoom_headHeight
    cp SCREEN_HEIGHT_PX
    jr c, .endIf_B
        ld a, SCREEN_HEIGHT_PX-1
    .endIf_B:
    ld [queen_headBottomY], a
    
    ; Calculate the lowest point of the queen's body  (clamp to $8F)
    ld a, [queen_bodyY]
    ld b, a
    ld a, [queen_bodyHeight]
    add b
    cp SCREEN_HEIGHT_PX
    jr c, .endIf_C
        ld a, SCREEN_HEIGHT_PX-1
    .endIf_C:
    ld d, a
    
    ld hl, queen_interruptList
    ld a, [queen_headBottomY]
    ld b, a
    ld a, [queen_bodyY]
    sub b
    jr c, .elseIf_D
        ; bodyY >= headBottomY
        ; Decide whether "disable window" is the only interrupt for its scanline or not
        ld c, $83
        jr z, .endIf_E
            ; bodyY > headBottomY
            ld c, $03
        .endIf_E:
        ; Write y pos of initial interrupt
        ld [hl], b
        ; Set interrupt type to "disable window"
        inc l
        ld [hl], c
        ; Set y pos of 2nd interrupt to the top of the queen's body
        inc l
        ld a, [queen_bodyY]
        ld [hl+], a
        ; Set interrupt tyoe to "queen's body"
        ld [hl], $01
        ; Set the ypos of the 3rd interrupt to the bottom of the queen's body
        inc l
        ld [hl], d
        ; Set interrupt type to "restore room"
        inc l
        ld [hl], $02
        jr .endIf_D
    .elseIf_D:
    
    ; bodyY < headBottomY
    ld a, b
    sub d
    jr c, .else_D
        ; headBottomY >= bodyBottomY
        ; Decide whether the "restore room" command will be the only iterrupt on its scanline
        ld c, $82
        jr z, .endIf_F
            ; headBottomY > bodyBottomY
            ld c, $02
        .endIf_F:
        ; Set the y position of the initial interrupt to the top of the queen's body
        ld a, [queen_bodyY]
        ld [hl+], a
        ; Set initial interrupt type to "queen's body"
        ld [hl], $01
        ; Set the ypos of next interrupt to the bottom of the queen's body
        inc l
        ld [hl], d
        ; Set interrupt type to "restore room"
        inc l
        ld [hl], c
        ; Set y pos of next interrupt to bottom of Queen's head
        inc l
        ld a, [queen_headBottomY]
        ld [hl+], a
        ; Set interrupt type to "disable window"
        ld [hl], $03
        jr .endIf_D
    .else_D:
        ; headBottomY < bodyBottomY
        ; Set y pos of inital interrupt to top of queen's body
        ld a, [queen_bodyY]
        ld [hl+], a
        ; Set interrupt type to "queen's body"
        ld [hl], $01
        ; Set y pos of 2nd interrupt to bottom of queen's head
        inc l
        ld a, [queen_headBottomY]
        ld [hl+], a
        ; Set interrupt type to "disable window"
        ld [hl], $03
        ; Set y pos of 3rd interrupt to bottom of queen's body
        inc l
        ld [hl], d
        ; Set interrupt type to "restore room"
        inc l
        ld [hl], $02
    .endIf_D:

; This displays the status bar by finding the first interrupt command with a scanline of 87 or greater and replacing it.
    ld b, $03
    ld hl, queen_interruptList
    .loop:
        ld a, [hl]
        cp $87
            jr nc, .break
        inc l
        inc l
        dec b
    jr nz, .loop
    .break:
    ; Set y position of last interrupt to $87 (scanline 135)
    ld [hl], $87
    ; Set interrupt type to "status bar"
    inc l
    ld [hl], $04
    ; Add interrupt list terminator
    inc l
    ld [hl], $ff
    ; Prep initial interrupt
    ld hl, queen_interruptList
    ld a, [hl+]
    ld [rLYC], a
    ; Prep interrupt pointer
    ld a, l
    ld [queen_pInterruptListLow], a
    ld a, h
    ld [queen_pInterruptListHigh], a
    ; Enable window display
    ld hl, rLCDC
    set 5, [hl]
ret ;}

bank3_freespace: ; 3:7DAD -- Freespace filled with $00 (nop)
