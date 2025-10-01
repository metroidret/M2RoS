# Original credit to Alex W and PJ

# Tool for extracting chr data into a binary file

import os


class GfxEntry:
    def __init__(self, gb_bank, gb_address, size, path):
        self.rom_address = (gb_bank * 0x4000) + (gb_address & 0x3fff)
        self.size = size
        self.path = "./SRC/" + path + ".chr"

gfx_list = [
    GfxEntry(0x5,0x5f34, 0xA00, "gfx/titleCredits/titleScreen"),
    GfxEntry(0x5,0x6934, 0x300, "gfx/titleCredits/creditsFont"),
    GfxEntry(0x5,0x6c34, 0x200, "gfx/titleCredits/itemFont"),
    GfxEntry(0x5,0x6e34, 0x100, "gfx/titleCredits/creditsNumbers"),
    GfxEntry(0x5,0x6f34, 0xF00, "gfx/titleCredits/creditsSprTiles"),
    GfxEntry(0x5,0x7e34, 0x100, "gfx/titleCredits/theEnd"),

    GfxEntry(0x6,0x4000,  0x20, "gfx/samus/cannonBeam"),
    GfxEntry(0x6,0x4020,  0x20, "gfx/samus/cannonMissile"),
    GfxEntry(0x6,0x4040,  0x20, "gfx/samus/beamIce"),
    GfxEntry(0x6,0x4060,  0x20, "gfx/samus/beamWave"),
    GfxEntry(0x6,0x4080,  0x20, "gfx/samus/beamSpazerPlasma"),
    GfxEntry(0x6,0x40a0,  0x70, "gfx/samus/spinSpaceTop"),
    GfxEntry(0x6,0x4110,  0x50, "gfx/samus/spinSpaceBottom"),
    GfxEntry(0x6,0x4160,  0x70, "gfx/samus/spinScrewTop"),
    GfxEntry(0x6,0x41d0,  0x50, "gfx/samus/spinScrewBottom"),
    GfxEntry(0x6,0x4220,  0x70, "gfx/samus/spinSpaceScrewTop"),
    GfxEntry(0x6,0x4290,  0x50, "gfx/samus/spinSpaceScrewBottom"),
    GfxEntry(0x6,0x42e0,  0x20, "gfx/samus/springBallTop"),
    GfxEntry(0x6,0x4300,  0x20, "gfx/samus/springBallBottom"),
    GfxEntry(0x6,0x4320, 0xB00, "gfx/samus/samusPowerSuit"),
    GfxEntry(0x6,0x4e20, 0xB00, "gfx/samus/samusVariaSuit"),
    GfxEntry(0x6,0x5920, 0x400, "gfx/enemies/enemiesA"),
    GfxEntry(0x6,0x5d20, 0x400, "gfx/enemies/enemiesB"),
    GfxEntry(0x6,0x6120, 0x400, "gfx/enemies/enemiesC"),
    GfxEntry(0x6,0x6520, 0x400, "gfx/enemies/enemiesD"),
    GfxEntry(0x6,0x6920, 0x400, "gfx/enemies/enemiesE"),
    GfxEntry(0x6,0x6d20, 0x400, "gfx/enemies/enemiesF"),
    GfxEntry(0x6,0x7120, 0x400, "gfx/enemies/arachnus"),
    GfxEntry(0x6,0x7520, 0x400, "gfx/enemies/surfaceSPR"),

    GfxEntry(0x7,0x4000, 0x800, "tilesets/plantBubbles"),
    GfxEntry(0x7,0x4800, 0x800, "tilesets/ruinsInside"),
    GfxEntry(0x7,0x5000, 0x800, "tilesets/queenBG"),
    GfxEntry(0x7,0x5800, 0x800, "tilesets/caveFirst"),
    GfxEntry(0x7,0x6000, 0x800, "tilesets/surfaceBG"),
    GfxEntry(0x7,0x6800, 0x530, "tilesets/lavaCavesA"),
    GfxEntry(0x7,0x6d30, 0x530, "tilesets/lavaCavesB"),
    GfxEntry(0x7,0x7260, 0x530, "tilesets/lavaCavesC"),
    GfxEntry(0x7,0x7790, 0x2C0, "gfx/items"),
    GfxEntry(0x7,0x7a50,  0x40, "gfx/itemOrb"),
    GfxEntry(0x7,0x7a90, 0x100, "gfx/commonItems"),
    
    GfxEntry(0x8,0x59bc, 0x400, "gfx/enemies/metAlpha"),
    GfxEntry(0x8,0x5dbc, 0x400, "gfx/enemies/metGamma"),
    GfxEntry(0x8,0x61bc, 0x400, "gfx/enemies/metZeta"),
    GfxEntry(0x8,0x65bc, 0x400, "gfx/enemies/metOmega"),
    GfxEntry(0x8,0x69bc, 0x800, "tilesets/ruinsExt"),
    GfxEntry(0x8,0x71bc, 0x800, "tilesets/finalLab"),
    GfxEntry(0x8,0x79bc, 0x500, "gfx/enemies/queenSPR"),
]

def extract():
    rom = open("./Metroid2.gb", "rb")
    for gfx in gfx_list:
        rom.seek(gfx.rom_address)
        chr = rom.read(gfx.size)
        with open(gfx.path, "wb") as f:
            f.write(chr)
    rom.close()

def clean():
    for gfx in gfx_list:
        if os.path.exists(gfx.path):
            os.remove(gfx.path)

# EoF
