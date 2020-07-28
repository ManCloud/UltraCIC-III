# UltraCIC-III
This code allows you to create a replacement CIC chip for N64 games that you own on an ATTiny25, ATTiny45 of ATTiny85. 
The original code was written by jesgdev and updated with multi-region support by saturnu. 
I simply extended the version Krikzz created under the name UltraCIC-II to support automatic switching between NTSC and PAL if the console was unable to boot.

# Instructions
- Install avra 
- Assemble the code
  - avra UltraCIC-III.asm -d {MCU}
  - {MCU} must be one of the supported MCUs (attiny25, attiny45 or attiny85)
- Flash the file to your ATTiny 
  - e.g.: "avrdude -p t25 -c usbtiny -U flash:w:UltraCIC-III.hex eeprom:w:UltraCIC-III.hex.eep" for attiny25
- Update fuses
  - e.g.: "avrdude -p t25 -c usbtiny -U lfuse:w:0xc0:m -U hfuse:w:0xdf:m" for attiny25
  
# More Information
[Sources for UltraCIC-II](https://web.archive.org/web/20180701050159/https://krikzz.com/pub/support/everdrive-64/ultracic2/)

[Multi-region patch information](https://krikzz.com/forum/index.php?topic=3450.0)

[Assembly guide by perkinsb1024](https://bitwise.bperki.com/2019/01/12/repairing-an-n64-cartridge-without-blowing-in-it/)
