import os
import importlib
modules = [importlib.import_module("scripts." + m) for m in [
    "extract_chr",
    "extract_maps",
    "extract_credits",
    "extract_doors",
    "extract_enemyData",
]]


print('Removing previous resources from disassembly')
for module in modules:
    module.clean()
print('Success\n')

print('Extracting resources from vanilla ROM')
if not os.path.exists("./Metroid2.gb"):
    print('Vanilla ROM file ./Metroid2.gb was not found')
    exit()
for module in modules:
    module.extract()
print('Success')
