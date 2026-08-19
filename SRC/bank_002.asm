; Disassembly of "Metroid2.gb"
; This file was created with:
; mgbdis v1.4 - Game Boy ROM disassembler by Matt Currie and contributors.
; https://github.com/mattcurrie/mgbdis

SECTION "ROM Bank $002", ROMX[$4000], BANK[$2]

enemyHandler: ;{ 02:4000
    ; Initialize flag to not force metroid music to end
    ld e, $00
    ld a, [currentLevelBank]
    inc a
    ld [unused_romBankPlusOne], a
    ; Clear some variables if a screen transition just started
    ld a, [justStartedTransition]
    and a
    jr z, .endIf_A
        ; Set flag to force metroid music to end
        ld e, a
        ; Clear variables
        xor a
        ld [larva_bombState], a
        ld [larva_latchState], a
        ld [justStartedTransition], a
        ; Clear enemy collision variables
        ld a, $ff
        ld hl, enSprCollision.weaponType
        ld [hl+], a
        ld [hl+], a
        ld [hl], a
        ; Clear more enemy collision variables
        ld hl, collision_weaponType
        ld [hl+], a ; collision_weaponType
        ld [hl+], a ; collision_pEnemyLow
        ld [hl+], a ; collision_pEnemyHigh
        ld [hl], a  ; collision_weaponDir
    .endIf_A:

; Handle restoring music after a metroid fight
    ld a, [metroid_fightActive]
    and a ; Case 0 - No Metroids
        jr z, .handleEnemies
    cp $02 ; Case 2 - Metroid just died
        jr z, .metroidJustDied

    ; Case 1 (default) - Metroid fight active
        ; Restore music if a transition just started
        ld a, e
        and a
            jr z, .handleEnemies
        jr .restoreMusic
    
    .metroidJustDied: ; Case 2 - Metroid just exploded
        ld hl, metroid_postDeathTimer
        ld a, [hl]
        cp $90
        jr z, .else_B
            ; Increment timer every other frame
            ld a, [frameCounter]
            and $01
                jr nz, .endIf_B
            inc [hl]
            jr .endIf_B
        .else_B:
        .restoreMusic:
            ; Resume music unless all metroids are dead
            ld a, [metroidCountReal]
            and a
            jr z, .endIf_C
                ld a, [currentRoomSong]
                add $11 ; TODO: Replace this with a constant
                ld [songRequest], a
            .endIf_C:
            xor a
            ld [metroid_postDeathTimer], a
            ld [metroid_state], a
            ld [metroid_fightActive], a
        .endIf_B:

.handleEnemies:
    ; Load enemySolidityIndex
    ld a, [enemySolidityIndex_canon]
    ld [enemySolidityIndex], a
    ; Done after a door transition script is executed
    ld hl, saveLoadSpawnFlagsRequest
    ld a, [hl]
    and a
    jr z, .endIf_D
        call inGame_saveAndLoadEnemySaveFlags ; Save and then load enemy spawn/save flags
        xor a
        ld [saveLoadSpawnFlagsRequest], a
    .endIf_D:
    ; Exit early if too much time has passed
    ld a, [rLY]
    cp $70
        ret nc
    ; Load spawn flags without saving beforehand. Used when exiting the queen or loading a save.
    ld a, [loadSpawnFlagsRequest]
    and a
    jr nz, .endIf_E
        ; Load enemy save flags without saving them
        call inGame_loadEnemySaveFlags
        ld a, $01
        ld [loadSpawnFlagsRequest], a
    .endIf_E:

    call scrollEnemies_farCall ; Adjust enemy positions due to scrolling
    call processEnemies ; Handle each enemy
    call updateScrollHistory
    ; Check if it's too late to draw enemies
    ld a, [rLY]
    cp $70
        ret nc
    call drawEnemies_farCall
ret
;}

; Iterates over every enemy
processEnemies: ;{ 02:409E
    ; Load sizeOf(enemy struct)
    ld de, enemyDataSlotSize
    ; Load first enemy to process (not $C600 we went over the CPU budget for the previous frame)
    ld a, [enemy_pFirstEnemyLow]
    ld l, a
    ld a, [enemy_pFirstEnemyHigh]
    ld h, a
    ; Check if we're okay to start processing enemies from the beginning again.
    ld a, [enemy_sameEnemyFrameFlag]
    and a
    jr nz, .endIf_A
        ; Increment frame counter (every other frame in practice)
        ldh a, [hEnemy_frameCounter]
        inc a
        ldh [hEnemy_frameCounter], a
        ; Set number of enemies to process
        ld a, [numEnemies.total]
        ld [enemiesLeftToProcess], a
    .endIf_A:
    ; Skip processing if there are no enemies to process
    ld a, [enemiesLeftToProcess]
    and a
        jp z, .allEnemiesDone

.processOneEnemy:
    ; Check if enemy if active
    ld a, [hl]
    and $0f
        jr z, .processActiveEnemy
    dec a
        jr z, .processInactiveEnemy
    
    .moveToNextEnemy:
        add hl, de
    jr .processOneEnemy
    
    .processActiveEnemy:
        ; These functions can override their returns to jump to .doneProcessingEnemy
        call enemy_moveFromWramToHram
        call enemy_getDamagedOrGiveDrop ; Routine for either damaging an enemy or Samus collecting a drop
        call deactivateOffscreenEnemy ; Check if offscreen
        call enemy_commonAI ; Enemy AI and related stuffs
    
    .doneProcessingEnemy: ; A common target for return overrides
        call enemy_moveFromHramToWram
        ; Check if we're all done with enemies
        ld a, [enemiesLeftToProcess]
        dec a
        ld [enemiesLeftToProcess], a
            jr z, .allEnemiesDone
        ; Reload sizeOf(enemy struct)
        ld de, enemyDataSlotSize ; $0020
        ; Reload enemy base address
        ldh a, [hEnemyWramAddrLow]
        ld l, a
        ldh a, [hEnemyWramAddrHigh]
        ld h, a
        ; Stop processing enemies (to avoid lag)
        ld a, [rLY]
        cp $58
            jr nc, .endFrameEarly
    jr .moveToNextEnemy
    
    .processInactiveEnemy:
        ; These functions can override their returns to jump to .doneProcessingEnemy
        call enemy_moveFromWramToHram
        call deleteOffscreenEnemy ; Check if enemy is in deletable range and kill it
        call reactivateOffscreenEnemy ; Check if back onscreen
    jr .doneProcessingEnemy

.endFrameEarly:
    ; Save address of next enemy to start on them for the next frame
    add hl, de
    ld a, l
    ld [enemy_pFirstEnemyLow], a
    ld a, h
    ld [enemy_pFirstEnemyHigh], a
    ; Do not start from the beginning
    ld hl, enemy_sameEnemyFrameFlag
    inc [hl]
    jr .exit

.allEnemiesDone:
    ; Start from the first enemy next time
    xor a
    ld [enemy_pFirstEnemyLow], a
    ld a, HIGH(enemyDataSlots)
    ld [enemy_pFirstEnemyHigh], a
    ; Set flag so enemies are only processed every other frame (30 FPS)
    ld hl, enemy_sameEnemyFrameFlag
    ld a, [hl]
    and a
    jr z, .else_B
        xor a
        ld [hl], a
        jr .endIf_B
    .else_B:
        inc [hl]
    .endIf_B:
.exit:
    ; Check if it's too late to load enemies
    ld a, [rLY]
    cp $6c
        ret nc
    call handleEnemyLoading_farCall
ret
;}

; Loads enemy save flags from save buffer to WRAM without saving the previous set of flags to the save buffer
inGame_loadEnemySaveFlags: ;{ 02:412F
    ld d, $00
    ; Update level bank
    ld a, [currentLevelBank]
    ld [previousLevelBank], a
    ; HL = saveBuf_enemySpawnFlags + ((currentLevelBank-9)*16)*4
    sub $09
    swap a
    add a
    add a
    ld e, a
    rl d
    ld hl, saveBuf_enemySpawnFlags
    add hl, de
    ; Load enemySpawnFlags.saved from buffer
    ld de, enemySpawnFlags.saved
    ld b, $40
    .loop:
        ld a, [hl+]
        ld [de], a
        inc e
        dec b
    jr nz, .loop

    ; Reset first enemy data slot
    ld a, HIGH(enemyDataSlots)
    ld [enemy_pFirstEnemyHigh], a
    xor a
    ld [enemy_pFirstEnemyLow], a
    ; Clear other variables
    ld [metroid_state], a
    ld [metroid_fightActive], a
    ld [cutsceneActive], a
    ld [numEnemies.total], a
    ld [numEnemies.active], a
    ld [numEnemies.offscreen], a
    ld [enemy_sameEnemyFrameFlag], a
    ; Clear sprite collision stuff
    ld a, $ff
    ld [enSprCollision.weaponType], a
    ld [enSprCollision.pEnemyLow], a
    ld [enSprCollision.pEnemyHigh], a
    ld [enemy_weaponType], a
    ; Clear scroll history
    ld hl, scrollHistory_B.y2
    ld a, [scrollY]
    ld [hl+], a
    ld [hl+], a
    ld a, [scrollX]
    ld [hl+], a
    ld [hl], a
    ; Reload blob thrower sprite
    call blobThrower_loadSprite
ret
;}

; Save enemy save flags for previous map and then load save flags for new map
inGame_saveAndLoadEnemySaveFlags: ;{ 02:418C
    ; Clear first $40 enemy spawn flags
    ld hl, enemySpawnFlags.unsaved
    ld b, $40
    ld a, $ff
    .loop_A:
        ld [hl+], a
        dec b
    jr nz, .loop_A

    ; Save the enemySpawnFlags.saved to the save buffer
    ld d, $00
    ; Save variable to C for later
    ld a, [currentLevelBank]
    ld c, a
    ; I think this is intended to compare the current and previous banks, but I'm not sure if it works as intended. Possible minor bug?
    ld a, [previousLevelBank]
    and a
    jr z, .endIf
        ; HL = saveBuf_enemySpawnFlags + ((currentLevelBank-9)*16)*4
        sub $09
        swap a
        add a
        add a
        ld e, a
        rl d
        ld hl, saveBuf_enemySpawnFlags
        add hl, de
        ; Save flags to save buffer
        ld de, enemySpawnFlags.saved
        ld b, $40
        .loop_B:
            ld a, [de]
            cp $02 ; Save $02 as $02
                jr z, .saveAsIs
            cp $fe ; Save $FE as $FE
                jr z, .saveAsIs
            cp $04 ; Save $04 as $FE
                jr z, .saveAsFE
            cp $05 ; Ignore everything else besides $05
                jr nz, .ignore
            ; Save $05 as $FE
            .saveAsFE:
                ld a, $fe
            .saveAsIs:
                ld [hl], a
            .ignore:
                inc l
                inc e
                dec b
        jr nz, .loop_B
    .endIf:

    ld d, $00
    ; Update level bank
    ld a, c
    ld [previousLevelBank], a
    ; HL = saveBuf_enemySpawnFlags + ((currentLevelBank-9)*16)*4
    sub $09
    swap a
    add a
    add a
    ld e, a
    rl d
    ld hl, saveBuf_enemySpawnFlags
    add hl, de
    ; Copy enemySpawnFlags.saved from save buffer
    ld de, enemySpawnFlags.saved
    ld b, $40
    .loop_C:
        ld a, [hl+]
        ld [de], a
        inc e
        dec b
    jr nz, .loop_C

    ; Clear some variables
    xor a
    ld [enemy_pFirstEnemyLow], a
    ld [enemiesLeftToProcess], a
    ld [enemy_sameEnemyFrameFlag], a
    ; Reset first enemy to process
    ld a, HIGH(enemyDataSlots)
    ld [enemy_pFirstEnemyHigh], a
    ; Clear collision variables
    ld a, $ff
    ld [enSprCollision.weaponType], a
    ld [enSprCollision.pEnemyLow], a
    ld [enSprCollision.pEnemyHigh], a
    ; Clear scroll history
    ld hl, scrollHistory_B.y2
    ld a, [scrollY]
    ld [hl+], a
    ld [hl+], a
    ld a, [scrollX]
    ld [hl+], a
    ld [hl], a

    call deactivateAllEnemies
ret
;}

; Deactivates all enemy slots
deactivateAllEnemies: ;{ 02:4217
    ; Deactivate all 10 enemy data slots
    ld a, $ff
    ld hl, enemyDataSlots
    ld c, enemyDataSlotSize ; $20
    ld d, $10
    .loop_A:
        ld [hl], a
        add hl, bc
        dec d
    jr nz, .loop_A

    ; Clear enemy temps in HRAM
    ld b, $16
    ld hl, hEnemyWorkingHram ; $ffe0
    .loop_B:
        ld [hl+], a
        dec b
    jr nz, .loop_B

    ; Clear numEnemies.total and related variables
    xor a
    ld hl, numEnemies
    ld b, $03
    .loop_C:
        ld [hl+], a
        dec b
    jr nz, .loop_C
ret
;}

;------------------------------------------------------------------------------
; Handles logic related to hurting enemies and collecting enemy drops
enemy_getDamagedOrGiveDrop: ;{ 02:4239
    ; Check if a collision was made and exit if not (?)
    ld hl, collision_weaponType
    ld a, [hl+]
    cp $ff
        ret z
    ldh a, [hEnemyWramAddrLow]
    cp [hl]
        ret nz
    inc hl
    ldh a, [hEnemyWramAddrHigh]
    cp [hl]
        ret nz

    ldh a, [hEnemy.explosionFlag]
    and a
        jp nz, .transferCollisionResults ; Exit
    ; If not a drop, attempt to apply damage
    ldh a, [hEnemy.dropType]
    and a
        jr z, .applyDamage

; Enemy Drop collection case {
    ; Check if touching drop
    dec hl
    dec hl
    ld a, [hl]
    cp $10
        jp c, .transferCollisionResults ; Exit

    ldh a, [hEnemy.dropType]
    dec a ; Case 1 - Small Health
        jr z, .giveSmallHealth
    dec a ; Case 2 - Large Health
        jr z, .giveLargeHealth
    ; Case 4 (default) - Missile Drop
        jr .giveMissileDrop

    .giveLargeHealth:
        ; Set value (BCD)
        ld b, $20
        ; Play sound
        ld a, sfx_square1_pickedUpLargeEnergyDrop
        ld [sfxRequest_square1], a
        jr .giveHealth
    .giveSmallHealth:
        ; Set value (BCD)
        ld b, $05
        ; Play sound
        ld a, sfx_square1_pickedUpSmallEnergyDrop
        ld [sfxRequest_square1], a

.giveHealth:
    ; Add health
    ld hl, samusCurHealthLow
    ld a, [hl]
    add b
    daa
    ld [hl+], a
    ; Carry results to energy tanks
    ld a, [hl]
    adc $00
    ld [hl], a
    ; Check if above max
    ld a, [samusEnergyTanks]
    sub [hl]
    jr nc, .endIf_A
        ; Clamp health to max
        dec [hl]
        dec hl
        ld [hl], $99
    .endIf_A:
.deleteDrop:
    call enemy_deleteSelf_farCall
    ; Kill enemy permanently if applicable
    ld a, $02
    ldh [hEnemy.spawnFlag], a
    ; Clear stuff
    call .transferCollisionResults
    ld hl, enSprCollision.weaponType
    ld a, $ff
    ld [hl+], a
    ld [hl+], a
    ld [hl+], a
    ld [hl], a
; Override return
pop af
jp processEnemies.doneProcessingEnemy ; Next enemy

.giveMissileDrop:
    ; Play sound
    ld a, sfx_square1_pickedUpMissileDrop
    ld [sfxRequest_square1], a
    ; Give 5 missiles
    ld hl, samusCurMissilesLow
    ld a, [hl]
    add $05
    daa
    ld [hl+], a
    ; Carry to the high byte
    ld a, [hl]
    adc $00
    ld [hl], a
    ; Check if high byte exceeds max
    ld a, [samusMaxMissilesHigh]
    sub [hl]
    jr c, .else_B
        ; Check low byte if high byte equal max
        jr nz, .deleteDrop
        dec hl
        ; Just delete the drop is the low byte does not exceed the max
        ld a, [samusMaxMissilesLow]
        sub [hl]
            jr nc, .deleteDrop
        jr .endIf_B
    .else_B:
        ; Clamp high byte to max
        ld a, [samusMaxMissilesHigh]
        ld [hl-], a
    .endIf_B:
    ; Clamp low byte to max
    ld a, [samusMaxMissilesLow]
    ld [hl], a
jr .deleteDrop
;} End drop collection logic

; Attempt to kill
.applyDamage:
    ; Exit if the sprite type is metroid-related (range $A0-$CF)
    ldh a, [hEnemy.spriteType]
    cp METROID_SPRITES_START ;$a0
    jr c, .endIf_C
        cp METROID_SPRITES_END + 1 ;$d0
        jp c, .transferCollisionResults ; Exit
    .endIf_C:

    ; Check if hit by Screw Attack
    dec hl
    dec hl
    ld a, [hl]
    cp $10
        jr z, .screwAttack
        jp nc, .transferCollisionResults ; Exit
    ; Check if not ice
    cp $01
        jr nz, .applyBeamDamage

; Ice Beam case {
    ; Check health before applying damage
    ld hl, hEnemy.health
    ld a, [hl] ; Frozen enemies can take an extra hit to kill
    and a ; if health == $00
        jr z, .smallExplosion
    inc a ; if health == $FF
        jr z, .plink ; Do nothing to enemy
    inc a
        jr z, .freezeInvulnerable ; if health == $FE

    call enemy_checkDirectionalShields ; Check vulnerabilities (override return)
    ; Manually subtract 2 health
    dec [hl]
    jr z, .endIf_D
        dec [hl]
    .endIf_D:
    ; Play freeze sound
    ld a, sfx_noise_enemyShot
    ld [sfxRequest_noise], a
.freeze:
    ld hl, hEnemy.stunCounter
    ld [hl], $10
    ld hl, hEnemy.iceCounter
    ld [hl], $01
jp .transferCollisionResults ; Exit

.freezeInvulnerable:
    ; Play plink sound
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
    jr .freeze
;} end Ice Beam case

; For all beams except Ice
.applyBeamDamage:
    ld e, a
    ld d, $00
    ld hl, weaponDamageTable
    add hl, de
    call enemy_checkDirectionalShields
    ldh a, [hEnemy.health]
    cp $fe
        jr nc, .plink ; Do nothing to enemy
    sub [hl]
        jr z, .smallExplosion
        jr c, .smallExplosion
    ldh [hEnemy.health], a
    ld a, sfx_noise_enemyShot
    ld [sfxRequest_noise], a
    call .transferCollisionResults ; Clear stuff
    ld a, $11
    ldh [hEnemy.stunCounter], a
; Override return
pop af
jp processEnemies.doneProcessingEnemy ; Next enemy


.screwAttack:
    ldh a, [hEnemy.health]
    cp $ff
    jr z, .endIf_E
        ; Store large explosion flag in B
        ld b, $20
        jr .prepareDrop
    .endIf_E:
.plink:
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
jr .transferCollisionResults ; Exit

; Small explosion if killed by beam or missile
.smallExplosion:
    ; Store small explosion flag in B
    ld b, $10

.prepareDrop: ;{
    ; Certain enemy projectiles give small health (100% chance)
    ldh a, [hEnemy.spawnFlag]
    cp $06
        jr z, .smallHealth
    and $0f
        jr z, .smallHealth
    ; Check initial health to determine drops
    ldh a, [hEnemy.maxHealth]
    cp $fd ; If max health == $FD (only arachnus?)
        jr z, .setExplosion
    cp $fe ; If max health == $FE (no enemies??)
        jr z, .setExplosion
    bit 0, a ; If max health is even
        jr z, .missileDrop
    cp $0a ; If max health is less than 10
        jr c, .smallHealth
    ; If max health is greater than 10

    ;.largeHealth:
        set 1, b ; Large health
            jr .setExplosion
    .smallHealth:
        set 0, b ; Small health
            jr .setExplosion
    .missileDrop:
        set 2, b ; Missile drop
    
.setExplosion:
    ; Set explosion flag with explosion and drop type
    ld a, b
    ldh [hEnemy.explosionFlag], a
    ; Clear timer
    xor a
    ldh [hEnemy.counter], a
    ; Play noise
    ld a, sfx_noise_enemyKilled
    ld [sfxRequest_noise], a
.unusedJump:
    call .transferCollisionResults ; Clear stuff
pop af
jp processEnemies.doneProcessingEnemy ; Skip to next enemy

; 02:4386 - Unused branch
    call enemy_deleteSelf_farCall
    ld a, $ff
    ldh [hEnemy.spawnFlag], a
    jr .unusedJump
; }

; Common exit for this function (called as a function by a couple exits)
.transferCollisionResults:
    ; Transfer enemy collision information from collision routine copies
    ;  to generic-enemy routine copies
    ld hl, collision_weaponType
    ld a, [hl+]
    ld [enSprCollision.weaponType], a
    ld a, [hl+]
    ld [enSprCollision.pEnemyLow], a
    ld a, [hl+]
    ld [enSprCollision.pEnemyHigh], a
    ld a, [hl]
    ld [enSprCollision.weaponDir], a
    ; Clear collision routine copies of the enemy collision information
    ld a, $ff
    ld [hl-], a
    ld [hl-], a
    ld [hl-], a
    ld [hl], a
ret
;}

; Checks if an enemy is invulnerable from a certain direction
enemy_checkDirectionalShields: ;{ 02:43A9
    ; Exit if weapon is Wave Beam
    ld a, [collision_weaponType]
    cp $02
        ret z
    ld c, a
    ; Exit if enemy has no directional shielding
    ldh a, [hEnemy.directionFlags]
    and $f0
        ret z
    ; Swap directional shielding to lower nybble, store in B
    swap a
    ld b, a
    ; Load direction of projectile into A
    ld a, [collision_weaponDir]
    ; Shift both variables right until we run into the direction bit of the projectile
    .loop:
        rrc b ; bit 0 loops back to bit 7
        srl a
        ; NOTE: This loop assumes that projectiles have a direction
        ;  You'll get a crash if you make one without one
        ;  Maybe switching these two lines of code would fix that
    jr nc, .loop
    ; Return (and damage the enemy) if the corresponding shield bit is not set
    bit 7, b
        ret z
; Override the return and make a plink sound if the the corresponding shield bit was set
pop af
jp enemy_getDamagedOrGiveDrop.plink
;}

weaponDamageTable: ; 02:43C8
    db $01 ; $00 - Power Beam
    db $02 ; $01 - Ice Beam (note: Ice Beam manually subtracts two health)
    db $04 ; $02 - Wave Beam
    db $08 ; $03 - Spazer Beam
    db $1E ; $04 - Plasma Beam (30!?)
    db $00 ; $05 - x
    db $00 ; $06 - x
    db $02 ; $07 - Bomb Beam !?
    db $14 ; $08 - Missiles (20!)
    db $0A ; $09 - Bomb Explosion

enemy_moveFromWramToHram: ;{ 02:43D2
    ; Save WRAM address of current enemy
    ld a, l
    ldh [hEnemyWramAddrLow], a
    ld a, h
    ldh [hEnemyWramAddrHigh], a
    ; Copy first 15 bytes of information
    ld b, $0f
    ld de, hEnemyWorkingHram ; $FFE0
    .loop_A:
        ld a, [hl+]
        ld [de], a
        inc e
        dec b
    jr nz, .loop_A
    ; Load some more things
    ld a, [hl+] ; enemyOffset + $0F
    ldh [hEnemy.yScreen], a
    ld a, [hl+] ; enemyOffset + $10
    ldh [hEnemy.xScreen], a
    ld a, [hl] ; enemyOffset + $11
    ldh [hEnemy.maxHealth], a
    ; Load spawn flag, spawn number, and AI pointer to $FFEF-$FFF2
    ; First get the address to them
    ldh a, [hEnemyWramAddrLow]
    add $1c
    ld l, a
    ; Then load them
    ld b, $04
    .loop_B:
        ld a, [hl+]
        ld [de], a
        inc e
        dec b
    jr nz, .loop_B
    ; Save backups of our coordinates
    ldh a, [hEnemy.yPos]
    ld [enemy_yPosMirror], a
    ldh a, [hEnemy.xPos]
    ld [enemy_xPosMirror], a
; Handle stun counter
    ; Return if stun counter is less than $11
    ldh a, [hEnemy.stunCounter]
    cp $11
        ret c
    ; Increment counter
    inc a
    ldh [hEnemy.stunCounter], a
    ; Check if stun period is over or not
    cp $14
    jr z, .else_A
        ; If not, skip to next enemy
        pop af
        jp processEnemies.doneProcessingEnemy
    .else_A:
        ; If so, check ice counter
        ldh a, [hEnemy.iceCounter]
        and a
        jr nz, .else_B
            ; Unstun and unfreeze
            xor a
            ldh [hEnemy.stunCounter], a
            ret
        .else_B:
            ; Retain frozen palette
            ld a, $10
            ldh [hEnemy.stunCounter], a
            ret
;} end proc

enemy_moveFromHramToWram: ;{ 02:4421
    ; Copy first 15 bytes from HRAM to WRAM
    ld b, $0f
    ld de, hEnemyWorkingHram ; $FFE0
    ldh a, [hEnemyWramAddrLow]
    ld l, a
    ldh a, [hEnemyWramAddrHigh]
    ld h, a
    .loop:
        ld a, [de]
        ld [hl+], a
        inc e
        dec b
    jr nz, .loop
    ; Copy screen coordinates
    ldh a, [hEnemy.yScreen]
    ld [hl+], a
    ldh a, [hEnemy.xScreen]
    ld [hl+], a
    
    ; NOTE: The initial health value is not copied here

    ; Get WRAM address of the last few bytes
    ldh a, [hEnemyWramAddrLow]
    add $1c
    ld l, a
    ; Move spawn flag
    ld a, [de]
    ld [hl+], a
    ; Move spawn number
    inc e
    ld a, [de]
    ld [hl+], a
    ld b, a ; Save spawn number for later
    ; Move AI pointer
    ldh a, [hEnemy.pAI_low]
    ld [hl+], a
    ldh a, [hEnemy.pAI_high]
    ld [hl], a
; Save spawn flag
    ; Get address for spawn flag
    ld hl, enemySpawnFlags
    ld l, b
    ; Load spawn flag in to enemySpawnFlag array
    dec e
    ld a, [de]
    ld [hl], a
    ; Check status of enemy
    ldh a, [hEnemyWramAddrLow]
    ld l, a
    ldh a, [hEnemyWramAddrHigh]
    ld h, a
    ld a, [hl]
    cp $ff
        ret nz
    ; If enemy is inactive, clear the spawn flag and spawn number
    ld a, l
    add $1c
    ld l, a
    ld [hl], $ff
    inc l
    ld [hl], $ff
ret
;}

; Checks if an enemy is sufficiently offscreen and deletes it
deleteOffscreenEnemy: ;{ 02:4464
    ; Check Y screen
    ld hl, hEnemy.yScreen
    ld a, [hl+]
    cp $fe
        jr z, .deleteEnemy
    cp $03
        jr nz, .checkX
    ; Fallthrough to .deleteEnemy

.deleteEnemy:
    ; Clear enemy HRAM (first 15 bytes)
    ld hl, hEnemyWorkingHram
    ld a, $ff
    ld b, $0f
    .loop:
        ld [hl+], a
        dec b
    jr nz, .loop
    ; Handle spawn flag
    ld a, [hl]
    cp $02
    jr z, .endIf_A
        cp $04
        jr nz, .endIf_B
            ld a, $fe
            ld [hl], a
            ld a, $ff
            jr .endIf_A
        .endIf_B:
            ld a, $ff
            ld [hl], a
    .endIf_A:

    ; Skip deleting spawn number
    inc l
    inc l
    ; Clear AI pointer
    ld [hl+], a
    ld [hl+], a
    ; Clear screen coordinates (Y,X)
    ld [hl+], a
    ld [hl], a
    ; Decrement numEnemies.total and numEnemies.offscreen
    ld hl, numEnemies.total
    dec [hl]
    inc l
    inc l
    dec [hl]
    ; Clear collision variables if these addresses are equal
    ld hl, enSprCollision.pEnemyHigh
    ld de, hEnemyWramAddrHigh
    ld a, [de]
    cp [hl]
    jr nz, .endIf_C
        dec e
        dec l
        ld a, [de]
        cp [hl]
        jr nz, .endIf_C
            dec l
            ld a, $ff
            ld [hl+], a
            ld [hl+], a
            ld [hl+], a
            ld [hl], a
    .endIf_C:
; Override return to skip to next enemy
pop af
jp processEnemies.doneProcessingEnemy

.checkX:
    ; Check X screen
    ld a, [hl]
    cp $fe
        jr z, .deleteEnemy
    cp $03
        ret nz ; Standard return. Proceed with processing this enemy
    jr .deleteEnemy
;} end proc

; Check if offscreen enemy needs to be reactivated
reactivateOffscreenEnemy: ;{ 02:44C0
; yScreen cases
    ld hl, hEnemy.yScreen
    ld de, hEnemy.yPos
    ld a, [hl]
    cp $ff ; If a screen above
        jr z, .ifScreenAbove
    and a ; If on same row of screens
        jr z, .ifOnSameScreenY
    dec a ; If not on the screen below
        jr nz, .checkX

    ;.ifScreenBelow
        ld a, [de]
        cp $c0
            jr nc, .checkX
      .moveScreenUp:
        dec [hl]
    jr .checkX
    
    .ifScreenAbove:
        ld a, [de]
        cp $f0
            jr c, .checkX
      .moveScreenDown:
        inc [hl]
    jr .checkX
    
    .ifOnSameScreenY:
        ld a, [de]
        cp $c0 ; $00-$BF, $F0-$FF - Do nothing
            jr c, .checkX
        cp $d8 ; $C0-$D7 - Move down
            jr c, .moveScreenDown
        cp $f0 ; $D8-$EF - Move up
            jr c, .moveScreenUp
; end yScreen cases

.checkX: ; xScreen cases
    inc l ; enemyXScreen
    inc e ; enemyXPos
    ld a, [hl]
    cp $ff ; If a screen left
        jr z, .ifScreenLeft
    and a ; If in same column of screens
        jr z, .ifOnSameScreenX
    dec a ; If not a screen to the right
        jr nz, .exit

    ;.ifScreenRight
        ld a, [de]
        cp $c0
            jr nc, .exit
      .moveScreenLeft:
        dec [hl]
    jr .exit
    
    .ifScreenLeft:
        ld a, [de]
        cp $f0
            jr c, .exit
      .moveScreenRight:
        inc [hl]
    jr .exit
    
    .ifOnSameScreenX:
        ld a, [de]
        cp $c0 ; $00-$BF, $F0-$FF - Do nothing
            jr c, .exit
        cp $d8 ; $C0-$D7 - Move right
            jr c, .moveScreenRight
        cp $f0 ; $D8-$EF - Move left
            jr c, .moveScreenLeft
; end xScreen cases

.exit:
    ; Exit if enemy is offscreen (relative screen coords are not (0,0))
    ldh a, [hEnemy.yScreen]
    ld b, a
    ldh a, [hEnemy.xScreen]
    or b
        ret nz ; Normal return to keep processing current enemy
    ; Reactivate enemy
    ld hl, hEnemy.status
    ld [hl], $00
    ; Increment number of active enemies
    ld hl, numEnemies.active
    inc [hl]
    inc l
    ; Decrement number of offscreen enemies
    dec [hl]
; Override return to start processing next enemy
pop af
jp processEnemies.doneProcessingEnemy
;}

; Check if enemy needs to be deactivated for being offscreen
deactivateOffscreenEnemy: ;{ 02:452E
    ; Clear flag
    xor a
    ld [hasMovedOffscreen], a
;.checkY:
    ld hl, hEnemy.yPos
    ld a, [hl+]
    cp $c0 ; $00-$BF - Do nothing
        jr c, .checkX
    cp $d8 ; $C0-$D7 - Move Down
        jr c, .moveDown
    cp $f0 ; $F0-$FF - Do nothing
        jr nc, .checkX
    ; $D8-$EF - Move Up
    
    ;.moveUp:
        ld a, $ff
        ldh [hEnemy.yScreen], a
        jr .setFlag_A
    .moveDown:
        ld a, $01
        ldh [hEnemy.yScreen], a

.setFlag_A: ; First chance to set this flag
    ld a, $01
    ld [hasMovedOffscreen], a
; end yScreen case

.checkX:
    ld a, [hl]
    cp $c0 ; $00-$BF - Do nothing
        jr c, .prepExit
    cp $d8 ; $C0-$D7 - Move Right
        jr c, .moveRight
    cp $f0 ; $F0-$FF - Do nothing
        jr nc, .prepExit
    ; $D8-$EF - Move Left
    
    ;.moveLeft:
        ld a, $ff
        ldh [hEnemy.xScreen], a
        jr .setFlag_B
    .moveRight:
        ld a, $01
        ldh [hEnemy.xScreen], a

.setFlag_B: ; Second chance to set this flag
    ld a, $01
    ld [hasMovedOffscreen], a
; end xScreen case

.prepExit:
    ld a, [hasMovedOffscreen]
    and a
        ret z ; Normal return to continue processing enemy
    ; Set status to inactive
    ld hl, hEnemy.status
    ld [hl], $01
    ldh a, [hEnemy.spawnFlag]
    cp $02
        jr z, .deleteDeadEnemy
    cp $06
        jr z, .deleteProjectile
    and $0f
        jr z, .deleteProjectile

    ; Deactivate enemy
    ld hl, numEnemies.active
    dec [hl]
    inc l
    inc [hl]
    ldh a, [hEnemy.spawnFlag]
    cp $03
        jr z, .waitingEnemy
    cp $04
        jr z, .seenEnemy
    cp $05
        jr z, .seenEnemy
; Override return to skip to next enemy
pop af
jp processEnemies.doneProcessingEnemy

.deleteDeadEnemy: ; Delete enemy marked as dead
    call enemy_deleteSelf_farCall
    ld a, $02
    ldh [hEnemy.spawnFlag], a
pop af
jp processEnemies.doneProcessingEnemy

.deleteProjectile: ; Delete an enemy marked as a child object
    call enemy_deleteSelf_farCall
    ld a, $ff
    ldh [hEnemy.spawnFlag], a
pop af
jp processEnemies.doneProcessingEnemy

; Case for enemies that keep track of if they've been seen or not (i.e. Metroids)
.seenEnemy:
    ; Set to 4 so the projectile-firing status is not saved
    ld a, $04
    ldh [hEnemy.spawnFlag], a
    xor a
    ld [metroid_postDeathTimer], a
    ld [metroid_state], a
pop af
jp processEnemies.doneProcessingEnemy

.waitingEnemy:
    ; Set to 1 so the projectile-firing status is not saved
    ld a, $01
    ldh [hEnemy.spawnFlag], a
pop af
jp processEnemies.doneProcessingEnemy
;}

; This copy of the scrolling history appears to be used in scrollEnemies (03:6BD2)
updateScrollHistory: ;{ 02:45CA
    ; y3 <= y2
    ld de, scrollHistory_A.y2
    ld hl, scrollHistory_A.y3
    ld a, [de]
    ld [hl+], a
    ; x3 <= x2
    inc e
    ld a, [de]
    ld [hl+], a
    ; y2 <= y1
    inc e
    ld a, [de]
    ld [hl+], a
    ; x2 <= x1
    inc e
    ld a, [de]
    ld [hl+], a
    ; y1 <= y0
    ld de, scrollY
    ld a, [de]
    ld [hl+], a
    ; x1 <= x0
    inc e
    ld a, [de]
    ld [hl], a
ret ;}

