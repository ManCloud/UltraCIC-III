CC=avr-gcc
AS=avra
LD=$(CC)

PROJECT=UltraCIC-III
TARGET=$(PROJECT)_$(AVRDUDE_CPU)
VERSION=1.0

UISP=uisp -dprog=stk500 -dpart=$(CPU) -dserial=/dev/avr
FLAGS=-D $(CPU)
AVRDUDE=avrdude

PROGRAMMER=usbtiny

OBJS=$(PROJECT).obj


all: $(TARGET).hex

.Phony: clean %.obj
clean: 
	rm -f $(PROJECT)*.hex $(PROJECT)*.obj

	
$(TARGET).hex: $(PROJECT).asm
	$(AS)   $< $(FLAGS) -o $@

#
# FUSE low byte
#
# 7: CKDIV8   -> 1
# 6: CKOUT    -> 1
# 5: SUT1     -> 0
# 4: SUT0     -> 0
# 3: CKSEL3   -> 0
# 2: CKSEL2   -> 0
# 1: CKSEL1   -> 0
# 0: CKSEL0   -> 0
#
# FUSE high byte
#
# 7: RSTDISBL  -> 1
# 6: DWEN      -> 1
# 5: SPIEN     -> 0
# 4: WDTON     -> 1
# 3: EESAVE    -> 1
# 2: BODLEVEL2 -> 1
# 1: BODLEVEL1 -> 1
# 0: BODLEVEL0 -> 1
#

fuse:
	$(AVRDUDE) -p $(AVRDUDE_CPU) -P usb -c $(PROGRAMMER) -Uhfuse:w:0xdf:m -Ulfuse:w:0xc0:m

flash: $(HEXFILE)
	$(AVRDUDE) -p $(AVRDUDE_CPU) -P usb -c $(PROGRAMMER) -Uflash:w:$(PROJECT).hex

reset:
	$(AVRDUDE) -p $(AVRDUDE_CPU) -P usb -c $(PROGRAMMER)
