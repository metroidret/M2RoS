import os

folder = "./SRC/maps/"

def byte_lines(data, per_row=16):
    data = [data[i:i+per_row] for i in range(0, len(data), per_row)]
    out = ""
    for line in data:
        out += "    db " + ", ".join([f"${byte:02X}" for byte in line]) + "\n"
    return out

def word_lines(data, per_row=16):
    data = [data[i+1]*256 + data[i] for i in range(0, len(data), 2)]
    data = [data[i:i+per_row] for i in range(0, len(data), per_row)]
    out = ""
    for line in data:
        out += "    dw " + ", ".join([f"${word:04X}" for word in line]) + "\n"
    return out

def create_map_bank_file(bank_data, bank_num):
    file_name = f"bank_{bank_num:03x}.asm"
    
    file_content = f"; Bank {bank_num:X} Level Data\n"
    file_content += ";  Extracted using extract_maps.py\n"
    file_content += f"SECTION \"ROM Bank ${bank_num:03X}\", ROMX[$4000], BANK[${bank_num:X}]"
    file_content += "\n; Screen Data Pointers\n\n"
    file_content += word_lines(bank_data[0x0000:0x0200])
    file_content += "\n; Scroll Data\n\n"
    file_content += byte_lines(bank_data[0x0200:0x0300])
    file_content += "\n; Room Transition Indexes\n\n"
    file_content += word_lines(bank_data[0x0300:0x0500])
    for s in range(0x0500, 0x4000, 0x0100):
        file_content += f"\n; Screen ${0x4000+s:04X}\n\n"
        file_content += byte_lines(bank_data[s:s+0x0100])
    file_content += "\n"
    
    with open(os.path.join(folder, file_name), "w") as f:
        f.write(file_content)

def extract():
    rom = open("./Metroid2.gb", "rb")
    for bank_num in range(0x9, 0xF+1):
        rom.seek(bank_num * 0x4000)
        bank_data = rom.read(0x4000)
        create_map_bank_file(bank_data, bank_num)
    rom.close()

def clean():
    for bank_num in range(0x9, 0xF+1):
        file_path = os.path.join(folder, f"bank_{bank_num:03x}.asm")
        if os.path.exists(file_path):
            os.remove(file_path)

# EoF