; Gets X direction of Samus
unused_getSamusDirection: ;{ 02:45E4 - Unreferenced
    ld a, [samus_onscreenXPos]
    ld b, a
    ld hl, hEnemy.xPos
    ld a, [hl]
    cp b
    jr nc, .else
        ; Samus to right
        xor a
        ld [unused_samusDirectionFromEnemy], a ; Variable appears to be unused
        ret
    .else:
        ; Samus to left
        ld a, $02
        ld [unused_samusDirectionFromEnemy], a
        ret
;} end proc

; Sets x-flip in sprite attributes based on the directional flags
unused_setXFlip: ;{ 02:45FA - Unreferenced
    ld hl, hEnemy.attr
    ldh a, [hEnemy.directionFlags]
    and a
    jr z, .else
        ld [hl], $00
        ret
    .else:
        ld [hl], OAM_XFLIP
        ret
;} end proc

;------------------------------------------------------------------------------
; Beginning of enemy tilemap collision routines
;
; "$11 routines" = Check right side of object
; 8 routines (2 unused)
enCollision_right: ;{ 02:4608
.nearSmall:
;(3,-3)
;(3, 3)
    ld a, $11
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $03
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    add $03
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitA

.midSmall: ; 02:4635 - Unused
;(7,-3)
;(7, 3)
    ld a, $11
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $03
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitA

.midMedium: ; 02:4662 - Note: saves tile number to metroid_babyTouchingTile
;(7,-6)
;(7, 0)
;(7, 6)
    ld a, $11
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $06
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c

.exitA:
    ld hl, en_bgCollisionResult
    res 0, [hl]
    ret

.farMedium: ; 02:46AC
;(11,-7)
;(11, 0)
;(11, 7)
    ld a, $11
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $07
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    add $0b
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $07
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $07
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitA

.midWide: ; 02:46E9 - Unused
;(7,-11)
;(7, -3)
;(7,  3)
;(7, 11)
    ld a, $11
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $0b
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $08
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $08
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitB

.farWide: ; 02:4736
;(11,-11)
;(11. -3)
;(11,  3)
;(11, 11)
    ld a, $11
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $0b
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    add $0b
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $08
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $08
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitB

.crawlA: ; 02:4783
;(7,-8)
;(7, 7)
    ld a, $11
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $08
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $0f
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c

.exitB:
    ld hl, en_bgCollisionResult
    res 0, [hl]
    ret

.crawlB: ; 02:47B4
;(7,-7)
;(7, 8)
    ld a, $11
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $07
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $0f
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitB
;}

; "$44 functions" = Check left edge of object
; 8 functions (2 unused)
enCollision_left: ;{ 02:47E1
.nearSmall:
;(-3,-3)
;(-3, 3)
    ld a, $44
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $03
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $03
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitA

.midSmall: ; 02:480E - Unused
;(-7,-3)
;(-7, 3)
    ld a, $44
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $03
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitA

.midMedium: ; 02:483B - Note: saves tile number to metroid_babyTouchingTile
;(-7,-6)
;(-7, 0)
;(-7, 6)
    ld a, $44
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $06
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c

.exitA:
    ld hl, en_bgCollisionResult
    res 2, [hl]
    ret

.farMedium: ; 02:4885
;(-11,-7)
;(-11, 0)
;(-11, 7)
    ld a, $44
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $07
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $0b
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $07
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $07
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitA

.midWide: ; 02:48C2 - Unused
;(-7,-11)
;(-7, -3)
;(-7,  3)
;(-7, 11)
    ld a, $44
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $0b
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $08
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $08
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitB

.farWide: ; 02:490F
;(-11,-11)
;(-11, -3)
;(-11,  3)
;(-11, 11)
    ld a, $44
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $0b
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $0b
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $08
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $06
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $08
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitB

.crawlA: ; 02:495C
;(-9,-7)
;(-9, 8)
    ld a, $44
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $07
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $09
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $0f
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c

.exitB:
    ld hl, en_bgCollisionResult
    res 2, [hl]
    ret

.crawlB: ; 02:498D
;(-9,-8)
;(-9, 7)
    ld a, $44
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $08
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $09
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointYPos]
    add $0f
    ld [enemy_testPointYPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitB
;}

; "$22 functions" - Check bottom edge of object
; 9 functions (2 unused)
enCollision_down: ;{ 02:49BA
.nearSmall:
;(-3,3)
;( 3,3)
    ld a, $22
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    add $03
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $03
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitA

.nearMedium: ; 02:49E7 - Unused
;(-7,3)
;( 0,3)
;( 7,3)
    ld a, $22
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    add $03
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c

.exitA:
    ld hl, en_bgCollisionResult
    res 1, [hl]
ret

.midMedium: ; 02:4A28 - Note: saves tile number to metroid_babyTouchingTile
;(-6,7)
;( 0,7)
;( 6,7)
    ld a, $22
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    add $07
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitA

.midWide: ; 02:4A6E - Unused
;(-11,7)
;( -3,7)
;(  3,7)
;( 11,7)
    ld a, $22
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    add $07
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $0b
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $08
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $08
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitB

.onePoint: ; 02:4ABB
;(0,11)
    ld a, $22
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    add $0b
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitB

.farMedium: ; 02:4AD6
;(-7,11)
;( 0,11)
;( 7,11)
    ld a, $22
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    add $0b
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c

.exitB:
    ld hl, en_bgCollisionResult
    res 1, [hl]
    ret

.farWide: ; 02:4B17
;(-11,11)
;( -3,11)
;(  3,11)
;( 11,11)
    ld a, $22
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    add $0b
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $0b
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $08
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $08
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitB

.crawlA: ; 02:4B64
;(-8,8)
;( 7,8)
    ld a, $22
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    add $08
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $08
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $0f
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitC

.crawlB: ; 02:4B19
;(-9,8)
;( 6,8)
    ld a, $22
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    add $08
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $09
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $0f
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c

.exitC:
    ld hl, en_bgCollisionResult
    res 1, [hl]
    ret
;}

; "$88 functions" - Check top edge of object
; 8 functions (3 unused)
enCollision_up: ;{ 02:4BC2
.nearSmall:
;(-3,-3)
;( 3,-3)
    ld a, $88
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $03
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $03
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitA

.nearMedium: ; 02:4BEF - Unused
;(-7,-3)
;( 0,-3)
;( 7,-3)
    ld a, $88
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $03
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c

.exitA:
    ld hl, en_bgCollisionResult
    res 3, [hl]
    ret

.midMedium: ; 02:4C30 - Note: saves tile number to metroid_babyTouchingTile
;(-6,-7)
;( 0,-7)
;( 6,-7)
    ld a, $88
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $07
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld [metroid_babyTouchingTile], a
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitA

.midWide: ; 02:4C76 - Unused
;(-11,-7)
;( -3,-7)
;(  3,-7)
;( 11,-7)
    ld a, $88
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $07
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $0b
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $08
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $08
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitB

.farMedium: ; 02:4CC3 - Unused
;(-7,-11)
;( 0,-11)
;( 7,-11)
    ld a, $88
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $0b
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $07
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c

.exitB:
    ld hl, en_bgCollisionResult
    res 3, [hl]
    ret

.farWide: ; 02:4D04
;(-11,-11)
;( -3,-11)
;(  3,-11)
;( 11,-11)
    ld a, $88
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $0b
    ld [enemy_testPointYPos], a
    ldh a, [hEnemy.xPos]
    sub $0b
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $08
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $06
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $08
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitB

.crawlA: ; 02:4D51
;(-9,-8)
;( 6,-8)
    ld a, $88
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $08
    ld [enemy_testPointYPos], a
    ld a, [enemy_xPosMirror]
    sub $09
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $0f
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    jr .exitC

.crawlB: ; 02:4D7F
;(-8,-8)
;( 7,-8)
    ld a, $88
    ld [en_bgCollisionResult], a
    ldh a, [hEnemy.yPos]
    sub $08
    ld [enemy_testPointYPos], a
    ld a, [enemy_xPosMirror]
    sub $08
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c
    ld a, [enemy_testPointXPos]
    add $0f
    ld [enemy_testPointXPos], a
    call getTileIndex.enemy
    ld hl, enemySolidityIndex
    cp [hl]
        ret c

.exitC:
    ld hl, en_bgCollisionResult
    res 3, [hl]
    ret
;}

; End of enemy tilemap collision routines
;------------------------------------------------------------------------------

; Loads the Blob Thrower sprite and hitbox into RAM
blobThrower_loadSprite: ;{ 02:4DB1
    ; Load the sprite
    ld hl, enAI_blobThrower.sprite ;$4ffe
    ld de, enSprite_blobThrower
    ld b, $3e
    .loop_A:
        ld a, [hl+]
        ld [de], a
        inc de
        dec b
    jr nz, .loop_A
    ; Load the hitbox
    ld hl, enAI_blobThrower.hitbox
    ld de, hitboxC360
    ld b, $04
    .loop_B:
        ld a, [hl+]
        ld [de], a
        inc de
        dec b
    jr nz, .loop_B
    ; Clear timer
    ld a, $00
    ld [blobThrower_actionTimer], a
ret
;}

