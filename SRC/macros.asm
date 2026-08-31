; macros.asm

; Call a function in another bank
MACRO callFar
    ld a, BANK(\1)
    ld [bankRegMirror], a
    ld [rMBC_BANK_REG], a
    call \1
ENDM

; Jump to a function in another bank
MACRO jpLong
    ld a, BANK(\1)
    ld [bankRegMirror], a
    ld [rMBC_BANK_REG], a
    jp \1
ENDM

; Switch active bank to another bank (based off of label)
MACRO switchBank
    ld a, BANK(\1)
    ld [bankRegMirror], a
    ld [rMBC_BANK_REG], a
ENDM

; Switch to another bank (based off some other expression)
MACRO switchBankVar
    ld a, \1
    ld [bankRegMirror], a
    ld [rMBC_BANK_REG], a
ENDM


macro LengthDutyOptions ; [sound length], [wave duty]
    static_assert \1 < $40, "Invalid sound length"
    static_assert \2 < 4, "Invalid wave duty"
    
    db \1 | \2 << 6
endm

macro EnvelopeOptions ; [number of envelope sweeps], [envelope sweep direction], [initial envelope]
    static_assert \1 < 8, "Invalid number of envelope sweeps"
    static_assert \2 < 2, "Invalid envelope sweep direction"
    static_assert \3 < $10, "Invalid initial envelope"
    
    db \1 | \2 << 3 | \3 << 4
endm

macro DescendingEnvelopeOptions ; [number of envelope sweeps], [initial envelope]
    EnvelopeOptions \1, 0, \2
endm

macro AscendingEnvelopeOptions ; [number of envelope sweeps], [initial envelope]
    EnvelopeOptions \1, 1, \2
endm
    
macro FrequencyOptions ; [initial frequency], [sound stops flag]
    static_assert \1 < $800, "Invalid initial frequency"
    static_assert \2 < 2, "Invalid sound stops flag"
    
    dw \1 | \2 << $E | 1 << $F
endm

macro SweepOptions ; [number of sweeps], [sweep direction], [sweep time]
    static_assert \1 < 8, "Invalid number of sweeps"
    static_assert \2 < 2, "Invalid sweep direction"
    static_assert \3 < 8, "Invalid sweep time"
    
    db \1 | \2 << 3 | \3 << 4
endm

macro AscendingSweepOptions ; [number of sweeps], [sweep time]
    SweepOptions \1, 0, \2
endm

macro DescendingSweepOptions ; [number of sweeps], [sweep time]
    SweepOptions \1, 1, \2
endm

macro LengthOptions ; [sound length]
    static_assert \1 < $40, "Invalid sound length"
    
    db \1
endm

macro PolynomialCounterOptions ; [frequency mantissa], [counter width], [frequency exponent]
    static_assert \1 < 8, "Invalid frequency mantissa"
    static_assert \2 < 2, "Invalid counter width"
    static_assert \3 < $10, "Invalid frequency exponent"
    
    db \1 | \2 << 3 | \3 << 4
endm

macro CounterControlOptions ; [sound stops flag]
    static_assert \1 < 2, "Invalid sound stops flag"
    
    db \1 << 6 | 1 << 7
endm

macro WaveOptions ; [wave pattern data pointer], [volume], [unused]
    static_assert \1 < $10000, "Invalid wave pattern data pointer"
    static_assert \2 < 4, "Invalid volume"
    static_assert \3 < $20, "Invalid unused"
    
    dw \1
    db \2 << 5 | \3
endm

macro WaveOptionSet ; [volume], [frequency]
    static_assert \1 < 4, "Invalid volume"
    static_assert \2 < $800, "Invalid frequency"
    
    db $80, $00, \1 << 5
    dw \2 | $8000
endm

macro SongHeader ; [music note offset], [tempo table pointer], [tone/sweep channel pointer], [tone channel pointer], [wave channel pointer], [noise channel pointer]
    static_assert \1 < $100, "Invalid music note offset"
    static_assert \2 < $10000, "Invalid tempo table pointer"
    assert \3 < $10000, "Invalid tone/sweep channel pointer"
    assert \4 < $10000, "Invalid tone channel pointer"
    assert \5 < $10000, "Invalid wave channel pointer"
    assert \6 < $10000, "Invalid noise channel pointer"
    
    db \1
    dw \2, \3, \4, \5, \6
endm

macro SongEnd
    db $00
endm

macro SongRest
    db $01
endm

macro Echo1
    db $03
endm

macro Echo2
    db $05
endm

macro SongNote ; [note name in "[A-G]b?[2-7]" format]
    def _note   equs strslice(\1, 0, strlen(\1) - 1)
    def _octave equs strslice(\1, strlen(\1) - 1)
    
    def _i_octave equ _octave - 2
    static_assert _i_octave < 6, "Invalid note octave"
    
    if "{_note}" === "C"
        def _i_note equ 0
    elif "{_note}" === "Db"
        def _i_note equ 1
    elif "{_note}" === "D"
        def _i_note equ 2
    elif "{_note}" === "Eb"
        def _i_note equ 3
    elif "{_note}" === "E"
        def _i_note equ 4
    elif "{_note}" === "F"
        def _i_note equ 5
    elif "{_note}" === "Gb"
        def _i_note equ 6
    elif "{_note}" === "G"
        def _i_note equ 7
    elif "{_note}" === "Ab"
        def _i_note equ 8
    elif "{_note}" === "A"
        def _i_note equ 9
    elif "{_note}" === "Bb"
        def _i_note equ $A
    elif "{_note}" === "B"
        def _i_note equ $B
    else
        fail "Invalid note name"
    endc
    
    db (_i_octave * $C + _i_note + 1) * 2
    
    purge _note, _octave, _i_octave, _i_note
endm

macro SongNoiseNote ; [note index]
    static_assert \1 - songNoiseChannelOptionSets == LOW(\1 - songNoiseChannelOptionSets), "Invalid noise note index"
    db \1 - songNoiseChannelOptionSets
endm

macro SongNoteLength ; [note length index]
    static_assert \1 < $20, "Invalid note length index"
    db \1 | $A0
endm

def SongNoteLength_Hemidemisemiquaver     equs "SongNoteLength 0"
def SongNoteLength_Demisemiquaver         equs "SongNoteLength 1"
def SongNoteLength_Semiquaver             equs "SongNoteLength 2"
def SongNoteLength_Quaver                 equs "SongNoteLength 3"
def SongNoteLength_Crochet                equs "SongNoteLength 4"
def SongNoteLength_Minum                  equs "SongNoteLength 5"
def SongNoteLength_DottedSemiquaver       equs "SongNoteLength 6"
def SongNoteLength_DottedQuaver           equs "SongNoteLength 7"
def SongNoteLength_DottedCrochet          equs "SongNoteLength 8"
def SongNoteLength_TripletSemiquaver      equs "SongNoteLength 9"
def SongNoteLength_TripletQuaver          equs "SongNoteLength $A"
def SongNoteLength_Semihemidemisemiquaver equs "SongNoteLength $B"
def SongNoteLength_Semibreve              equs "SongNoteLength $C"

macro SongOptions
    db $F1
endm

macro SongTempo ; [tempo]
    static_assert \1 < $10000, "Invalid tempo"
    db $F2
    dw \1
endm

macro SongTranspose ; [transpose]
    static_assert \1 < $100, "Invalid transpose"
    db $F3
    db \1
endm

macro SongRepeatSetup ; [repetitions]
    static_assert \1 < $100, "Invalid number of repetitions"
    db $F4
    db \1
endm

macro SongRepeat
    db $F5
endm
