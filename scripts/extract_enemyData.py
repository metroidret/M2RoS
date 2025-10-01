# Original credit to Alex W and PJ
import os

file_path = "./SRC/maps/enemyData.asm"

gb2rom = lambda gb_bank, gb_address: (gb_bank * 0x4000) + (gb_address & 0x3fff)


def extract():
    rom = open("./Metroid2.gb", "rb")
    rom_read = lambda n: int.from_bytes(rom.read(n), byteorder='little')
    enemy_pointers_begin = gb2rom(0x3,0x42E0)
    enemy_data_begin = gb2rom(0x3,0x50E0)
    enemy_end = gb2rom(0x3,0x6244)
    file_content = ""
    
    #Read enemy pointers and give each a name
    enemy_pointers = {}
    enemy_pointers_bank = []
    rom.seek(enemy_pointers_begin)
    bank = 9
    x = 0
    y = 0
    while rom.tell() < enemy_data_begin:
        temp = gb2rom(0x3,rom_read(2))
        enemy_pointers_bank.append([temp, "enemyBank{:X}_{:X}{:X}".format(bank,y,x)])
        x += 1
        if x == 0x10:
            x = 0
            y += 1
            if y == 0x10:
                y = 0
                enemy_pointers[bank] = enemy_pointers_bank
                enemy_pointers_bank = []
                bank += 1
    
    #Write the enemyPointerTable with label names
    for bank, enemy_pointers_bank in enemy_pointers.items():
        file_content += f"; Enemy Data Pointers for Bank {bank:X}\n"
        for row in [enemy_pointers_bank[i:i+16] for i in range(0, len(enemy_pointers_bank), 16)]:
            file_content += "    dw " + ", ".join([d[1] for d in row]) + "\n"
        file_content += "\n"

    # Read the enemy data
    enemy_pointers = [d for enemy_pointers_bank in enemy_pointers.values() for d in enemy_pointers_bank]
    enemy_pointers.sort(key=lambda ptr: ptr[0])
    enemy_pointers.append([-1, ""])
    
    file_content += "\n\n; Enemy Data for Banks 9-F\n; <spawn number>, <sprite type>, <X>, <Y>\n"
    rom.seek(enemy_data_begin)
    while rom.tell() < enemy_end:
        if rom.tell() == enemy_pointers[0][0]:
            file_content += "\n"
            while rom.tell() == enemy_pointers[0][0]:
                ptr = enemy_pointers.pop(0)
                file_content += ptr[1] + ":\n"
        
        byte1 = rom_read(1)
        line = f"    db ${byte1:02X}"
        if byte1 != 0xFF:
            byte2 = rom_read(1)
            byte3 = rom_read(1)
            byte4 = rom_read(1)
            line += f", ${byte2:02X}, ${byte3:02X}, ${byte4:02X}"
        file_content += line + "\n"
    
    with open(file_path, "w") as f:
        f.write(file_content)

def clean():
    if os.path.exists(file_path):
        os.remove(file_path)

# EoF
