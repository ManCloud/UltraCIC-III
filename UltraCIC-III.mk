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
# 7: SPIEN    -> 0
# 6: EESAVE   -> 1
# 5: WDTON    -> 1
# 4: CKDIV8   -> 1
# 3: SUT1     -> 1
# 2: SUT0     -> 0
# 1: CKSEL1   -> 1
# 0: CKSEL0   -> 1
#
# FUSE high byte
#
# 7: RESERVED  -> 1
# 6: RESERVED  -> 1
# 5: RESERVED  -> 1
# 4: SELFPRGEN -> 1
# 3: DWEN      -> 1
# 2: BODLEVEL1 -> 1
# 1: BODLEVEL0 -> 1
# 0: RSTDISBL  -> 0
#

fuse:
	$(AVRDUDE) -p $(AVRDUDE_CPU) -P usb -c $(PROGRAMMER) -Uhfuse:w:0xfe:m -Ulfuse:w:0x7b:m -B 64.0 -F

flash: $(HEXFILE)
	$(AVRDUDE) -p $(AVRDUDE_CPU) -P usb -c $(PROGRAMMER) -Uflash:w:$(PROJECT).hex -B 64.0 -F

reset:
	$(AVRDUDE) -p $(AVRDUDE_CPU) -P usb -c $(PROGRAMMER) -B 64.0 -F