;------------------------------------------------------------------------------
; Item Orb and Item AI
;  Note 1: Orbs have even enemy IDs, items have odd enemy IDs
;  Note 2: handleItemPickup (00:372F) handles the other half of item collection logic
enAI_itemOrb: ;{ 02:4DD3
    ldh a, [hEnemy.spriteType]
    bit 0, a ; Jump ahead if orb, not item
    jr z, .endIf_A
        ; Animate item
        ld a, [frameCounter]
        and $06
        jr nz, .endIf_A
            ldh a, [hEnemy.stunCounter]
            xor $10
            ldh [hEnemy.stunCounter], a
    .endIf_A:

    call enemy_getSamusCollisionResults
    ; Exit if no collision
    ld a, [enemy_weaponType]
    cp $ff
        ret z
    ld b, a ; Save collision type to B

    ; Save collision results
    ld [itemOrb_collisionType], a
    ldh a, [hEnemyWramAddrLow]
    ld [itemOrb_pEnemyWramLow], a
    ldh a, [hEnemyWramAddrHigh]
    ld [itemOrb_pEnemyWramHigh], a
    
    ; Branch ahead if not orb
    ldh a, [hEnemy.spriteType]
    ld c, a ; Save sprite type to C
    bit 0, a
        jr nz, .branchItem

; Orb branch
    ; Check if orb got hit
    ld a, b
    ; Ignore bombs
    cp $09
        ret z
    ; Ignore screw attack
    cp $10
        ret z
    ; Ignore touching
    cp $20
        ret z
    ; Request sound effect
    xor a ; sfx_square1_nothing
    ld [sfxRequest_square1], a
    ld a, sfx_noise_enemyKilled
    ld [sfxRequest_noise], a
    ; Change orb into item
    ld a, c
    inc a
    ldh [hEnemy.spriteType], a
ret

.branchItem:
    ; Continue if touching
    ld a, b
    cp $20
    jr z, .endIf_B
        ; Exit if not Screw Attack
        cp $10
            ret nz
        ; Clear sound effect
        ld a, $ff
        ld [sfxRequest_square1], a
    .endIf_B:
    ; Branch ahead if an item is being collected now
    ld a, [itemCollectionFlag]
    and a
        jr nz, .checkIfDone

    ld a, c
    cp SPRITE_ENERGY_REFILL ; $9B ; Jump ahead if not energy refill
        jr nz, .branchMissileRefill
; Energy refill branch
    ; Return if at full health
    ld a, [samusCurHealthLow]
    cp $99
        jr nz, .getItemNum
    ld a, [samusEnergyTanks]
    ld b, a
    ld a, [samusCurHealthHigh]
    cp b
        jr nz, .getItemNum
ret

.branchMissileRefill:
    cp SPRITE_MISSILE_REFILL ; $9D ; Jump ahead if not missile refill
        jr nz, .getItemNum
    ; Return if full at full missiles
    ld a, [samusCurMissilesLow]
    ld b, a
    ld a, [samusMaxMissilesLow]
    cp b
        jr nz, .getItemNum
    ld a, [samusCurMissilesHigh]
    ld b, a
    ld a, [samusMaxMissilesHigh]
    cp b
        ret z

.getItemNum:
    ; Converts the sprite type into the item type
    ; Formula is equivalent to (([enemy sprite ID] - 81h)/2) + 1
    ld a, c
    ld [temp_spriteType], a
    ld c, $01

    .loop:
        cp SPRITE_ITEM_BASE_ID ; $81
            jr z, .break
        sub $02
        inc c
    jr .loop
    .break:

    ; Set item number being collected
    ld a, c
    ld [itemCollected], a
    
    ldh a, [hEnemy.yPos]
    ld [unused_itemOrb_yPos], a
    ldh a, [hEnemy.xPos]
    ld [unused_itemOrb_xPos], a
    ; Let game know that an item is being collected now
    ld a, $ff
    ld [itemCollectionFlag], a
ret

.checkIfDone:
    ld b, a
    ; Clear item collected (so we don't collect it multiple times)
    xor a
    ld [itemCollected], a
    ; return until handleItemPickup sets the itemCollectionFlag to $03
    ld a, b
    cp $ff
        ret z

    ; Clear item variables
    xor a
    ld [itemCollected], a
    ld [itemCollectionFlag], a
    ; Don't delete the refills
    ld a, [temp_spriteType]
    cp $9b ; Exit if energy refill
        ret z
    cp $9d ; Exit if missile refill
        ret z
    ; Delete the items
    call enemy_deleteSelf_farCall
    ld a, $02 ; Set collected flag
    ldh [hEnemy.spawnFlag], a
ret
;}

;------------------------------------------------------------------------------
; Blob Thrower AI (plant that spits out spores)
enAI_blobThrower: ;{ 02:4EA1
    ; Make stem blink periodically by changing tile numbers
    ld a, [frameCounter]
    and $0e
    jr nz, .endIf_A
        ; Blink the first three tiles
        ld de, $0004
        ld b, $03
        ld hl, enSprite_blobThrower + 4*4 + 2 ;$C312
        .blinkLoop:
            ld a, [hl]
            xor $07
            ld [hl], a
            add hl, de
            dec b
        jr nz, .blinkLoop
        ; Blink two other tiles (8 and 11)
        ld hl, enSprite_blobThrower + 8*4 + 2 ; $C322
        ld a, [hl]
        xor $0d
        ld [hl], a
        ld hl, enSprite_blobThrower + 11*4 + 2 ; $C32E
        ld a, [hl]
        xor $0d
        ld [hl], a
    .endIf_A:

    ; Wait on the wait timer
    ld a, [blobThrower_waitTimer]
    and a
    jr z, .else_B
        ; Decrement timer
        dec a
        ld [blobThrower_waitTimer], a
        ret
    .else_B:
        ; Go to current state
        ld a, [blobThrower_state]
        and a
            jr z, .state_0 ; case 0
        cp $01
            jr z, .state_1 ; case 1
        cp $02
            jr z, .state_2 ; case 2
        jp .state_3 ; case 3

.state_0: ; Main action
    ; Adjust sprites
    ld de, enSprite_blobThrower
    ld hl, .speedTable_top
    ld a, $04
    call .moveSprites
    
    ld hl, .speedTable_top
    ld a, $01
    call .moveSprites
    
    ld hl, .speedTable_middle
    ld a, $01
    call .moveSprites
    
    ld hl, .speedTable_bottom
    ld a, $01
    call .moveSprites
    ; Adjust hitbox
    ld hl, .speedTable_top
    ld a, [blobThrower_actionTimer]
    ld e, a
    ld d, $00
    add hl, de
    ld de, hitboxC360
    ld a, [de]
    add [hl]
    ld [de], a
    ; Increment timer
    ld a, [blobThrower_actionTimer]
    inc a
    ld [blobThrower_actionTimer], a
    ; Check if at peak height
    cp $15
        ret nz

    ; Open up mouth by modifying first four tile numbers
    ld hl, enSprite_blobThrower + 2 ;$c302
    ld de, $0004
    ld [hl], $df
    add hl, de
    ld [hl], $df
    add hl, de
    ld [hl], $e1
    add hl, de
    ld [hl], $e1
    ; Set y-pos for the 13th sprite so it and the next one get rendered
    ld hl, enSprite_blobThrower + 13*4; $C334
    ld [hl], $e8
    ; Prep next state
    ld a, $04
    ld [blobThrower_waitTimer], a
    ld a, $01
    ld [blobThrower_state], a
ret

.state_1: ; Open mouth
    ld hl, enSprite_blobThrower + 2 ;$c302
    ld de, $0004
    ld [hl], $e2
    add hl, de
    ld [hl], $e2
    ld a, $04
    ld [blobThrower_waitTimer], a
    ld a, $02
    ld [blobThrower_state], a
ret

.state_2: ; Spew blobs
    ld hl, enSprite_blobThrower + 2 ;$c302
    ld de, $0004
    ld [hl], $e3
    add hl, de
    ld [hl], $e3
    ld a, $40
    ld [blobThrower_waitTimer], a
    ld a, $03
    ld [blobThrower_state], a
    call .getFacingDirection
    ld de, .blobHeader_A
    call .spewBlob
    ld de, .blobHeader_B
    call .spewBlob
    ld de, .blobHeader_C
    call .spewBlob
    ld de, .blobHeader_D
    call .spewBlob
ret

.getFacingDirection: ; 02:4F87 - Shared with Arachnus
    ld a, [samus_onscreenXPos]
    ld b, a
    ldh a, [hEnemy.xPos]
    cp b
    ld a, $00
    jr c, .endIf_C
        inc a
    .endIf_C:

    ld [blobThrower_facingDirection], a
ret

.spewBlob:
    call loadEnemy_getFirstEmptySlot_longJump
    ; Activate enemy
    ld [hl], $00
    inc hl
    ; Set position of enemy
    ldh a, [hEnemy.yPos]
    sub $20
    ld [hl+], a
    ldh a, [hEnemy.xPos]
    ld [hl+], a
    ; Load header
    ld a, $06
    ld [enemy_tempSpawnFlag], a
    push hl
        call enemy_spawnObject.longHeader
    pop hl
    ; Dynamically set [hEnemy.generalVar] for the blobs (their lower bound) depending on the y position of the thrower.
    ld de, $0004
    add hl, de
    ldh a, [hEnemy.yPos]
    add $40
    ld [hl], a
ret

.state_3: ; State 3 - Close mouth
    ld hl, enSprite_blobThrower + 2 ; $c302
    ld de, $0004
    ld [hl], $dd
    add hl, de
    ld [hl], $dd
    add hl, de
    ld [hl], $de
    add hl, de
    ld [hl], $de
    ; Set this y coordinate to $FF so this sprite and the one after it don't get rendered
    ld hl, enSprite_blobThrower + 13*4; $C334
    ld [hl], METASPRITE_END ; $ff
    xor a
    ld [blobThrower_state], a
ret

; A = number of sprites to move
.moveSprites:
    push de
    push af
    push hl
    ld a, [blobThrower_actionTimer]

    .readLoop:
        ; Check that we're not at the end of the list
        ld e, a
        ld d, $00
        add hl, de
        ld a, [hl]
        cp $80
        jr z, .endIf_D
            pop bc
            pop bc ; This is where B gets assigned the argument from A
            pop de
            ; Move the sprites, then exit
            .moveLoop:
                ld a, [de]
                add [hl]
                ld [de], a
                inc de
                inc de
                inc de
                inc de
                dec b
            jr nz, .moveLoop
            ret
        .endIf_D:
        ; Delay when at bottom
        ld a, $30
        ld [blobThrower_waitTimer], a
        ; Reset index
        xor a
        ld [blobThrower_actionTimer], a
        pop hl
        push hl
    jr .readLoop
; end proc

; Main blob thrower sprite
.sprite: ; 02:4FFE
    db $F8, $00, $DD, $20
    db $F8, $F8, $DD, $00
    db $00, $00, $DE, $20
    db $00, $F8, $DE, $00
    db $08, $FC, $DB, $00
    db $08, $FC, $DB, $00
    db $08, $FC, $DB, $00
    db $08, $F4, $D6, $00
    db $08, $FC, $DA, $00
    db $08, $04, $D8, $00
    db $10, $F4, $D3, $00
    db $10, $FC, $D9, $00
    db $10, $04, $D5, $00
    db METASPRITE_END, $F0, $E0, $00 ; Note the METASPRITE_END. It's dynamically changed to a valid y-position so this sprite and the next appear conditionally.
    db $E8, $08, $E0, $20
    db METASPRITE_END
.hitbox: ; 02:503B
    db $FC, $18, $F8, $08

; Speed tables for moving the top, middile, and bottom parts of the blob thrower sprite
.speedTable_top: ; 02:503F
    db $00, $FE, $FF, $FF, $FF, $FF, $FF, $FF, $FE, $FE, $FE, $FE, $FE, $FE, $FD, $FF
    db $00, $00, $00, $00, $00, $00, $02, $01, $00, $01, $01, $01, $01, $00, $01, $00
    db $02, $01, $01, $01, $01, $02, $00, $00, $01, $01, $01, $02, $01, $00, $02, $00
    db $00, $80
.speedTable_middle: ; 02:5071
    db $00, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FF, $FE, $FF, $FF, $FF, $FE, $FF, $00
    db $00, $00, $00, $00, $00, $00, $01, $00, $01, $02, $00, $00, $00, $00, $00, $00
    db $00, $00, $00, $01, $00, $01, $02, $00, $02, $00, $01, $01, $01, $01, $01, $01
    db $00, $80
.speedTable_bottom: ; 02:50A3
    db $00, $FF, $00, $FF, $00, $FF, $00, $00, $FF, $00, $FF, $00, $FF, $FF, $FF, $00
    db $00, $00, $00, $00, $00, $01, $00, $00, $01, $01, $00, $00, $00, $00, $00, $01
    db $00, $00, $00, $01, $00, $01, $00, $00, $00, $00, $01, $00, $00, $00, $01, $00
    db $00, $80
; Enemy headers for projectiles
.blobHeader_A: ; 02:50D5
    db $9E, $00, $00, $00, $00, $00
    dw blobMovementTable_A
    db $00, $02, $02
    dw enAI_blobProjectile
.blobHeader_B: ; 02:50E2
    db $9E, $00, $00, $00, $00, $00
    dw blobMovementTable_B
    db $00, $02, $03
    dw enAI_blobProjectile
.blobHeader_C: ; 02:50EF
    db $9E, $00, $00, $00, $00, $00
    dw blobMovementTable_C
    db $00, $02, $04
    dw enAI_blobProjectile
.blobHeader_D: ; 02:50FC
    db $9E, $00, $00, $00, $00, $00
    dw blobMovementTable_D
    db $00, $02, $05
    dw enAI_blobProjectile
;}

;------------------------------------------------------------------------------
; Arachnus / Arachnus Orb
enAI_arachnus: ;{ 02:5109
    ldh a, [hEnemy.generalVar]
    rst LOW(RST_28)
        dw .state_0 ; Init and start fight
        dw .state_1 ; Initial bouncing for the intro
        dw .state_2 ; An additional small bounce for the intro
        dw .state_3 ; Standing up (part 1)
        dw .state_4 ; Standing up (part 2)
        dw .state_5 ; Attacking/Vulnerable
        dw .state_6 ; Bouncing again (loops back to state 3)
        dw enAI_NULL ;arachnus_5651

.state_0: ; 02:511C - State 0 - Init and start fight
    ; Clear arachnus scratchpad
    ld hl, arachnus_jumpCounter
    xor a
    ld b, $06
    .initLoop:
        ld [hl+], a
        dec b
    jr nz, .initLoop
    ; Set actual health and fake health
    ld a, $06
    ld [arachnus_health], a
    ld a, $ff
    ldh [hEnemy.health], a
    ; Check if hit
    call enemy_getSamusCollisionResults
    ld a, [enemy_weaponType]
    cp $ff ; Exit if touching
        ret z
    cp $09 ; Exit if not hit with bombs or a beam
        ret nc
; Actually start the fight
    ; Set sprite to arachnus
    ld a, SPRITE_ARACHNUS_ROLL_1 ; $76
    ldh [hEnemy.spriteType], a
  .nextStateAndResetJumpCounterAndUnknownVar:
    ld a, $05
    ld [arachnus_unknownVar], a
  .nextStateAndResetJumpCounter:
    xor a
    ld [arachnus_jumpCounter], a
    ld a, $20
  .nextState:
    ld [arachnus_actionTimer], a
    ; Next state
    ld hl, hEnemy.generalVar
    inc [hl]
ret

.state_1: ; 02:5152 - State 1 - Initial Bouncing
    ld hl, .jumpSpeedTable_high
    call .jump
        jr nz, .nextStateAndResetJumpCounterAndUnknownVar
    ; Move right
    ld hl, hEnemy.xPos
    ld a, [hl]
    add $01
    ld [hl], a
    ; Animate
  .flipSpriteId: ; 02:5161
    ld a, [frameCounter]
    and $06
        ret nz
    ldh a, [hEnemy.spriteType]
    xor $01
    ldh [hEnemy.spriteType], a
ret

; Subroutine, not a state
.jump: ; 02:516E
    ; Read value from jump table
    ld a, [arachnus_jumpCounter]
    ld e, a
    ld d, $00
    add hl, de
    ld a, [hl]
    ; Store distance in B
    ld b, a
    ; Check if it's a special token ($80 or $81) or not
    cp $80
    jr nz, .else_A
        ld bc, $0380 ; B = speed, C = status
        jr .endIf_A
    .else_A:
        cp $81
        jr nz, .else_B
            ld bc, $0381 ; B = speed, C = status
            jr .endIf_A
        .else_B:
            ; Increment jump counter
            inc e
            ld a, e
            ld [arachnus_jumpCounter], a
            ld c, $00
    .endIf_A:
    ; Move vertically
    ldh a, [hEnemy.yPos]
    add b
    ldh [hEnemy.yPos], a
    ; Save value of c
    ld a, c
    ld [arachnus_jumpStatus], a
    ; Exit if no collision happened
    call enCollision_down.midMedium
    ld a, [en_bgCollisionResult]
    and $02
        ret z
    
    ld a, [arachnus_jumpStatus]
    and a ; Return nz if we somehow landed early
    jr z, .else_C
        cp $81 ; Return nz if we're at the end of the last bounce
        jr z, .else_C
            ; If arachnus_jumpStatus was $80, move on to the next jump speed table (so it bounces)
            ; (note that the jump speed tables are right next to each other, and only the last one ends in $81)
            ld a, [arachnus_jumpCounter]
            inc a
            ld [arachnus_jumpCounter], a
            ; Return zero
            xor a
            and a
            ret
    .else_C:
        ; Return non-zero
        inc a
        and a
        ret
; end state

.state_2: ; 02:51B9 - State 2 - An additional small bounce
    ld hl, .jumpSpeedTable_low
  .jumpAndAnimate:
    call enAI_arachnus.jump
    jr nz, .else_D ; Animate spin
        jr enAI_arachnus.flipSpriteId
    .else_D: ; Done bouncing
        ; Set timer
        ld a, $04
        ld [arachnus_actionTimer], a
        ; Move to state 3
        ld hl, hEnemy.generalVar
        ld [hl], $03
        ret

.state_3: ; 02:51CE - State 3 - Standing up (part 1)
    ld a, [arachnus_actionTimer]
    and a
    jr z, .else_E
        dec a
        ld [arachnus_actionTimer], a
        jr enAI_arachnus.flipSpriteId
    .else_E:
        call .faceSamus
        ; Stand up
        ldh a, [hEnemy.yPos]
        sub $08
        ldh [hEnemy.yPos], a
        ld a, SPRITE_ARACHNUS_UPRIGHT_1 ; $78
      .nextStateAndSetSprite:
        ldh [hEnemy.spriteType], a
        ld a, $04 ; value for animation timer
        jp enAI_arachnus.nextState
; end state

.state_4: ; 02:51EC - State 4 - Standing up (part 2)
    ld a, [arachnus_actionTimer]
    and a
    jr z, .else_F
        dec a
        ld [arachnus_actionTimer], a
        ret
    .else_F:
        ld a, SPRITE_ARACHNUS_UPRIGHT_3 ; $7A ; Set sprite type
        jr .nextStateAndSetSprite
; end state

.state_5: ; 02:51FB - State 5 - Attacking/Vulnerable
    call enemy_getSamusCollisionResults
    ld a, [enemy_weaponType]
    cp $ff ; Skip ahead if nothing
    jr z, .endIf_G
        cp $09 ; Check if bomb
        jr nz, .endIf_G
            ld a, sfx_noise_metroidHurt
            ld [sfxRequest_noise], a
            ld a, $11
            ldh [hEnemy.stunCounter], a
            ld a, [arachnus_health]
            dec a
            ld [arachnus_health], a
                jr z, .die
    .endIf_G:

    ld a, [hInputPressed]
    and PAD_B
    jr nz, .else_H
        call .faceSamus
        ld a, [arachnus_actionTimer]
        and a
        jr z, .else_I
            dec a
            ld [arachnus_actionTimer], a
            ret
        .else_I:
            ; Spit fireball sprite
            ld a, SPRITE_ARACHNUS_UPRIGHT_3 ; $7A
            ldh [hEnemy.spriteType], a
            ldh a, [hEnemy.spawnFlag]
            cp $01
                ret nz
            ; Spawn projectile
            ld de, .fireballHeader
            call .shootFireball
            ld a, SPRITE_ARACHNUS_UPRIGHT_2 ; $79
            ldh [hEnemy.spriteType], a
            ; Reset action timer
            ld a, $10
            ld [arachnus_actionTimer], a
            ret
    .else_H:
        ldh a, [hEnemy.yPos]
        add $08
        ldh [hEnemy.yPos], a
        ld a, SPRITE_ARACHNUS_ROLL_1 ; $76
        ldh [hEnemy.spriteType], a
        jp .nextStateAndResetJumpCounter
; end state

.die: ; Become Spring ball
    ld a, sfx_noise_metroidKilled
    ld [sfxRequest_noise], a
    ; Transform into spring ball
    ld hl, hEnemy.health
    ld [hl], $ff
    ld a, SPRITE_SPRING_BALL_ITEM ; Spring Ball
    ldh [hEnemy.spriteType], a
    ld hl, hEnemy.pAI_low ;$fff1
    ld de, enAI_itemOrb ;$4dd3
    ld [hl], e
    inc l
    ld [hl], d
ret

.state_6: ; 02:526E - State 6 - Bouncing again (loops back to state 3)
    ldh a, [hEnemy.attr]
    and a
    jr z, .else_J
        ; Try right
        call enCollision_right.midMedium
        ld b, 1 ; Speed
        ld a, [en_bgCollisionResult]
        and $01
        jr z, .moveHorizontal
            jr .moveVertical
            
          .moveHorizontal:
            ldh a, [hEnemy.xPos]
            add b
            ldh [hEnemy.xPos], a
          .moveVertical:
            ld hl, .jumpSpeedTable_mid
            jp .jumpAndAnimate
    .else_J:
        ; Try left
        call enCollision_left.midMedium
        ld b, -1 ; Speed
        ld a, [en_bgCollisionResult]
        and $04
        jr z, .moveHorizontal
            jr .moveVertical
; end state

.faceSamus: ; 02:529A
    call enAI_blobThrower.getFacingDirection
    and a
    ld a, OAM_XFLIP ;$20
    jr z, .endIf_K
        xor a
    .endIf_K:
    ldh [hEnemy.attr], a
ret

.shootFireball: ; 02:52A6
    call loadEnemy_getFirstEmptySlot_longJump
    ld [hl], $00
    inc hl
    ldh a, [hEnemy.yPos]
    add $fd
    ld [hl+], a
    ; Adjust x-position based on facing
    ldh a, [hEnemy.attr]
    ld b, $18
    and a
    jr nz, .endIf_L
        ld b, -$18 ; $E8
    .endIf_L:
    ldh a, [hEnemy.xPos]
    add b
    ld [hl+], a
    
    push hl
        call enemy_createLinkForChildObject ; Fireball doesn't bother with this link
        call enemy_spawnObject.longHeader
    pop hl
    ld de, $0004
    add hl, de
    ldh a, [hEnemy.attr]
    ld [hl], a
    ld a, $03
    ldh [hEnemy.spawnFlag], a
ret

.fireballHeader: ; 02:52D2 - Enemy header
    db $7b, $00, $00, $00, $00, $00, $00, $00, $00, $02, $02
    dw .fireballAI

.fireballAI: ; 02:52DF
    ld hl, hEnemy.xPos
    ldh a, [hEnemy.generalVar]
    and a
    ; Set speed
    ld b, 3
    jr nz, .endIf_M
        ld b, -3 ;$fd
    .endIf_M:
    ; Move
    ld a, [hl]
    add b
    ld [hl], a
    ; Animate
    ld a, [frameCounter]
    and $06
        ret nz
    ldh a, [hEnemy.spriteType]
    xor SPRITE_ARACHNUS_FIREBALL_1 ^ SPRITE_ARACHNUS_FIREBALL_2 ; $07
    ldh [hEnemy.spriteType], a
ret

    ret ; 02:52FB - Unreferenced

; Notes: These tables need to be contiguous, and the code that accesses them only supports
;  them having a combined length of 256 (easy enough to fix though).
; The $80 at the end of each table should coincide with the moment that Arachnus lands on the ground,
;  assuming you want it to continue on to the next bounce.
; The last table should end with $81 so the game doesn't read junk data as velocities
.jumpSpeedTable_high: ; 02:52FC - State 1 (jump off the pedestal)
    db $FF, $FE, $FE, $FE, $FF, $FF, $FE, $FF, $FE, $FE, $FE, $FF, $FF, $FF, $00, $00
    db $00, $00, $01, $00, $01, $01, $00, $01, $01, $01, $01, $01, $01, $01, $01, $01
    db $01, $02, $02, $02, $02, $02, $02, $02, $02, $03, $03, $03, $03, $03, $03, $03
    db $00, $80
.jumpSpeedTable_mid: ; 02:532E - State 6
    db $FC, $FD, $FD, $FD, $FE, $FE, $FD, $FE, $FE, $FE, $FE, $FF, $FE, $FF, $FE, $FF
    db $FF, $00, $00, $00, $00, $01, $01, $02, $01, $02, $01, $02, $02, $02, $02, $03
    db $02, $02, $03, $03, $03, $04, $00, $80
.jumpSpeedTable_low: ; 02:5356 - State 2
    db $FD, $FE, $FE, $FE, $FF, $FF, $00, $FF, $FF, $00, $FF, $00, $00, $01, $00, $01
    db $01, $00, $01, $01, $02, $02, $02, $03, $81
;}

;------------------------------------------------------------------------------
; Blob thrower projectile
enAI_blobProjectile: ;{ 02:536F
    ldh a, [hEnemy_frameCounter]
    ld b, a
    and $01
        ret nz
    ; Animate
    ld a, b
    and $01
    jr nz, .endIf_A ; This conditional seems superfluous given the conditional return above
        ldh a, [hEnemy.spriteType]
        xor SPRITE_BLOB_1 ^ SPRITE_BLOB_2 ; $01
        ldh [hEnemy.spriteType], a
    .endIf_A:

    ; Load pointer to movement table (two bytes)
    ld hl, hEnemy.counter
    ld e, [hl]
    inc l
    ld d, [hl]
    
    ; Check if at end of table
    ld a, [de]
    cp $80
        jr z, .done

;moveHorizontal
    ; Extract upper nybble
    ld a, [de]
    and $f0
    swap a
    ; Apply the sign-bit if necessary (uses sign-magnitude format)
    bit 3, a
    jr z, .endIf_B
        and $07
        cpl
        inc a
    .endIf_B:
    ; Save result
    ld b, a

    ; Negate if Samus is to the right side of the parent blob thrower
    ld a, [blobThrower_facingDirection]
    and a
    jr z, .endIf_C
        ld a, b
        cpl
        inc a
        ld b, a
    .endIf_C:

    ; Apply velocity
    ldh a, [hEnemy.xPos]
    add b
    ldh [hEnemy.xPos], a

;moveVertical
    ; Extract lower nybble
    ld a, [de]
    and $0f
    ; Apply the sign-bit if necessary (uses sign-magnitude format)
    bit 3, a
    jr z, .endIf_D
        and $07
        cpl
        inc a
    .endIf_D:
    ; Save result to B (unnecessary)
    ld b, a
    ; Apply velocity
    ldh a, [hEnemy.yPos]
    add b
    ldh [hEnemy.yPos], a

    ; Increment and save movement table pointer
    inc de
    ld [hl], d
    dec l
    ld [hl], e
ret

.done:
    ; Clear unused variable
    xor a
    ld [blobThrowerBlob_unknownVar], a
    ; Check if below threshold
    ldh a, [hEnemy.generalVar]
    ld b, a
    ldh a, [hEnemy.yPos]
    cp b
    jr nc, .else
        ; Move down
        inc a
        inc a
        ldh [hEnemy.yPos], a
        ret
    .else:
        ; Delete self
        call enemy_deleteSelf_farCall
        ld a, $ff
        ldh [hEnemy.spawnFlag], a
        ret
; end

; Bitpacked speed pairs
; - Signed-magnitude format (Signs: $X---Y---, Magnitudes: $-xxx-yyy)
blobMovementTable_A: ; 02:53D7
    db $19, $1A, $1A, $29, $28, $31, $32, $32, $33, $34, $34, $25, $89, $9B, $9B, $A9
    db $A8, $B1, $B2, $C2, $C3, $D4, $D4, $C5, $09, $1B, $1B, $29, $28, $31, $32, $42
    db $43, $54, $54, $45, $89, $9B, $9B, $A9, $A8, $B1, $B2, $C2, $C3, $D4, $D4, $C5
    db $80
blobMovementTable_B: ; 02:5408
    db $09, $1A, $1A, $2A, $3A, $3A, $4A, $49, $58, $51, $89, $9B, $9B, $A9, $A8, $B1
    db $B2, $C2, $C3, $D4, $D4, $C5, $09, $1B, $1B, $29, $28, $31, $32, $42, $43, $54
    db $54, $45, $89, $9B, $9B, $A9, $A8, $B1, $B2, $C2, $C3, $D4, $D4, $C5, $80
blobMovementTable_C: ; 02:5437
    db $19, $1A, $2B, $4B, $4A, $5A, $59, $09, $1B, $1B, $29, $28, $31, $32, $42, $43
    db $54, $54, $45, $89, $9B, $9B, $A9, $A8, $B1, $B2, $C2, $C3, $D4, $D4, $C5, $09
    db $1B, $1B, $29, $28, $31, $32, $42, $43, $54, $54, $45, $80
blobMovementTable_D: ; 02:5463
    db $29, $39, $3A, $4A, $4B, $5B, $58, $6B, $09, $1B, $1B, $29, $28, $31, $32, $42
    db $43, $54, $54, $45, $89, $9B, $9B, $A9, $A8, $B1, $B2, $C2, $C3, $D4, $D4, $C5
    db $09, $1B, $1B, $29, $28, $31, $32, $42, $43, $54, $54, $45, $EB, $FA, $FA, $E9
    db $E9, $D8, $D8, $C1, $C1, $B2, $B2, $A3, $A3, $94, $94, $85, $85, $80
;}

;------------------------------------------------------------------------------
; Glow Fly AI (thing that goes back and forth between walls)
enAI_glowFly: ;{ 02:54A1
    ; Move if state is non-zero
    ldh a, [hEnemy.state]
    and a
        jr nz, .case_move
    ; Increment wait timer
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $50
        jr z, .case_launch
    cp $45
        jr z, .case_windUpFrame
    call .animateIdle
ret

.case_windUpFrame:
    ; Animate wind-up frame before movement
    ld a, SPRITE_GLOWFLY_WINDUP ; $2E
    ldh [hEnemy.spriteType], a
ret

.case_launch:
    ; Start launching off the wall
    ; Set sprite graphics
    ld a, SPRITE_GLOWFLY_WINDUP ; $2E
    ldh [hEnemy.spriteType], a
    ; Reset wait timer
    ld [hl], $00
    ; Set state to move
    ld a, $01
    ldh [hEnemy.state], a
ret

.case_move:
    ; Set sprite type
    ld a, SPRITE_GLOWFLY_MOVING ; $2F
    ldh [hEnemy.spriteType], a
    call .move
    call .tryFlip
ret

.move:
    ld hl, hEnemy.xPos
    ; Check direction
    ldh a, [hEnemy.directionFlags]
    and a
    jr nz, .else_A
        ; Move right
        ld a, [hl]
        add $03
        ld [hl], a
        ret
    .else_A:
        ; Move left
        ld a, [hl]
        sub $03
        ld [hl], a
        ret
; end proc

.tryFlip:
    ldh a, [hEnemy.directionFlags]
    and a
        jr nz, .goingLeft

;goingRight
    call enCollision_right.nearSmall
    ld a, [en_bgCollisionResult]
    bit 0, a
        ret z

.flip:
    ; Animate sprite
    ld a, SPRITE_GLOWFLY_IDLE_1 ; $2C
    ldh [hEnemy.spriteType], a
    ; Flip sprite (graphics)
    ld hl, hEnemy.attr
    ld a, [hl]
    xor OAM_XFLIP
    ld [hl], a
    ; Flip sprite (logic)
    ld hl, hEnemy.directionFlags
    ld a, [hl]
    xor $01
    ld [hl], a
    ; Reset state
    xor a
    ldh [hEnemy.state], a
ret

.goingLeft:
    call enCollision_left.nearSmall
    ld a, [en_bgCollisionResult]
    bit 2, a
        ret z
    jr .flip ; Unconditional jump (code below is orphaned)

; 02:5513 - Unreferenced/unused code?
    ; Perhaps meant to reset state?
    ld [hl], $00
    ; Flip sprite (logic)
    ld hl, hEnemy.directionFlags
    ld a, [hl]
    xor $01
    ld [hl], a
    ; Flip sprite (graphics)
    ld hl, hEnemy.attr
    ld a, [hl]
    xor OAM_XFLIP
    ld [hl], a
    ; This unused branch doesn't animate the sprite
ret

.animateIdle:
    ; Execute every 8th frame
    ldh a, [hEnemy_frameCounter]
    and $07
        ret nz
    ; Looks like a really convoluted way of oscillating between $2C and $2D
    ldh a, [hEnemy.spriteType]
    cp SPRITE_GLOWFLY_IDLE_1 ; $2C
    jr nz, .else_B
        inc a
        ldh [hEnemy.spriteType], a
        ret
    .else_B:
        ldh a, [hEnemy.spriteType]
        cp SPRITE_GLOWFLY_IDLE_2 ; $2D
        jr nz, .else_C
            dec a
            ldh [hEnemy.spriteType], a
            ret
        .else_C:
            ld a, SPRITE_GLOWFLY_IDLE_1 ; $2C
            ldh [hEnemy.spriteType], a
            ret
;}

;------------------------------------------------------------------------------
; Rock Icicle (discount skree)
enAI_rockIcicle: ;{ 02:5542
    ldh a, [hEnemy.state] ; state
    cp $00
        jp z, .case_0
    cp $01
        jp z, .case_1
    cp $02
        jp z, .case_2
    cp $03
        jp z, .case_3
    cp $04
        jp z, .case_4
    cp $05
        jp z, .case_5
ret


.case_0:
    ; set the sprite ID
    ld a, SPRITE_ROCKICICLE_IDLE_1 ; $34
    ldh [hEnemy.spriteType], a
    ; inc the animation counter
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    ; exit if counter < 0xB
    cp $0b
        ret c

    ; inc the state
    ldh a, [hEnemy.state]
    inc a
    ldh [hEnemy.state], a
    ; set the next sprite ID
    ld a, SPRITE_ROCKICICLE_IDLE_2 ; $35
    ldh [hEnemy.spriteType], a
    ; clear the counter
    ld hl, hEnemy.counter
    ld a, [hl]
    xor a
    ld [hl], a
ret


.case_1:
    ; inc the animation counter
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    ; exit if counter < 0x7
    cp $07
        ret c

    ; inc the state
    ldh a, [hEnemy.state]
    inc a
    ldh [hEnemy.state], a
    ; clear the animation counter
    ld hl, hEnemy.counter
    ld a, [hl]
    xor a
    ld [hl], a
ret


.case_2:
    ldh a, [hEnemy_frameCounter]
    and $03 ; Act 1 out of 4 frames
        ret nz

    call .animate
    call .moveOnePixel
    cp $04 ; Move to next state after moving 4 pixels
        ret nz

    ld a, SPRITE_ROCKICICLE_MOVING_1 ; $36
    ldh [hEnemy.spriteType], a
    ; inc to next state
    ldh a, [hEnemy.state]
    inc a
    ldh [hEnemy.state], a
ret

    ret ; Unreferenced return

.moveOnePixel:
    ; Move one pixel
    ld hl, hEnemy.yPos
    ld a, [hl]
    inc a
    ld [hl], a
    ; Increment distance travelled
    ldh a, [hEnemy.generalVar]
    inc a
    ldh [hEnemy.generalVar], a
    ; Return distance travelled
    ldh a, [hEnemy.generalVar]
ret


.case_4:
    call .animate
    ; inc animation counter
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $10 ; Wait until 16 frames have elapsed
        ret nz

    ; clear animation counter
    xor a
    ld [hl], a
    ; inc the state
    ldh a, [hEnemy.state]
    inc a
    ldh [hEnemy.state], a
ret


.case_3:
    call .animate
    ldh a, [hEnemy_frameCounter]
    and $05
        ret nz

    ; inc to next state
    ldh a, [hEnemy.state]
    inc a
    ldh [hEnemy.state], a
ret


.case_5: ; Falling
    call .animate
    ; Move enemy down
    ld hl, hEnemy.yPos
    ld a, [hl]
    add $04
    ld [hl], a
    ; Increment distance travelled
    ldh a, [hEnemy.generalVar]
    add $04
    ldh [hEnemy.generalVar], a

    call enCollision_down.nearSmall ; Tilemap collision routine
    ld a, [en_bgCollisionResult]
    bit 1, a ; Bit 1 being set indicates a collision
    jr nz, .endIf_A
        ldh a, [hEnemy.yPos]
        cp $a0
            ret c
        ; Reset back to home if it falls off the bottom of the screen
    .endIf_A:
    
    ; Play sound effect
    ld a, sfx_noise_enemyHitGround
    ld [sfxRequest_noise], a
    
    ; Return to home y-position
    ; yPos = yPos - distance travelled
    ld hl, hEnemy.generalVar
    ld de, hEnemy.yPos
    ld a, [de]
    sub [hl]
    ld [de], a

    xor a
    ldh [hEnemy.generalVar], a ; Reset distance travelled
    ldh [hEnemy.state], a ; Reset state to 0
    ld a, SPRITE_ROCKICICLE_IDLE_1 ; $34
    ldh [hEnemy.spriteType], a
ret

.animate: ; Animates by flipping between sprites $36 and $37
    ldh a, [hEnemy_frameCounter]
    and $01
    ret nz

    ldh a, [hEnemy.spriteType]
    cp SPRITE_ROCKICICLE_MOVING_1 ; $36
    jr nz, .endIf_B
        inc a
        ldh [hEnemy.spriteType], a
            ret
    .endIf_B:
    
    ldh a, [hEnemy.spriteType]
    cp SPRITE_ROCKICICLE_MOVING_2 ; $37
    jr nz, .endIf_C
        dec a
        ldh [hEnemy.spriteType], a
            ret
    .endIf_C:
    
    ld a, SPRITE_ROCKICICLE_MOVING_1 ; $36
    ldh [hEnemy.spriteType], a
ret
;}

;------------------------------------------------------------------------------
; Common enemy handler
enemy_commonAI: ;{ 02:5630
    ; Check if a drop
    ldh a, [hEnemy.dropType]
    and a
        jr nz, enemy_animateDrop
    ; Check if exploding/becoming a drop
    ldh a, [hEnemy.explosionFlag]
    and a
        jp nz, enemy_animateExplosion
    ; Check if frozen
    ldh a, [hEnemy.iceCounter]
    and a
        jr nz, enemy_animateIce
    ; Check if metroid has been killed?
    ld a, [metroid_state]
    cp $80
        jp z, enemy_metroidExplosion
.jumpToAI:
    ld bc, hEnemy.pAI_high ;$fff2
    ld a, [bc]
    ld h, a
    dec c
    ld a, [bc]
    ld l, a
    jp hl ; Jump to enemy AI !!!

; Default AI stub
enAI_NULL: ; 02:5651
    ret

; Handles the ice beam timer and the unfreezing animation
;  Called directly by the normal metroids
enemy_animateIce: ;{ 02:5652
    ; Check if sprite is a standard metroid
    ; (the standard metroid will call this on its own terms)
    ldh a, [hEnemy.spriteType]
    cp SPRITE_METROID_1 ; $A0
        jr z, enemy_commonAI.jumpToAI
    sub SPRITE_METROID_2 ; $CE
        jr z, enemy_commonAI.jumpToAI
    dec a ; checks for SPRITE_METROID_3 ($CF)
        jr z, enemy_commonAI.jumpToAI
.call: ; 02:565F - Called directly by normal metroids
    ; Act every other frame
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    ; Do nothing except increment the ice counter if it is below $C4
    ld hl, hEnemy.iceCounter
    ld a, [hl]
    cp $c4
    ; Double increment to adjust for only doing this every other frame
    inc [hl]
    inc [hl]
        ret c
    cp $d0
    jr nc, .else_A
        ; Blink for a few frames
        ld hl, hEnemy.status
        ld a, [hl]
        xor $80
        ld [hl], a
        ret
    .else_A:
        ; Clear ice counter
        xor a
        ld [hl+], a
        ; Check health
        ld a, [hl]
        and a
        jr z, .else_B
            ; Unfreeze
            xor a
            ldh [hEnemy.stunCounter], a
            ldh [hEnemy.status], a
            ret
        .else_B:
            ; Kill
            ld a, sfx_noise_enemyKilled
            ld [sfxRequest_noise], a
            call enemy_deleteSelf_farCall
            ld a, $02
            ldh [hEnemy.spawnFlag], a
            ret
;} end branch

; Drop animation handler
;  [hEnemy.counter] is used as a timer in this state
enemy_animateDrop: ;{ 02:5692
    ; Check and increment timer
    ld hl, hEnemy.counter
    ld a, [hl]
    inc [hl]
    cp $b0
    jr z, .else_A
        ; Have the drop pulsate more rapidly after $80 frames
        cp $80
        jr nc, .else_B
            ; Animate every 4th frame
            ldh a, [hEnemy_frameCounter]
            and $03
                ret nz
            jr .endIf_B
        .else_B:
            ; Animate every other frame
            ldh a, [hEnemy_frameCounter]
            and $01
                ret nz
        .endIf_B:
        ; Flip low bit of sprite type
        ld hl, hEnemy.spriteType
        ld a, [hl]
        xor $01
        ld [hl], a
        ret
    .else_A:
        ; Clear timer and drop type
        xor a
        ld [hl], a
        ldh [hEnemy.dropType], a
        ; Die
        call enemy_deleteSelf_farCall
        ; Permanently kill enemy if applicable
        ld a, $02
        ldh [hEnemy.spawnFlag], a
        ret
;} end branch

; Explosion animation handler
; - Note that explosion and drop type is set in enemy_getDamagedOrGiveDrop
enemy_animateExplosion: ;{ 02:56BF
    bit 5, a
        jr nz, .screwExplosion
; Normal explosions
    ld b, SPRITE_NORMAL_EXPLOSION_END - SPRITE_NORMAL_EXPLOSION_START + 1 ; $03
    cp $11 ; Small health
        jr z, .normalExplosion
    ; Make explosions for other drops last an extra frame
    inc b
jr .normalExplosion

.screwExplosion: ; Also, doors
    ; Increment animation counter
    ld hl, hEnemy.counter
    ld a, [hl]
    inc [hl]
    ; Become drop after 6 frames
    cp SPRITE_SCREW_EXPLOSION_END - SPRITE_SCREW_EXPLOSION_START + 1 ; $06
        jr z, .becomeDrop
    add SPRITE_SCREW_EXPLOSION_START ; $E2 ; Base sprite number of screw explosion
    ldh [hEnemy.spriteType], a
ret

.normalExplosion:
    ; Increment animation counter
    ld hl, hEnemy.counter
    ld a, [hl]
    inc [hl]
    ; Become drop after 3 or 4 frames
    cp b
        jr z, .becomeDrop
    add SPRITE_NORMAL_EXPLOSION_START ; $E8 ; Base sprite number of normal explosion
    ldh [hEnemy.spriteType], a
ret

.becomeDrop:
    ; Special case for enemies with initial health of $FD
    ; (only Arachnus in vanilla, but he doesn't seem to rely on it)
    ldh a, [hEnemy.maxHealth]
    cp $fd
        jr z, .doNotDie

    ; 50% chance of dropping nothing
    ld a, [rDIV]
    and $01
        jr nz, .dropNothing

    ldh a, [hEnemy.explosionFlag]
    and $0f
        jr z, .dropNothing ; Case 0 - Nothing/default?
    dec a
        jr z, .dropSmallHealth ; Case 1 - Small Health
    dec a
        jr z, .dropLargeHealth ; Case 2 - Large health

    ; Missile drop
        ld bc, ($04 << 8) | SPRITE_MISSILE_DROP ; $04EE ; drop type, sprite ID
        jr .setDrop
    .dropSmallHealth:
        ld bc, ($01 << 8) | SPRITE_SMALL_HEALTH ; $01E0 ; drop type, sprite ID
        jr .setDrop
    .dropLargeHealth:
        ld bc, ($02 << 8) | SPRITE_BIG_HEALTH ; $02EC ; drop type, sprite ID
        jr .setDrop

.setDrop:
    ; Set drop and sprite type based on what's in bc
    ld a, b
    ldh [hEnemy.dropType], a
    ld a, c
    ldh [hEnemy.spriteType], a
    ; Clear counters
    xor a
    ldh [hEnemy.stunCounter], a
    ldh [hEnemy.iceCounter], a
    ldh [hEnemy.counter], a
    ldh [hEnemy.explosionFlag], a
ret

.dropNothing:
    ; Delete self
    call enemy_deleteSelf_farCall
    ; Permanently kill self if applicable
    ld a, $02
    ldh [hEnemy.spawnFlag], a
ret

.doNotDie:
    ; Clear variables
    xor a
    ldh [hEnemy.stunCounter], a
    ldh [hEnemy.iceCounter], a
    ldh [hEnemy.explosionFlag], a
    ; Increment this counter
    inc a
    ldh [hEnemy.counter], a
ret
;}

; Metroid death branch
enemy_metroidExplosion: ;{ 02:5732
    ; If an projectile, delete self
    ldh a, [hEnemy.spawnFlag]
    cp $06
        jr z, .deleteProjectile
    ; If not a Metroid explosion, do AI
    ldh a, [hEnemy.spriteType]
    cp SPRITE_SCREW_EXPLOSION_START ; $E2
        jp c, enemy_commonAI.jumpToAI
    cp SPRITE_SCREW_EXPLOSION_END + 1 ; $E8
        jp nc, enemy_commonAI.jumpToAI

    ; Activate cutscene (freeze Samus) if not activated
    ld hl, cutsceneActive
    ld a, [hl]
    and a
    jr nz, .endIf_A
        ld [hl], $01
        call .forceOnscreen
    .endIf_A:

    ; Check counter
    ld hl, hEnemy.counter
    ld a, [hl]
    cp SPRITE_SCREW_EXPLOSION_END - SPRITE_SCREW_EXPLOSION_START + 1 ; $06
    jr z, .else_B
        ; Set sprite type
        add SPRITE_SCREW_EXPLOSION_START ; $E2 ; Base sprite number of explosion
        ldh [hEnemy.spriteType], a
        ; Increment animation counter
        inc [hl]
        ret
    .else_B:
        ; Restart animation counter
        ld [hl], $00
        ; Different states to make multiple explosions
        ld hl, hEnemy.state
        inc [hl]
        ld a, [hl]
        dec a ; State 1
            jr z, .case_1
        dec a ; State 2
            jr z, .case_2
        dec a ; State 3
            jr z, .case_3
        ; State 4
    
    ;.case_4:
        ; Clear collision variables
        ld a, $ff
        ld hl, enSprCollision.weaponType
        ld [hl+], a
        ld [hl+], a
        ld [hl], a
        ; Delete self (permanently if possible)
        call enemy_deleteSelf_farCall
        ld a, $02
        ldh [hEnemy.spawnFlag], a
        ; Clear flags
        xor a
        ld [metroid_state], a ; Ensure we're done with this branch
        ld [cutsceneActive], a ; Unfreeze Samus
        ret
    ; end if

    .case_1: ; Left
        ; Move left
        ld hl, hEnemy.xPos
        ld a, [hl]
        sub $10
        ld [hl], a
        call .forceOnscreen
    ret
    
    .case_2: ; Up right
        ; Move up
        ld hl, hEnemy.yPos
        ld a, [hl]
        sub $10
        ld [hl], a
      .moveRight:
        ; Move right
        ld hl, hEnemy.xPos
        ld a, [hl]
        add $10
        ld [hl], a
        call .forceOnscreen
    ret
    
    .case_3: ; Down right
        ; Move down
        ld hl, hEnemy.yPos
        ld a, [hl]
        add $10
        ld [hl], a
    jr .moveRight
; end cases

.deleteProjectile:
    call enemy_deleteSelf_farCall
    ld a, $ff
    ldh [hEnemy.spawnFlag], a
ret

; Forces explosion back onscreen
.forceOnscreen: ; 02:57B3
;.yPosCase
    ld hl, hEnemy.yPos
    ld a, [hl]
    cp $f0
        jr nc, .topEdge
    cp $a0
        jr nc, .bottomEdge
    cp $0a
        jr c, .topEdge

.xPosCase:
    inc l
    ld a, [hl]
    cp $f0
        jr nc, .leftEdge
    cp $a0
        jr nc, .rightEdge
    cp $0a
        ret nc

    .leftEdge:
        ld [hl], $18
        ret
    
    .bottomEdge:
        ld [hl], $98
        jr .xPosCase
    
    .topEdge:
        ld [hl], $18
        jr .xPosCase
    
    .rightEdge:
        ld [hl], $98
        ret
;}
;}

;------------------------------------------------------------------------------
; Tsumuri/Needler/Moheek AI (crawlers)
; - Type A (faces right when on top of a platform)
;  - Goes counter-clockwise in enclosed spaces
;  - Goes clockwise on floating platforms
;
; Note about the directional values used here in [hEnemy.directionFlags]
;  0 (b:00) - Right
;  1 (b:01) - Down
;  2 (b:10) - Left
;  3 (b:11) - Up
; Essentially, bit 0 controls the axis while bit 1 controls whether it goes
;  forward or backwards on the given axis.
; The Gunzoo uses the same schema.
enAI_crawlerA: ;{ 02:57DE
    jr .convexChecks

.gotoConcaveChecks:
    ; I don't know why this is here
    ld a, $ff
    ldh [hEnemy.counter], a
jr .concaveChecks

.moveAndAnimate:
    call crawler_move
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    ld hl, hEnemy.spriteType
    call enemy_flipSpriteId.now
ret

; Check inside corners
.concaveChecks:
    ; Check movement direction
    ldh a, [hEnemy.directionFlags]
    and a ; Case 0 - Right
        jr z, .insideCornerCheck_bottomRight
    dec a ; Case 1 - Down
        jr z, .insideCornerCheck_bottomLeft
    dec a ; Case 2 - Left
        jr z, .insideCornerCheck_topLeft
    ; Case 3 - Up

;.insideCornerCheck_topRight:
    call enCollision_up.crawlA
    ld a, [en_bgCollisionResult]
    bit 3, a
        jr z, .moveAndAnimate
    call crawler_turn.left
ret

.insideCornerCheck_bottomRight: ; Right
    call enCollision_right.crawlA
    ld a, [en_bgCollisionResult]
    bit 0, a
        jr z, .moveAndAnimate
    call crawler_turn.up
ret

.insideCornerCheck_bottomLeft: ; Down
    call enCollision_down.crawlA
    ld a, [en_bgCollisionResult]
    bit 1, a
        jr z, .moveAndAnimate
    call crawler_turn.right
ret

.insideCornerCheck_topLeft: ; Left
    call enCollision_left.crawlA
    ld a, [en_bgCollisionResult]
    bit 2, a
        jr z, .moveAndAnimate
    call crawler_turn.down
ret
; end concave checks

; Check the outside corners
.convexChecks:
    ; Check movement direction
    ldh a, [hEnemy.directionFlags]
    and a ; Case 0 - Right
        jr z, .outsideCornerCheck_topRight
    dec a ; Case 1 - Down
        jr z, .outsideCornerCheck_bottomRight
    dec a ; Case 2 - Left
        jr z, .outsideCornerCheck_bottomLeft
    ; Case 3 - Up

;.outsideCornerCheck_topLeft:
    call enCollision_right.crawlA
    ld a, [en_bgCollisionResult]
    bit 0, a
        jr nz, .gotoConcaveChecks
    call crawler_turn.right
ret

.outsideCornerCheck_topRight: ; Right
    call enCollision_down.crawlA
    ld a, [en_bgCollisionResult]
    bit 1, a
        jp nz, .gotoConcaveChecks
    call crawler_turn.down
ret

.outsideCornerCheck_bottomRight: ; Down
    call enCollision_left.crawlA
    ld a, [en_bgCollisionResult]
    bit 2, a
        jp nz, .gotoConcaveChecks
    call crawler_turn.left
ret

.outsideCornerCheck_bottomLeft: ; Left
    call enCollision_up.crawlA
    ld a, [en_bgCollisionResult]
    bit 3, a
        jp nz, .gotoConcaveChecks
    call crawler_turn.up
ret
;}

;--------------------------------------
; Shared movement subroutine for the crawlers
crawler_move: ;{ 02:587E
    ld hl, hEnemy.yPos
    ldh a, [hEnemy.directionFlags]
    and $0f
    ; Y movement cases
    cp $01 ; Case 1 - go down
        jr z, .moveForward
    cp $03 ; Case 3 - go up
        jr z, .moveBack
    ; X movement cases
    inc l
    and a ; Case 0 - go right
        jr z, .moveForward
    ; Case 2 - go left
    
    .moveBack:
        dec [hl]
        ret
    .moveForward:
        inc [hl]
        ret
;} end crawler_move

; Shared rotation functions for the crawlers
crawler_turn: ;{
.right: ; 02:5895
    ; Set direction to right (0)
    ldh a, [hEnemy.directionFlags]
    and $f0
    ldh [hEnemy.directionFlags], a
    ; Set sprite type to $x0
    ld hl, hEnemy.spriteType
    ld a, [hl]
    and $f0
.xFlip:
    ; Set attributes
    ld [hl+], a
    inc l
    ld a, OAM_XFLIP
    ld [hl], a
ret

.down: ; 02:58A7
    ; Set direction to down (1)
    ldh a, [hEnemy.directionFlags]
    and $f0
    inc a
    ldh [hEnemy.directionFlags], a
    ; Set sprite type to $x2
    ld hl, hEnemy.spriteType
    ld a, [hl]
    and $f0
    add $02
jr .xFlip

.left: ; 02:58B8
    ; Set direction to left (2)
    ldh a, [hEnemy.directionFlags]
    and $f0
    add $02
    ldh [hEnemy.directionFlags], a
    ; Set sprite type to $x0
    ld hl, hEnemy.spriteType
    ld a, [hl]
    and $f0
.yFlip:
    ld [hl+], a
    ; Set attributes
    inc l
    ld a, OAM_YFLIP
    ld [hl], a
ret

.up: ; 02:58CC
    ; Set direction to up (3)
    ldh a, [hEnemy.directionFlags]
    and $f0
    add $03
    ldh [hEnemy.directionFlags], a
    ; Set sprite type to $x2
    ld hl, hEnemy.spriteType
    ld a, [hl]
    and $f0
    add $02
jr .yFlip
;}

;------------------------------------------------------------------------------
; Tsumuri/Needler/Moheek AI (crawlers)
; - Type A (faces left when on top of a platform)
;  - Goes clockwise in enclosed spaces
;  - Goes counter-clockwise on floating platforms
enAI_crawlerB: ;{ 02:58DE
    jr .convexChecks

.gotoConcaveChecks:
    ; I don't know what this is
    ld a, $ff
    ldh [hEnemy.counter], a
jr .concaveChecks

.moveAndAnimate:
    call crawler_move
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    call enemy_flipSpriteId.now
ret

; Check inside corners
.concaveChecks:
    ldh a, [hEnemy.directionFlags]
    and a ; Case 0 - Right
        jr z, .insideCornerCheck_topRight
    dec a ; Case 1 - Down
        jp z, .insideCornerCheck_bottomRight
    dec a ; Case 2 - Left
        jp z, .insideCornerCheck_bottomLeft
    ; Case 3 - Up

;.insideCornerCheck_topLeft:
    call enCollision_up.crawlB
    ld a, [en_bgCollisionResult]
    bit 3, a
        jr z, .moveAndAnimate
    call crawler_turn.right
    ld hl, hEnemy.attr
    set B_OAM_YFLIP, [hl]
ret

.insideCornerCheck_topRight: ; Right
    call enCollision_right.crawlB
    ld a, [en_bgCollisionResult]
    bit 0, a
        jr z, .moveAndAnimate
    call crawler_turn.down
    ld hl, hEnemy.attr
    res B_OAM_XFLIP, [hl]
ret

.insideCornerCheck_bottomRight: ; Down
    call enCollision_down.crawlB
    ld a, [en_bgCollisionResult]
    bit 1, a
        jr z, .moveAndAnimate
    call crawler_turn.left
    ld hl, hEnemy.attr
    res B_OAM_YFLIP, [hl]
ret

.insideCornerCheck_bottomLeft: ; Left
    call enCollision_left.crawlB
    ld a, [en_bgCollisionResult]
    bit 2, a
        jr z, .moveAndAnimate
    call crawler_turn.up
    ld hl, hEnemy.attr
    set B_OAM_XFLIP, [hl]
ret
; end concave checks

; Check the outside corners
.convexChecks:
    ldh a, [hEnemy.directionFlags]
    and a ; Case 0 - Right
        jr z, .outsideCornerCheck_bottomRight
    dec a ; Case 1 - Down
        jr z, .outsideCornerCheck_bottomLeft
    dec a ; Case 2 - Left
        jr z, .outsideCornerCheck_topLeft
    ; Case 3 - Up

;.outsideCornerCheck_topRight:
    call enCollision_left.crawlB
    ld a, [en_bgCollisionResult]
    bit 2, a
        jp nz, .gotoConcaveChecks
    call crawler_turn.left
    ld hl, hEnemy.attr
    res B_OAM_YFLIP, [hl]
ret

.outsideCornerCheck_bottomRight: ; Right
    call enCollision_up.crawlB
    ld a, [en_bgCollisionResult]
    bit 3, a
        jp nz, .gotoConcaveChecks
    call crawler_turn.up
    ld hl, hEnemy.attr
    set B_OAM_XFLIP, [hl]
ret

.outsideCornerCheck_bottomLeft: ; Down
    call enCollision_right.crawlB
    ld a, [en_bgCollisionResult]
    bit 0, a
        jp nz, .gotoConcaveChecks
    call crawler_turn.right
    ld hl, hEnemy.attr
    set B_OAM_YFLIP, [hl]
ret

.outsideCornerCheck_topLeft: ; Left
    call enCollision_down.crawlB
    ld a, [en_bgCollisionResult]
    bit 1, a
        jp nz, .gotoConcaveChecks
    call crawler_turn.down
    ld hl, hEnemy.attr
    res B_OAM_XFLIP, [hl]
ret
;}

;------------------------------------------------------------------------------
; Skreek projectile code
skreek_projectileCode: ;{ 02:59A6
    ; Decrement timer
    ;  Note: the projectile's header sets hEnemy.counter with an initial value of $10
    ld hl, hEnemy.counter
    dec [hl]
    jr z, .else_A
        ld hl, hEnemy.xPos
        ld b, $02 ; Load speed
        ldh a, [hEnemy.attr]
        bit B_OAM_XFLIP, a
        jr nz, .else_B
            ; Move left
            ld a, [hl]
            sub b
            ld [hl], a
            ret
        .else_B:
            ; Move right
            ld a, [hl]
            add b
            ld [hl], a
            ret
    .else_A:
        call enemy_deleteSelf_farCall
        ld a, $ff
        ldh [hEnemy.spawnFlag], a
        ret
;}

; Skreek AI (bird faced things that jump out of lava and spit at samus)
enAI_skreek: ;{ 02:59C7
    ldh a, [hEnemy.spawnFlag]
    and $0f
        jr z, skreek_projectileCode

    call .animate
    ; State graph is a simple 0->1->2->3->0 loop
    ldh a, [hEnemy.counter]
    dec a ; State 1 - Move up and spit
        jr z, .case_1
    dec a ; State 2 - Wait for projectile to disappear
        jr z, .case_2
    dec a ; State 3 - Move down
        jr z, .case_3

; State 0 - Wait to act
    ; Wait until timer is equal to $10
    ld hl, hEnemy.state
    inc [hl]
    ld a, [hl]
    cp $10
        ret nz
    ; Reset timer
    ld [hl], $00

    ld c, $00 ; Default - Face right
    ; Compare positions to see which side Samus is on
    ld a, [samus_onscreenXPos]
    ld b, a
    ld hl, hEnemy.xPos
    ld a, [hl]
    sub b
    jr nc, .endIf_A
        ; Face left
        cpl
        inc a
        ld c, OAM_XFLIP
    .endIf_A:
    ; Also, only act if Samus is in range
    cp $30
        ret nc
    ; Set direction
    ld a, c
    ldh [hEnemy.attr], a
    ; Set state to 1 (rising/firing)
    ld a, $01
    ldh [hEnemy.counter], a
ret

.case_2:
    ; Wait for spit to disappear
    ldh a, [hEnemy.spawnFlag]
    cp $03
        ret z
    ; Close mouth
    ld a, SPRITE_SKREEK_1 ; $04
    ldh [hEnemy.spriteType], a
    ; Set state to 3
    ld a, $03
    ldh [hEnemy.counter], a
ret

.case_3:
    ; Decrement timer
    ld hl, hEnemy.state
    dec [hl]
    jr z, .else_B
        ; Get speed from table, based on timer
        ld e, [hl]
        ld d, $00
        ld hl, .jumpSpeedTable
        add hl, de
        ld b, [hl]
        ; Move down
        ld hl, hEnemy.yPos
        ld a, [hl]
        add b
        ld [hl], a
        ret
    .else_B:
        ; Set state back to 0
        xor a
        ldh [hEnemy.counter], a
        ret
; end proc

.case_1: ; Move up and spit
    ; Check timer
    ld hl, hEnemy.state
    ld a, [hl]
    cp $21
    jr z, .else_C
        ; Get speed from table, based on timer
        ld e, a
        ld d, $00
        inc [hl] ; Increment timer
        ld hl, .jumpSpeedTable
        add hl, de
        ld b, [hl]
        ; Move up
        ld hl, hEnemy.yPos
        ld a, [hl]
        sub b
        ld [hl], a
        ret
    .else_C:
        ; Set state to 2
        ld a, $02
        ldh [hEnemy.counter], a
        ; Spawn projectile
        call loadEnemy_getFirstEmptySlot_longJump
        ; Set status to active
        xor a
        ld [hl+], a
        ; Set y pos
        ldh a, [hEnemy.yPos]
        ld [hl+], a
        ; Check attribute to set x pos
        ldh a, [hEnemy.attr]
        ld b, a
        bit B_OAM_XFLIP, a
        jr nz, .else_D
            ; Left side
            ldh a, [hEnemy.xPos]
            sub $04
            jr .endIf_D
        .else_D:
            ; Right side
            ldh a, [hEnemy.xPos]
            add $04
        .endIf_D:
        ld [hl+], a
        ; Set sprite number
        ld a, SPRITE_SKREEK_SPIT ; $08
        ld [hl+], a
        ; Set base sprite attribute
        ld a, $80
        ld [hl+], a
        ; Set sprite attribute
        ld a, b
        ld [hl+], a

        ld de, .projectileHeader
        ; Check link so the projectile's death can be signaled to the skreek
        call enemy_createLinkForChildObject
        ; Load header
        call enemy_spawnObject.shortHeader
        ; Set spawn flag to wait until projectile disappears
        ld a, $03
        ldh [hEnemy.spawnFlag], a
        ; Open mouth
        ld a, SPRITE_SKREEK_4 ; $07
        ldh [hEnemy.spriteType], a
        ; *spit*
        ld a, sfx_noise_enemyProjectileFired
        ld [sfxRequest_noise], a
        ret
; end state

.jumpSpeedTable: ; 02:5A7D
    db $00, $05, $05, $05, $04, $05, $03, $03, $02, $03, $03, $03, $02, $03, $03, $02
    db $02, $03, $02, $02, $00, $01, $01, $01, $00, $01, $01, $00, $00, $01, $00, $00
    db $00
.projectileHeader: ; 02:5A9E
    db $00, $00, $00, $10, $00, $00, $ff, $07
    dw enAI_skreek

.animate:
    ; Don't animate when projectile is active
    ldh a, [hEnemy.spawnFlag]
    cp $03
        ret z
    ; Animate every fourth frame
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    ; Animate 4-5-6, 4-5-6, etc.
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_SKREEK_3 ; $06
    jr z, .else_E
        inc [hl]
        ret
    .else_E:
        ld [hl], SPRITE_SKREEK_1 ; $04
        ret
;}

;------------------------------------------------------------------------------
; 02:5ABF - small bug AI (enemy 12h)
; Yumbos, Meboids, Mumbos, Pincher Flies, Seerooks, and TPOs
; (TODO: verify they all actually use this)
; Uses spritemaps 12h and 13h
enAI_smallBug: ;{ 02:5ABF
    call enemy_flipSpriteId.now ; Animate
    call .act
ret

.act:
    ; Turn around when frame counter reaches $40
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $40 ; turnaround time
        jr z, .flip

    ; Move according to direction
    ld hl, hEnemy.xPos
    ldh a, [hEnemy.attr]
    bit B_OAM_XFLIP, a
        jr nz, .moveRight
    
    ; Move Left
    dec [hl]
ret

    .moveRight:
    inc [hl]
ret

    .flip:
    ld [hl], $00
    call enemy_flipHorizontal.now
ret
;}

;------------------------------------------------------------------------------
; Drivel AI (bomb-dropping bat)
enAI_drivel: ;{ 02:5AE2
    call .animate
    ldh a, [hEnemy.state]
    and a
        jr nz, .tryShooting
    ; Randomly enter try-shooting state
    ld a, [rDIV]
    and $0f
        jr z, .startTryShooting
    ; Fallthrough to moving

.move:
    ld de, hEnemy.yPos
    ld hl, .ySpeedTable
    ldh a, [hEnemy.counter]
    ld c, a
    ld b, $00
    add hl, bc
    ld a, [hl]
    cp $80
        jr z, .flipDirection

    ; Check if negative
    bit 7, [hl]
    jr nz, .else_A
        ; If not, then add
        ld a, [de]
        add [hl]
        jr .endIf_A
    .else_A:
        ; else, negate and then subtract
        ld a, [hl]
        cpl
        inc a
        ld b, a
        ld a, [de]
        sub b
        ld b, $00
    .endIf_A:
    ; Store the result
    ld [de], a
    ; DE now points to xpos
    inc e
    ld hl, .xSpeedTable
    add hl, bc
    ldh a, [hEnemy.directionFlags]
    and a
        jr nz, .moveLeft
; move right
    ld a, [de]
    add [hl]
    ld [de], a
    ; inc counter
    ld hl, hEnemy.counter
    inc [hl]
ret

.flipDirection:
    ; flip direction
    ldh a, [hEnemy.directionFlags]
    xor $02
    ldh [hEnemy.directionFlags], a
    ; Reset counter
    xor a
    ldh [hEnemy.counter], a
ret

.moveLeft:
    ; move left
    ld a, [de]
    sub [hl]
    ld [de], a
    ; inc counter
    ld hl, hEnemy.counter
    inc [hl]
ret

.startTryShooting:
    ; Set try shooting state
    ld a, $01
    ldh [hEnemy.state], a
.tryShooting:
    ; abs(samusX_screen - enemyX)
    ld a, [samus_onscreenXPos]
    ld b, a
    ld hl, hEnemy.xPos
    ld a, [hl]
    sub b
    jr nc, .endIf_B
        cpl
        inc a
    .endIf_B:
    ; If not within range, just move
    cp $30
        jr nc, .move
    ; else, shoot projectile
    ; Reset state
    ld hl, hEnemy.state
    ld [hl], $00
    ; Spawn projectile
    call loadEnemy_getFirstEmptySlot_longJump
    xor a
    ld [hl+], a
    ldh a, [hEnemy.yPos]
    add $08
    ld [hl+], a
    ldh a, [hEnemy.xPos]
    ld [hl+], a
    ld de, .projectileHeader
    call enemy_createLinkForChildObject
    call enemy_spawnObject.longHeader
    ; Causes drivel to animate, but not act (see .animate function below)
    ld a, $03
    ldh [hEnemy.spawnFlag], a
ret

.projectileHeader: ; 02:5B6C
    db $0C, $80, $00, $00, $00, $00, $00, $00, $00, $01, $00
    dw enAI_drivelSpit
.ySpeedTable: ; 02:5B79
    db $01, $01, $01, $02, $03, $03, $03, $03, $03, $02, $02, $02, $02, $01, $01, $00
    db $00, $FF, $FE, $FD, $FC, $FA, $FD, $FE, $FE, $FE, $FE, $FE, $FF, $80
.xSpeedTable: ; 02:5B97
    db $00, $01, $00, $01, $01, $02, $01, $02, $02, $03, $02, $03, $04, $03, $03, $02
    db $04, $02, $05, $04, $05, $04, $01, $02, $01, $01, $00, $01, $00, $80

; Excellent spaghetti code
.animate: ; 02:5BB5
    ldh a, [hEnemy.spawnFlag]
    ld hl, hEnemy.spriteType
    ; Check if this enemy's projectile is onscreen
    cp $03
        jr z, .forceInaction
    ; Check timer so enemy does not animate for the first few frames of its swoop motion
    ldh a, [hEnemy.counter]
    cp $0c
        jr nc, .nextFrame
.resetAnimation:
    ld [hl], SPRITE_DRIVEL_1 ; $09
    ret
    
.forceInaction:
    ; Pop the return address of the stack so the next ret instruction exits the enemy AI
    ; so the enemy animates, but does no other action while its projectile is onscreen
    pop af
.nextFrame:
    ; Animate every other frame
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    ; Loop back to start of animation if at the end
    ld a, [hl]
    cp SPRITE_DRIVEL_3 ; $0B
        jr z, .resetAnimation
    ; Set next frame
    inc [hl]
ret
;}

; Drivel projectile code
enAI_drivelSpit: ;{ 02:5BD4
    ; Initial enemySpriteType is $0C
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_DRIVEL_SPIT_3 ; $0E
        jr z, .fall  ; Jump if equal
        jr nc, .explode ; Jump if greater

; animate start
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    inc [hl]
ret

.fall: ; Fall
    ; Move
    ld hl, hEnemy.yPos
    inc [hl]
    call enemy_accelForwards
    ; Check collision
    call enCollision_down.nearSmall
    ld a, [en_bgCollisionResult]
    bit 1, a
        ret z
    ; Ground has been hit, so move on to next state
    ld a, SPRITE_DRIVEL_SPIT_4 ; $0F
    ldh [hEnemy.spriteType], a
    ld a, sfx_noise_enemyHitGround
    ld [sfxRequest_noise], a
ret

.explode:
    ; Execute every 4th frame
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    ; Animate explosion
    ; inc enemySpriteType
    inc [hl]
    ld a, [hl]
    cp SPRITE_DRIVEL_SPIT_6 + 1 ; $12
        ret c
    
    ; Get WRAM offset for parent creature
    ld h, $c6
    ldh a, [hEnemy.spawnFlag]
    bit 4, a
    jr nz, .else_A
        add $1c
        ld l, a
        jr .endIf_A
    .else_A:
        add $0c
        ld l, a
        inc h
    .endIf_A:

    ; Check if parent enemy still exists
    ld a, [hl]
    cp $03
    jr nz, .endIf_B
        ; Tell it that this projectile is done
        ld a, $01
        ld [hl+], a
        ; Also update the spawn flag table accordingly
        ld a, [hl]
        ld hl, enemySpawnFlags
        ld l, a
        ld [hl], $01
    .endIf_B:

    ; Delete self
    call enemy_deleteSelf_farCall
    ld a, sfx_noise_enemyExplosion
    ld [sfxRequest_noise], a
    ld a, $ff
    ldh [hEnemy.spawnFlag], a
ret
;}

;------------------------------------------------------------------------------
; Senjoo/Shirk AI (things that move in a diamond shaped loop)
enAI_senjooShirk: ;{ 02:5C36
    call .animate ; animate
    ; Get absolute value of distance between enemy and Samus
    ld a, [samus_onscreenXPos]
    ld b, a
    ld hl, hEnemy.xPos
    ld a, [hl]
    sub b
    jr nc, .endIf_A
        cpl
        inc a
    .endIf_A:
    ; Prep HL for idle motion
    ld hl, hEnemy.generalVar
    ; Do active motion if within $50 pixels
    cp $50
        jr c, .activeMotion
    ; else, do idle motion

;idleMotion: ; bob up and down
    ; Act every other frame
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
        
    ld a, [hl]
    cp $0c
    jr z, .else_A
        ; Move down 8 frames at 2 px/frame
        ; Move up   4 frames at 4 px/frame
        cp $08
        jr nc, .else_B
            inc [hl] ; hEnemy.generalVar
            ; Move down
            ld hl, hEnemy.yPos
            ld a, [hl]
            add $02
            ld [hl], a
            ret
        .else_B:
            inc [hl] ; hEnemy.generalVar
            ; Move up
            ld hl, hEnemy.yPos
            ld a, [hl]
            sub $04
            ld [hl], a
            ret
    .else_A:
        ; Reset idle motion
        ldh a, [hEnemy_frameCounter]
        and $03
            ret nz
        ; Reset hEnemy.generalVar
        ld [hl], $00
        ret

; go in a diamond pattern
.activeMotion:
    ld b, $10
    ld hl, hEnemy.state
    ld a, [hl-]
    and a
        jr z, .case_downLeft ; case 0
    dec a
        jr z, .case_downRight ; case 1
    dec a
        jr z, .case_upRight ; case 2
    ; case 3 (default case)

; case_upLeft
    ; Check behavior counter
    ld a, [hl] ; HL = hEnemy.counter
    cp b
        jr z, .resetState
    inc [hl]
    ; ypos - go up
    ld hl, hEnemy.yPos
    dec [hl]
    dec [hl]
    ; xpos - go left
    inc l
    dec [hl]
    dec [hl]
ret

.resetState:
    xor a
    ld [hl+], a
    xor a
    ld [hl], a
ret

.case_downLeft:
    ; Check behavior counter
    ld a, [hl]
    cp b
        jr z, .nextState
    inc [hl]
    ; ypos - go down
    ld hl, hEnemy.yPos
    inc [hl]
    inc [hl]
    ; xpos - go left
    inc l
    dec [hl]
    dec [hl]
ret

.nextState:
    ; reset behavior counter
    xor a
    ld [hl+], a
    ; inc hEnemy.state
    ld a, [hl]
    inc a
    ld [hl], a
ret

.case_downRight:
    ; Check behavior counter
    ld a, [hl]
    cp b
        jr z, .nextState
    inc [hl]
    ; ypos - go down
    ld hl, hEnemy.yPos
    inc [hl]
    inc [hl]
    ; xpox - go right
    inc l
    inc [hl]
    inc [hl]
ret

.case_upRight:
    ; Check behavior counter
    ld a, [hl]
    cp b
        jr z, .nextState
    inc [hl]
    ; ypos - go up
    ld hl, hEnemy.yPos
    dec [hl]
    dec [hl]
    ; xpos - go right
    inc l
    inc [hl]
    inc [hl]
ret

.animate:
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_SHIRK_1 ; $63
    jr nc, .endIf_B
        ; Senjoo animation
        ld hl, hEnemy.attr
        ld a, [hl]
        xor OAM_XFLIP
        ld [hl], a
        ret
    .endIf_B:
        ; Shirk animation
        xor SPRITE_SHIRK_1 ^ SPRITE_SHIRK_2 ; $07
        ld [hl], a
        ret
;} end proc

;------------------------------------------------------------------------------
; gullugg AI - Thing that flies in a circle
enAI_gullugg: ;{ 02:5CE0
    call .animate
    ; [hEnemy.counter] appears to be an animation counter
    ld hl, hEnemy.counter
    ld c, [hl]
    ld b, $00

    ; Read next value from a looping, $80-terminated table
    .loop:
        ld hl, .ySpeedTable_cw ; yPos table
        add hl, bc
        ld a, [hl]
        cp $80
            jr nz, .break
    
        ; If the table gave us a value of $80, reset the counter try again at the beginning
        ld c, $00
        xor a
        ldh [hEnemy.counter], a
    jr .loop

.break:
    ; Handle y movement
    ldh a, [hEnemy.yPos]
    add [hl]
    ldh [hEnemy.yPos], a
    ; Index the x speed table
    ld hl, .xSpeedTable_cw
    add hl, bc
    ; Handle x movement
    ldh a, [hEnemy.xPos]
    add [hl]
    ldh [hEnemy.xPos], a
    ; Increment the counter
    ld hl, hEnemy.counter
    inc [hl]
ret

; Tables for counter-clockwise circular motion (unused)
.ySpeedTable_ccw: ; 02:5D0C
    db $01, $00, $01, $02, $01, $02, $03, $02, $03, $03, $04, $03, $04, $04, $03, $04
    db $04, $04, $03, $03, $04, $03, $02, $03, $02, $01, $02, $01, $00, $00, $00, $00
    db $FF, $FE, $FF, $FE, $FD, $FE, $FD, $FC, $FD, $FD, $FC, $FC, $FC, $FD, $FC, $FC
    db $FD, $FC, $FD, $FD, $FE, $FD, $FE, $FF, $FE, $FF, $00, $FF, $80
.xSpeedTable_ccw: ; 02:5D49
    db $FD, $FC, $FC, $FD, $FC, $FD, $FD, $FE, $FD, $FE, $FF, $FE, $FF, $00, $FF, $01
    db $00, $01, $02, $01, $02, $03, $02, $03, $03, $04, $03, $04, $04, $03, $04, $04
    db $04, $03, $03, $04, $03, $02, $03, $02, $01, $02, $01, $00, $00, $00, $00, $FF
    db $FE, $FF, $FE, $FD, $FE, $FD, $FC, $FD, $FD, $FC, $FC, $FC

; Tables for clockwise circle motion
.ySpeedTable_cw: ; 02:5D85
    db $01, $00, $01, $01, $01, $02, $02, $02, $02, $02, $03, $03, $03, $03, $02, $03
    db $03, $03, $03, $02, $03, $02, $02, $02, $02, $01, $01, $01, $00, $00, $00, $00
    db $ff, $ff, $ff, $fe, $fe, $fe, $fe, $fd, $fe, $fd, $fd, $fd, $fd, $fe, $fd, $fd
    db $fd, $fd, $fe, $fe, $fe, $fe, $fe, $ff, $ff, $ff, $00, $ff, $80
.xSpeedTable_cw: ; 02:5DC2
    db $02, $03, $03, $03, $03, $02, $02, $02, $02, $02, $01, $01, $01, $00, $01, $FF
    db $00, $FF, $FF, $FF, $FE, $FE, $FE, $FE, $FE, $FD, $FD, $FD, $FD, $FE, $FD, $FD
    db $FD, $FD, $FE, $FD, $FE, $FE, $FE, $FE, $FF, $FF, $FF, $00, $00, $00, $00, $01
    db $01, $01, $02, $02, $02, $02, $03, $02, $03, $03, $03, $03

.animate:
    ; Three-frame animation cycling from $D8->$D9->$DA->$D9, etc.
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_GULLUGG_3 ; $DC
    jr z, .endIf
        inc [hl]
            ret
    .endIf:
    ld [hl], SPRITE_GULLUGG_1 ; $D8
ret
;} End of gullugg code

;------------------------------------------------------------------------------
; enemy octroll/chute leech
enAI_chuteLeech: ;{ 02:5E0B
    ldh a, [hEnemy.state]
    dec a
        jr z, .case_ascend ; if state = 1
    dec a
        jr z, .case_descend ; if state = 2

    ; Fall-through case
    ; abs(samusX_screen - enemyX)
    ld a, [samus_onscreenXPos]
    ld b, a
    ld hl, hEnemy.xPos
    ld a, [hl]
    sub b
    jr nc, .endIf_A ; a = -a (two's compliment negation)
        cpl
        inc a
    .endIf_A:

    ; Exit if not withing 5 blocks of distance
    cp $50
        ret nc

    ; state = 1
    ld a, $01
    ldh [hEnemy.state], a
    ; Clear flip flag
    xor a
    ldh [hEnemy.attr], a
    ; Animate ascent
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_OCTROLL_1 ; $3E ; Check if an octroll
    jr nc, .else_A
        ld [hl], SPRITE_CHUTELEECH_2 ; $1C ; Chute leech ascent pose
        ret
    .else_A:
        ld [hl], SPRITE_OCTROLL_1 ; $3E
        ret
; end proc

.case_ascend:
    ; Animate if an octroll
    ldh a, [hEnemy.spriteType]
    cp SPRITE_OCTROLL_1 ; $3E
        call nc, enemy_flipSpriteId.twoFrame

    ; Check if counter == $16
    ldh a, [hEnemy.counter]
    cp $16
        jr z, .prepState2
    ; Ascend
    ld hl, hEnemy.yPos
    ld a, [hl]
    sub $04
    ld [hl], a
    ; Increment counter
    ld hl, hEnemy.counter
    inc [hl]
ret

.prepState2: ; Prep state 2
    ; Clear counter
    xor a
    ldh [hEnemy.counter], a
    ; Go to state 2
    ld a, $02
    ldh [hEnemy.state], a
    ; Animate
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_OCTROLL_1 ; $3E ; Check if not an octroll
    jr nc, .else_B
        ld [hl], SPRITE_CHUTELEECH_3 ; $1D ; chute leech descent pose
        ret
    .else_B:
        ld [hl], SPRITE_OCTROLL_3 ; $40
        ret
; end proc


.case_descend:
    ; Load x speed from table using animation counter
    ld hl, hEnemy.counter
    ld c, [hl]
    ld b, $00
    ld hl, .xSpeedTable
    add hl, bc
    ld a, [hl]
    cp $80 ; speed table is $80-terminated
        jr nz, .descend

    ; Restart AI
    ; Reset counter
    xor a
    ldh [hEnemy.counter], a
    ; Reset state
    ldh [hEnemy.state], a
    ; Animate
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_OCTROLL_1 ; $3E ; Check if not octroll
        ret nc
    ld [hl], SPRITE_CHUTELEECH_1 ; $1B
ret


.descend: ; Move down
    ; Handle flipping animation
    ; Check if flipped
    ldh a, [hEnemy.attr]
    and a
    jr nz, .else_C
        ; Check if not moving left
        bit 7, [hl]
            jr nz, .moveDown
        ; Increment a secondary counter
        ldh a, [hEnemy.generalVar]
        inc a
        ldh [hEnemy.generalVar], a
        cp $04 ; Hang in place for 4 frames
            ret nz
        ; Clear the secondary counter
        xor a
        ldh [hEnemy.generalVar], a
        ; Flip the sprite horizontally
        ldh a, [hEnemy.attr]
        xor OAM_XFLIP
        ldh [hEnemy.attr], a
            jr .moveDown
    
    .else_C:
        ; Check if not moving right
        bit 7, [hl]
            jr z, .moveDown
        ; Increment a secondary counter
        ldh a, [hEnemy.generalVar]
        inc a
        ldh [hEnemy.generalVar], a
        cp $04 ; Hang in place for 4 frames
            ret nz
        ; Clear the secondary counter
        xor a
        ldh [hEnemy.generalVar], a
        ; Flip the sprite horizontally
        ldh a, [hEnemy.attr]
        xor OAM_XFLIP
        ldh [hEnemy.attr], a

.moveDown:
    ; Handle x position
    ldh a, [hEnemy.xPos]
    add [hl]
    ldh [hEnemy.xPos], a
    ; Handle y position
    ld hl, .ySpeedTable
    add hl, bc
    ldh a, [hEnemy.yPos]
    add [hl]
    ldh [hEnemy.yPos], a
    ; Increment counter
    ld hl, hEnemy.counter
    inc [hl]
ret

.xSpeedTable:
    db $ff, $ff, $fe, $fe, $ff, $ff, $02, $02, $02, $02, $03, $03, $02, $04, $02, $02
    db $fe, $fe, $fe, $fe, $fe, $fd, $fd, $fd, $fd, $fd, $fd, $fc, $fd, $fd, $fe, $02
    db $03, $02, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $03, $04, $03, $04
    db $03, $02, $fe, $fd, $fd, $fd, $fd, $fc, $fc, $fc, $fc, $fd, $fb, $fd, $fc, $fb
    db $fc, $fc, $fd, $fd, $03, $03, $03, $02, $04, $03, $03, $03, $04, $02, $02, $80
.ySpeedTable:
    db $02, $02, $02, $01, $01, $00, $02, $01, $01, $01, $01, $01, $00, $01, $00, $00
    db $02, $02, $01, $02, $01, $02, $01, $01, $01, $01, $00, $01, $00, $01, $00, $02
    db $01, $02, $01, $01, $01, $01, $01, $01, $01, $01, $00, $01, $00, $01, $00, $01
    db $00, $00, $02, $03, $02, $02, $01, $02, $02, $01, $01, $02, $02, $01, $01, $00
    db $01, $01, $00, $00, $03, $02, $02, $01, $02, $02, $01, $01, $01, $01, $00
;}

;------------------------------------------------------------------------------
; Gawron/Yumee spawner/bug AI (pipe bugs)
enAI_pipeBug: ;{ 02:5F67
    ; Do nothing while child is active
    ldh a, [hEnemy.spawnFlag]
    cp $03
        ret z
    ; If a bug, do bug things
    cp $01
        jp nz, .pipeBugAI
; Spawner AI
    ; Increment wait timer
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $18
        ret c
    ; Reset wait timer
    ld [hl], $00

    ; Check the number of bugs we've spawned
    ld hl, hEnemy.generalVar
    ld a, [hl]
    cp $0a
    jr c, .endIf_A
        ; Delete self
        call enemy_deleteSelf_farCall
        ; Play sound
        ld a, sfx_square1_pipeBugSpawnerStop
        ld [sfxRequest_square1], a
        ; Kill permanently if spawn number is within the saved range of $40-$7F (!)
        ld a, $02
        ldh [hEnemy.spawnFlag], a
        ret
    .endIf_A:
    ; Increment the number of bugs we've spawned
    inc [hl]

; Load in new pipe bug
    ; Get first unused slot
    call loadEnemy_getFirstEmptySlot_longJump
    ; Set status
    xor a
    ld [hl+], a
    ; Set y pos
    ldh a, [hEnemy.yPos]
    ld [hl+], a
    ; Set x pos
    ldh a, [hEnemy.xPos]
    ld [hl+], a

    ; Set sprite type depending on current sprite type
    ldh a, [hEnemy.spriteType]
    cp SPRITE_YUMEE_SPAWNER_1 ; $3C
    jr nc, .else_B
        ld a, SPRITE_GAWRON_1 ; $17 ; Gawron
        jr .endIf_B
    .else_B:
        ld a, SPRITE_YUMEE_1 ; $38 ; Yumee
    .endIf_B:
    ld [hl+], a

    ; Load header
    ld de, .pipeBugHeader ;$5fff
    ld b, $09
    .loadLoop_A:
        ld a, [de]
        ld [hl+], a
        inc de
        dec b
    jr nz, .loadLoop_A
    ; Save max health to C
    ld c, a

    ; Clear 4 bytes (drop type, explosion flag, Y/X screens away)
    xor a
    ld b, $04
    .clearLoop:
        ld [hl+], a
        dec b
    jr nz, .clearLoop
    ; Save max health properly
    ld [hl], c

    ; Similar to enemy_createLinkForChildObject
    ;  Set the spawn flag so the pipe bug can tell its parent when it's dead
    ld a, l
    add $0b
    ld l, a
    ldh a, [hEnemyWramAddrHigh]
    cp $c6
    jr nz, .else_C
        ldh a, [hEnemyWramAddrLow]
        jr .endIf_C
    .else_C:
        ldh a, [hEnemyWramAddrLow]
        add $10
    .endIf_C:
    ld [hl+], a
    ld [enemy_tempSpawnFlag], a
    
    ; Load spawn number depending on parent sprite type (why?)
    ldh a, [hEnemy.spriteType]
    bit 0, a
    jr nz, .else_D
        xor a
        jr .endIf_D
    .else_D:
        ld a, $01
    .endIf_D:
    ld [hl+], a
    
    ; Load AI pointer
    ld b, $02
    .loadLoop_B:
        ld a, [de]
        ld [hl+], a
        inc e
        dec b
    jr nz, .loadLoop_B

    ; Load spawn flag of child into enemySpawnFlags[spawnNumber]
    dec l
    dec l
    dec l
    ld a, [hl]
    ld hl, enemySpawnFlags
    ld l, a
    ld a, [enemy_tempSpawnFlag]
    ld [hl], a
    ; Increment total number of enemies and number of active enemies
    ld hl, numEnemies.total
    inc [hl]
    inc l
    inc [hl]
    ; Set spawner status to dormant
    ld hl, hEnemy.spawnFlag
    ld [hl], $03
ret

; Pipe bug enemy header (non-standard 11 byte header)
.pipeBugHeader: ; 02:5FFF
    db $80, $00, $00, $00, $00, $00, $00, $00, $01
    dw enAI_pipeBug

.pipeBugAI:
    call .animate
    ldh a, [hEnemy.state]
    and a ; State 0
        jr z, .case_wait
    dec a ; State 1
        jr z, .case_rise
    ; State 2
        jr .case_moveHorizontal

.case_wait: ; State 0
    ld c, $02 ; Used to make bug face left
    ; Check if Samus is within range
    ld a, [samus_onscreenXPos]
    ld b, a
    ld hl, hEnemy.xPos
    ld a, [hl]
    sub b
    jr nc, .endIf_E
        cpl
        inc a
        ld c, $00 ; Used to make bug face right
    .endIf_E:
    cp $50
        ret nc

    ; Apply C to set the direction of the bug
    ld a, c
    ldh [hEnemy.directionFlags], a
    and a
    jr z, .else_F
        xor a
        ldh [hEnemy.attr], a
        jr .endIf_F
    .else_F:
        ld a, OAM_XFLIP
        ldh [hEnemy.attr], a
    .endIf_F:
    ; Increment to the next state
    ld a, $01
    ldh [hEnemy.state], a
; continue to next state

.case_rise: ; State 1
    ; Check if Samus is within vertical range
    ld hl, hEnemy.yPos
    ld a, [hl]
    sub $04
    ld [hl], a
    ld a, [samus_onscreenYPos]
    add $05
    cp [hl]
        ret c
    ; Increment state to moving forward
    ld hl, hEnemy.state
    inc [hl]
    ; Animate if a Yumee
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_YUMEE_1 ; $38
        ret c
    ld [hl], SPRITE_YUMEE_3 ; $3A
ret

.case_moveHorizontal: ; State 2
    ld hl, hEnemy.xPos
    ld a, [hl]
    cp $a8
    jr nc, .else_G
        ; Check behavioral flip flag
        ldh a, [hEnemy.directionFlags]
        and a
        jr z, .else_H
            ; Move left
            dec [hl]
            dec [hl]
            call enemy_accelBackwards
            ret
        .else_H:
            ; Move right
            inc [hl]
            inc [hl]
            call enemy_accelForwards
            ret
    .else_G:
        ; Get address of spawn flag of parent object
        ld h, $c6
        ldh a, [hEnemy.spawnFlag]
        bit 4, a
        jr nz, .else_I
            add $1c
            ld l, a
            jr .endIf_I
        .else_I:
            add $0c
            ld l, a
            inc h
        .endIf_I:
        
        ; Check if parent object is inactive
        ld a, [hl]
        cp $03
        jr nz, .endIf_J
            ; Set it to active
            ld a, $01
            ld [hl+], a
            ; Set its spawn flag in the enemySpawnFlags array
            ld a, [hl]
            ld hl, enemySpawnFlags
            ld l, a
            ld [hl], $01
        .endIf_J:
        ; Delete self
        call enemy_deleteSelf_farCall
        ld a, $ff
        ldh [hEnemy.spawnFlag], a
        ret
; end state

.animate: ; 02:609B
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_YUMEE_1 ; $38
    jr nc, .else_K
        ; Gawron animation
        xor SPRITE_GAWRON_1 ^ SPRITE_GAWRON_2 ; $0F
        jr .endIf_K
    .else_K:
        ; Yumee animation
        xor SPRITE_YUMEE_1 ^ SPRITE_YUMEE_2 ; $01
    .endIf_K:
    ld [hl], a
ret
;} end pipe bug AI

;------------------------------------------------------------------------------
; Skorp AI (vertical type) - Things with circular saws that poke out of walls
enAI_skorpVert: ;{ 02:60AB
    ld hl, hEnemy.state
    ld a, [hl-] ; HL decrements to the state counter
    dec a ; Wait while extended
        jr z, .case_1
    dec a ; Retract
        jr z, .case_2
    dec a ; Wait while retracted
        jr z, .case_3

;.case_0 - Extend
    ; Increment counter
    inc [hl]
    ld a, [hl]
    cp $20
    jr z, .nextState
        ; Animate
        call enemy_flipHorizontal.twoFrame
        ; Extend based on direction in header
        ld hl, hEnemy.yPos
        ldh a, [hEnemy.attr]
        bit B_OAM_YFLIP, a
        jr nz, .else_A
            dec [hl]
            ret
        .else_A:
            inc [hl]
            ret
    .nextState:
        ; Clear counter, increment state
        xor a
        ld [hl+], a
        inc [hl]
        ret
; end state

.case_1: ; Wait while extended
    ; Increment counter
    inc [hl]
    ld a, [hl]
    cp $08
        jr z, .nextState
    ret

.case_2: ; Retract
    ; Increment counter
    inc [hl]
    ld a, [hl]
    cp $20
        jr z, .nextState
    ; Animate
    call enemy_flipHorizontal.twoFrame
    ; Retract based on direction in header
    ld hl, hEnemy.yPos
    ldh a, [hEnemy.attr]
    bit B_OAM_YFLIP, a
    jr nz, .else_B
        inc [hl]
        ret
    .else_B:
        dec [hl]
        ret
; end state

.case_3: ; Wait while retracted
    ; Increment counter
    inc [hl]
    ld a, [hl]
    cp $08
        ret nz
    ; Clear counter
    xor a
    ld [hl+], a
    ; Back to state 0
    ld [hl], a
ret
;}

;------------------------------------------------------------------------------
; Skorp AI (horizontal type) - Things with circular saws that poke out of walls
enAI_skorpHori: ;{ 02:60F8
    ld hl, hEnemy.state
    ld a, [hl-]
    dec a ; Wait while extended
        jr z, .case_1
    dec a ; Extend
        jr z, .case_2
    dec a ; Wait while retracted
        jr z, .case_3

;.case_0 - Extend
    ; Increment counter
    inc [hl]
    ld a, [hl]
    cp $20
    jr z, .nextState
        ; Animate
        call enemy_flipVertical.twoFrame
        ; Extend based on direction in header
        ld hl, hEnemy.xPos
        ldh a, [hEnemy.attr]
        bit B_OAM_XFLIP, a
        jr z, .else_A
            dec [hl]
            ret
        .else_A:
            inc [hl]
            ret
    .nextState:
        ; Clear counter, increment state
        xor a
        ld [hl+], a
        inc [hl]
        ret
; end state

.case_1: ; Wait while extended
    ; Increment counter
    inc [hl]
    ld a, [hl]
    cp $08
        jr z, .nextState
    ret
; end state

.case_2: ; Retract
    ; Increment counter
    inc [hl]
    ld a, [hl]
    cp $20
        jr z, .nextState
    ; Animate
    call enemy_flipVertical.twoFrame
    ; Retract based on direction in header
    ld hl, hEnemy.xPos
    ldh a, [hEnemy.attr]
    bit B_OAM_XFLIP, a
    jr z, .else_B
        inc [hl]
        ret
    .else_B:
        dec [hl]
        ret
; end state

.case_3: ; Wait while retracted
    ; Increment counter
    inc [hl]
    ld a, [hl]
    cp $08
        ret nz
    ; Clear counter
    xor a
    ld [hl+], a
    ; Back to state 0
    ld [hl], a
ret
;}

;------------------------------------------------------------------------------
; Autrack AI (laser turret)
enAI_autrack: ;{ 02:6145
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_AUTRACK_FLIPPED ; $1E ; Check to change the flipped version to refer to the proper sprite
    jr nz, .endIf_A
        ld [hl], SPRITE_AUTRACK_1 ; $41
    .endIf_A:
    
    ; Check if this object is actually the laser
    ldh a, [hEnemy.spawnFlag]
    cp $06
        jr z, .laser ; Laser AI

    ld hl, hEnemy.spriteType
    ldh a, [hEnemy.directionFlags]
    bit 1, a
    jr nz, .else_B
        ld a, [hl]
        cp SPRITE_AUTRACK_3 ; $43
            jr z, .fireLaser
        inc [hl]
        ret
    .else_B:
        ld a, [hl]
        cp SPRITE_AUTRACK_1 ; $41
            jr z, .action
        dec [hl]
        ret
; end proc

.fireLaser:
    ; Only act every 16 frames
    ldh a, [hEnemy_frameCounter]
    and $0f
        ret nz

    ; set HL to enemy's slot
    call loadEnemy_getFirstEmptySlot_longJump
    ; Set enemy to active
    xor a
    ld [hl+], a
    ; Set y position
    ldh a, [hEnemy.yPos]
    sub $14
    ld [hl+], a
    ; Adjust spawn location of laser depending on direction facing
    ldh a, [hEnemy.attr]
    ld b, a
    bit B_OAM_XFLIP, a
    jr nz, .else_C
        ldh a, [hEnemy.xPos]
        sub $08
        jr .endIf_C
    .else_C:
        ldh a, [hEnemy.xPos]
        add $08
    .endIf_C:
    ld [hl+], a
    ; Set sprite ID
    ld a, SPRITE_AUTRACK_LASER ; $45
    ld [hl+], a
    
    ld a, $00
    ld [hl+], a
    ; Set attributes
    ld a, b
    ld [hl+], a
    ; Load data from header
    ld de, .laserHeader
    ld a, $06
    ld [enemy_tempSpawnFlag], a
    call enemy_spawnObject.shortHeader
    
    ; Animate cannon
    ld a, SPRITE_AUTRACK_4 ; $44
    ldh [hEnemy.spriteType], a
    ; Request sound effect
    ld a, sfx_noise_autrackLaser
    ld [sfxRequest_noise], a

.action:
    ; Only act every 16 frames
    ldh a, [hEnemy_frameCounter]
    and $0f
        ret nz

    ; Flip a flag
    ld hl, hEnemy.directionFlags
    ld a, [hl]
    xor $0a
    ld [hl], a
    cp $08
        ret nz

    ; Request sound effect
    ld a, sfx_noise_autrackRises
    ld [sfxRequest_noise], a
ret

.laser: ; Laser AI
    ld hl, hEnemy.xPos
    ldh a, [hEnemy.attr]
    bit B_OAM_XFLIP, a
    jr nz, .moveLeft
    ; move left
        ld a, [hl]
        sub $05
        ld [hl], a
        ret
    .moveLeft:
        ld a, [hl]
        add $05
        ld [hl], a
        ret
; end proc

; Enemy header for laser
.laserHeader: ; 02:61D1
    db $00, $00, $00, $00, $00, $00, $fe, $00
    dw enAI_autrack
;}

;------------------------------------------------------------------------------
; hornoad/autotoad/ramulken AI (enemy 14h)
; various hoppers
enAI_hopper: ;{ 02:61DB
    ld bc, hEnemy.yPos
    ; Check state
    ; Note: Initial state is 2 thanks to the enemy header
    ldh a, [hEnemy.state]
    dec a
        jr z, .case_pastApex ; if state = 1
    dec a
        jp z, .case_faceSamus  ; if state = 2
    ldh a, [hEnemy.counter]
    cp $10
        jr nz, .case_jumpUp
    ; Fall-through case
    ; Clear animation counter
    xor a
    ldh [hEnemy.counter], a
    ; Set state to 1
    inc a
    ldh [hEnemy.state], a
    ; Decrement sprite ID
    ld hl, hEnemy.spriteType
    dec [hl]
ret

.case_jumpUp: ; Handles upward movement of the jump
    ; DE = [hEnemy.counter]
    ld e, a
    ld d, $00
    ld hl, .jumpYSpeedTable
    add hl, de
    ld a, [bc] ; BC is the y position
    sub [hl]   ; subtraction is upwards movement
    ld [bc], a ; save the yPos

    ; Handle x movement
    inc c ; BC now refers to the x position
    ld hl, .jumpXSpeedTable
    add hl, de
    ldh a, [hEnemy.attr]
    and a
    jr z, .else_A
        ; move right
        ld a, [bc]
        add [hl]
        jr .endIf_A
    .else_A:
        ; move left
        ld a, [bc]
        sub [hl]
    .endIf_A:
    ld [bc], a ; save the xPos

    ; Increment animation counter
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    ; Animate on the 5th frame of the jump
    cp $05
        ret nz
    ld hl, hEnemy.spriteType
    inc [hl]
    ld a, [hl]
    ; Play jumping SFX if a certain enemy type during a certain frame
    cp SPRITE_AUTOAD_2 ; $47
        ret nz
    ld a, sfx_noise_autoadJump
    ld [sfxRequest_noise], a
ret

.case_pastApex: ; Handles downward movement in general
    ldh a, [hEnemy.counter]
    cp $10
    jr nz, .moveDown

    call enCollision_down.midMedium
    ld a, [en_bgCollisionResult]
    bit 1, a
    jr nz, .prepNextJump

    ; Force downward movement to be ySpeedTable[0]
    ld a, $0f
    ldh [hEnemy.counter], a
    ld bc, hEnemy.yPos
jr .moveDown

.prepNextJump:
    ; Clear animation counter and state
    xor a
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    ; Increment jump counter
    ld hl, hEnemy.generalVar
    inc [hl]
    ld a, [hl]
    cp $03
        ret nz
    ; Every 4 jumps, reset jump counter and flip around
    ld [hl], $00
    call enemy_flipHorizontal.now
ret

.moveDown: ; Handle downward half of jumping arc
    ; yPos = yPos + ySpeedTable[$0F-[hEnemy.counter]]
    ;  Function iterates through the speed table backwards
    ld e, a
    ld a, $0f
    sub e
    ld e, a
    ld d, $00
    ld hl, .jumpYSpeedTable
    add hl, de
    ld a, [bc]
    add [hl]
    ld [bc], a

    push de
    call enCollision_down.midMedium ; BG collision function
    pop de
    ld a, [en_bgCollisionResult]
    bit 1, a ; Exit if we've hit ground (don't move forward)
        jr nz, .prepNextJump

    ; Handle X movemnt
    ld bc, hEnemy.xPos
    ld hl, .jumpXSpeedTable
    add hl, de
    ldh a, [hEnemy.attr]
    and a
    jr z, .else_B
        ;move right
        ld a, [bc]
        add [hl]
        jr .endIf_B
    .else_B:
        ; move left
        ld a, [bc]
        sub [hl]
    .endIf_B:
    ld [bc], a ; save the xPos

    ; inc the animation counter
    ld hl, hEnemy.counter
    inc [hl]
ret

; Only used if you approach it from the right side, so it ends up facing you
.case_faceSamus:
    ldh a, [hEnemy.xPos]
    cp $c8
    jr nc, .endIf_C
        call enemy_flipHorizontal.now
    .endIf_C:
    ; Clear state
    xor a
    ldh [hEnemy.state], a
ret

; 02:6294 - jump arc? y velocity?
.jumpYSpeedTable:
    db $04, $03, $04, $03, $03, $02, $03, $02, $02, $02, $01, $01, $01, $01, $00, $00
; 02:62A4 - jump arc? x velocity?
.jumpXSpeedTable:
    db $00, $01, $01, $01, $01, $01, $02, $01, $01, $01, $01, $01, $01, $01, $01, $01
;}

;------------------------------------------------------------------------------
; Wallfire AI (bird mask on wall that shoots you)
enAI_wallfire: ;{ 02:62B4
    ; Set the opposite facing ones to the right direction
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_WALLFIRE_FLIPPED ; $1F
    jr nz, .endIf_A
        ld [hl], SPRITE_WALLFIRE_1 ; $4A
    .endIf_A:
    ; Check if a projectile
    call enemy_getSamusCollisionResults
    ldh a, [hEnemy.spawnFlag]
    cp $06
        jr z, .projectileCode
    ; Exit if destroyed
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_WALLFIRE_DEAD ; $4C
        ret z
    ; Check if damaged
    ld a, [enemy_weaponType]
    cp $20 ; Touch
        jr nc, .normalAction
    ; Become destroyed
    ld a, SPRITE_WALLFIRE_DEAD ; $4C
    ld [hl], a
    ld a, $ff
    ld [sfxRequest_square1], a
    ld a, sfx_noise_enemyKilled
    ld [sfxRequest_noise], a
ret

.normalAction:
    ld a, [hl]
    cp $4b ; Check if mouth is open
        jr z, .closeMouth
    ; Wait until timer reaches $50 before spitting fire
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $50
        ret nz
    ; Reset timer
    ld [hl], $00
; Spawn projectile
    ; Get base address of new enemy
    call loadEnemy_getFirstEmptySlot_longJump
    ; Set status
    xor a
    ld [hl+], a
    ; Set y position
    ldh a, [hEnemy.yPos]
    sub $04
    ld [hl+], a
    ; Set x position depending on facing direction
    ldh a, [hEnemy.attr]
    ld b, a
    bit B_OAM_XFLIP, a
    jr nz, .else_B
        ldh a, [hEnemy.xPos]
        add $08
        jr .endIf_B
    .else_B:
        ldh a, [hEnemy.xPos]
        sub $08
    .endIf_B:
    ld [hl+], a
    ; Set sprite type
    ld a, SPRITE_WALLFIRE_SHOT_1 ; $4D
    ld [hl+], a
    ; Set base sprite attributes
    ld a, $00
    ld [hl+], a
    ; Set sprite attributes
    ld a, b
    ld [hl+], a
    ld de, .fireballHeader
    ; Set spawn flag in indicate projectile status
    ld a, $06
    ld [enemy_tempSpawnFlag], a
    ; Spawn
    call enemy_spawnObject.shortHeader
    ; Open mouth
    ld a, SPRITE_WALLFIRE_2 ; $4B
    ldh [hEnemy.spriteType], a
    ld a, sfx_noise_enemyProjectileFired
    ld [sfxRequest_noise], a
ret

.closeMouth: ; Open mouth
    ; Wait 8 frames before closing mouth
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $08
        ret nz
    ; Reset timer
    ld [hl], $00
    ld a, SPRITE_WALLFIRE_1 ; $4A ; Close mouth
    ldh [hEnemy.spriteType], a
ret

.projectileCode:
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_WALLFIRE_SHOT_3 ; $4F ; Check in an explosion sprite type
        jr nc, .explode
    ; Animate
    call enemy_flipSpriteId_2Bits.twoFrame
    
    ld hl, hEnemy.xPos
    ; Check direction
    ldh a, [hEnemy.attr]
    bit B_OAM_XFLIP, a
    jr nz, .else_C
        ; Move right
        ld a, [hl]
        add $04
        ld [hl], a
        ; Check collision
        call enCollision_right.nearSmall
        ld a, [en_bgCollisionResult]
        bit 0, a
            ret z
    .startExploding: ; Explode if collision is made
        ; Set sprite type and make noise
        ld a, SPRITE_WALLFIRE_SHOT_3 ; $4F
        ldh [hEnemy.spriteType], a
        ld a, sfx_noise_enemyExplosion
        ld [sfxRequest_noise], a
        ret
    .else_C:
        ; Move left
        ld a, [hl]
        sub $04
        ld [hl], a
        ; Check collision
        call enCollision_left.nearSmall
        ld a, [en_bgCollisionResult]
        bit 2, a
            ret z
        jr .startExploding

.explode:
    ; Check if at end of explosion animation or not
    cp SPRITE_WALLFIRE_SHOT_4 ; $50
    jr z, .else_D
        ; Increment sprite type
        inc [hl]
        ret
    .else_D:
        ; Delete self
        call enemy_deleteSelf_farCall
        ld a, $ff
        ldh [hEnemy.spawnFlag], a
        ret

.fireballHeader:
    db $00, $00, $00, $00, $00, $00, $fe, $01
    dw enAI_wallfire
;}

;------------------------------------------------------------------------------
; Gunzoo AI (floating robot with gun's)
enAI_gunzoo: ;{ 02:638C
    ldh a, [hEnemy.spawnFlag]
    cp $06
        jp z, .projectileCode

; Note about the directional values used here in [hEnemy.directionFlags]
;  0 (b:00) - Right
;  1 (b:01) - Down
;  2 (b:10) - Left
;  3 (b:11) - Up
; Essentially, bit 0 controls the axis while bit 1 controls whether it goes
;  forward or backwards on the given axis.
    ldh a, [hEnemy.directionFlags]
    bit 0, a ; Horizontal case
        jp z, .horizontalCase

; Vertical case
    ; Animate
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_GUNZOO_1 ; $51
        call nz, .resetSpriteType

    ; Check state (number of shots fired, for this case)
    ldh a, [hEnemy.state]
    dec a ; State 1 - Fire a shot based on the global timer, and move
        jr z, .shootHorizontalRegular ; State 1
    dec a ; State 2 - Just move
        jr z, .moveVertical ; State 2
; State 0 - Shoot at random, and move
    ; Shoot at random
    ld a, [rDIV]
    and $1f
        jr z, .shootHorizontalRandom
    jr .moveVertical

.moveVertical:
    ld de, hEnemy.yPos
    ld hl, hEnemy.counter
    ; Check direction
    ldh a, [hEnemy.directionFlags]
    bit 1, a
        jr nz, .moveUp
; moveDown
    ; Increment and check counter
    inc [hl]
    ld a, [hl]
    cp $20
        jr z, .flipVerticalDirection
    ; Move down
    ld a, [de]
    add $02
    ld [de], a
ret

    ; Common spaghetti between the up and down branches
    .checkIfSwitchToHorizontal:
        ; Don't switch to horizontal unless the random and regular shot have been fired
        ldh a, [hEnemy.state]
        cp $02
            jr z, .switchToHorizontal
    .flipVerticalDirection:
        ld hl, hEnemy.directionFlags
        ld a, [hl]
        xor $02
        ld [hl], a
    ret

.moveUp:
    dec [hl]
        jr z, .checkIfSwitchToHorizontal
    ld a, [de]
    sub $02
    ld [de], a
ret
; end main vertical movement logic

; Shoot from the upper cannon
.shootHorizontalRandom:
    call loadEnemy_getFirstEmptySlot_longJump
    ; Set status
    xor a
    ld [hl+], a
    ; Set y pos
    ldh a, [hEnemy.yPos]
    sub $08
    ld [hl+], a
    ; Set x pos
    ldh a, [hEnemy.xPos]
    sub $10
    ld [hl+], a
    ; Set spawn flag (to let it know it's a projectile)
    ld a, $06
    ld [enemy_tempSpawnFlag], a
    ; Load header
    ld de, .upperCannonShotHeader
    call enemy_spawnObject.longHeader
    
    ; Animate (upper cannon fired)
    ld hl, hEnemy.spriteType
    inc [hl]
    ; Increment state
    ld hl, hEnemy.state
    inc [hl]
    ; Make noise
    ld a, sfx_noise_enemyProjectileFired
    ld [sfxRequest_noise], a
ret

; Shoot from the lower cannon
.shootHorizontalRegular:
    ; Wait to shoot
    ldh a, [hEnemy_frameCounter]
    and $1f
        jr nz, .moveVertical
    
    call loadEnemy_getFirstEmptySlot_longJump
    ; Set status
    xor a
    ld [hl+], a
    ; Set y pos
    ldh a, [hEnemy.yPos]
    ld [hl+], a
    ; Set x pos
    ldh a, [hEnemy.xPos]
    sub $10
    ld [hl+], a
    ; Set spawn flag (to let it know it's a projectile)
    ld a, $06
    ld [enemy_tempSpawnFlag], a
    ; Load header
    ld de, .lowerCannonShotHeader
    call enemy_spawnObject.longHeader

    ; Animate (lower cannon fired)
    ld a, SPRITE_GUNZOO_3 ; $53
    ldh [hEnemy.spriteType], a
    ; Increment state
    ld hl, hEnemy.state
    inc [hl]
    ; Make noise
    ld a, sfx_noise_enemyProjectileFired
    ld [sfxRequest_noise], a
ret

.switchToHorizontal:
    ; Reset sprite type
    ld a, SPRITE_GUNZOO_1 ; $51
    ldh [hEnemy.spriteType], a
    ; Set movement direction to right
    xor a
    ldh [hEnemy.directionFlags], a
    ; Clear movement counter
    ldh [hEnemy.counter], a
    ; Clear shot counter
    ldh [hEnemy.state], a
    ret
; end of everything relating to the vertical case

.horizontalCase:
    ; Randomly shoot diagonally if we haven't shot diagonally before
    ldh a, [hEnemy.state]
    and a
    jr nz, .endIf_A
        ld a, [rDIV]
        and $1f
        jr z, .shootDiagonal ; Shoot diagonal
    .endIf_A:

    ld de, hEnemy.xPos
    ld hl, hEnemy.counter
    ; Check direction
    ldh a, [hEnemy.directionFlags]
    bit 1, a
        jr nz, .moveLeft

; moveRight
    ; Increment and check timer
    inc [hl]
    ld a, [hl]
    cp $20
        jr z, .flipHorizontalDirection
    ; Move right
    ld a, [de]
    add $02
    ld [de], a
ret

    ; Common spaghetti between the left and right branches
    .checkIfSwitchToVertical:
        ldh a, [hEnemy.state]
        and a ; Only switch to vertical if at least one diagonal shot has been fired
        jr nz, .switchToVertical
    .flipHorizontalDirection: ; Switch between left and right
            ld hl, hEnemy.directionFlags
            ld a, [hl]
            xor $02
            ld [hl], a
            ret
        .switchToVertical: ; Switch to moving down
            ; Clear movement counter
            xor a
            ldh [hEnemy.counter], a
            ; Clear shot fired flag
            ldh [hEnemy.state], a
            ; Set direction to down
            ld a, $01
            ldh [hEnemy.directionFlags], a
            ret

.moveLeft:
    ; Decrement and check timer
    dec [hl]
        jr z, .checkIfSwitchToVertical
    ; Move left
    ld a, [de]
    sub $02
    ld [de], a
ret
; end horizontal case logic

.shootDiagonal:
    call loadEnemy_getFirstEmptySlot_longJump
    ; Set initial status
    xor a
    ld [hl+], a
    ; Set y pos
    ldh a, [hEnemy.yPos]
    add $08
    ld [hl+], a
    ; Set x pos
    ldh a, [hEnemy.xPos]
    sub $08
    ld [hl+], a
    ; Set spawn flag (to let it know it's a projectile)
    ld a, $06
    ld [enemy_tempSpawnFlag], a
    ; Load header
    ld de, .diagonalShotHeader
    call enemy_spawnObject.longHeader

    ; Set flag to indicate a diagonal shot has been fired
    ld a, $01
    ldh [hEnemy.state], a
    ld a, sfx_noise_enemyProjectileFired
    ld [sfxRequest_noise], a
ret

; Projectile code
.projectileCode:
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_GUNZOO_HSHOT_1 ; $57 ; Sprite $57+ (left)
        jr nc, .horizontalShot
; Diagonal projectile
    sub SPRITE_GUNZOO_DIAGSHOT_2 ; $55 ; Sprite $55
        jr z, .diagonalShotExplosion
    dec a ; Sprite $56 (SPRITE_GUNZOO_DIAGSHOT_3)
        jr z, .projectileDelete

; Sprite $54 (SPRITE_GUNZOO_DIAGSHOT_1)
    ; Move down
    ld hl, hEnemy.yPos
    ld a, [hl]
    add $02
    ld [hl+], a
    ; Move left
    ld a, [hl]
    sub $02
    ld [hl], a
    call enCollision_down.nearSmall
    ld a, [en_bgCollisionResult]
    bit 1, a
        ret z
    ; Set sprite type
    ld a, SPRITE_GUNZOO_DIAGSHOT_2 ; $55
    ldh [hEnemy.spriteType], a
    ; Move up
    ld hl, hEnemy.yPos
    ld a, [hl]
    sub $04
    ld [hl], a
    ; Noise
    ld a, sfx_noise_enemyExplosion
    ld [sfxRequest_noise], a
ret

.diagonalShotExplosion:
    ; Increment sprite type
    ld [hl], SPRITE_GUNZOO_DIAGSHOT_3 ; $56
    ; Move up
    ld hl, hEnemy.yPos
    ld a, [hl]
    sub $08
    ld [hl], a
ret

.projectileDelete:
    call enemy_deleteSelf_farCall
    ld a, $ff
    ldh [hEnemy.spawnFlag], a
ret

.horizontalShot:
    ; Check if at end of explosion
    cp SPRITE_GUNZOO_HSHOT_5 ; $5B
        jr z, .projectileDelete
    cp SPRITE_GUNZOO_HSHOT_3 ; $59
    jr nc, .else_B
        ; Move left
        ld hl, hEnemy.xPos
        ld a, [hl]
        sub $03
        ld [hl], a
        ; Test collision
        call enCollision_left.nearSmall
        ld a, [en_bgCollisionResult]
        bit 2, a
            ret z
        ; Change sprite to explosion
        ld a, SPRITE_GUNZOO_HSHOT_3 ; $59
        ldh [hEnemy.spriteType], a
        ; Make noise
        ld a, sfx_noise_enemyExplosion
        ld [sfxRequest_noise], a
        ret
    .else_B:
        ; Animate explosion
        inc [hl]
        ret

; Enemy Headers
.upperCannonShotHeader: ; 02:6511 - Horizontal from upper cannon (random)
    db SPRITE_GUNZOO_HSHOT_1 ; $57
    db $00, $00, $00, $00, $00, $00, $00, $00, $fe, $01
    dw enAI_gunzoo
.lowerCannonShotHeader: ; 02:651E - Horizontal from lower cannon (regular)
    db SPRITE_GUNZOO_HSHOT_1 ; $57
    db $00, $00, $00, $00, $00, $00, $00, $00, $fe, $02
    dw enAI_gunzoo
.diagonalShotHeader: ; 92:651E - Diagonal
    db SPRITE_GUNZOO_DIAGSHOT_1 ; $54
    db $00, $00, $00, $00, $00, $00, $00, $00, $fe, $03
    dw enAI_gunzoo

.resetSpriteType:
    ldh a, [hEnemy_frameCounter]
    and $07
        ret nz
    ld [hl], SPRITE_GUNZOO_1 ; $51
ret
;}

;------------------------------------------------------------------------------
; Autom AI (robot that shoots a flamethrower downwards)
enAI_autom: ;{ 02:6540
    ; Don't do anything while shooting stuff
    ldh a, [hEnemy.spawnFlag]
    cp $03
        ret z
    and $0f
        jr z, .projectileCode
    ; Randomly shoot
    ld a, [rDIV]
    and $1f
        jr z, .useFlamethrower

    ; Animate
    ld a, SPRITE_AUTOM_1 ; $5C ; Sprite with light off
    ldh [hEnemy.spriteType], a
    ; Prep variables
    ld de, hEnemy.xPos
    ld hl, hEnemy.counter
    ; Check direction
    ldh a, [hEnemy.state]
    and a
    jr nz, .else_A
        ; Increment timer
        inc [hl]
        ld a, [hl]
        cp $20
            jr z, .flipDirection
        ; Move right
        ld a, [de]
        add $03
        ld [de], a
        ret
        
.flipDirection:
        ld hl, hEnemy.state
        ld a, [hl]
        xor $01
        ld [hl], a
        ret
    
    .else_A:
        ; Decrement timer
        dec [hl]
            jr z, .flipDirection
        ; Move left
        ld a, [de]
        sub $03
        ld [de], a
        ret
; end state

.useFlamethrower: ; A fan wiki says its a flamethrower
    call loadEnemy_getFirstEmptySlot_longJump
    ; Set enemy slot to active
    xor a
    ld [hl+], a
    ; Set position
    ldh a, [hEnemy.yPos]
    add $10
    ld [hl+], a
    ldh a, [hEnemy.xPos]
    inc a
    ld [hl+], a
    ; Load header
    call enemy_createLinkForChildObject
    ld de, .flamethrowerHeader
    call enemy_spawnObject.longHeader
    ; Animate
    ld hl, hEnemy.spriteType
    ld [hl], SPRITE_AUTOM_2 ; $5D ; Sprite with light on
    ; Stay inactive while projectile is onscreen
    ld a, $03
    ldh [hEnemy.spawnFlag], a
ret

.projectileCode:
    ld a, sfx_square2_automFlamethrower
    ld [sfxRequest_square2], a
    ; Check sprite type
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_AUTOM_SHOT_3 ; $60
    jr z, .else_B
    jr nc, .else_C
        ; Increment sprite type
        inc [hl]
        ; Move down
        ld hl, hEnemy.yPos
        ld a, [hl]
        add $08
        ld [hl], a
        ret

    .else_B:
        ; Increment sprite type
        inc [hl]
        ret
        
    .else_C:
        ; Animate
        call enemy_flipSpriteId_2Bits.fourFrame
        ; Increment and check timer
        ld hl, hEnemy.counter
        inc [hl]
        ld a, [hl]
        cp $20
            ret nz
        ; Delete self
        call enemy_deleteSelf_farCall
        ld a, $ff
        ldh [hEnemy.spawnFlag], a
        ret
; end proc

.flamethrowerHeader:
    db SPRITE_AUTOM_SHOT_1 ; $5E
    db $00, $00, $00, $00, $00, $00, $00, $00, $ff, $00
    dw enAI_autom
;}

;------------------------------------------------------------------------------
; Proboscum AI (nose on wall that is acts as a platform)
enAI_proboscum: ;{ 02:65D5
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_PROBOSCUM_FLIPPED ; $6E ; Check to make sure the flipped version has the correct sprite
    jr nz, .endIf
        ld [hl], SPRITE_PROBOSCUM_1 ; $72
    .endIf:

    ; State graph is a simple 0->1->2->3->0 loop, but with a clever trick that makes states 0 and 2 use the same code
    ldh a, [hEnemy.state]
    dec a ; State 1
        jr z, .case_1 ; Diagonal nose waiting to go down
    dec a ; State 2
        jr z, .case_2 ; Lowered nose waiting to go up
    dec a ; State 3
        jr z, .case_3 ; Diagonal nose waiting to go up
    ; Case 0 - Raised nose waiting to go down

.case_2: ; Both states 0 and 2 here are "waiting to become diagonal"
    ; Wait for 64 frames
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $40 ; Long wait
        ret nz

    ; Reset counter
    ld [hl], $00
    ld a, SPRITE_PROBOSCUM_2 ; $73 ; Nose half-extended
    ldh [hEnemy.spriteType], a
    ; state becomes 1 or 3, depending on if we fell-through to here or not
    ld hl, hEnemy.state
    inc [hl]
ret

.case_1: ; Diagonal nose waiting to go down
    ; Wait for two frames
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $02
        ret nz

    ; Reset counter
    ld [hl], $00
    ; Change sprite
    ld a, SPRITE_PROBOSCUM_3 ; $74 ; Nose down
    ldh [hEnemy.spriteType], a
    ; state = 2
    ld a, $02
    ldh [hEnemy.state], a
ret

.case_3: ; Diagonal nose waiting to go up
    ; Wait for two frames
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $02
        ret nz

    ; Reset counter
    ld [hl], $00
    ; Change sprite
    ld a, SPRITE_PROBOSCUM_1 ; $72 ; Nose forward
    ldh [hEnemy.spriteType], a
    ; state = 0 (fall-through to 2)
    xor a
    ldh [hEnemy.state], a
ret
;}

;------------------------------------------------------------------------------
; Missile block AI
enAI_missileBlock: ;{ 02:6622
    call enemy_getSamusCollisionResults
    ; Check state
    ld hl, hEnemy.state
    ld a, [hl]
    dec a
        jr z, .case_rising ; state 1
    dec a
        jr z, .case_falling ; state 2
    dec a
        jp z, .case_exploding ; state 3

; Case 0 (default state)
    ; Exit if not hit by a projectile
    ld a, [enemy_weaponType]
    cp $20
        ret nc
    ld b, a
    ; Play plink sound
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
    ; Exit if not hit by a missile
    ld a, b
    cp $08
        ret nz

    ; Clear plink sound
    ld a, $ff
    ld [sfxRequest_square1], a
    ; Play missile hit sound
    ld a, sfx_noise_missileDamage
    ld [sfxRequest_noise], a
    ; Check direction block was hit from
    ld a, [enemy_weaponDir]
    bit 0, a
    jr nz, .endIf_A
        ; Set directional flag
        ld a, $02
        ldh [hEnemy.directionFlags], a
    .endIf_A:

    ; Next state
    ld a, $01
    ldh [hEnemy.state], a
    ; Set double speed flag for the curved movement routine
    ld a, $01
    ldh [hEnemy.generalVar], a
; continue to case_1

.case_rising: ; State 1
    ; Check movement counter used by the call below
    ldh a, [hEnemy.counter]
    cp $0a
        jr z, .prepCase_2

    call enAI_halzyn.moveVertical ; Y movement
    ; Check direction hit from
    ldh a, [hEnemy.directionFlags]
    and a
    ; X movement
    jr z, .else_B
        call enAI_halzyn.moveLeft
        jr .endIf_B
    .else_B:
        call enAI_halzyn.moveRight
    .endIf_B:
; continue to common exit

.common_exit:
    call .animate
    ; Check BG collision
    call enCollision_down.midMedium
    ld a, [en_bgCollisionResult]
    bit 1, a
        ret z
    ; Set state to exploding
    ld a, $03
    ldh [hEnemy.state], a
    ; Set sprite to explosion
    ld a, SPRITE_SCREW_EXPLOSION_START ; $E2
    ldh [hEnemy.spriteType], a
ret

.prepCase_2:
    ; Reset counter
    xor a
    ldh [hEnemy.counter], a
    ; Set state
    ld a, $02
    ldh [hEnemy.state], a
; continue to case 2

.case_falling: ; State 2
    ; Move block down
    ld hl, hEnemy.yPos
    ld a, [hl]
    add $04
    ld [hl], a
    call enemy_accelForwards ; Downwards
    ; Move block horizontally
    inc l ; HL is now x position
    ld b, $01
    ldh a, [hEnemy.directionFlags]
    and a
    jr z, .else_C
        ; Move left
        ld a, [hl]
        sub b
        ld [hl], a
        jr .common_exit
    .else_C:
        ; Move right
        ld a, [hl]
        add b
        ld [hl], a
        jr .common_exit
; end branch

.case_exploding: ; State 3
    ; Animate from $E2 to $E7
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_SCREW_EXPLOSION_END ; $E7
        jr z, .deleteSelf
    inc [hl]
ret

.deleteSelf:
    call enemy_deleteSelf_farCall ; Delete self
    ; Delete self for good
    ld a, $02
    ldh [hEnemy.spawnFlag], a
ret

; Animate missile block by flipping around
; [hEnemy.directionFlags] determines if it is "clockwise" or "counter-clockwise"
;  (since the sprites aren't actually rotating, CW/CCW are technically inaccurate terms)
.animate: ; 03:66C0
    ; Animate every 4 frames
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    ; Load HL
    ld hl, hEnemy.attr
    ; Check which direction the block is spinning
    ldh a, [hEnemy.directionFlags]
    and a
        jr nz, .animate_ccw

;animate_cw
    ld a, [hl]
    and a
        jr z, .setYFlip
    cp OAM_XFLIP
        jr z, .setNoFlip
    cp OAM_YFLIP
        jr z, .setXYFlip
    ; continue to .setXFlip

.setXFlip:
    ld [hl], OAM_XFLIP
    ret
.setNoFlip:
    ld [hl], $00
    ret
.setYFlip:
    ld [hl], OAM_YFLIP
    ret
.setXYFlip:
    ld [hl], OAM_XFLIP | OAM_YFLIP
    ret

.animate_ccw:
    ld a, [hl]
    and a
        jr z, .setXFlip
    cp OAM_XFLIP
        jr z, .setXYFlip
    cp OAM_YFLIP
        jr z, .setNoFlip
    jr .setYFlip
;} end proc

;------------------------------------------------------------------------------
; Moto AI (the animal with a face-plate)
enAI_moto: ;{ 02:66F3
    call .animate
    ; Act every other frame
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    ; Handle movement
    ld hl, hEnemy.xPos
    ld b, $02 ; Speed
    ; Check direction
    ldh a, [hEnemy.directionFlags]
    and $0f
    jr z, .moveRight

; Move left
    ld a, [hl]
    sub b
    ld [hl], a

.checkFront:
    ; Check floor below (don't run off a cliff)
    call enCollision_down.onePoint
    ld a, [en_bgCollisionResult]
    bit 1, a
        ret nz
    ; Flip enemy (visually)
    ld hl, hEnemy.attr
    ld a, [hl]
    xor OAM_XFLIP
    ld [hl], a
    ; Flip enemy (logically)
    ld hl, hEnemy.directionFlags
    ld a, [hl]
    xor %00110010 ; Upper nybble flips directional shield, lower nybble flips logical direction
    ld [hl], a
ret

.moveRight:
    ld a, [hl]
    add b
    ld [hl], a
    jr .checkFront
; end proc

.animate:
    ; Animate every other frame
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    ; Skip ahead if not sprite $68
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_MOTO_2 ; $68
    jr nz, .endIf
        ; Inc/Dec depending on this flag
        ldh a, [hEnemy.counter]
        and a
        jr z, .else
            inc [hl]
            ret
        .else:
            dec [hl]
            ret
    .endIf:

    ; Reset sprite type
    ld [hl], SPRITE_MOTO_2 ; $68
    ; Switch between incrementing/decrementing the sprite type
    ld hl, hEnemy.counter
    ld a, [hl]
    xor $01
    ld [hl], a
ret
;}

;------------------------------------------------------------------------------
; Halzyn (flying enemy with sheilds on the sides)
;  Shares subroutines with the missile block, of all things
enAI_halzyn: ;{ 02:6746
    call enemy_flipHorizontal.fourFrame ; Animate
    call .moveVertical ; Y Movment
    ; Check direction of movement
    ldh a, [hEnemy.directionFlags]
    and $0f
    jr z, .else_A
        call .moveLeft ; X Movement
        ; Check collision
        call enCollision_left.farMedium
        ld a, [en_bgCollisionResult]
        bit 2, a
            ret z
        ; Turn around
        ld hl, hEnemy.directionFlags
        ld a, [hl]
        and $f0 ; Preserve directional vulnerabilities
        ld [hl], a
            ret
    .else_A:
        call .moveRight ; X Movement
        ; Check collision
        call enCollision_right.farMedium
        ld a, [en_bgCollisionResult]
        bit 0, a
            ret z
        ; Turn around
        ld hl, hEnemy.directionFlags
        ld a, [hl]
        and $f0 ; Preserve directional vulnerabilities
        add $02
        ld [hl], a
            ret
; end proc

; Psuedo-Sinusoidal motion routines (shared with missile block!!)
;  Vertical movement
.moveVertical: ; 02:677C
    ; BC = yPos
    ld bc, hEnemy.yPos
    ; Note: Incrementing [hEnemy.counter] is handled by using one of the accompanying horizontal functions
    ld hl, hEnemy.counter
    ld a, [hl]
    cp $0a
    jr nz, .endIf_B
        ; Reset table index
        ld [hl], $00
        ; Cycle through movement states
        ld hl, hEnemy.state
        ld a, [hl]
        cp $03
        jr z, .else_C
            inc [hl]
            jr .endIf_B
        .else_C:
            ld [hl], $00
            ; Toggle speed between normal and double
            ld hl, hEnemy.generalVar
            ld a, [hl]
            xor $01
            ld [hl], a
    .endIf_B:

    ; Use [hEnemy.counter] as the index
    ldh a, [hEnemy.counter]
    ld e, a
    ld d, $00
    ldh a, [hEnemy.state]
    dec a
        jr z, .vertState1 ; State 1
    dec a
        jr z, .vertState2 ; State 2
    dec a
        jr z, .vertState3 ; State 3
    ; State 0 (default)

    ; .vertState0
        ld hl, .concaveSpeedTable
        jr .moveBack
    .vertState1:
        ld hl, .convexSpeedTable
        jr .moveAhead
    .vertState2:
        ld hl, .concaveSpeedTable
        jr .moveAhead
    .vertState3:
        ld hl, .convexSpeedTable
        ; jr .moveBack (implicit)

; HL = table
; DE = index into table
; BC = position
; [hEnemy.generalVar] = Double speed flag
.moveBack: ; Move back
    add hl, de
    ldh a, [hEnemy.generalVar] ; Load double speed flag
    ld d, a
    ld a, [bc]
    sub [hl]
    bit 0, d
        jr z, .exit
    ; Double speed
    sub [hl]

.exit: ; Save result
    ld [bc], a
ret

.moveAhead: ; Move ahead
    add hl, de
    ldh a, [hEnemy.generalVar] ; Load double speed flag
    ld d, a
    ld a, [bc]
    add [hl]
    bit 0, d
        jr z, .exit
    ; Double speed
    add [hl]
    ld [bc], a
ret

; Leftward movement
; Called by multiple enemies (Missile block and Halzyn)
.moveLeft: ; 02:67D9
    ld bc, hEnemy.xPos
    ; Use [hEnemy.counter] as an index
    ld hl, hEnemy.counter
    ld a, [hl]
    ld e, a
    ld d, $00
    ; Increment table index
    inc [hl]
    ldh a, [hEnemy.state]
    dec a
        jr z, .leftState1 ; State 1
    dec a
        jr z, .leftState2 ; State 2
    dec a
        jr z, .leftState3 ; State 3
    ; State 0 (default)

    ; .leftState0
        ld hl, .convexSpeedTable
        jr .moveBack
    .leftState1:
        ld hl, .concaveSpeedTable
        jr .moveBack
    .leftState2:
        ld hl, .convexSpeedTable
        jr .moveBack
    .leftState3:
        ld hl, .concaveSpeedTable
        jr .moveBack

; Rightward movement
; Called by multiple enemies (Missile block and Halzyn)
.moveRight: ; 02:6803
    ld bc, hEnemy.xPos
    ; Use $E9 as an index
    ld hl, hEnemy.counter
    ld a, [hl]
    ld e, a
    ld d, $00
    ; Increment table index
    inc [hl]
    ldh a, [hEnemy.state]
    dec a
        jr z, .rightState1 ; State 1
    dec a
        jr z, .rightState2 ; State 2
    dec a
        jr z, .rightState3 ; State 3
    ; State 0 (default)

    ; .rightState0
        ld hl, .convexSpeedTable
        jr .moveAhead
    .rightState1:
        ld hl, .concaveSpeedTable
        jr .moveAhead
    .rightState2:
        ld hl, .convexSpeedTable
        jr .moveAhead
    .rightState3:
        ld hl, .concaveSpeedTable
        jr .moveAhead

; Curve that is slightly slowing down
.concaveSpeedTable: ; 02:682D
    db $01, $01, $01, $01, $01, $01, $01, $00, $01, $00
; Curve that is slightly speeding up
.convexSpeedTable: ; 02:6837
    db $00, $01, $00, $01, $01, $01, $01, $01, $01, $01
;}

;------------------------------------------------------------------------------
; Septogg AI (floating platforms)
;  Uses $E9 and $EA as a 16-bit distance-travelled counter
enAI_septogg: ;{ 02:6841
    call enemy_flipSpriteId_2Bits.twoFrame
    call enemy_getSamusCollisionResults ; Get sprite collision results
    ; Check if shot
    ld a, [enemy_weaponType]
    cp $20
        jr nz, .goBackUp
    
    ld a, [samus_onSolidSprite]
    and a
        jr z, .goBackUp

    ; Test if going down is okay
    ld b, $03
    ld hl, hEnemy.yPos
    ld a, [hl]
    add b
    ld [hl], a
    call enCollision_down.farMedium
    ld a, [en_bgCollisionResult]
    bit 1, a
    jr z, .else
        ; Hit floor. Stay in place
        ld a, [enemy_yPosMirror]
        ldh [hEnemy.yPos], a
        ret
    .else:
        ; Go down
        ld b, $03 ; Speed
        ; Add distance travelled to counter
        ld hl, hEnemy.counter
        ld a, [hl]
        add b
        ld [hl+], a
        ld a, [hl]
        adc $00
        ld [hl], a
        ; Move Samus down (on-screen y-pos)
        ld hl, samus_onscreenYPos
        ld a, [hl]
        add b
        ld [hl], a
        ; Move Samus down (real position)
        ld hl, hSamusYPixel
        ld a, [hl]
        add b
        ld [hl+], a
            ret nc
        ; Don't forget about the y screen coordinate
        inc [hl]
        ret
; end proc

.goBackUp: ; Move back up if distance counter is non-zero
    ; Check low byte of counter
    ld hl, hEnemy.counter
    ld a, [hl]
    and a
    jr nz, .then
        ; Check high byte of counter
        inc l
        ld a, [hl]
        and a
            ret z
    .then:
        ; Move back up
        ld hl, hEnemy.yPos
        dec [hl]
        ; Move back up
        ; Adjust low byte
        ld hl, hEnemy.counter
        dec [hl]
        ld a, [hl]
        inc a
            ret nz
        ; Adjust high byte
        inc l
        dec [hl]
        ret
;} end proc

;------------------------------------------------------------------------------
; Flitt AI (weird platforms) (vanishing type)
enAI_flittVanishing: ;{ 02:68A0
    ld de, hEnemy.spriteType ; This line doesn't appear to get used
    ; State graph is a simple loop of 0 -> 1 -> 2 -> 3 -> 0...
    ld hl, hEnemy.state
    ld a, [hl]
    dec a ; Case 1
        jr z, .case_1 ; Wait to disappear
    dec a ; Case 2
        jr z, .case_2 ; Wait to reappear (mouth closed)
    dec a
        jr z, .case_3 ; Wait to open mouth wide

; Case 0 (default) - Wait to close mouth
    ; Check timer
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $38 ; Long wait
        ret nz
    ld [hl], $00 ; Reset timer
    ; Animate
    ld a, $01
    ldh [hEnemy.state], a
    ld a, SPRITE_FLITT_2 ; $D1 ; Close mouth
    ldh [hEnemy.spriteType], a
ret

.case_1: ; Wait to disappear
    ; Check timer
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $0e
        ret nz
    ld [hl], $00 ; Reset timer
    ; Disappear
    ld a, $02
    ldh [hEnemy.state], a
    ld a, SPRITE_FLITT_INVISIBLE ; $FD ; Disappear (no graphics)
    ldh [hEnemy.spriteType], a
ret
; Funny note: Sprite $FD uses the same hitbox as the Queen's body, so it's absolutely huge (nearly 50x50 pixels)
;  However, you'd only notice if you brought the Screw Attack into its room, because it makes noise on contact for some reason.

.case_2: ; Wait to reappear (with mouth closed)
    ; Check timer
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $0c
        ret nz
    ld [hl], $00 ; Reset timer
    ; Reappear
    ld a, $03
    ldh [hEnemy.state], a
    ld a, SPRITE_FLITT_2 ; $D1 ; Closed mouth
    ldh [hEnemy.spriteType], a
ret

.case_3: ; Wait to open mouth wide
    ; Check timer
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $0d
        ret nz
    ld [hl], $00 ; Reset timer
    ; Animate
    ld a, $00
    ldh [hEnemy.state], a
    ld a, SPRITE_FLITT_1 ; $D0 ; Open mouth
    ldh [hEnemy.spriteType], a
ret
;}

;------------------------------------------------------------------------------
; Flitt AI (weird platforms) (moving type)
enAI_flittMoving: ;{ 02:68FC
    call enemy_flipSpriteId.fourFrame
    call enemy_getSamusCollisionResults ; Get collision results
    ; Check logical direction
    ldh a, [hEnemy.directionFlags]
    and a
    jr nz, .else_A
        ; Moving right
        ld hl, hEnemy.counter
        inc [hl]
        ld a, [hl]
        cp $60
        jr z, .else_B
            ; Move right
            ld hl, hEnemy.xPos
            inc [hl]
            ; Check if Samus is touching and standing on sprite
            ld a, [enemy_weaponType]
            cp $20
                ret nz
            ld a, [samus_onSolidSprite]
            and a
                ret z
            ; Move camera and such right
            ld hl, samus_onscreenXPos
            inc [hl]
            ld hl, camera_speedRight
            inc [hl]
            ; Move Samus right
            ld hl, hSamusXPixel
            inc [hl]
                ret nz
            inc l
            inc [hl]
            ret
        .else_B:
            ; Flip direction
            ld a, $02
            ldh [hEnemy.directionFlags], a
            
    .else_A:
        ; Moving left
        ld hl, hEnemy.counter
        dec [hl]
        jr z, .else_C
            ; Move left
            ld hl, hEnemy.xPos
            dec [hl]
            ; Check if Samus is touching and standing on sprite
            ld a, [enemy_weaponType]
            cp $20
                ret nz
            ld a, [samus_onSolidSprite]
            and a
                ret z
            ; Move camera left
            ld hl, samus_onscreenXPos
            dec [hl]
            ld hl, camera_speedLeft
            inc [hl]
            ; Move Samus left
            ld hl, hSamusXPixel
            dec [hl]
            ld a, [hl]
            cp $ff
                ret nz
            inc l
            dec [hl]
            ret
        .else_C:
            ; Flip direction
            xor a
            ldh [hEnemy.directionFlags], a
            ret
; end proc
;}

;------------------------------------------------------------------------------
; Gravitt AI (crawler with a hat that pops out of the ground)
enAI_gravitt: ;{ 02:695F
    ld hl, hEnemy.state
    ld a, [hl]
    dec a
        jr z, .unburrow ; State 1
    dec a
        jr z, .crawl ; State 2 - Crawl in one direction
    dec a
        jr z, .crawl ; State 3 - And then crawl in the opposite
    dec a
        jr z, .burrow ; State 4
    dec a
        jp z, .wait ; State 5

; Default state
    ; Don't act if Samus isn't within range
    ; abs(samus_xpos - enemy_xpos) < $38
    ; Uses B to mark which direction Samus approaches from
    ld hl, hEnemy.xPos
    ld b, $00 ; Samus is to the left
    ld a, [samus_onscreenXPos]
    sub [hl]
    jr nc, .endIf_A
        cpl
        inc a
        inc b ; Samus is to the right
    .endIf_A:
    cp $38
        ret nc
    ; Animate
    ld hl, hEnemy.spriteType
    inc [hl]
    ; Peek up a bit
    ld hl, hEnemy.yPos
    dec [hl]
    dec [hl]
    ; Next state
    ld a, $01
    ldh [hEnemy.state], a
    ; Set movement direction (bit 1 of direction flags)
    ld a, b
    and a
    jr nz, .else_B
        ; movement will be to the right
        ld a, %10000000 ;$80
        ldh [hEnemy.directionFlags], a
        ret
    .else_B:
        ; movement will be to the left
        ld a, %10000010 ;$82
        ldh [hEnemy.directionFlags], a
        ret
; end state

.unburrow: ; State 1
    ; Increment timer
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $06
    jr z, .else_C
        ; Peek up
        ld hl, hEnemy.yPos
        dec [hl]
        dec [hl]
        ret
    .else_C:
        ; Clear timer
        xor a
        ld [hl+], a
        ; Next state
        ld a, $02
        ldh [hEnemy.state], a
        ret
; end state

.crawl: ; States 2 and 3
    call .animate
    ; Check and increment timer
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $18
    jr z, .else_D
        ; Move
        ld hl, hEnemy.xPos
        ldh a, [hEnemy.directionFlags]
        bit 1, a ; Check direction
        jr z, .else_E
            ; Move left
            dec [hl]
            dec [hl]
            ret
        .else_E:
            ; Move right
            inc [hl]
            inc [hl]
            ret
    .else_D:
        ;  Clear timer
        ld [hl], $00
        ; Reverse heading
        ld hl, hEnemy.directionFlags
        ld a, [hl]
        xor $02
        ld [hl], a
        ; Increment state
        ld hl, hEnemy.state
        inc [hl]
        ret
; end state

.burrow: ; State 4
    ; Check and increment timer
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $07
    jr z, .else_F
        ; Move down
        ld hl, hEnemy.yPos
        inc [hl]
        inc [hl]
        ret
    .else_F:
        ; Clear timer
        xor a
        ld [hl+], a
        ; Next state
        ld a, $05
        ldh [hEnemy.state], a
        ; Animate
        ld a, SPRITE_GRAVITT_1 ; $D3
        ldh [hEnemy.spriteType], a
        ret
; end state

.wait: ; State 5
    ; Increment and check timer
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $30
        ret nz
    ; Clear timer
    xor a
    ld [hl+], a
    ; Clear state
    ld [hl], a
ret

.animate:
    ; Animate every other frame
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    ; $D4 -> $D5 -> $D6 -> $D7 animation loop
    ld hl, hEnemy.spriteType
    inc [hl]
    ld a, [hl]
    cp SPRITE_GRAVITT_5 + 1 ; $D8
        ret nz
    ld [hl], $d4
ret
;}

;------------------------------------------------------------------------------
; Missile Door
enAI_missileDoor: ;{ 02:6A14
    ; Load results of collision tests with this object
    call enemy_getSamusCollisionResults
    ; If not the door sprite, jump ahead
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_MISSILE_DOOR ; $F8
        jr nz, .exploding

    ; Exit if not hit with a projectile
    ld a, [enemy_weaponType]
    cp $20
        ret nc

    ld b, a
    ; Play sound (plink)
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
    ; Exit if not hit by missile
    ld a, b
    cp $08
        ret nz

    ; Clear plink sound
    ld a, $ff
    ld [sfxRequest_square1], a
    ; Play missile sound
    ld a, sfx_noise_missileDamage
    ld [sfxRequest_noise], a
    ; Change palette for a few frames
    ld a, $13
    ldh [hEnemy.stunCounter], a
    ; Increment hit counter
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    ; Exit if not hit with 5 missiles
    cp $05
        ret nz

    ; Clear hit counter and palette effect
    xor a
    ld [hl], a
    ldh [hEnemy.stunCounter], a
    ; Change sprite ID to explosion
    ld a, SPRITE_SCREW_EXPLOSION_START ; $E2
    ldh [hEnemy.spriteType], a
    ; Play sound effect
    ld a, sfx_square1_missileDoorExploding
    ld [sfxRequest_square1], a
    
    ; Check which direction the door was hit from, to adjust the position of the explosion
    ld a, [enemy_weaponDir]
    bit 1, a
        jr nz, .rightSide

;.leftSide:
    ; Adjust position so the explosion is on the left
    ld hl, hEnemy.xPos
    ld a, [hl]
    sub $18
    ld [hl], a
ret

.exploding:
    ; Animate the explosion (sprites $E2 thru $E7)
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_SCREW_EXPLOSION_END ; $E7
        jr z, .deleteDoor
    inc [hl]
ret

.rightSide:
    ; Adjust position so the explosion is on the right
    ld hl, hEnemy.xPos
    ld a, [hl]
    add $18
    ld [hl], a
ret

.deleteDoor:
    call enemy_deleteSelf_farCall ; Delete self
    ; Set enemy spawn flag to dead
    ld a, $02
    ldh [hEnemy.spawnFlag], a
ret ;}

; Called by multiple enemies
; Used to move enemies "forwards" (right or down) in an accelerating fashion
; Takes HL as an argument/return
enemy_accelForwards: ;{ 02:6A7B
    push bc
    push de
        push hl
            ; Load value from [hEnemy.generalVar], perform bounds check, and increment
            ld bc, hEnemy.generalVar
            ld a, [bc]
            cp $17
            jr z, .endIf
                inc a
                ld [bc], a
            .endIf:
            ; Load value from table
            ld e, a
            ld d, $00
            ld hl, .speedTable
            add hl, de
            ld a, [hl]
        pop hl
        ; Add value of table to [hl]
        add [hl]
        ld [hl], a
    pop de
    pop bc
ret

.speedTable: ; 02:6A96 - First entry is unused
    db $00, $00, $01, $00, $01, $00, $01, $01, $02, $01, $02, $01, $02, $02, $03, $02
    db $03, $03, $04, $03, $04, $04, $03, $04
;}

; Called by multiple enemies
; Used to move enemies "forwards" (right or down) in an accelerating fashion
; Takes HL as an argument/return
enemy_accelBackwards: ;{ 02:6AAE
    push bc
    push de
        push hl
            ; Load value from [hEnemy.generalVar], perform bounds check, and increment
            ld bc, hEnemy.generalVar
            ld a, [bc]
            cp $17
            jr z, .endIf
                inc a
                ld [bc], a
            .endIf:
            ; Load value from table
            ld e, a
            ld d, $00
            ld hl, .speedTable
            add hl, de
            ld a, [hl]
        pop hl
        ; Add value of table to [hl]
        add [hl]
        ld [hl], a
    pop de
    pop bc
ret

.speedTable: ; 02:6AC9 First entry is unused
    db $00, $00, $ff, $00, $ff, $00, $ff, $ff, $fe, $ff, $fe, $ff, $fe, $fe, $fd, $fe
    db $fd, $fd, $fc, $fd, $fc, $fc, $fd, $fc
;}

; Unused (?) but similar to the above routines
; Takes HL as an argument/return
; Seems unnecessarily complex with the separate positive/negative cases
unknownProc_6AE1: ;{ 02:6AE1
    push bc
    push de
        push hl
            ; Load value from [hEnemy.generalVar], perform bounds check, and increment
            ld bc, hEnemy.generalVar
            ld a, [bc]
            cp $17
            jr z, .endIf_A
                inc a
                ld [bc], a
            .endIf_A:
            ; Check if value in table is negative
            ld e, a
            ld d, $00
            ld hl, .unknownTable
            add hl, de
            bit 7, [hl]
            jr z, .else_B
                ; If it was negative, take the two's compliment to make it positive
                ld a, [hl]
                cpl
                inc a
                ld b, a
                
                pop hl
                ; And then subtract the value from the popped HL
                ld a, [hl]
                sub b
                jr .endIf_B
            .else_B:
                ; If it was non-negative, then add the value from the table to the popped HL
                ld a, [hl]
                pop hl
                add [hl]
            .endIf_B:
        ; HL has been popped by this point
    ld [hl], a
    pop de
    pop bc
ret

.unknownTable: ; 02:6B09
    db $00, $FE, $FE, $FE, $FF, $FE, $FE, $FF, $FF, $FE, $FF, $FF, $FF, $00, $FF, $FF
    db $00, $FF, $00, $00, $FF, $00, $00, $00
;}

; When used in conjunction with a child-object spawner routine,
;  this makes a child object point to its parent
enemy_createLinkForChildObject: ;{ 02:6B21
    ldh a, [hEnemyWramAddrHigh]
    cp $c6
    jr nz, .else
        ldh a, [hEnemyWramAddrLow]
        jr .endIf
    .else:
        ldh a, [hEnemyWramAddrLow]
        add $10
    .endIf:

    ld [enemy_tempSpawnFlag], a
ret
;}

;------------------------------------------------------------------------------
; Flip sprite ID (low bit)
enemy_flipSpriteId: ;{ Procedure has 3 entry points
    .twoFrame: ; 02:6B33 - Once every 2 frames
        ldh a, [hEnemy_frameCounter]
        and $01
            ret nz
        jr .now
    .fourFrame: ; 02:6B3A - Once every 4 frames
        ldh a, [hEnemy_frameCounter]
        and $03
            ret nz
.now: ; 02:6B3F - Immediately
    ld hl, hEnemy.spriteType
    ld a, [hl]
    xor %00000001 ;$01
    ld [hl], a
ret
;}

;------------------------------------------------------------------------------
; Flip sprite ID (lowest two bits)
enemy_flipSpriteId_2Bits: ;{ Procedure has 3 entry points
    .fourFrame: ; 02:6B47
        ldh a, [hEnemy_frameCounter]
        and $03
            ret nz
        jr .now
    .twoFrame: ; 02:6B47
        ldh a, [hEnemy_frameCounter]
        and $01
            ret nz
.now: ; 02:6B53 - Never called directly
    ld hl, hEnemy.spriteType
    ld a, [hl]
    xor %00000011 ;$03
    ld [hl], a
ret
;}

;------------------------------------------------------------------------------
; Flip sprite horizontally
enemy_flipHorizontal: ;{ Procedure has 3 entry points
    .twoFrame: ; 02:6B5B
        ldh a, [hEnemy_frameCounter]
        and $01
            ret nz
        jr enemy_flipHorizontal.now
    .fourFrame: ; 02:6B5B
        ldh a, [hEnemy_frameCounter]
        and $03
            ret nz
.now: ; 02:6B62
    ld hl, hEnemy.attr
    ld a, [hl]
    xor OAM_XFLIP
    ld [hl], a
ret
;}

;------------------------------------------------------------------------------
; Flip sprite vertically
enemy_flipVertical: ;{ Procedure has 3 entry points
    .twoFrame: ; 02:6B6F
        ldh a, [hEnemy_frameCounter]
        and $01
            ret nz
        jr .now
    .fourFrame: ; 02:6B76 - Never called
        ldh a, [hEnemy_frameCounter]
        and $03
            ret nz
.now: ; 02:6B7B - Never called directly
    ld hl, hEnemy.attr
    ld a, [hl]
    xor OAM_YFLIP
    ld [hl], a
ret
;}

;------------------------------------------------------------------------------
; Metroid stinger event
enAI_metroidStinger: ;{ 02:6B83
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $8a
    jr z, .else
        ; Only do this stuff on the first frame
        dec a
            ret nz
        ; Increment displayed metroid count
        ld hl, metroidCountDisplayed
        ld a, [hl]
        add $08
        daa
        ld [hl], a
        ; Shuffle metroid timer
        ld a, $ca
        ld [metroidCountShuffleTimer], a
        ; Play metroid hive song with intro
        ld a, $1f
        ld [songRequest], a
        ; Freeze Samus
        ld a, $01
        ld [cutsceneActive], a
        ret
    .else:
        ; Delete self
        call enemy_deleteSelf_farCall
        ld a, $02
        ldh [hEnemy.spawnFlag], a
        ; Unfreeze Samus
        xor a
        ld [cutsceneActive], a
        ret
;}

;------------------------------------------------------------------------------
; Hatching Alpha Metroid AI
enAI_hatchingAlpha: ;{ 02:6BB2
;Jump_002_6bb2:
    call enemy_getSamusCollisionResults
    ; Check if stunned
    ld hl, alpha_stunCounter
    ld a, [hl]
    and a
    jr z, .endIf_A
        dec [hl]
        jr z, .else_B
            ; Stunned case
            call metroid_missileKnockback ; Knockback
            call enemy_toggleVisibility ; Blink
            ld a, [enemy_weaponType]
            cp $10
                ret nc
            ld a, sfx_square1_beamDink
            ld [sfxRequest_square1], a
            ret
        .else_B:
            ; End stun
            xor a
            ldh [hEnemy.status], a
            ld a, $ff
            ldh [hEnemy.directionFlags], a
            ld a, SPRITE_ALPHA_1 ; $A3 ; Alpha metroid
            ldh [hEnemy.spriteType], a
    .endIf_A:
    ; State 2 = fight is happening
    ld a, [metroid_state]
    cp $02
        jp z, enAI_alphaMetroid.checkIfHurt
    ld b, a
    ; Jump to quickIntro if we've already seen this Metroid
    ldh a, [hEnemy.spawnFlag]
    cp $04
        jr z, enAI_alphaMetroid.checkIfInRange
    ld c, a
; Fancy intro
    ; State 1 = start fight
    ld a, b
    cp $01
        jp z, enAI_alphaMetroid.startFight
    ; Check if in screen-facing pose
    ldh a, [hEnemy.spriteType]
    cp SPRITE_ALPHA_FACE ; $A1 ; Metroid hatching
        jp z, enAI_alphaMetroid.appearanceRise

    ld a, [cutsceneActive]
    and a
    jr nz, .else_C
        ldh a, [hEnemy_frameCounter]
        and $03
            ret nz
        ; Flash sprite
        ldh a, [hEnemy.stunCounter]
        xor $10
        ldh [hEnemy.stunCounter], a
        ; Check if Samus is in range
        ld hl, hEnemy.xPos
        ld a, [samus_onscreenXPos]
        sub [hl]
        jr nc, .endIf_D
            cpl
            inc a
        .endIf_D:
        cp $50
            ret nc
        ; Activate fight
        ld a, $01
        ld [cutsceneActive], a
        ld a, $01
        ld [metroid_fightActive], a
        ; Trigger Metroid fight music
        ld a, [songPlaying]
        cp $0c
            ret z
        ld a, $0c
        ld [songRequest], a
        ret
    .else_C:
        ; Cutscene is active
        ; Continue every 4th frame
        ldh a, [hEnemy_frameCounter]
        and $03
            ret nz
        ; Wait a few frames before facing the screen
        ld hl, hEnemy.counter
        inc [hl]
        ld a, [hl]
        cp $08
            jp z, enAI_alphaMetroid.appearanceFaceScreen
        ; Flash sprite in the meantime
        ldh a, [hEnemy.stunCounter]
        xor $10
        ldh [hEnemy.stunCounter], a
        ret
; end proc
;}

;------------------------------------------------------------------------------
; Alpha Metroid AI
enAI_alphaMetroid: ;{ 02:6C44
    ld a, [metroid_fightActive]
    and a
        jp nz, enAI_hatchingAlpha ; Jump to actual AI is here, for some reason
    ; Check for before it attacks
    ld a, $04
    ldh [hEnemy.spawnFlag], a
.checkIfInRange: ; Jump from hatchingAlpha
    ld a, SPRITE_ALPHA_1 ; $A3 ; Alpha metroid
    ldh [hEnemy.spriteType], a
    ; Check if samus is within $50 pixels
    ld hl, hEnemy.xPos
    ld a, [samus_onscreenXPos]
    sub [hl]
    jr nc, .endIf_A
        cpl
        inc a
    .endIf_A:
    cp $50
        ret nc
    ; Start fight
    xor a
    ld [alpha_stunCounter], a
    ld a, $01
    ld [metroid_fightActive], a
    ld a, $02
    ld [metroid_state], a
    ld a, [songPlaying]
    cp $0c
        jr z, .standardAction
    ; Trigger Metroid fight music
    ld a, $0c
    ld [songRequest], a
jr .standardAction

.checkIfHurt: ; Shot reactions
    ld a, [enemy_weaponType]
    cp $20 ; Not shot
        jp nc, .standardAction
    cp $10
        jr z, .screwReaction
    cp $08
        jr z, .hurtReaction
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
ret

.standardAction:
; Check if knockback direction not $FF
    ldh a, [hEnemy.directionFlags]
    inc a
    jr z, .endIf_B
        call metroid_screwKnockback ; Screw attack knockback?
        ld hl, metroid_screwKnockbackDone
        ld a, [hl]
        and a
            ret z
        ld [hl], $00
        ld a, $ff
        ldh [hEnemy.directionFlags], a
        ld a, SPRITE_ALPHA_1 ; $A3
        ldh [hEnemy.spriteType], a
        xor a
        ldh [hEnemy.counter], a
        ldh [hEnemy.state], a
        ret
    .endIf_B:

; $E9 is used as a counter between lunges
    ld hl, hEnemy.counter
    ld a, [hl]
    and a
    jr nz, .endIf_C
        ; Get direction of next lunge
        call alpha_getAngle_farCall
        ; Face Samus
        ld hl, hEnemy.xPos
        ld a, [hl]
        add $10
        ld b, a
        ld a, [samus_onscreenXPos]
        sub b
        jr c, .else_D
            ld a, OAM_XFLIP
            ldh [hEnemy.attr], a
            jr .endIf_C
        .else_D:
            xor a
            ldh [hEnemy.attr], a
    .endIf_C:

; Lunge for a few frames, pause for a few, then restart
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $0e
    jr c, .endIf_E
        cp $14
            ret nz
        ld [hl], $00
    .endIf_E:

    call alpha_getSpeedVector_farCall ; Translate angle to velocity vector
    call .lungeMovement ; Move
    call .animate ; Animate
ret

.screwReaction:
    call metroid_screwReaction
    ld a, sfx_square1_metroidScrewAttacked
    ld [sfxRequest_square1], a
ret

.hurtReaction:
    ld hl, hEnemy.health
    dec [hl]
    ld a, [hl]
    and a
        jr z, .death
    ld a, $08
    ld [alpha_stunCounter], a
    ld a, sfx_noise_metroidHurt
    ld [sfxRequest_noise], a
    ; Clear directional flag
    ld hl, hEnemy.directionFlags
    ld [hl], $00
    ; Check direction and handle knockback
    ld a, [enemy_weaponDir]
    ld b, a
    bit 0, b ; Right
        jr nz, .case_setKnockbackRight
    bit 3, b ; Down
        jr nz, .case_setKnockbackDown
    bit 1, b ; Left
        jr nz, .case_setKnockbackLeft

; Vertical cases
    ;case_setKnockbackUp:
        ldh a, [hEnemy.yPos]
        sub $05
        cp $10
        jr c, .knockback_randHorizontal
            ldh [hEnemy.yPos], a
            set 3, [hl]
            jr .knockback_randHorizontal
    .case_setKnockbackDown:
        set 1, [hl]
        ldh a, [hEnemy.yPos]
        add $05
        ldh [hEnemy.yPos], a
.knockback_randHorizontal:
    ld a, [rDIV]
    and $01
    jr z, .else_F
        set 0, [hl] ; Right
        ret
    .else_F:
        set 2, [hl] ; Left
        ret

; Horizontal cases
    .case_setKnockbackRight:
        set 0, [hl]
        ldh a, [hEnemy.xPos]
        add $05
        ldh [hEnemy.xPos], a
        jr .knockback_randVertical
    .case_setKnockbackLeft:
        ldh a, [hEnemy.xPos]
        sub $05
        cp $08
        jr c, .knockback_randVertical
            ldh [hEnemy.xPos], a
            set 2, [hl]
            jr .knockback_randVertical
.knockback_randVertical:
    ld a, [rDIV]
    and $01
    jr z, .else_G
        set 1, [hl] ; Down
        ret
    .else_G:
        set 3, [hl] ; Up
        ret
; end branch

.death:
    xor a
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    ld a, $80
    ld [metroid_state], a
    ; Explode
    ld a, SPRITE_SCREW_EXPLOSION_START ; $E2
    ldh [hEnemy.spriteType], a
    ld a, sfx_noise_metroidKilled
    ld [sfxRequest_noise], a
    ; Play metroid killed jingle
    ld a, $0f
    ld [songRequest], a

    ld a, $02
    ld [metroid_fightActive], a
    ldh [hEnemy.spawnFlag], a
    ; Adjust Metroid counts
    ld hl, metroidCountReal
    ld a, [hl]
    sub $01
    daa
    ld [hl], a
    ld hl, metroidCountDisplayed
    ld a, [hl]
    sub $01
    daa
    ld [hl], a
    ; Metroid counter shuffle effect
    ld a, $c0
    ld [metroidCountShuffleTimer], a
    ; Queue earthquake if necessary
    call earthquakeCheck_farCall
ret

; Appearance related branches
.startFight:
    ld hl, hEnemy.spriteType
    ld [hl], SPRITE_ALPHA_1 ; $A3
    ld a, $04
    ldh [hEnemy.spawnFlag], a
    xor a
    ld [cutsceneActive], a
    ld a, $02
    ld [metroid_state], a
ret

.appearanceFaceScreen:
    ; Clear counter
    xor a
    ld [hl], a
    ldh [hEnemy.stunCounter], a
    ; Screen-facing pose
    ld a, SPRITE_ALPHA_FACE ; $A1
    ldh [hEnemy.spriteType], a
ret

.appearanceRise:
    call enAI_zetaMetroid.oscillateNarrow ; Osciallate horizontally
    ; Continue every 8th frame
    ldh a, [hEnemy_frameCounter]
    and $07
        ret nz
    ; Move up
    ld hl, hEnemy.yPos
    ld a, [hl]
    sub $02
    ld [hl], a
    ; Timer
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $0d
        ret nz
    ; Clear timer
    xor a
    ld [hl], a
    inc a
    ld [metroid_state], a
jr .startFight


; BC should contain the YYXX movement vector
; (each component is in sign-magnitude format)
; Also used by the Gamma Metroid
.lungeMovement: ; 02:6DD4
    push bc
        ld a, b
        and a
        jr z, .endIf_H
            ld hl, hEnemy.yPos
            bit 7, b
            jr z, .else_I
                ; Move up
                res 7, b
                ld a, [hl]
                sub b
                ld [hl], a
                call enCollision_up.farWide
                ld a, [en_bgCollisionResult]
                bit 3, a
                jr z, .endIf_H
                    ld a, [enemy_yPosMirror]
                    ldh [hEnemy.yPos], a
                    jr .endIf_H
            .else_I:
                ; Move down
                ld a, [hl]
                add b
                ld [hl], a
                call enCollision_down.farWide
                ld a, [en_bgCollisionResult]
                bit 1, a
                jr z, .endIf_H
                    ld a, [enemy_yPosMirror]
                    ldh [hEnemy.yPos], a
        .endIf_H:
    pop bc
    
    ld a, c
    and a
        ret z
    ld hl, hEnemy.xPos
    bit 7, c
    jr z, .else_J
        ; Move left
        res 7, c
        ld a, [hl]
        sub c
        ld [hl], a
        call enCollision_left.farWide
        ld a, [en_bgCollisionResult]
        bit 2, a
            ret z
        ld a, [enemy_xPosMirror]
        ldh [hEnemy.xPos], a
        ret
    .else_J:
        ; Move right
        ld a, [hl]
        add c
        ld [hl], a
        call enCollision_right.farWide
        ld a, [en_bgCollisionResult]
        bit 0, a
            ret z
        ld a, [enemy_xPosMirror]
        ldh [hEnemy.xPos], a
        ret
; end proc

.animate: ; 02:6E39
    ld hl, hEnemy.spriteType
    ld a, [hl]
    xor SPRITE_ALPHA_1 ^ SPRITE_ALPHA_2 ; $07
    ld [hl], a
ret
;}

;--------------------------------------
; Common metroid routines

; Determine direction of screw attack knockback
metroid_screwReaction: ;{ 02:6E41
    ; Clear D and E
    ld d, $00
    ld e, d
    ; Get absolute value of Y distance between Samus and metroid
    ; (set direction in E)
    ld hl, hEnemy.yPos
    ld a, [samus_onscreenYPos]
    sub [hl]
    jr nc, .endIf_A
        cpl
        inc a
        inc e
    .endIf_A:
    ; Store difference in B
    ld b, a

    ; Get absolute value of X distance between Samus and metroid
    ; (set direction in D)
    inc l
    ld a, [samus_onscreenXPos]
    sub [hl]
    jr nc, .endIf_B
        cpl
        inc a
        inc d
    .endIf_B:
    ; Store difference in C
    ld c, a

    ; Check if X or Y difference is greater
    cp b
        jr c, .setVertical

    ; Check horizontal direction
    ld a, d
    and a
        jr nz, .setRight
    ld a, $02 ; Left

.exit:
    ldh [hEnemy.directionFlags], a
    xor a
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    call metroid_screwKnockback
ret

.setRight:
    xor a ; Right
    jr .exit

.setVertical:
    ; Check vertical direction
    ld a, e
    and a
    jr nz, .else_C
        ld a, $03 ; Up
        jr .exit
    .else_C:
        ld a, $01 ; Down
        jr .exit
;} end proc


; Screw attack knockback routine
metroid_screwKnockback: ;{ 02:6E7F
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $06
    jr nz, .endIf
        ld a, $01
        ld [metroid_screwKnockbackDone], a
        ret
    .endIf:

    ld hl, hEnemy.xPos
    ldh a, [hEnemy.directionFlags]
    ; Horizontal cases
    and a ; Case 0
        jr z, .moveRight
    cp $02 ; Case 2
        jr z, .moveLeft
    dec l ; yPos
    ; Vertical cases
    dec a ; Case 1
        jr z, .moveDown
    ; Case 3 - moveUp

; Move up
    ld a, [hl]
    sub $05
    cp $10
        ret c
    ld [hl], a
    call enCollision_up.farWide
    ld a, [en_bgCollisionResult]
    bit 3, a
        ret z
    ld a, [enemy_yPosMirror]
    ldh [hEnemy.yPos], a
ret

.moveLeft:
    ld a, [hl]
    sub $05
    cp $10
        ret c
    ld [hl], a
    call enCollision_left.farWide
    ld a, [en_bgCollisionResult]
    bit 2, a
        ret z
    ld a, [enemy_xPosMirror]
    ldh [hEnemy.xPos], a
ret

.moveRight:
    ld a, [hl]
    add $05
    ld [hl], a
    call enCollision_right.farWide
    ld a, [en_bgCollisionResult]
    bit 0, a
        ret z
    ld a, [enemy_xPosMirror]
    ldh [hEnemy.xPos], a
ret

.moveDown:
    ld a, [hl]
    add $05
    ld [hl], a
    call enCollision_down.farWide
    ld a, [en_bgCollisionResult]
    bit 1, a
        ret z
    ld a, [enemy_yPosMirror]
    ldh [hEnemy.yPos], a
ret
; end proc


; Alpha/Gamma missile knockback
metroid_missileKnockback: ; 02:6EF0
    ; Vertical movement
    ld hl, hEnemy.yPos
    ldh a, [hEnemy.directionFlags]
    bit 1, a
    jr nz, .else_A
        bit 3, a
        jr z, .endIf_A
            ; Move up
            call .moveBack
            call enCollision_up.farWide
            ld a, [en_bgCollisionResult]
            bit 3, a
            jr z, .endIf_A
                ld a, [enemy_yPosMirror]
                ldh [hEnemy.yPos], a
                jr .endIf_A
    .else_A:
        ; Move down
        call .moveForwards
        call enCollision_down.farWide
        ld a, [en_bgCollisionResult]
        bit 1, a
        jr z, .endIf_A
            ld a, [enemy_yPosMirror]
            ldh [hEnemy.yPos], a
    .endIf_A:

    ; Horizontal movement
    ld hl, hEnemy.xPos
    ldh a, [hEnemy.directionFlags]
    bit 0, a
    jr nz, .else_B
        bit 2, a
            ret z
        ; Move left
        call .moveBack
        call enCollision_left.farWide
        ld a, [en_bgCollisionResult]
        bit 2, a
            ret z
        ld a, [enemy_xPosMirror]
        ldh [hEnemy.xPos], a
        ret
    .else_B:
        ; Move right
        call .moveForwards
        call enCollision_right.farWide
        ld a, [en_bgCollisionResult]
        bit 0, a
            ret z
        ld a, [enemy_xPosMirror]
        ldh [hEnemy.xPos], a
        ret
; end proc

; Subroutines to the above
.moveBack: ; Back
    ld a, [hl]
    sub $04
    cp $10
        ret c
    ld [hl], a
ret

.moveForwards: ; Forwards
    ld a, [hl]
    add $04
    ld [hl], a
ret
;}

;------------------------------------------------------------------------------
; Gamma Metroid AI
enAI_gammaMetroid: ;{ 02:6F60
    call enemy_getSamusCollisionResults
    ld hl, gamma_stunCounter
    ld a, [hl]
    and a
        jr z, .checkIfActing
    dec [hl]
        jr z, .stunEnd
    ; Stunned case
    call metroid_missileKnockback ; Knockback
    call enemy_toggleVisibility ; Blink
    ; When stunned, only process screw attack collision
    ld a, [enemy_weaponType]
    cp $10
        ret nc
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
ret

.despawn: ; Delete self (don't save it)
    call enemy_deleteSelf_farCall
    ld a, $ff
    ldh [hEnemy.spawnFlag], a
ret

.stunEnd:
    ld a, $ff
    ldh [hEnemy.directionFlags], a
    xor a
    ldh [hEnemy.status], a
.checkIfActing:
    ; Act if fight is happening
    ld a, [metroid_state]
    and a
        jp nz, .checkIfHurt

    ldh a, [hEnemy.spawnFlag]
    cp $04 ; Check if we've already seen this one
        jr z, .quickIntro ; Quick entrance
    and $0f ; Check if killed (?)
        jr z, .despawn ; Despawn self

    ; Fancy entrance
    ld a, [cutsceneActive]
    and a
    jr nz, .endIf_A
        ; Check if Samus is in range
        ld hl, hEnemy.xPos
        ld a, [samus_onscreenXPos]
        sub [hl]
        jr nc, .endIf_B
            cpl
            inc a
        .endIf_B:
        cp $50
            ret nc
    
        ld a, $01
        ld [cutsceneActive], a
        ; Trigger Metroid fight music
        ld a, $0c
        ld [songRequest], a
        ld a, $01
        ld [metroid_fightActive], a
    .endIf_A:
    
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $10
        jp z, .longIntroEnd
    ldh a, [hEnemy.spriteType]
    xor SPRITE_ALPHA_1 ^ SPRITE_GAMMA_1 ; $0E -- Switch between Alpha and Gamma sprites
    ldh [hEnemy.spriteType], a
ret

.quickIntro:
    ; Load proper Gamma sprite
    ld a, SPRITE_GAMMA_1 ; $AD
    ldh [hEnemy.spriteType], a
    ; Check if Samus is in range
    ld hl, hEnemy.xPos
    ld a, [samus_onscreenXPos]
    sub [hl]
    jr nc, .endIf_C
        cpl
        inc a
    .endIf_C:
    cp $50
        ret nc

    xor a
    ld [gamma_stunCounter], a
    inc a
    ld [metroid_state], a
    ld a, $01
    ld [metroid_fightActive], a
    ; Trigger Metroid fight music
    ld a, [songPlaying]
    cp $0c
        ret z
    ld a, $0c
    ld [songRequest], a
ret

.longIntroEnd:
    ; Clear [hEnemy.counter]
    xor a
    ld [hl], a
    ; Load proper Gamma sprite
    ld a, SPRITE_GAMMA_1 ; $AD
    ldh [hEnemy.spriteType], a
    xor a
    ld [cutsceneActive], a
    inc a
    ld [metroid_state], a
    ; Set spawn flag to "seen"
    ld a, $04
    ldh [hEnemy.spawnFlag], a
ret


.checkIfHurt:
    ldh a, [hEnemy.spawnFlag]
    cp $05
        ret z
    ; Check if a Gamma projectile
    and $0f
    jr nz, .else_D
        call .projectileCode
        ld a, [enemy_weaponType]
        cp $10
            ret nc
        ld a, sfx_square1_beamDink
        ld [sfxRequest_square1], a
        ret
    .else_D:
        ld a, [enemy_weaponType]
        cp $20
            jp nc, .standardAction ; Standard action if not hit with projectile
        cp $10
            jr z, .screwReaction
        cp $08
            jr z, .hurtReaction
        ld a, sfx_square1_beamDink
        ld [sfxRequest_square1], a
        ret
; end branch

.screwReaction:
    call metroid_screwReaction
    ld a, sfx_square1_metroidScrewAttacked
    ld [sfxRequest_square1], a
ret

.hurtReaction:
    ld hl, hEnemy.health
    dec [hl]
    ld a, [hl]
    and a
        jp z, .death

    ld a, $08
    ld [gamma_stunCounter], a
    ld a, sfx_noise_metroidHurt
    ld [sfxRequest_noise], a
    ld hl, hEnemy.directionFlags
    ld [hl], $00
    ; Prep knockback based on hit direction
    ld a, [enemy_weaponDir]
    ld b, a
    bit 0, b ; Right
        jr nz, .case_setKnockbackRight
    bit 3, b ; Down
        jr nz, .case_setKnockbackDown
    bit 1, b ; Left
        jr nz, .case_setKnockbackLeft

; Vertical cases
    ;case_setKnockbackUp:
        ldh a, [hEnemy.yPos]
        sub $05
        cp $10
            jr c, .knockback_randHorizontal
        ldh [hEnemy.yPos], a
        call enCollision_up.farWide
        ld a, [en_bgCollisionResult]
        bit 3, a
        jr nz, .knockback_resetYPos
            ld hl, hEnemy.directionFlags
            set 3, [hl]
            jr .knockback_randHorizontal

        .knockback_resetYPos:
            ld a, [enemy_yPosMirror]
            ldh [hEnemy.yPos], a
            ld hl, hEnemy.directionFlags
            jr .knockback_randHorizontal

    .case_setKnockbackDown:
        ldh a, [hEnemy.yPos]
        add $05
        ldh [hEnemy.yPos], a
        call enCollision_down.farWide
        ld a, [en_bgCollisionResult]
        bit 1, a
            jr nz, .knockback_resetYPos
        ld hl, hEnemy.directionFlags
        set 1, [hl]

.knockback_randHorizontal:
    ld a, [rDIV]
    and $01
    jr z, .else_E
        set 0, [hl] ; Right
        ret
    .else_E:
        set 2, [hl] ; Left
        ret

; Horizontal cases
    .case_setKnockbackRight:
        ldh a, [hEnemy.xPos]
        add $05
        ldh [hEnemy.xPos], a
        call enCollision_right.farWide
        ld a, [en_bgCollisionResult]
        bit 0, a
        jr nz, .knockback_resetXPos
            ld hl, hEnemy.directionFlags
            set 0, [hl]
            jr .knockback_randVertical

        .knockback_resetXPos:
            ld a, [enemy_xPosMirror]
            ldh [hEnemy.xPos], a
            ld hl, hEnemy.directionFlags
            jr .knockback_randVertical

    .case_setKnockbackLeft:
        ldh a, [hEnemy.xPos]
        cp $10
            jr c, .knockback_randVertical
        sub $05
        ldh [hEnemy.xPos], a
        call enCollision_left.farWide
        ld a, [en_bgCollisionResult]
        bit 2, a
            jr nz, .knockback_resetXPos
        ld hl, hEnemy.directionFlags
        set 2, [hl]
        jr .knockback_randVertical

.knockback_randVertical:
    ld a, [rDIV]
    and $01
    jr z, .else_F
        set 1, [hl] ; Down
        ret
    .else_F:
        set 3, [hl] ; Up
        ret
; end branch

.death:
    xor a
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    ld a, $80
    ld [metroid_state], a
    ld a, SPRITE_SCREW_EXPLOSION_START ; $E2
    ldh [hEnemy.spriteType], a
    ld a, sfx_noise_metroidKilled
    ld [sfxRequest_noise], a
    ; Play "killed metroid" jingle
    ld a, $0f
    ld [songRequest], a
    ld a, $02
    ld [metroid_fightActive], a
    ldh [hEnemy.spawnFlag], a
    ; Adjust Metroid counts
    ld hl, metroidCountReal
    ld a, [hl]
    sub $01
    daa
    ld [hl], a
    ld hl, metroidCountDisplayed
    ld a, [hl]
    sub $01
    daa
    ld [hl], a
    ; Shuffle counter and check earthquake
    ld a, $c0
    ld [metroidCountShuffleTimer], a
    call earthquakeCheck_farCall
ret

.standardAction:
    ; Check knockback direction
    ldh a, [hEnemy.directionFlags]
    inc a
    jr z, .endIf_G
        call metroid_screwKnockback
        ld hl, metroid_screwKnockbackDone
        ld a, [hl]
        and a
            ret z
        ld [hl], $00
        ld a, $ff
        ldh [hEnemy.directionFlags], a
        xor a
        ldh [hEnemy.counter], a
        ldh [hEnemy.state], a
        inc a
        ld [metroid_state], a
        ld a, SPRITE_GAMMA_1 ; $AD
        ldh [hEnemy.spriteType], a
        ret
    .endIf_G:

    ld hl, hEnemy.counter
    ld a, [hl]
    and a
    jr nz, .endIf_H
        call gamma_getAngle_farCall
        ld hl, hEnemy.xPos
        ld a, [hl]
        add $10
        ld b, a
        ld a, [samus_onscreenXPos]
        sub b
        jr c, .else_I
            ld a, OAM_XFLIP
            ldh [hEnemy.attr], a
            jr .endIf_H
        .else_I:
            xor a
            ldh [hEnemy.attr], a
    .endIf_H:

    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $0f
    jr nc, .else_J
        call gamma_getSpeedVector_farCall
        call enAI_alphaMetroid.lungeMovement
        ld a, SPRITE_GAMMA_2 ; $B0
        ldh [hEnemy.spriteType], a
        ret
    .else_J:
        cp $14
            ret c
        call loadEnemy_getFirstEmptySlot_longJump
        xor a
        ld [hl+], a
        ldh a, [hEnemy.yPos]
        add $0c
        ld [hl+], a
        ldh a, [hEnemy.attr]
        ; Adjust attack xpos based on facing direction
        bit B_OAM_XFLIP, a
        jr nz, .else_K
            ldh a, [hEnemy.xPos]
            sub $08
            jr .endIf_K
        .else_K:
            ldh a, [hEnemy.xPos]
            add $08
        .endIf_K:
    
        ld [hl+], a
        ld a, SPRITE_GAMMA_BOLT_1 ; $AE
        ld [hl+], a
        ld a, $00
        ld [hl+], a
        ldh a, [hEnemy.attr]
        ld [hl+], a
        ld de, .projectileHeader
        call enemy_createLinkForChildObject
        call enemy_spawnObject.shortHeader
        ld a, $05
        ldh [hEnemy.spawnFlag], a
        xor a
        ldh [hEnemy.counter], a
        ld a, sfx_noise_gammaMetroidLightning
        ld [sfxRequest_noise], a
        ret

.projectileHeader: ; 02:71D0
    db $00, $00, $ff, $00, $00, $00, $ff, $07
    dw enAI_gammaMetroid

; Gamma Projectile code
.projectileCode: ; 02:71DA
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_GAMMA_BOLT_1 ; $AE
    jr z, .else_L
        dec [hl]
        ldh a, [hEnemy.attr]
        set B_OAM_YFLIP, a
        ldh [hEnemy.attr], a
        ldh a, [hEnemy.yPos]
        sub $0d
        ldh [hEnemy.yPos], a
        ldh a, [hEnemy.attr]
        bit B_OAM_XFLIP, a
        jr nz, .else_M
            ldh a, [hEnemy.xPos]
            add $04
            ldh [hEnemy.xPos], a
            ret
        .else_M:
            ldh a, [hEnemy.xPos]
            sub $04
            ldh [hEnemy.xPos], a
            ret
    .else_L:
        ldh a, [hEnemy.attr]
        bit B_OAM_YFLIP, a
        jr nz, .else_N
            inc [hl]
            ldh a, [hEnemy.yPos]
            sub $10
            ldh [hEnemy.yPos], a
            ldh a, [hEnemy.attr]
            bit B_OAM_XFLIP, a
            jr nz, .else_O
                ldh a, [hEnemy.xPos]
                sub $04
                ldh [hEnemy.xPos], a
                ret
            .else_O:
                ldh a, [hEnemy.xPos]
                add $04
                ldh [hEnemy.xPos], a
                ret
        .else_N:
            call enemy_deleteSelf_farCall
            ld a, $ff
            ldh [hEnemy.spawnFlag], a
            ret
;}

;------------------------------------------------------------------------------
; Note that the caller function needs to set enemy_tempSpawnFlag
; - $06 is a common value for spawned projectiles
; - If the spawned object should tell the parent it is dead, then
;    the return value of enemy_createLinkForChildObject should be used
enemy_spawnObject: ;{ Procedure has two entry points
    .shortHeader: ; 02:7231
        ld b, $07
        jr .start
    .longHeader: ;02:7235
        ld b, $0a
.start:

    .loadLoop_A:
        ld a, [de]
        ld [hl+], a
        inc de
        dec b
    jr nz, .loadLoop_A
    ; Save max health to C
    ld c, a
    ; Clear 4 bytes (drop type, explosion flag, Y/X screens away)
    xor a
    ld b, $04
    .clearLoop:
        ld [hl+], a
        dec b
    jr nz, .clearLoop
    ; Save max health properly
    ld [hl], c
    
    ; Set spawn flag to provided temp value
    ld a, l
    add $0b
    ld l, a
    ld a, [enemy_tempSpawnFlag]
    ld [hl+], a
    
    ; Load spawn number and AI pointer
    ld b, $03
    .loadLoop_B:
        ld a, [de]
        ld [hl+], a
        inc de
        dec b
    jr nz, .loadLoop_B

    ; Load spawn flag into enemySpawnFlags[spawnNumber]
    dec l
    dec l
    dec l
    ld a, [hl]
    ld hl, enemySpawnFlags
    ld l, a
    ld a, [enemy_tempSpawnFlag]
    ld [hl], a
    ; Increment total number of enemies and number of active enemies
    ld hl, numEnemies.total
    inc [hl]
    inc l
    inc [hl]
ret
;}

; Unused partner function to enemy_createLinkForChildObject
;  enemy_deleteSelf in bank 3 handles this stuff instead
enemy_getAddressOfParentObject: ;{ 02:7269 - Unused
    ld h, HIGH(enemyDataSlots)
    ldh a, [hEnemy.spawnFlag]
    bit 4, a
    jr z, .endIf
        sub $10
        inc h
    .endIf:
    ld l, a
ret
;}

;------------------------------------------------------------------------------
; Zeta Metroid AI
enAI_zetaMetroid: ;{ 02:7276
    call enemy_getSamusCollisionResults
    ldh a, [hEnemy.spawnFlag]
    cp $06
        jp z, .fireball
    ; Force zeta to say onscreen
    ld a, [metroid_state]
    and a
        call nz, metroid_keepOnscreen
    ; Check if not stunned
    ld hl, zeta_stunCounter
    ld a, [hl]
    and a
        jr z, .checkIfActing
    dec [hl]
        jr z, .stunEnd
    ; Stunned case
    call .animateHurt
    ; When stunned, only process screw touch reaction
    ld a, [enemy_weaponType]
    cp $10
        ret nc
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
ret

.stunEnd:
    xor a
    ldh [hEnemy.status], a
    ld a, $ff
    ldh [hEnemy.directionFlags], a
    ld a, SPRITE_ZETA_5 ; $B7
    ldh [hEnemy.spriteType], a
    ; Reset chasing vector
    ld a, $10
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
.checkIfActing:
    ld a, [metroid_state]
    cp $03
        jp nc, .checkIfHurt
    ld b, a
    ; Check if we've seen this zeta before
    ldh a, [hEnemy.spawnFlag]
    cp $04
        jr z, .quickIntro
    ld c, a
; Fancy intro stuff
    ld a, b
    cp $02 ; When the husk has fallen offscreen
        jp z, .startFight
    ldh a, [hEnemy.spriteType]
    sub SPRITE_GAMMA_HUSK ; $B2
        jp z, .gammaHuskBranch
    dec a ; Checks for $B3
        jp z, .appearanceRise
    ld a, [cutsceneActive]
    and a
        jr nz, .longIntroStart

    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    ; Blink
    ldh a, [hEnemy.stunCounter]
    xor $10
    ldh [hEnemy.stunCounter], a
    ; Check if Samus is in range
    ld hl, hEnemy.xPos
    ld a, [samus_onscreenXPos]
    sub [hl]
    jr nc, .endIf_A
        cpl
        inc a
    .endIf_A:
    cp $50
        ret nc
    ; Start fight
    ld a, $01
    ld [cutsceneActive], a
    ; Play Metroid fight song
    ld a, $0c
    ld [songRequest], a
    ld a, $01
    ld [metroid_fightActive], a
ret

; Flash for a few frames and then let the husk fall off
.longIntroStart:
    ; Act every 4th frame
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    ; Wait a few frames before shedding husk
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $08
        jp z, .spawnGammaHusk
    ; Blink in the meantime
    ldh a, [hEnemy.stunCounter]
    xor $10
    ldh [hEnemy.stunCounter], a
ret

.quickIntro:
    ld a, SPRITE_ZETA_5 ; $B7
    ldh [hEnemy.spriteType], a
    ld hl, hEnemy.xPos
    ld a, [samus_onscreenXPos]
    sub [hl]
    jr nc, .endIf_B
        cpl
        inc a
    .endIf_B:
    cp $50
        ret nc
    
    ld a, $10
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    xor a
    ld [zeta_stunCounter], a
    ld a, $01
    ld [metroid_fightActive], a
    ld a, $03
    ld [metroid_state], a
    ld a, [songPlaying]
    cp $0c
        jr z, .standardAction
    ; Play metroid fight song
    ld a, $0c
    ld [songRequest], a
jr .standardAction

.standardAction:
    ; Check about screw knockback
    ldh a, [hEnemy.directionFlags]
    inc a
    jr z, .endIf_C
        call metroid_screwKnockback
        ld hl, metroid_screwKnockbackDone
        ld a, [hl]
        and a
            ret z
        ld [hl], $00
        ld a, $ff
        ldh [hEnemy.directionFlags], a
        ld a, SPRITE_ZETA_5 ; $B7
        ldh [hEnemy.spriteType], a
        ld a, $10
        ldh [hEnemy.counter], a
        ldh [hEnemy.state], a
        ld a, $03
        ld [metroid_state], a
        ret
    .endIf_C:

    ld a, [metroid_state]
    cp $04
        jp nc, .states4AndUp

; State 3 - Chase Samus
    ld b, $02
    ld de, $2000
    call enemy_seekSamus_farCall
    ; Check if Samus is within $20 pixels on the x axis
    ld hl, hEnemy.xPos
    ld a, [samus_onscreenXPos]
    sub [hl]
    jr c, .else_D
        cp $20
        jr nc, .endIf_E
            ld a, $01
            ld [zeta_xProximityFlag], a
        .endIf_E:
        ld a, OAM_XFLIP
        ldh [hEnemy.attr], a
        jr .endIf_D
    .else_D:
        cp -$20 ;$e0
        jr c, .endIf_F
            ld a, $01
            ld [zeta_xProximityFlag], a
        .endIf_F:
        xor a
        ldh [hEnemy.attr], a
    .endIf_D:
    ld hl, zeta_xProximityFlag
    ld a, [hl]
    and a
        ret z
    ; Clear proximity flag for next frame's check
    ld [hl], $00
    ; Check if Samus is within $20 pixels underneath Zeta
    ld hl, hEnemy.yPos
    ld a, [samus_onscreenYPos]
    sub [hl]
        ret c
    cp $20
        ret nc
    ; Spit fireball, move to next state
    call .spawnFireball
    ld a, $05
    ldh [hEnemy.spawnFlag], a
    ld a, $04
    ld [metroid_state], a
    xor a
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    ld a, SPRITE_ZETA_6 ; $B8
    ldh [hEnemy.spriteType], a
ret

.checkIfHurt:
    ld a, [enemy_weaponType]
    cp $20
        jp nc, .standardAction
    cp $10
        jr z, .screwReaction
    cp $08
        jr z, .hurtReaction
.plink:
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
ret

.screwReaction:
    call metroid_screwReaction
    ld a, sfx_square1_metroidScrewAttacked
    ld [sfxRequest_square1], a
ret

.hurtReaction:
    ; Invulnerable to upwards shots
    ld a, [enemy_weaponDir]
    ld b, a
    bit 2, b
        jr nz, .plink

    ld hl, hEnemy.health
    dec [hl]
    ld a, [hl]
    and a
        jr z, .death

    ld a, SPRITE_ZETA_8 ; $BA
    ldh [hEnemy.spriteType], a
    ld a, $08
    ld [zeta_stunCounter], a
    ld a, sfx_noise_metroidHurt
    ld [sfxRequest_noise], a
    ld hl, hEnemy.directionFlags
    ld [hl], $00
    bit 0, b ; Check if missile was going right
    jr nz, .setKnockbackRight
        inc a
        bit 3, b ; Check if missile was going down
        jr nz, .else_G
            inc a
            jr .setKnockbackLeft
        .else_G:
            set 1, [hl] ; Knock Zeta down
            ldh a, [hEnemy.yPos]
            add $05
            ldh [hEnemy.yPos], a
            ld a, [rDIV]
            and $01
            jr z, .else_H
                set 0, [hl] ; Knock Zeta right
                ret
            .else_H:
                set 2, [hl] ; Knock Zeta left
                ret
    .setKnockbackRight:
        set 0, [hl] ; Knock Zeta right
        ldh a, [hEnemy.xPos]
        add $05
        ldh [hEnemy.xPos], a
            jr .knockback_randVertical
    .setKnockbackLeft:
        ldh a, [hEnemy.xPos]
        sub $05
        cp $10
        jr c, .knockback_randVertical
            ldh [hEnemy.xPos], a
            set 2, [hl] ; Knock Zeta left
    .knockback_randVertical:
        ld a, [rDIV]
        and $01
        jr z, .else_I
            set 1, [hl] ; Knock Zeta down
            ret
        .else_I:
            set 3, [hl] ; Knock Zeta up
            ret
; end branch

.death:
    ; Set up explosion
    xor a
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    ld a, $80
    ld [metroid_state], a
    ld a, SPRITE_SCREW_EXPLOSION_START ; $E2
    ldh [hEnemy.spriteType], a
    ld a, sfx_noise_metroidKilled
    ld [sfxRequest_noise], a
    ; Play metroid killed jingle
    ld a, $0f
    ld [songRequest], a
    
    ld a, $02
    ld [metroid_fightActive], a
    ldh [hEnemy.spawnFlag], a
    ; Adjust metroid counts
    ld hl, metroidCountReal
    ld a, [hl]
    sub $01
    daa
    ld [hl], a
    ld hl, metroidCountDisplayed
    ld a, [hl]
    sub $01
    daa
    ld [hl], a
    ; Shuffle counter and prep earthquake
    ld a, $c0
    ld [metroidCountShuffleTimer], a
    call earthquakeCheck_farCall
ret


.states4AndUp:
    ld a, [metroid_state]
    cp $05
        jr z, .state5
    cp $06
        jr z, .state6

; State 4 - Spitting animation
    ; Act every other frame
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    ; Animate from $B8 -> $B9 -> $B8 -> $B7
    ; [hEnemy.counter] is used as a flag to start decrementing the animation
    ldh a, [hEnemy.counter]
    ld hl, hEnemy.spriteType
    and a
    jr z, .else_J
        ld a, [hl]
        cp SPRITE_ZETA_5 ; $B7
        jr z, .moveToState5
            dec [hl]
            ret
    .else_J:
        inc [hl]
        ld a, $01
        ldh [hEnemy.counter], a
        ret
        
.moveToState5:
    xor a
    ldh [hEnemy.counter], a
    ld a, $05
    ld [metroid_state], a
ret
; end state

.fireball: ; Projectile code
    ld a, [metroid_state]
    cp $06
    jr z, .else_K
        ld hl, hEnemy.yPos
        ld a, [hl]
        add $03
        cp $90
        jr nc, .else_K
            ld [hl+], a
            ; Move
            ldh a, [hEnemy.attr]
            bit B_OAM_XFLIP, a
            jr nz, .else_L
                dec [hl]
                ret
            .else_L:
                inc [hl]
                ret
    .else_K:
        ; Delete self
        call enemy_deleteSelf_farCall
        ld a, $ff
        ldh [hEnemy.spawnFlag], a
        ret
; end proc

.state5: ; Ascend
    ; Move Up
    ld hl, hEnemy.yPos
    call enemy_accelBackwards
    ; Check if within $30 pixels of the top of the screen
    ld a, [hl+]
    cp $30
    jr c, .else_M
        ; Move forward
        ldh a, [hEnemy.attr]
        bit B_OAM_XFLIP, a
        jr nz, .else_N
            dec [hl]
            ret
        .else_N:
            inc [hl]
            ret
    .else_M:
        ; Move on to next state
        ld a, $06
        ld [metroid_state], a
        xor a
        ldh [hEnemy.generalVar], a
        ld a, SPRITE_ZETA_1 ; $B3
        ldh [hEnemy.spriteType], a
        ret
; end state

.state6: ; Wait for state 3
    ; Wait a few frames
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $20
    jr z, .else_O
        call .animateWait ; Animate
        ret
    .else_O:
        ; Clear counter
        ld [hl], $00
        ; Return to state 3
        ld a, $03
        ld [metroid_state], a
        ld a, $04
        ldh [hEnemy.spawnFlag], a
        ld a, SPRITE_ZETA_5 ; $B7
        ldh [hEnemy.spriteType], a
        ret
; end state

.startFight:
    ld hl, hEnemy.spriteType
    ld [hl], SPRITE_ZETA_5 ; $B7
    ; Initialize chasing vector
    ld a, $10
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    ld a, $04
    ldh [hEnemy.spawnFlag], a
    xor a
    ld [cutsceneActive], a
    ld a, $03
    ld [metroid_state], a
ret

.gammaHuskBranch:
    ld a, [metroid_state]
    and a
    jr nz, .else_P
        call .oscillateWide ; Oscillate
        ret
    .else_P:
        ; Change palette
        ld a, $10
        ldh [hEnemy.stunCounter], a
        ; Move downwards
        ld hl, hEnemy.yPos
        call enemy_accelForwards
        ld a, [hl]
        cp $90
            ret c
        ; Despawn
        call enemy_deleteSelf_farCall
        ld a, $02
        ldh [hEnemy.spawnFlag], a
        ld a, $02
        ld [metroid_state], a
        ret
; end branch

.spawnGammaHusk:
    xor a
    ld [hl], a
    ldh [hEnemy.stunCounter], a
    call loadEnemy_getFirstEmptySlot_longJump
    xor a
    ld [hl+], a
    ldh a, [hEnemy.yPos]
    ld [hl+], a
    ldh a, [hEnemy.xPos]
    ld [hl+], a
    ld de, .gammaHuskHeader
    ld a, $03
    ld [enemy_tempSpawnFlag], a
    call enemy_spawnObject.longHeader
    ; Adjust position of zeta
    ld hl, hEnemy.yPos
    ld a, [hl]
    sub $08
    ld [hl], a
    ; Set sprite type to zeta
    ld a, SPRITE_ZETA_1 ; $B3
    ldh [hEnemy.spriteType], a
ret

.appearanceRise:
    ld a, [metroid_state]
    and a
        ret nz
    call .oscillateNarrow ; Oscillate
    ; Continue every 8th frame
    ldh a, [hEnemy_frameCounter]
    and $07
        ret nz
    ; Move up
    ld hl, hEnemy.yPos
    dec [hl]
    ; Wait a few frames
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $06
        ret nz
    ; Reset counter
    xor a
    ld [hl], a
    ; Next state
    inc a
    ld [metroid_state], a
ret

; Gamma husk header
.gammaHuskHeader: ; 02:759F
    db SPRITE_GAMMA_HUSK ; $B2
    db $80, $00, $00, $00, $00, $00, $00, $00, $ff, $06
    dw enAI_zetaMetroid

.spawnFireball: ; 02:75AC
    call loadEnemy_getFirstEmptySlot_longJump
    xor a
    ld [hl+], a
    ldh a, [hEnemy.yPos]
    add $04
    ld [hl+], a
    ldh a, [hEnemy.attr]
    ld b, a
    bit B_OAM_XFLIP, a
    jr nz, .else_Q
        ldh a, [hEnemy.xPos]
        sub $18
        ld [hl+], a
        jr .endIf_Q
    .else_Q:
        ldh a, [hEnemy.xPos]
        add $18
        ld [hl+], a
    .endIf_Q:

    ld a, SPRITE_ZETA_SHOT ; $BE
    ld [hl+], a
    ld a, $80
    ld [hl+], a
    ld a, b
    ld [hl+], a
    ld de, .fireballHeader
    ld a, $06
    ld [enemy_tempSpawnFlag], a
    call enemy_spawnObject.shortHeader
    ld a, sfx_noise_metroidFireball
    ld [sfxRequest_noise], a
    ret

; Fireball header
.fireballHeader:
    db $00, $00, $ff, $00, $00, $00, $ff, $08
    dw enAI_zetaMetroid

; Horizontally oscillate 2 pixels left and right
; Shared with the alpha metroid
.oscillateNarrow: ; 02:75EC
    ; Continue 3 frames out of 4
    ldh a, [hEnemy_frameCounter]
    and $03
        ret z
    ; Move right 2px when A is 1, left 2px when a is 2, otherwise do nothing
    ld hl, hEnemy.xPos
    dec a
    jr z, .else_R
        dec a
            ret z
        dec [hl]
        dec [hl]
        ret
    .else_R:
        inc [hl]
        inc [hl]
        ret
; end proc

; Horizontally oscillate 3 pixels left and right
.oscillateWide: ; 02:75FF
    ; Continue 3 frames out of 4
    ldh a, [hEnemy_frameCounter]
    and $03
        ret z
    ; Move right 3px when A is 1, left 3px when a is 2, otherwise do nothing
    ld hl, hEnemy.xPos
    dec a
    jr z, .else_S
        dec a
            ret z
        dec [hl]
        dec [hl]
        dec [hl]
        ret
    .else_S:
        inc [hl]
        inc [hl]
        inc [hl]
        ret
; end proc

; Does a cute animation of the Zeta's tail :)
.animateWait: ; 02:7614
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz

    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_ZETA_4 ; $B6
    jr nz, .endIf
        ld [hl], SPRITE_ZETA_1 - 1 ; $B2
    .endIf:
    inc [hl]
ret

.animateHurt:
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_ZETA_B ; $BD
    jr nz, .endIf_T
        ld [hl], SPRITE_ZETA_8 ; $BA
    .endIf_T:
    inc [hl]
ret
;}

;------------------------------------------------------------------------------
; Omega Metroid AI
enAI_omegaMetroid: ;{ 02:7631
    call enemy_getSamusCollisionResults
    ldh a, [hEnemy.spawnFlag]
    cp $06
        jp z, .fireball
    ; For omega to stay onscreen
    ld a, [metroid_state]
    and a
        call nz, metroid_keepOnscreen
    ; Act if not stunned
    ld hl, omega_stunCounter
    ld a, [hl]
    and a
        jr z, .checkIfHurt
    dec [hl]
        jr z, .stunEnd
    ; Stun animation
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    call enemy_flipSpriteId.now
    ; While stunned, only hit reaction is screw attack
    ld a, [enemy_weaponType]
    cp $10
        ret nc
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
ret


.stunEnd:
    ; Reset sprite type
    ld a, [omega_tempSpriteType]
    ldh [hEnemy.spriteType], a
.checkIfHurt:
    ; Check if fight has even started
    ld a, [metroid_state]
    and a
        jp z, .tryStartingFight
    ; Check for hit reactions
    ld a, [enemy_weaponType]
    cp $20 ; Standard action
        jp nc, .standardAction
    cp $10 ; Screw
        jr z, .screwReaction
    cp $08 ; Missiles
        jr z, .hurtReaction
.plink:
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
ret

.screwReaction:
    call metroid_screwReaction
    ld a, sfx_square1_metroidScrewAttacked
    ld [sfxRequest_square1], a
ret

.hurtReaction:
    ; Ignore vertical shots
    ld a, [enemy_weaponDir]
    ld b, a
    ld a, b
    and $03
        jr z, .plink
    ; Check if hit from front or behind
    ldh a, [hEnemy.attr]
    bit B_OAM_XFLIP, a
    jr nz, .else_A
        bit 1, b
            jr z, .hurtOneDamage
        jr .hurtWeakPoint
    .else_A:
        bit 0, b
            jr z, .hurtOneDamage

    .hurtWeakPoint:
        ; Omega Metroid was hit in the back (do 3x damage)
        ld hl, hEnemy.health
        ld a, [hl]
        sub $03
            jr c, .death
            jr z, .death
        ld [hl], a
        ld a, $10 ; Longer stun timer
        jr .endIf_hurt
    .hurtOneDamage:
        ld hl, hEnemy.health
        dec [hl]
            jr z, .death
        ld a, $03 ; Shorter stun timer
    .endIf_hurt:

    ld [omega_stunCounter], a
    ; Save sprite type to temp
    ld hl, hEnemy.spriteType
    ld a, [hl]
    ld [omega_tempSpriteType], a
    ; Animate
    ld [hl], $c4
    ; Noise
    ld a, sfx_noise_metroidQueenCry
    ld [sfxRequest_noise], a
    ; Apply knockback
    bit 0, b
    jr z, .else_B
        ldh a, [hEnemy.xPos]
        add $05
        ldh [hEnemy.xPos], a
        ret
    .else_B:
        ldh a, [hEnemy.xPos]
        sub $05
        cp $10
            ret c
        ldh [hEnemy.xPos], a
        ret
; end branch

.death:
    ; Clear variables
    xor a
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    ld [omega_waitCounter], a
    ld [omega_chaseTimerIndex], a
    ; Prep explosion
    ld a, $80
    ld [metroid_state], a
    ld a, SPRITE_SCREW_EXPLOSION_START ; $E2
    ldh [hEnemy.spriteType], a
    ; Play noise
    ld a, sfx_noise_omegaMetroidExplosion
    ld [sfxRequest_noise], a
    ; Play metroid killed jingle
    ld a, $0f
    ld [songRequest], a
    ; Adjust flags
    ld a, $02
    ld [metroid_fightActive], a
    ldh [hEnemy.spawnFlag], a
    ; Adjust Metroid counts
    ld hl, metroidCountReal
    ld a, [hl]
    sub $01
    daa
    ld [hl], a
    ld hl, metroidCountDisplayed
    ld a, [hl]
    sub $01
    daa
    ld [hl], a
    ; Shuffle counter and check for earthquake
    ld a, $c0
    ld [metroidCountShuffleTimer], a
    call earthquakeCheck_farCall
ret

.standardAction:
    ldh a, [hEnemy.directionFlags]
    inc a
        jr z, .handleStates
    ; Screw knockback stuff
    call metroid_screwKnockback
    ld hl, metroid_screwKnockbackDone
    ld a, [hl]
    and a
        ret z
    ld [hl], $00
    ld a, $ff
    ldh [hEnemy.directionFlags], a
    xor a
    ld [omega_waitCounter], a
    ld a, $03
    ld [omega_chaseTimerIndex], a
    ld a, $10
    ldh [hEnemy.generalVar], a
    ld a, $10
    ldh [hEnemy.counter], a
    ld a, $10
    ldh [hEnemy.state], a
    ld a, SPRITE_OMEGA_5 ; $C3
    ldh [hEnemy.spriteType], a
    ld a, $05
    ld [metroid_state], a
ret

; Wait before returning to state 1
.state7:
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $38
    jr z, .else_C
        call .animateTail
        ret
    .else_C:
        ld [hl], $00
        ld a, $01
        ld [metroid_state], a
        ret
; end state 7

; Return to state 1
.state4:
    ; Reset counters
    xor a
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    ld a, $01
    ld [metroid_state], a
  .closeMouth:
    ld a, SPRITE_OMEGA_1 ; $BF
    ldh [hEnemy.spriteType], a
    ret
; end state 4

.animateState2:
    ; Animate tail for several frames before facing Samus
    ld hl, hEnemy.state
    ld a, [hl]
    cp $24
    jr z, .else_D
        inc [hl]
        call .animateTail
        ret
    .else_D:
        call .faceSamus
        ret
; end proc

.handleStates:
    ld a, [metroid_state]
    cp $05 ; Chase Samus
        jr z, .state5
    cp $06 ; Move up and forwards
        jr z, .state6
    cp $07 ; Wait before returning to state 1
        jr z, .state7

    call .selectChaseTimer ; Sets metroid_state to 5 when omega_waitCounter expires
    ld a, [metroid_state]
    cp $04 ; Prep state 1
        jr z, .state4
    dec a ; Shoot fireball
        jp z, .state1

; State 2 - Idle while fireballs are onscreen (can be preempted by .selectChaseTimer)
;  (note: state 3 appears to be unused for Omega Metroids, while state 0 is used for setup)
    ; Set state to 1 once there are no more fireballs
    ld a, [numEnemies.total]
    dec a
        jr z, .state4
    ; Wait some frames before using .animateState2
    ld b, $18
    ld hl, hEnemy.counter
    ld a, [hl]
    cp b
        jr z, .animateState2
    ; Increment timer in the meantime before closing mouth
    inc [hl]
    ld a, [hl]
    cp b
        jr z, .closeMouth
    ; Wiggle tail with mouth open in the mean time
    call enemy_flipSpriteId_2Bits.twoFrame
ret

; Chase Samus
.state5:
    ; Stop chasing once time has depleted
    ld hl, hEnemy.generalVar
    dec [hl]
        jr z, .moveToState6
    ; Force chase if index is 4
    ld a, [omega_chaseTimerIndex]
    cp $04
        jr z, .chaseSamus
    ; If crouching, skip/stop chasing
    ld a, [samusPose]
    cp pose_crouch
        jr z, .moveToState6
.chaseSamus:
    ; Chase Samus
    ld b, $02
    ld de, $2000
    call enemy_seekSamus_farCall
    ld hl, hEnemy.xPos
    ld a, [samus_onscreenXPos]
    sub [hl]
    jr c, .else_E
        cp $10
        jr c, .endIf_E
            ld a, OAM_XFLIP
            ldh [hEnemy.attr], a
            jr .endIf_E
    .else_E:
        cp $f0
        jr nc, .endIf_E
            xor a
            ldh [hEnemy.attr], a
    .endIf_E:
ret

.moveToState6:
    ld a, $06
    ld [metroid_state], a
    xor a
    ldh [hEnemy.generalVar], a
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
ret
; end of state 5

; Move up and forwards
.state6:
    ; Move upwards
    ld hl, hEnemy.yPos
    call enemy_accelBackwards
    ; Check y pos
    ld a, [hl+]
    cp $34
    jr c, .else_F
        ; Move forwards
        ldh a, [hEnemy.attr]
        bit B_OAM_XFLIP, a
        jr nz, .else_G
            dec [hl]
            dec [hl]
            ret
        .else_G:
            inc [hl]
            inc [hl]
            ret
    .else_F:
        ; Next state
        ld a, $07
        ld [metroid_state], a
        xor a
        ldh [hEnemy.generalVar], a
        ld a, SPRITE_OMEGA_1 ; $BF
        ldh [hEnemy.spriteType], a
        ret
; end state 6

.state1: ; State 1 - Shoot fireball
    call .faceSamus
    ; Wait a few frames
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $10
        ret nz
    ; Reset counter
    ld [hl], $00
    call .spawnFireball
    ld a, $02
    ld [metroid_state], a
    ld a, $05
    ldh [hEnemy.spawnFlag], a
    ld a, SPRITE_OMEGA_3 ; $C1
    ldh [hEnemy.spriteType], a
    ld a, sfx_noise_metroidFireball
    ld [sfxRequest_noise], a
ret

; start fireball code
.fireball: ; Omega fireball
    ld a, [metroid_fightActive]
    cp $02
        jp z, .fireballDelete

    ldh a, [hEnemy.spriteType]
    cp $c8
        jr nc, .fireballExplode

    ; Get angle if we haven't yet
    ld hl, hEnemy.counter
    ld a, [hl]
    and a
    jr nz, .endIf_H
        ld [hl], $01
        call gamma_getAngle_farCall
    .endIf_H:

    ; Get the speed vector for the angle and move
    call gamma_getSpeedVector_farCall
    ; Vertical movement and collision check
    ld a, b
    and a
    jr z, .endIf_I
        bit 7, b
        jr z, .else_J
            res 7, b
            ld hl, hEnemy.yPos
            ld a, [hl]
            sub b
            ld [hl], a
            call enCollision_up.nearSmall
            ld a, [en_bgCollisionResult]
            bit 3, a
                jr nz, .fireballHit
            jr .endIf_I
        .else_J:
            ld hl, hEnemy.yPos
            ld a, [hl]
            add b
            ld [hl], a
            call enCollision_down.nearSmall
            ld a, [en_bgCollisionResult]
            bit 1, a
                jr nz, .fireballHit
    .endIf_I:
    ; Horizontal movement
    ld hl, hEnemy.xPos
    bit 7, c
    jr z, .else_K
        res 7, c
        ld a, [hl]
        sub c
        jr .endIf_K
    .else_K:
        ld a, [hl]
        add c
    .endIf_K:

    ld [hl], a
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    call enemy_flipSpriteId.now
ret

.fireballHit:
    ld a, [en_bgCollisionResult]
    ld [unknown_C42D], a
    xor a
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    ld a, SPRITE_OMEGA_SHOT_3 ; $C8
    ldh [hEnemy.spriteType], a
ret

.fireballExplode: ; Animate fireball explosion
    ld hl, hEnemy.spriteType
    ld a, [hl]
    cp SPRITE_OMEGA_SHOT_7 ; $CC
        jr z, .fireballDelete
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    inc [hl]
ret

.fireballDelete:
    call enemy_deleteSelf_farCall
    ld a, $ff
    ldh [hEnemy.spawnFlag], a
    ld hl, metroid_state
    ld a, [hl]
    cp $02
        ret nz
    ld a, $04
    ld [metroid_state], a
ret
; end fireball code

.tryStartingFight:
    ldh a, [hEnemy.spawnFlag]
    cp $04
        jp z, .quickIntro
    ; Check if cutscene active
    ld a, [cutsceneActive]
    and a
    jr nz, .endIf_L
        ; Check if Samus is in range
        ld hl, hEnemy.xPos
        ld a, [hl]
        add $10
        ld b, a
        ld a, [samus_onscreenXPos]
        add $10
        sub b
        jr nc, .endIf_M
            cpl
            inc a
        .endIf_M:
        cp $50
            ret nc
        ; Activate cutscene
        ld a, $01
        ld [cutsceneActive], a
        ; Trigger Metroid fight music
        ld a, $0c
        ld [songRequest], a
        ld a, $01
        ld [metroid_fightActive], a
    .endIf_L:

    ; Continue every 4th frame
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    ; Wait several frames to start fight
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $18
        jp z, .startFight
    ; Switch between zeta and omega sprites
    ldh a, [hEnemy.spriteType]
    xor SPRITE_ZETA_1 ^ SPRITE_OMEGA_1 ; $0C
    ldh [hEnemy.spriteType], a
ret

.spawnFireball:
    call loadEnemy_getFirstEmptySlot_longJump
    xor a
    ld [hl+], a
    ldh a, [hEnemy.yPos]
    ld [hl+], a
    ldh a, [hEnemy.attr]
    ld b, a
    bit B_OAM_XFLIP, a
    jr nz, .else_N
        ldh a, [hEnemy.xPos]
        sub $10
        ld [hl+], a
        jr .endIf_N
    .else_N:
        ldh a, [hEnemy.xPos]
        add $10
        ld [hl+], a
    .endIf_N:

    ld a, SPRITE_OMEGA_SHOT_1 ; $C6
    ld [hl+], a
    xor a
    ld [hl+], a
    ld a, b
    ld [hl+], a
    ld de, .fireballHeader
    ld a, $06
    ld [enemy_tempSpawnFlag], a
    call enemy_spawnObject.shortHeader
ret

.quickIntro:
    ld a, SPRITE_OMEGA_1 ; $BF
    ldh [hEnemy.spriteType], a
    ; Check if Samus is in range
    ld hl, hEnemy.xPos
    ld a, [samus_onscreenXPos]
    sub [hl]
    jr nc, .endIf_O
        cpl
        inc a
    .endIf_O:
    cp $50
        ret nc
    ; Init variables
    xor a
    ldh [hEnemy.generalVar], a
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    ld [omega_stunCounter], a
    ld [omega_waitCounter], a
    ld [omega_chaseTimerIndex], a
    ; Increment state to 1
    inc a
    ld [metroid_state], a
    ld a, $01
    ld [metroid_fightActive], a
    ld a, $ff
    ldh [hEnemy.directionFlags], a
    ; Trigger Metroid fight music
    ld a, [songPlaying]
    cp $0c
        ret z
    ld a, $0c
    ld [songRequest], a
ret

.startFight:
    ; Clear counter
    xor a
    ld [hl], a
    ld a, SPRITE_OMEGA_1 ; $BF
    ldh [hEnemy.spriteType], a
    xor a
    ld [cutsceneActive], a
    ; Increment state to 1
    inc a
    ld [metroid_state], a
    ld a, $04
    ldh [hEnemy.spawnFlag], a
ret

.fireballHeader: ; 02:799E
    db $00, $00, $ff, $00, $00, $00, $ff, $08
    dw enAI_omegaMetroid

.selectChaseTimer: ; 02:79A8
    ld hl, omega_waitCounter
    ld a, [hl]
    cp $40
    jr z, .endIf_P
        inc [hl]
        ret
    .endIf_P:
    ld [hl], $00 ; Loop back to zero
    
    ; If Samus has lost enough health since last time this was called, reset timer index to zero
    ld hl, samusCurHealthLow
    ld a, [omega_samusPrevHealth]
    sub [hl]
    cp $30
        jr nc, .timerCase_default

    ld hl, omega_chaseTimerIndex
    inc [hl]
    ld a, [hl]
    dec a
        jr z, .timerCase_1
    dec a
        jr z, .timerCase_2
    dec a
        jr z, .timerCase_3
    dec a
        jr z, .timerCase_4

    .timerCase_default:
        xor a
        ld [omega_chaseTimerIndex], a
        ld a, $0c
        jr .endTimerCases
    .timerCase_1:
        ld a, $14
        jr .endTimerCases
    .timerCase_2:
        ld a, $28
        jr .endTimerCases
    .timerCase_3:
        ld a, $40
        jr .endTimerCases
    .timerCase_4:
        ld a, $60
.endTimerCases:
    ; Load chase timer value
    ldh [hEnemy.generalVar], a
    ; Update health
    ld a, [samusCurHealthLow]
    ld [omega_samusPrevHealth], a
    ; Initialize chasing vector
    ld a, $10
    ldh [hEnemy.counter], a
    ld a, $10
    ldh [hEnemy.state], a
    ; Set sprite type, SFX, and state
    ld a, SPRITE_OMEGA_5 ; $C3
    ldh [hEnemy.spriteType], a
    ld a, sfx_square1_2D
    ld [sfxRequest_square1], a
    ld a, $05
    ld [metroid_state], a
; Force the parent function to return as well
pop af
ret

.unusedProc: ; 02:7A06 - Unused movement proc
    ld b, $05
    ld de, hEnemy.yPos
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    dec a
        jr z, .unusedCase_1 ; Up-left
    dec a
        jr z, .unusedCase_2 ; Up-right
    dec a
        jr z, .unusedCase_3 ; Down-right
    ld [hl], $00
        jr .unusedCase_4 ; Left

.unusedCase_1: ; Move up
    ld a, [de]
    sub b
    ld [de], a
.unusedCase_4: ; Move left
    inc e
    ld a, [de]
    sub b
    ld [de], a
    ret

.unusedCase_2: ; Move up
    ld a, [de]
    sub b
    ld [de], a
.unusedRightBranch: ; Move right
    inc e
    ld a, [de]
    add b
    ld [de], a
    ret

.unusedCase_3: ; Move down
    ld a, [de]
    add b
    ld [de], a
    jr .unusedRightBranch
; end unused proc

.faceSamus: ; 02:7A32
    ; Compare x positions
    ld hl, hEnemy.xPos
    ld a, [samus_onscreenXPos]
    sub [hl]
    jr nc, .else_Q
        xor a
        jr .endIf_Q
    .else_Q:
        ld a, OAM_XFLIP
    .endIf_Q:
    ldh [hEnemy.attr], a
; fallthrough to next proc (!)

.animateTail: ; 02:7A42
    ; Continue every 4th frame
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    ; Oscillate between two values
    ld hl, hEnemy.spriteType
    ld a, [hl]
    xor SPRITE_OMEGA_1 ^ SPRITE_OMEGA_2 ; $7f - Osciallates between $BF and $C0
    ld [hl], a
ret
;}

;------------------------------------------------------------------------------
; Standard (larval) Metroid AI
enAI_normalMetroid: ;{ 02:7A4F
    call enemy_getSamusCollisionResults
    ; Check if latched
    ldh a, [hEnemy.generalVar]
    and a
        jr z, .unlatchedActions ; Not latched

; Latched
    call .animate
    ld a, [larva_latchState]
    and a ; State 0
        jr z, .restart
    dec a ; State 1
        jr z, .unlatch
; State 2
    call .stayAttached
    ; Unlatch if bombed
    ld a, [enemy_weaponType]
    cp $09
        ret nz
    ld hl, larva_latchState
    dec [hl]
ret

.unlatch:
    ; Return to normal floating state after a few frames
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $18
        jr z, .restart
    ; Set bomb state to prevent erroneous relatching by other metroids
    ld a, $02
    ld [larva_bombState], a
    ; Move up and check collision
    ldh a, [hEnemy.yPos]
    sub $03
    cp $10
    jr c, .endIf_A
        ldh [hEnemy.yPos], a
        call enCollision_up.farWide
        ld a, [en_bgCollisionResult]
        bit 3, a
        jr z, .endIf_A
            ld a, [enemy_yPosMirror]
            ldh [hEnemy.yPos], a
    .endIf_A:
    ; Move left and check collision
    ldh a, [hEnemy.xPos]
    sub $03
    cp $10
        ret c
    ldh [hEnemy.xPos], a
    call enCollision_left.farWide
    ld a, [en_bgCollisionResult]
    bit 2, a
        ret z
    ld a, [enemy_xPosMirror]
    ldh [hEnemy.xPos], a
ret

.restart:
    ; Clear flags
    xor a
    ld [larva_bombState], a
    ldh [hEnemy.generalVar], a
    ld [larva_latchState], a
    ; Reset seek vector
    ld a, $10
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
ret

; Normal AI (not latched)
.unlatchedActions:
    ; Hurt animation
    ld hl, larva_hurtAnimCounter
    ld a, [hl]
    and a
    jr z, .endIf_B
        dec [hl]
            ret nz
        ld a, SPRITE_METROID_2 ; $CE
        ldh [hEnemy.spriteType], a
    .endIf_B:

    ldh a, [hEnemy.iceCounter]
    and a
        jr z, .unfrozenActions ; Not frozen

; Frozen
    call enemy_animateIce.call ; Generic ice stuff
    ldh a, [hEnemy.iceCounter]
    and a
        jr z, .unfreeze

    ; Frozen shot reactions
    ld a, [enemy_weaponType]
    cp $20 ; Touch
        ret nc
    cp $08 ; Missiles
        jr z, .hurtReaction
    dec a ; $01 - Ice (refreeze)
        jp z, .freeze
    ; Plink
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
ret

.unfreeze:
    ; Reset chase vector
    ld a, $10
    ldh [hEnemy.counter], a
    ldh [hEnemy.state], a
    ; Reset sprite type
    ld a, SPRITE_METROID_2 ; $CE
    ldh [hEnemy.spriteType], a
    ; Reset health
    ld a, $05
    ldh [hEnemy.health], a
ret

.hurtReaction:
    ; Take health
    ld hl, hEnemy.health
    dec [hl]
    ld a, [hl]
    and a
        jr z, .death
    ; Animate and make sound
    ld a, $03
    ld [larva_hurtAnimCounter], a
    ld a, SPRITE_METROID_3 ; $CF
    ldh [hEnemy.spriteType], a
    ld a, sfx_noise_metroidHurt
    ld [sfxRequest_noise], a
ret

.death:
    ; Clear variables
    xor a
    ldh [hEnemy.counter], a
    ld [larva_bombState], a
    ld [larva_latchState], a
    ; Set spawn flag to dead
    ld a, $02
    ldh [hEnemy.spawnFlag], a
    ; Prep explosion
    ld a, $10
    ldh [hEnemy.explosionFlag], a
    ld a, sfx_noise_metroidKilled
    ld [sfxRequest_noise], a
    ; Adjust Metroid counts
    ld hl, metroidCountReal
    ld a, [hl]
    sub $01
    daa
    ld [hl], a
    ld hl, metroidCountDisplayed
    ld a, [hl]
    sub $01
    daa
    ld [hl], a
    ; Shuffle counter
    ld a, $c0
    ld [metroidCountShuffleTimer], a
    ; Earthquake
    call earthquakeCheck_farCall
ret

.unfrozenActions: ; Normal shot reactions
    call .animate
    ld a, [enemy_weaponType]
    cp $ff ; Not hit
        jp z, .standardAction
    cp $20 ; Touch
        jp z, .touchReaction
    cp $10 ; Screw
        jr z, .screwReaction
    cp $09 ; Bomb
        jr z, .bombReaction
    dec a ; $01 - Ice
        jr z, .freeze
    ld a, sfx_square1_beamDink
    ld [sfxRequest_square1], a
ret

.touchReaction:
    ld hl, larva_bombState
    ld a, [hl]
    cp $02
    jr z, .else_C
        cp $01
        jr z, .endIf_D
            ld a, $01
            ld [larva_bombState], a
        .endIf_D:
        ld a, $02 ; Latch state = latched on
        jr .endIf_C
    .else_C:
        ld a, $01 ; Latch state = fly away
    .endIf_C:
    
    ld [larva_latchState], a
    ; Latch on
    ld a, $01
    ldh [hEnemy.generalVar], a
    xor a
    ldh [hEnemy.counter], a
ret

.screwReaction:
.bombReaction:
    ; Set screw knockback timer to zero
    xor a
    ldh [hEnemy.counter], a
    call metroid_screwReaction
    ld a, sfx_square1_metroidScrewAttacked
    ld [sfxRequest_square1], a
ret

.freeze:
    ld a, sfx_square1_metroidScrewAttacked
    ld [sfxRequest_square1], a
    ld a, $10
    ldh [hEnemy.stunCounter], a
    ld a, $44
    ldh [hEnemy.iceCounter], a
    xor a
    ldh [hEnemy.status], a
ret

.standardAction:
    ; Check if $FF
    ldh a, [hEnemy.directionFlags]
    inc a
    jr z, .else_E
        ; Screw attack knockback
        call metroid_screwKnockback
        ld hl, metroid_screwKnockbackDone
        ld a, [hl]
        and a
            ret z
        ld [hl], $00
        ld a, $ff
        ldh [hEnemy.directionFlags], a
        ld a, $10
        ldh [hEnemy.counter], a
        ld a, $10
        ldh [hEnemy.state], a
        ret
    .else_E:
        ; Chase Samus
        ld b, $01
        ld de, $1e02
        call enemy_seekSamus_farCall ; Move
        call metroid_correctPosition ; Correct position
        ret
; end branch

.animate:
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    ld hl, hEnemy.spriteType
    ld a, [hl]
    xor SPRITE_METROID_1 ^ SPRITE_METROID_2 ; $6E ; Osciallate between $A0 and $CE
    ld [hl], a
ret

.stayAttached: ; Stay attached to Samus
    ld hl, hEnemy.yPos
    ld a, [samus_onscreenYPos]
    ld [hl+], a
    ld a, [samus_onscreenXPos]
    ld [hl], a
ret
;}

;------------------------------------------------------------------------------
; Baby Metroid AI
enAI_babyMetroid: ;{ 02:7BE5
    ld a, [metroid_state]
    and a
        jr z, .case_0 ; case 0
    dec a
        jr z, .case_1 ; case 1
    dec a ; v--- sneaky nz instead of z
        jp nz, .case_3 ; default case (3)
        
; case 2 (active)
    call enemy_flipSpriteId.fourFrame
    ; Chase Samus
    ld b, $02
    ld de, $2000
    call enemy_seekSamus_farCall
    
    call baby_checkBlocks
    call baby_keepOnscreen
ret

.case_1: ; case 1 - Metroid moves up from the egg
    call enAI_zetaMetroid.oscillateWide ; Oscillate horizontally
    ; Move up
    ld hl, hEnemy.yPos
    dec [hl]
    ; Wait a few frames before proceeding
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    cp $0c
        ret nz
    ; Set up $E9/$EA for seekSamus
    ld a, $10
    ld [hl+], a
    ld [hl], a
    ; Set to state 2 (active)
    ld hl, metroid_state
    inc [hl]
    ; Clear cutscene
    xor a
    ld [cutsceneActive], a
ret

.case_0: ; case 0 - Waiting
    ldh a, [hEnemy.spawnFlag]
    cp $04
    jr z, .else_A
        call .animateFlash
        ; Check if Samus is in range
        ; On x axis
        ld hl, hEnemy.xPos
        ld a, [samus_onscreenXPos]
        sub [hl]
        jr nc, .endIf_B
            cpl
            inc a
        .endIf_B:
        cp $18
            ret nc
        ; On y axis
        dec l
        ld a, [samus_onscreenYPos]
        sub [hl]
        jr nc, .endIf_C
            cpl
            inc a
        .endIf_C:
        cp $10
            ret nc
        ; Freeze Samus in place
        ld a, $01
        ld [cutsceneActive], a
        call .animateEggWiggle ; Animate egg hatching
        ; Increment counter
        ld hl, hEnemy.state
        inc [hl]
        ld a, [hl]
        cp $30
            ret nz
        ; Clear variables
        xor a
        ld [hl-], a
        ld [hl], a
        ; Unblink
        ldh [hEnemy.stunCounter], a
        ; Set state to egg exploding
        ld a, $03
        ld [metroid_state], a
        ; Sure, why not?
        ld hl, metroid_fightActive
        inc [hl]
        ld a, $04
        ldh [hEnemy.spawnFlag], a
        ld a, sfx_noise_babyMetroidClearingBlock
        ld [sfxRequest_noise], a
        ret
    .else_A:
        ld a, SPRITE_BABY_1 ; $A8
        ldh [hEnemy.spriteType], a
        ; Check if Samus is in range
        ld hl, hEnemy.xPos
        ld a, [samus_onscreenXPos]
        sub [hl]
        jr nc, .endIf_D
            cpl
            inc a
        .endIf_D:
        cp $60
            ret nc
        ; Sure, why not?
        ld a, $01
        ld [metroid_fightActive], a
        ; Set to state 2 (active)
        ld a, $02
        ld [metroid_state], a
        ld a, sfx_noise_babyMetroidClearingBlock
        ld [sfxRequest_noise], a
        ret
; end proc

.case_3: ; Case 2 - Egg exploding
    ld hl, hEnemy.counter
    inc [hl]
    ld a, [hl]
    bit 0, a
    jr z, .else_E
        srl a
        add SPRITE_SCREW_EXPLOSION_START ; $E2 ; Explosion
        ldh [hEnemy.spriteType], a
        ret
    .else_E:
        cp $0c
            call z, .prepState1
        ld a, SPRITE_BABY_1 ; $A8
        ldh [hEnemy.spriteType], a
        ret
; end proc

.prepState1:
    ; Reset timer
    ld [hl], $00
    ; Set state to 1
    ld a, $01
    ld [metroid_state], a
ret

.animateFlash:
    ; Do every 4 frames
    ldh a, [hEnemy_frameCounter]
    and $03
        ret nz
    ; Flash by oscillating this value between $00 and $10
    ld hl, hEnemy.stunCounter
    ld a, [hl]
    xor $10
    ld [hl], a
ret

.animateEggWiggle: ; Animate egg hatching
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    ld hl, hEnemy.spriteType
    ldh a, [hEnemy.counter]
    dec a
    jr z, .else
        inc [hl]
        ld a, [hl]
        cp SPRITE_EGG_3 ; $A7 ; Upper threshold of wiggle
            ret nz
    
    ; Switch direction of wiggle
      .switchDirection:
        ld hl, hEnemy.counter
        ld a, [hl]
        xor $01
        ld [hl], a
        ret
        
    .else:
        dec [hl]
        ld a, [hl]
        cp SPRITE_EGG_1 ; $A5 ; Lower threshold of wiggle
            ret nz
        jr .switchDirection
; end proc
;} end baby specific code

; Used by normal metroids to correct their position when moving
metroid_correctPosition: ;{ 02:7CDD
    ldh a, [hEnemy.counter]
    cp $10
    jr c, .else_A
        call enCollision_down.farWide
        ld a, [en_bgCollisionResult]
        bit 1, a
            jr z, .endIf_A
    
        .revertYPos:
        ld a, [enemy_yPosMirror]
        ldh [hEnemy.yPos], a
            jr .endIf_A
    .else_A:
        ldh a, [hEnemy.yPos]
        cp $10
            jr c, .revertYPos
        call enCollision_up.farWide
        ld a, [en_bgCollisionResult]
        bit 3, a
            jr nz, .revertYPos
    .endIf_A:

    ldh a, [hEnemy.state]
    cp $10
    jr c, .else_B
        call enCollision_right.farWide
        ld a, [en_bgCollisionResult]
        bit 0, a
            ret z
            
        .revertXPos:
        ld a, [enemy_xPosMirror]
        ldh [hEnemy.xPos], a
        ret
    .else_B:
        ldh a, [hEnemy.xPos]
        cp $10
            jr c, .revertXPos
        call enCollision_left.farWide
        ld a, [en_bgCollisionResult]
        bit 2, a
            jr nz, .revertXPos
ret
;}

baby_checkBlocks: ;{ 02:7D2A - Check if blocks need to be cleared
    ; Save prospective x position to temp
    ld hl, hEnemy.xPos
    ld a, [hl]
    ld [baby_tempXpos], a
    ; Load previous x position when testing y collision
    ld a, [enemy_xPosMirror]
    ld [hl], a
    ; Check Y chasing vector to choose between checking up or down
    ldh a, [hEnemy.counter]
    cp $10
    jr c, .else_A
        call enCollision_down.midMedium
        ld a, [en_bgCollisionResult]
        bit 1, a
            jr z, .endIf_A

        .clearBlockY:
        ld a, [metroid_babyTouchingTile]
        cp $64 ; Tile ID of the block the baby can clear
        call z, baby_clearBlock
    
        .revertYPos:
        ld a, [enemy_yPosMirror]
        ldh [hEnemy.yPos], a
            jr .endIf_A
    .else_A:
        ldh a, [hEnemy.yPos]
        cp $10
            jr c, .revertYPos
        call enCollision_up.midMedium
        ld a, [en_bgCollisionResult]
        bit 3, a
            jr nz, .clearBlockY
    .endIf_A:
    ; Reload x position from temp
    ld a, [baby_tempXpos]
    ldh [hEnemy.xPos], a

    ; Check x chasing vector to chose between checking left or right
    ldh a, [hEnemy.state]
    cp $10
    jr c, .else_B
        call enCollision_right.midMedium
        ld a, [en_bgCollisionResult]
        bit 0, a
            ret z
    
        .clearBlockX:
        ld a, [metroid_babyTouchingTile]
        cp $64 ; Tile ID of the block the baby can clear
            call z, baby_clearBlock
    
        .revertXPos:
        ld a, [enemy_xPosMirror]
        ldh [hEnemy.xPos], a
        ret
    .else_B:
        ldh a, [hEnemy.xPos]
        cp $10
            jr c, .revertXPos
    
        call enCollision_left.midMedium
        ld a, [en_bgCollisionResult]
        bit 2, a
            jr nz, .clearBlockX
ret
;}

baby_clearBlock: ;{ 02:7D97
    call destroyBlock_farCall
    ld a, sfx_noise_babyMetroidClearingBlock
    ld [sfxRequest_noise], a
ret
;}

; Verify that enemy was hit by Samus, and copy the results to a working variable
;  Return values (enemy_weaponType, enemy_weaponDir)
; $00 - Power beam
; $01 - Ice
; $02 - Wave
; $03 - Spazer
; $04 - Plasma
; $09 - Bombs
; $10 - Screw
; $20 - Touch
; $FF - Nothing
enemy_getSamusCollisionResults: ;{ 02:7DA0
    ; Save null result first
    ld a, $ff
    ld [enemy_weaponType], a
    ld c, a
    ; Check if enCollision_pEnemy is equal to the current enemy pointer in HRAM
    ld hl, enSprCollision.pEnemyHigh
    ld de, hEnemyWramAddrHigh
    ld a, [de]
    cp [hl]
        ret nz
    dec e
    dec l
    ld a, [de]
    cp [hl]
        ret nz
    ; A collision with the currently processed enemy has occurred
    dec l
    ld c, [hl] ; Read enSprCollision.weaponType
    ld a, $ff
    ld [hl+], a ; Clear enSprCollision.weaponType
    ld [hl+], a ; Clear enSprCollision.pEnemyLow
    ld [hl+], a ; Clear enSprCollision.pEnemyHigh
    ld b, [hl]  ; Read enSprCollision.weaponDir
    ld [hl], a
    ; Save results
    ld a, c
    ld [enemy_weaponType], a ; Collision type
    ld a, b
    ld [enemy_weaponDir], a ; Direction hit from
ret
;}

; Used to keep zeta and omegas onscreen
metroid_keepOnscreen: ;{ 02:7DC6
    ld bc, $1890 ; Not a pointer. This is just loading two different values into B and C.
    ; Clamp enemy y pos to top of screen
    ld hl, hEnemy.yPos
    ld a, [hl]
    cp b
    jr nc, .endIf
        ld [hl], b
    .endIf:
    ; This function doesn't prevent them from going below the screen

    ; Clamp the x position between B and C
    inc l
    ld a, [hl]
    cp b
    jr nc, .else
        ld [hl], b
        ret
    .else:
        cp c
            ret c
        ld [hl], c
        ret
;} end proc

baby_keepOnscreen: ;{ 02:7DDC
    ld bc, $1890 ; Not a pointer. B is a minimum and C is a maximum
    ; Clamp Y position between B and C
    ld hl, hEnemy.yPos
    ld a, [hl]
    cp b
    jr nc, .else_A
        ld [hl], b
        jr .endIf_A
    .else_A:
        cp c
        jr c, .endIf_A
            ld [hl], c
    .endIf_A:
    
    ; Clamp X position between B and C
    inc l
    ld a, [hl]
    cp b
    jr nc, .else_B
        ld [hl], b
        ret
    .else_B:
        cp c
            ret c
        ld [hl], c
        ret
;} end proc

enemy_toggleVisibility: ;{ 02:7DF8
    ; Exit if the frame is odd
    ldh a, [hEnemy_frameCounter]
    and $01
        ret nz
    ; Toggle visibility
    ld hl, hEnemy.status
    ld a, [hl]
    xor $80
    ld [hl], a
ret
;}

bank2_freespace: ; 02:7E05 - Freespace 
