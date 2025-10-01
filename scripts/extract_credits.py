# Original credit to Alex W and PJ
import os

file_path = "./SRC/data/credits.asm"

def parse_credits_line(line_data):
    for i in range(len(line_data)):
        if line_data[i] == 0x5E: # Dashes aren't ^s
            line_data[i] = "-"
        elif line_data[i] == 0x1B: # Colon for time
            line_data[i] = ":"
        elif line_data[i] > 0x20 and line_data[i] < 0x30: # For the "The End" tilemap
            pass
        else:
            line_data[i] = bytearray([line_data[i]]).decode()
    
    for i in range(len(line_data)-1, 0, -1):
        if type(line_data[i-1]) is str and type(line_data[i]) is str:
            line_data[i-1] += line_data.pop(i)
    
    for i in range(len(line_data)):
        if type(line_data[i]) is str:
            line_data[i] = '"' + line_data[i] + '"'
        else:
            line_data[i] = f"${line_data[i]:02X}"
    
    return '    db ' + ",".join(line_data) + "\n"

def extract():
    rom = open("./Metroid2.gb", "rb")
    credits_begin = (0x6 * 0x4000) + (0x7920 & 0x3fff)
    rom.seek(credits_begin)
    
    file_content = "; Credits text - 06:7920\nSETCHARMAP creditsText\n\n"
    temp = rom.read(1)[0]
    while temp != 0xF0:
        if temp == 0xF1: # Newline
            file_content += '    db "\\n"\n'
        else:
            rom.seek(rom.tell()-1) # Undo the previous read (because we don't have goto)
            file_content += parse_credits_line(list(rom.read(20)))
        temp = rom.read(1)[0]
    rom.close()
    file_content += '    db "<END>"'
    
    with open(file_path, "w") as f:
        f.write(file_content)

def clean():
    if os.path.exists(file_path):
        os.remove(file_path)

# EoF
