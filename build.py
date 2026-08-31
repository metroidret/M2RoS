import os
import subprocess
import hashlib
from scripts import enemy_csv2asm
from scripts import samus_csv2asm
from scripts import general_csv2asm

def run_or_exit(args, err):
    completed_process = subprocess.run(args, shell=True)
    if completed_process.returncode != 0:
        print("\n" + err + "\n")
        exit(completed_process.returncode)


def main():
    if not os.path.exists('out/'):
        os.mkdir('out/')

    print('Running scripts')
    enemy_csv2asm.csv2asm("SRC/data/enemies.csv", "SRC/data")
    samus_csv2asm.csv2asm("SRC/samus/samus.csv", "SRC/samus")
    general_csv2asm.csv2asm("SRC/data/sprites_credits.csv","SRC/data","sprites_credits")
    general_csv2asm.csv2asm("SRC/data/sprites_samus.csv","SRC/data","sprites_samus")
    print('Success\n')

    completed_process = subprocess.run("rgbasm -V", shell=True)
    if completed_process.returncode != 0:
        print("RGBDS not detected. Downloading...")
        run_or_exit("curl -LJO \"https://github.com/gbdev/rgbds/releases/download/v1.0.1/rgbds-win32.zip\"", "Failed to download.")
        run_or_exit("tar -xvf rgbds-win32.zip", "Failed to extract RGBDS archive.")
        run_or_exit("rgbasm -V", "Unable to use downloaded RGBDS.")

    print('RGBDS detected')
    print('Assembling .asm files')
    run_or_exit("rgbasm -o out/game.o -Weverything -I SRC/ SRC/game.asm", "Assembler Error.")
    print('Success\n')

    print('Linking .o files')
    run_or_exit("rgblink -n out/M2RoS.sym -Weverything -m out/M2RoS.map -o out/M2RoS.gb out/game.o", "Linker Error.")
    print('Success\n')

    print('Writing header')
    run_or_exit("rgbfix -v -t METROID2 -l 0x01 -m MBC1+RAM+BATTERY -r 0x02 -p 0x00 -j out/M2RoS.gb", "RGBFIX Error.")
    print('Done\n')

    with open("out/M2RoS.gb", "rb") as f:
        md5_hash_generated = hashlib.md5(f.read())
    print('MD5 hash: ' + md5_hash_generated.hexdigest())

    try:
        with open("Metroid2.gb", "rb") as f:
            md5_hash_expected = hashlib.md5(f.read())
        if md5_hash_generated.hexdigest() == md5_hash_expected.hexdigest():
            print("Hash matches vanilla ROM.")
        else:
            print("Hash does not match vanilla ROM.")
    except FileNotFoundError:
        print("Could not check hash against vanilla ROM.")


if __name__ == "__main__":
    main()
