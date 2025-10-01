; Constants

; Hardware related constants (not covered by hardware.inc)
def rMBC_BANK_REG = $2100 ; Dunno why it just doesn't use $2000


def METASPRITE_END = $FF ; I recommend setting this to $80 (-128) if you plan on doing your own sprite editing

; Map related memory locations (fixed in each bank)
def map_screenPointers = $4000 ; $200 bytes
def map_scrollData     = $4200 ; $100 bytes
def map_doorIndexes    = $4300 ; $200 bytes - Also contains sprite priority bits per screen
; Note: Map data starts at $4500

; Scrolling Directions (bitfields and bit numbers)
def scrollDir_right = $10
def scrollDir_left  = $20
def scrollDir_up    = $40
def scrollDir_down  = $80
def scrollDirBit_right = 4
def scrollDirBit_left  = 5
def scrollDirBit_up    = 6
def scrollDirBit_down  = 7

; Samus physics constants
def samus_jumpArrayBaseOffset = $40
def samus_unmorphJumpTime = $10

; Samus position offsets
def samusOriginX_toCenter = $08 ; center is 8px to the right of origin
def samusOriginY_toCenter = $0a ; center is 10px down from origin
def samusOriginX_toLeft = samusOriginX_toCenter - $05
def samusOriginX_toRight = samusOriginX_toCenter + $04
def samusOriginY_toStand = samusOriginY_toCenter - $12
    def samusOriginY_toStandCheck = samusOriginY_toStand + $08
def samusOriginY_toCrouch = samusOriginY_toCenter - $08
    def samusOriginY_toCrouchBG = samusOriginY_toCenter - $0a
    def samusOriginY_toCrouchCheck = samusOriginY_toCrouch + $06
def samusOriginY_toNJump = samusOriginY_toCenter - $0a
    def samusOriginY_toNJumpBG = samusOriginY_toCenter - $06
def samusOriginY_toSpinJump = samusOriginY_toCenter - $02
    def samusOriginY_toSpinJumpBG = samusOriginY_toCenter - $00
def samusOriginY_toMorph = samusOriginY_toCenter + $06
def samusOriginY_toBottom = samusOriginY_toCenter + $12
    

; Samus' Gear constants
;  Bitfields
def itemMask_bomb   = %00000001 ; 01: Bombs
def itemMask_hiJump = %00000010 ; 02: Hi-jump
def itemMask_screw  = %00000100 ; 04: Screw attack
def itemMask_space  = %00001000 ; 08: Space jump
def itemMask_spring = %00010000 ; 10: Spring ball
def itemMask_spider = %00100000 ; 20: Spider ball
def itemMask_varia  = %01000000 ; 40: Varia suit
def itemMask_UNUSED = %10000000 ; 80: Unused
;  Bit Numbers
def itemBit_bomb   = 0
def itemBit_hiJump = 1
def itemBit_screw  = 2
def itemBit_space  = 3
def itemBit_spring = 4
def itemBit_spider = 5
def itemBit_varia  = 6
def itemBit_UNUSED = 7

; Collision block-type bit numbers
def blockType_water = 0 ;Water (also causes morph ball sound effect glitch)
def blockType_up    = 1 ;Half-solid floor (can jump through)
def blockType_down  = 2 ;Half-solid ceiling (can fall through)
def blockType_spike = 3 ;Spike
def blockType_acid  = 4 ;Acid
def blockType_shot  = 5 ;Shot block
def blockType_bomb  = 6 ;Bomb block
def blockType_save  = 7 ;Save pillar

; Samus' pose constants ($D020)
include "samus/samus_poseConstants.asm"


; charmaps
PUSHC

NEWCHARMAP creditsText
CHARMAP "<END>", $F0
CHARMAP "\n", $F1
CHARMAP "-", $5E
CHARMAP ":", $1B

; Standard ASCII characters
CHARMAP " ", $20
CHARMAP "A", $41
CHARMAP "B", $42
CHARMAP "C", $43
CHARMAP "D", $44
CHARMAP "E", $45
CHARMAP "F", $46
CHARMAP "G", $47
CHARMAP "H", $48
CHARMAP "I", $49
CHARMAP "J", $4A
CHARMAP "K", $4B
CHARMAP "L", $4C
CHARMAP "M", $4D
CHARMAP "N", $4E
CHARMAP "O", $4F
CHARMAP "P", $50
CHARMAP "Q", $51
CHARMAP "R", $52
CHARMAP "S", $53
CHARMAP "T", $54
CHARMAP "U", $55
CHARMAP "V", $56
CHARMAP "W", $57
CHARMAP "X", $58
CHARMAP "Y", $59
CHARMAP "Z", $5A

POPC

