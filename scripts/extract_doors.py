# Original credit to Alex W and PJ
import os

file_path = "./SRC/maps/doors.asm"

gb2rom = lambda gb_bank, gb_address: (gb_bank * 0x4000) + (gb_address & 0x3fff)

# Source Pointers
pointer_src_dict = {
    gb2rom(0x6,0x5920): "gfx_enemiesA",
    gb2rom(0x6,0x5D20): "gfx_enemiesB",
    gb2rom(0x6,0x6120): "gfx_enemiesC",
    gb2rom(0x6,0x6520): "gfx_enemiesD",
    gb2rom(0x6,0x6920): "gfx_enemiesE",
    gb2rom(0x6,0x6D20): "gfx_enemiesF",
    gb2rom(0x6,0x7120): "gfx_arachnus",
    gb2rom(0x6,0x7520): "gfx_surfaceSPR",
    gb2rom(0x7,0x4000): "gfx_plantBubbles",
    gb2rom(0x7,0x4800): "gfx_ruinsInside",
    gb2rom(0x7,0x5000): "gfx_queenBG",
    gb2rom(0x7,0x5800): "gfx_caveFirst",
    gb2rom(0x7,0x6000): "gfx_surfaceBG",
    gb2rom(0x7,0x6800): "gfx_lavaCavesA",
    gb2rom(0x7,0x6D30): "gfx_lavaCavesB",
    gb2rom(0x7,0x7260): "gfx_lavaCavesC",
    gb2rom(0x7,0x7A90): "gfx_commonItems",
    gb2rom(0x8,0x4000): "bg_queenHead.row1",
    gb2rom(0x8,0x4020): "bg_queenHead.row2",
    gb2rom(0x8,0x4040): "bg_queenHead.row3",
    gb2rom(0x8,0x4060): "bg_queenHead.row4",
    gb2rom(0x8,0x59BC): "gfx_metAlpha",
    gb2rom(0x8,0x5DBC): "gfx_metGamma",
    gb2rom(0x8,0x61BC): "gfx_metZeta",
    gb2rom(0x8,0x65BC): "gfx_metOmega",
    gb2rom(0x8,0x69BC): "gfx_ruinsExt",
    gb2rom(0x8,0x71BC): "gfx_finalLab",
    gb2rom(0x8,0x79BC): "gfx_queenSPR",
}

# Destination Pointers
pointer_dest_dict = {
    0x8B00: "vramDest_enemies",
    0x8F00: "vramDest_commonItems",
    0x9C00: "_SCRN1",
    0x9C20: "(_SCRN1+$20)",
    0x9C40: "(_SCRN1+$40)",
    0x9C60: "(_SCRN1+$60)"
}


def extract():
    rom = open("./Metroid2.gb", "rb")
    rom_read = lambda n: int.from_bytes(rom.read(n), byteorder='little')
    door_pointers_begin = gb2rom(0x5,0x42E5)
    door_data_begin = gb2rom(0x5,0x46E5)
    door_end = gb2rom(0x5,0x55A3)
    freespace = gb2rom(0x5,0x7F34)
    
    door_pointers = []
    #Read doors and give each a name
    rom.seek(door_pointers_begin)
    i = 0
    while rom.tell() < door_data_begin:
        temp = gb2rom(0x5,rom_read(2))
        label = f"door{i:03X}"
        if temp == freespace:
            label = "bank5_freespace"
        door_pointers.append([temp, label])
        i += 1
    
    file_content = ""
    #Write the doorPointerTable with label names
    for row in [door_pointers[i:i+16] for i in range(0, len(door_pointers), 16)]:
        file_content += "    dw " + ", ".join([item[1] for item in row]) + "\n"
    file_content += "\n"
    
    door_pointers.sort(key=lambda ptr: ptr[0])
    
    rom.seek(door_data_begin)
    while True:
        if rom.tell() == door_pointers[0][0]:
            file_content += "\n"
            while rom.tell() == door_pointers[0][0]:
                ptr = door_pointers.pop(0)
                file_content += ptr[1] + ":\n"
        
        if rom.tell() >= door_end:
            break
        
        door_opcode = rom_read(1)
        if door_opcode >> 4 == 0x0:
            src_label = pointer_src_dict[gb2rom(rom_read(1),rom_read(2))]
            dest_label = pointer_dest_dict[rom_read(2)]
            move_length = rom_read(2)
            macro_name = ["COPY_DATA", "COPY_BG", "COPY_SPR"][door_opcode & 0x0F]
            file_content += f"    {macro_name} {src_label}, {dest_label}, ${move_length:04X}\n"
        elif door_opcode >> 4 == 0x1:
            tiletable = door_opcode & 0x0F
            file_content += f"    TILETABLE ${tiletable:X}\n"
        elif door_opcode >> 4 == 0x2:
            collision = door_opcode & 0x0F
            file_content += f"    COLLISION ${collision:X}\n"
        elif door_opcode >> 4 == 0x3:
            solidity = door_opcode & 0x0F
            file_content += f"    SOLIDITY ${solidity:X}\n"
        elif door_opcode >> 4 == 0x4:
            warp_bank = door_opcode & 0x0F
            warp_pos = rom_read(1)
            file_content += f"    WARP ${warp_bank:X}, ${warp_pos:02X}\n"
        elif door_opcode >> 4 == 0x5:
            file_content += "    ESCAPE_QUEEN\n"
        elif door_opcode >> 4 == 0x6:
            damage_acid = rom_read(1)
            damage_spike = rom_read(1)
            file_content += f"    DAMAGE ${damage_acid:02X}, ${damage_spike:02X}\n"
        elif door_opcode >> 4 == 0x7:
            file_content += "    EXIT_QUEEN\n"
        elif door_opcode >> 4 == 0x8:
            enter_bank = door_opcode & 0x0F
            scroll_y = rom_read(2)
            scroll_x = rom_read(2)
            samus_y = rom_read(2)
            samus_x = rom_read(2)
            file_content += f"    ENTER_QUEEN ${enter_bank:X}, ${scroll_y:04X}, ${scroll_x:04X}, ${samus_y:04X}, ${samus_x:04X}\n"
        elif door_opcode >> 4 == 0x9:
            met_num = rom_read(1)
            trans_index = rom_read(2)
            file_content += f"    IF_MET_LESS ${met_num:02X}, ${trans_index:04X}\n"
        elif door_opcode >> 4 == 0xA:
            file_content += "    FADEOUT\n"
        elif door_opcode >> 4 == 0xB:
            src_label = pointer_src_dict[gb2rom(rom_read(1),rom_read(2))]
            macro_name = [None, "LOAD_BG", "LOAD_SPR"][door_opcode & 0x0F]
            file_content += f"    {macro_name} {src_label}\n"
        elif door_opcode >> 4 == 0xC:
            song_index = door_opcode & 0x0F
            file_content += f"    SONG ${song_index:X}\n"
        elif door_opcode >> 4 == 0xD:
            item_index = door_opcode & 0x0F
            file_content += f"    ITEM ${item_index:X}\n"
        elif door_opcode == 0xFF:
            file_content += "    END_DOOR\n"
    
    rom.close()
    
    with open(file_path, "w") as f:
        f.write(file_content)

def clean():
    if os.path.exists(file_path):
        os.remove(file_path)

# EoF
