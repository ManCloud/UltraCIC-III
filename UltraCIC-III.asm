.if defined(attiny25)
.include "tn25def.inc"
.message "Build UltraCIC-III for ATtiny25"
.elif defined(attiny45)
.include "tn45def.inc"
.message "Build UltraCIC-III for ATtiny45"
.elif defined(attiny85)
.include "tn85def.inc"
.message "Build UltraCIC-III for ATtiny85"
.else
.warning "no suitable MCU specified"
.endif




;UltraCIC-III.asm
;N64 CIC clone!
;ATtiny85
;
;Author: jesgdev
;Credits:
;	ccsfp221-kammerstetter.pdf - Thanks to those authors!
;	KRIKzz - 710x dumps and testing.
;	saturnu - UltraCIC-II mix mode features.
;	ManCloud - UltraCIC-III - auto region change
;
; How-To change region: insert into console. If it doesn't boot, power off and power on again. Region is changed
;
;Pinout(references(direct, pad,  etc..) refer to the CIC footprint on a typical cart board).
;1: Reset, this is the actual /RST pin of AVR.  Pad is VCC.  Lift and jump or disconnect VCC from pad.
;2: CLKIN, unused pad, jumper to 11(cic pinout), cart edge #19
;3: ??, unused pad
;4: GND, unused pad, jump to nearby pad(last 3 in row are GND)
;5: CICPIN2_2, direct, tied to GND(always?)
;6: CICPIN2_1, direct, cart edge #43 (Data Clock)
;7: CICPIN2_0, direct, cart edge #18 (Data I/O)
;8: VCC, direct
;
;1 cic clock = 2 AVR clocks.  Clocks given in code are avr clocks.
;
;Programming the AVR:
;Fuses:
;/Reset enabled
;Disable debug wire
;disable watchdog
;disable bod(probably doesn't matter?)
;No clock div(default is div8, make sure to disable!)
;Fastest startup, external clock
;SUT=00
;CKSEL=0000
;
;tiny85
;LOW: 0xc0
;high: 0xdf


;------------------------------------------------
;Choose the CIC type(pick one):
;------------------------------------------------
.equ CIC_TYPE=0b0000	;6102
;.equ CIC_TYPE=0b0001	;6103
;.equ CIC_TYPE=0b0010	;6106
;.equ CIC_TYPE=0b0011	;6101
;.equ CIC_TYPE=0b0100	;6105
;.equ CIC_TYPE=0b0101	;6105
;.equ CIC_TYPE=0b0110	;6105
;.equ CIC_TYPE=0b0111	;6105
;.equ CIC_TYPE=0b1000	;7101
;.equ CIC_TYPE=0b1001	;7103
;.equ CIC_TYPE=0b1010	;7106
;.equ CIC_TYPE=0b1011	;7102
;.equ CIC_TYPE=0b1100	;7105
;.equ CIC_TYPE=0b1101	;7105
;.equ CIC_TYPE=0b1110	;7105
;.equ CIC_TYPE=0b1111	;7105
;------------------------------------------------

;registers
.def const0=r0
.def const1=r1
.def constF=r15
.def areg=r16           ;cic a register
.def xreg=r17           ;cic x register
.def flags=r18			;bit flags, descriptions below.
.def scr0=r22           ;scratch registers(scr2 & scr3 must be a 16bit pair)
.def scr1=r23
.def scr2=r24			;LSB of pair
.def scr3=r25			;MSB of pair

;ram, need 64 consecutive bytes...watch the stack!
.equ CICRAM_START=0x80

;I/O
.equ CICPINS=PINB
.equ CICPORT=PORTB
.equ CICDDR=DDRB
.equ CICPIN0=PINB2		;cic port2 pin0
.equ CICPIN1=PINB1		;cic port2 pin1
.equ CICPIN2=PINB0		;cic port2 pin2

;Flags(bit location of flag in flags register,  do not change these values)
.equ FLAG_x105_MODE=0			;0=x10x, 1=x105
.equ FLAG_M0112_M0132_MODE=1	;m0112 mode(see method for use)
.equ FLAG_710x_MODE=2			;0=610x, 1=710x

.cseg
.org 0x00
	rjmp reset

.org OVF0addr
	rjmp isr_tim0_ov

reset:

	;ATtiny85 reset delay=14clk

	;device setup, adapt as needed for device
	;default CIC pins to input with pullup
    nop
	ldi scr0, 0
	out DDRB, scr0			;inputs
	ldi scr0, 0xFF
	out PORTB, scr0			;with pullup
	ldi scr0, 0x0B
	out PRR, scr0			;power reduction - all but TIMER0
	ldi scr0, 0x80
	out ACSR, scr0			;comparator disable
	ldi scr0, LOW(RAMEND)	;STACK!  Make sure SPH is not needed for the part
	out SPL, scr0

	;setup death timer
	ldi scr0, 0x05
	out TCCR0B, scr0	;prescaler 1024
	LDI scr0, 0x02
	OUT TIMSK, scr0		;enable TIMER0 overflow interrupt
	;rjmp ucDeath
	
	;setup registers, memory, etc..
	ldi scr0, 0
	mov const0, scr0
    ldi scr0, 1
    mov const1, scr0
	ldi scr0, 0x0F
	mov constF, scr0
    ldi YH, 0
	ldi YL, CICRAM_START
	mov areg, const0
	mov flags, const0
	mov xreg, const0
	std Y+2, const0		;CICs seem to use this unitialzed?
	std Y+3, const0		;CICs seem to use this unitialzed?


	rcall EE_READ

	;setup key address
	in scr0, EEDR
	andi scr0, 0x08
	sbrc scr0, 3
	sbr flags, (1 << FLAG_710x_MODE)
	;sbrc scr0, 2
	;sbr flags, (1 << FLAG_x105_MODE)
	nop
	ori flags, (1 << FLAG_x105_MODE)
	lsl scr0
	lsl scr0
	lsl scr0
	ldi ZH, HIGH(CIC_KEY_DATA * 2)
    ldi ZL, LOW(CIC_KEY_DATA * 2)
	add ZL, scr0
	adc ZH, const0

	;79 ticks total(based on guesswork, up to 82 seems fine, signals match best @ 79) TODO: check real ticks consumed
	
;----------------------
; CIC implementation. |
;----------------------
	
    ;00:00 - 00:05(12clk)
cic_start:
    nop
	nop
	nop
	rcall ucWaste7
    ldi YL, CICRAM_START + 0x02
	set				;initial output state

    ;00:06 - 00:0E(mode0=10clk, mode1=12clk or death!)
    sbr flags, (1 << FLAG_M0112_M0132_MODE)
	;sbis CICPINS, CICPIN2
	nop
    rjmp cic_start_mode_0
cic_start_mode_1:
    rcall m0112		;in m0132 mode
    cbr flags, (1 << FLAG_M0112_M0132_MODE)
    nop
    nop
    nop
    brcs cic_start_mode_all
	rjmp ucDeath
cic_start_mode_0:
    ldi areg, 0
	clt				;initial output state
	cbr flags, (1 << FLAG_M0112_M0132_MODE)
    rcall m0112
    ;00:0F - 00:14(12clk)
cic_start_mode_all:
    clt
	sbrc flags, FLAG_710x_MODE
	set
    rcall m0106_skip2		;initial handshake, send (0 for 610x, 1 for 710x)
    clt
    rcall m0106		;0
    set
    rcall m0106		;1

    ;00:15-00:16(446clk, call to 03:00) + 00:17 - 00:19(6clk), (452clk total)
    ;Loads key from Bm=4 to 0:C-0:F in ram
	ldi YL, CICRAM_START + 0x0C
	ldi scr3, 2
	rcall ucLoadFromRom		;(2itr * 14) + 7 = 35 ticks
	ldi scr3, 134
	rcall ucWasteTicks      ;409 ticks
    rcall m022F
    ldi YL, CICRAM_START + 0x0A		;m022F screws the pointer, reset it.
	nop
    sei

    ;00:1A - 00:1D(8clk per iteration)
cic_start_commloop1:
    nop
    rcall m020F
    cli
    nop
    add YL, const1
    brhc cic_start_commloop1
    nop

    ;00:1E-00:1F(call to 03:06)
    ;Loads key from Bm=5-7 to 0:4-0:F in ram(644clk)
	dec YL							;backup one and store the value at 0:F for later
	ld areg, Y
	ldi YL, CICRAM_START + 0x04
	ldi scr3, 6
	rcall ucLoadFromRom				;(6itr * 14) + 7 = 91 ticks
	ldi scr3, 180
	rcall ucWasteTicks        		;547 ticks

    ;00:20 - 00:26(14clk)
    nop
    rcall m0622		;uses ram 0:2 unitialized??
    nop
    rcall m0220		;uses ram 0:3 unitialized??
	nop
	ldi YL, CICRAM_START
	nop
    rcall m0104
	
    ;00:27 - 00:2A(8clk per iteration)
cic_start_commloop2:
    nop
    rcall m020F
    nop
    add YL, const1
    brhc cic_start_commloop2
    nop

    ;00:2B - 00:2C(4clk)
    nop
    nop
    nop
    nop 	;CIC rom long jumps to 06:00, we just fall into it.

	;06:00 - 06:1A(392clk)
cic_ram_init:

;	0:0 = Leftover counter value, probably not important0
;	0:1 = ??, will be provided by console
;	0:2-0:F = Seed from 04:00 area(PAT instruction) LSB
;	1:0 = Unitialized
;	1:1 = Set to 0xB but will be provided by console
;	1:2-1:F = Seed from 04:00 area(PAT instruction) MSB
;	2:0-3:F = Unitialized(will be set to zero)
;	RAM(610x): E09A185A13E10DEC
;			   0B14F8B57CD61E98
;		       0000000000000000
;		       0000000000000000
;
;	RAM(710x): E04F51217198575A
;			   0B123F827198115C
;			   0000000000000000
;		       0000000000000000

	sbrc flags, FLAG_710x_MODE
	rjmp cic_ram_init_710x
	ldi ZH, HIGH(CIC_INITIAL_RAM_610x * 2)
    ldi ZL, LOW(CIC_INITIAL_RAM_610x * 2)
	rjmp cic_ram_init_load
cic_ram_init_710x:
	ldi ZH, HIGH(CIC_INITIAL_RAM_710x * 2)
    ldi ZL, LOW(CIC_INITIAL_RAM_710x * 2)
	nop
cic_ram_init_load:
	ldi YL, CICRAM_START
	ldi scr3, 16
	rcall ucLoadFromRom			;231, loads first two pages(low pages)
	ldi scr3, 16
cic_ram_init_zero_fill:			;80 ticks
	st Y+, const0
	dec scr3
	brne cic_ram_init_zero_fill
	nop							;80th tick
	ldi xreg, 0
	ldi YL, CICRAM_START + 1
	ldi scr3, 20
	rcall ucWasteTicks			;67 ticks
	nop
	nop

	;06:1B - 06:21(14clk)
cic_ram_init_2:
	nop
	rcall m0200
	st Y, scr3		;store result of m0200(0:1 from console)
	ori YL, 0x10
	rcall m0200
	st Y, scr3		;store result of m0200(1:1 from console)
	nop
	;nop	;CIC rom long jumps to 04:0E, we just fall into it.
	
;04:0E - 04:3B
;Main loop, must be 1 clock early on enter!	
m040E:
	rcall m0112
	brcc m040E_no_carry
	nop
	nop
	rcall m0112
	nop
	nop
	in scr0, SREG
	sbrs scr0, SREG_C
	rjmp m0700
	nop
	nop
	nop
	clh
	clc
	rjmp m031F
m040E_no_carry:
	nop
	rcall m0112
	in scr0, SREG
	sbrc scr0, SREG_C
	rjmp ucDeath
	nop
	andi YL, 0x0F
	ori YL, CICRAM_START
	rcall m0500
	rcall m0500
	rcall m0500
	andi YL, 0x0F
	ori YL, CICRAM_START + 0x10
	rcall m0500
	rcall m0500
	rcall m0500
	ldi YL, CICRAM_START + 0x17
	ld areg, Y
	ldi scr3, 1				;for ucWasteTicks
	rcall ucWasteTicks		;10(11 total including two ldi)
	nop
	nop
	
	;setup Z for loop depending on mode(610x vs 710x)
	sbrc flags, FLAG_710x_MODE
	rjmp m040E_710x_loop_mode
	ldi ZH, HIGH(m040E_loop_610x)
	ldi ZL, LOW(m040E_loop_610x)
	rjmp m040E_pre_loop
m040E_710x_loop_mode:
	ldi ZH, HIGH(m040E_loop_710x)
	ldi ZL, LOW(m040E_loop_710x)
	nop

m040E_pre_loop:
	andi areg, 0x0F
	cpse areg, const0
	add areg, constF
	inc areg
	andi areg, 0x0F
	andi YL, 0xF0
	or YL, areg
	ijmp			        ;jump to loop setup above

;loop for 610x mode, differs from 710x in 'loop_prep'
m040E_loop_610x:
	rcall m0112
	andi YL, 0x0F
	ori YL, CICRAM_START + 0x10
	ld scr0, Y
	set
	sbrs scr0, 0
	clt
	rcall m0106
	andi YL, 0x0F
	ori YL, CICRAM_START
	ld scr0, Y
	brcs m040E_carry_610x
	sbrs scr0, 0
	rjmp m040E_loop_prep_610x
	rjmp ucDeath
m040E_carry_610x:
	sbrs scr0, 0
	rjmp ucDeath
m040E_loop_prep_610x:
	nop
	nop
	add YL, const1
	brhc m040E_loop_610x	;1 tick early
	subi YL, 0x10			;decrement page(cic doesn't overflow into page)
	rjmp m040E				;1 tick early
	
;loop for 710x mode, differs from 610x in 'loop_prep'
m040E_loop_710x:
	rcall m0112
	andi YL, 0x0F
	ori YL, CICRAM_START + 0x10
	ld scr0, Y
	set
	sbrs scr0, 0
	clt
	rcall m0106
	andi YL, 0x0F
	ori YL, CICRAM_START
	ld scr0, Y
	brcs m040E_carry_710x
	sbrs scr0, 0
	rjmp m040E_loop_prep_710x
	rjmp ucDeath
m040E_carry_710x:
	sbrs scr0, 0
	rjmp ucDeath
m040E_loop_prep_710x:
	dec YL
	mov areg, YL
	andi areg, 0x0F
	brne m040E_loop_710x	;1 tick early
	nop
	rjmp m040E				;1 tick early
;end m040E

m0104:
    nop
    nop
	nop
    clt		;send 0
;end m0104, falls into m0106

;comm routine, send SREG_T bit, then 1 on CICPIN0
m0106:
    nop
    nop
m0106_skip2:
	nop
	sbic CICPINS, CICPIN1
	rjmp m0106				;wait for at 0
	in scr0, CICPORT
	bld scr0, CICPIN0
	out CICPORT, scr0		;output [0,1] depending on SREG_T
m0106_wait1:
	nop
	sbis CICPINS, CICPIN1
	rjmp m0106_wait1
	nop
	ldi areg, 1
	in scr0, CICPORT
	sbr scr0, (1 << CICPIN0)	;output 1
	out CICPORT, scr0
	ret
;end m0106

;comm routine, sets SREG_C depending on PIN0(switches dir)
m0112:
	in scr0, CICPORT
	in scr1, CICDDR
	sbrc scr1, CICPIN0		;if pin is output
	bst scr0, CICPIN0		;store output state(T preset on 1st call), always 1??
	sbr scr0, (1 << CICPIN0);pullup enabled
	cbr scr1, (1 << CICPIN0);input
	sec
	nop
	out CICDDR, scr1		;PIN0 to input
	out CICPORT, scr0		;with pullup
m0112_wait0:
	nop
	nop
	nop
	sbic CICPINS, CICPIN1
	rjmp m0112_wait0
	sbrc flags, FLAG_M0112_M0132_MODE
	rcall m0132_read_delay
	sbis CICPINS, CICPIN0	;test pin0
	clc
	nop
	in scr0, CICPORT
	in scr1, CICDDR
	bld scr0, CICPIN0
	sbr scr1, (1 << CICPIN0)
	out CICPORT, scr0		;restore port state
	out CICDDR, scr1		;set PIN0 back to output
	nop
	nop
m0112_wait1:
	nop
	sbis CICPINS, CICPIN1
	rjmp m0112_wait1
	ldi areg, 1
	ret
;end m0112

;delay used when calling m0112 in m0132 mode
m0132_read_delay:		;17clk including rcall + ret
	rcall ucWaste7
	nop
	nop
	nop
	ret
	
;comm routine reads a nybble from the console, result in scr3 on exit
m0200:	;30ticks(not including call)
	nop
m0200_29:	;29 tick version for m0700
	ldi scr3, 0x0F			;starting value
	nop
	rcall m0112				;@6ticks
	in scr0, SREG
	sbrs scr0, SREG_C
	cbr scr3, 0x08			;clear bit3
	rcall m0112				;@12ticks
	in scr0, SREG
	sbrs scr0, SREG_C
	cbr scr3, 0x04			;clear bit2
	rcall m0112				;@18ticks
	in scr0, SREG
	sbrs scr0, SREG_C
	cbr scr3, 0x02			;clear bit1
	rcall m0112				;@24ticks
	brcs m0200_skipbit0
	cbr scr3, 0x01			;clear bit0
m0200_skipbit0:
	ret
;end m0200

;sends a nybble via m0106
m020F:	;34clk(not including call)
    ld scr3, Y
    set
    sbrs scr3, 3
    clt
    ;this led stays on in case of error
    ;sbi DDRB, 0
    ;sbi PORTB, 0
    rcall m0106		;@8ticks
    nop
	nop
    set
    sbrs scr3, 2
    clt
    rcall m0106		;@16ticks
    nop
	nop
    set
    sbrs scr3, 1
    clt
    rcall m0106		;@24ticks
    nop
	nop
    set
    sbrs scr3, 0
    clt
    nop
    nop
	nop
    rjmp m0106		;@34ticks
;end m020F

m0220:	;14clk(not including call)
    nop
    rcall m022B
    subi YL, 0x10			;go back page
    rcall m022B
    subi YL, 0x10			;go back page
    rcall m022B
    subi YL, 0x10			;go back page
    nop
;end m0220, falls into m022B

m022B:
    ld areg, Y
    add YL, const1
    brhc m022B_work
    ret
m022B_work:
    nop
	inc areg
	ld scr0, Y
	add areg, scr0
	st Y, areg
	rjmp m022B
;end m022B

m022F:	;20clk(not including call)
	ldi YL, CICRAM_START + 0x0B
	ldi areg, 0x05
	st  Y, areg
	ldi areg, 0x0B
	st  -Y, areg
	rcall ucWaste7
	rcall m022B
	ldi YL, CICRAM_START + 0x0A		;reset pointer
	rjmp m022B
;end m022F

;03:1F - 03:3C, a long delay.
m031F:	;1083564clk(not including call)
	ldi areg, 0
	ldi xreg, 0
	ldi YL, CICRAM_START
	st Y, areg
	ldi YL, CICRAM_START + 0x10
	st Y, areg
	ldi scr3, 0
	ldi scr2, 0
	rcall ucBigWasteTicks	;262151
	rcall ucBigWasteTicks	;262151
	rcall ucBigWasteTicks	;262151
	rcall ucBigWasteTicks	;262151
	
	;1048614 used, 34950 remain.  Need 8 at exit, use 34942 more...
	ldi scr3, 0x22
	ldi scr2, 0x1D
	rcall ucBigWasteTicks	;34939
	nop
	
	;1083556 used, 8 remain.  Use 7 and last 1 is from 040E.
	nop
	nop
	rcall m0104
	rjmp m040E				;1 clk early for m040E sync
;end m031F

;05:00 - 05:23
;main hashing algorithm
m0500:
	ori YL, 0x0F
	ld areg, Y
	mov xreg, areg
m0500_loop:
	nop
	andi YL, 0xF0
	ori YL, 1
	ld scr0, Y
	sec
	adc areg, scr0
	st Y+, areg
	ld scr0, Y
	sec
	adc areg, scr0
	com areg
	st Y+, areg
	mov areg, scr0
	ld scr0, Y
	sec
	adc areg, scr0
	brhc m0500_noskip0
	nop
	nop
	nop
	nop
	rjmp m0500_skip0
m0500_noskip0:
	st Y+, areg
	mov areg, scr0
	ld scr0, Y
m0500_skip0:
	add areg, scr0
	st Y+, areg
	ld scr0, Y
	add areg, scr0
	st Y+, areg
	ld areg, Y
	ldi scr1, 8
	add scr0, scr1
	in scr1, SREG
	sbrs scr1, SREG_H
	add scr0, areg
	st Y+, scr0
	nop
m0500_inner_loop:
	inc areg
	ld scr0, Y
	add areg, scr0
	st Y, areg
	nop
	nop
	nop
	add YL, const1
	in scr1, SREG
	sbrs scr1, SREG_H
	rjmp m0500_inner_loop	;14clk per iteration
	subi YL, 0x10			;fix mem pointer(cic doesn't increment page on overflow)
	add xreg, constF
	brhs m0500_prep_next
	ret
m0500_prep_next:
	mov areg, xreg
	nop
	nop
	rjmp m0500_loop
;end m0500

;06:22 - 06:36
;Very strange setup method that uses unitialized ram??
;TODO: Take time and actually figure out what this does!
m0622:
	ldi YL, CICRAM_START + 0x02
	nop
	nop
m0622_loop0:
	mov scr0, areg		;a <==> x
	mov areg, xreg
	mov xreg, scr0
m0622_loop1:
	sbis CICPINS, CICPIN1
	rjmp m0622_done
	nop
	nop
	nop
	nop
	nop
	add areg, const1
	brhc m0622_loop1	;1clk late, target is 2nd half of cic clock
	mov scr0, areg		;a <==> x
	mov areg, xreg
	mov xreg, scr0
	add areg, const1
	brhc m0622_loop0
	nop
	ld scr0, Y
	add scr0, const1
	brhc m0622_prep_loop1_swap
	st Y, areg
	mov areg, scr0
	rjmp m0622_loop1	;1clk late, target is 2nd half of cic clock
m0622_prep_loop1_swap:
	st Y, scr0
	rjmp m0622_loop1	;1clk late, target is 2nd half of cic clock
m0622_done:
	ld scr0, Y
	add areg, scr0
	st -Y, xreg
	st -Y, areg
	mov xreg, scr0
	ret
;end m0622

;An odd method
;Operates in high mem(pages 2 & 3) which only exists on the 6105(zero on others)
;The 6105 has a modified version of m072C and an extra method at m0900
;I suspect this is never called on 610x cic??
m0700:
	ldi YL, CICRAM_START + 0x20
	ldi areg, 0x0A
	sbrs flags, FLAG_x105_MODE
	ldi areg, 0			;zero if not 6105
	st Y, areg
	nop
	nop
	nop
	rcall m020F
	nop
	rcall m020F
	mov areg, xreg
	ldi xreg, 0x0F
	nop
	nop
	nop
	nop
	nop
m0700_loop1:
	add xreg, constF
	brhc m0700_loop1_end
	nop
	nop
	nop
	nop
	rcall m0200
	sbrs flags, FLAG_x105_MODE
	ldi scr3, 0			;zero if 610x(ram is unimplemented and always returns 0)
	st Y+, scr3			;store result of m0200
	rcall m0200_29		;1 tick late, use special version
	sbrs flags, FLAG_x105_MODE
	ldi scr3, 0			;zero if 610x(ram is unimplemented and always returns 0)
	st Y, scr3			;store result of m0200
	add YL, const1
	brhc m0700_loop1
	nop
	nop
	ldi YL, CICRAM_START + 0x30
	rjmp m0700_loop1
m0700_loop1_end:
	nop
	rcall m072C
	ldi YL, CICRAM_START + 0x20
	mov areg, xreg
	ldi xreg, 0x0F
	nop
	nop
	nop
	nop
	rcall m0104
m0700_loop2:
	nop
	nop
	add xreg, constF
	brhc m0700_loop2_end
	rcall ucWaste7
	rcall m020F
	nop
	inc YL
	nop
	rcall m020F
	nop
	add YL, const1
	brhc m0700_loop2
	nop
	nop
	ldi YL, CICRAM_START + 0x30
	rjmp m0700_loop2
m0700_loop2_end:
	rjmp m040E			;1 tick early for m040E
;end m0700
	
m072C:
	ldi YL, CICRAM_START + 0x20
	mov areg, xreg
	ldi xreg, 0x0F
	sbrc flags, FLAG_x105_MODE
	rjmp m072C_6105
	nop
	
	;in 610x mode we just waste time, see CIC rom for actual implementation
	;the high pages of ram are not implemented
	;TODO: Are there any 64 nybble ram CIC beside 6105 that need this???
	ldi scr3, 0x6D
	rcall ucWasteTicks		;334 ticks
	ldi YL, CICRAM_START + 0x20
	ldi areg, 0x0F
	ldi xreg, 0
	ret		;348 ticks includes this(but not rcall)
	
m072C_6105:
	rcall ucWaste7
	nop
	nop
	nop
	ldi areg, 0x05
	set				;use SREG_T for carry in m0900
	;CIC TL to 0900 here, we just fall into it
	
;09:00 - 09:30
;6105 only!
;TODO: can cut this method size in half since its just an unrolled loop
m0900:
	nop
	nop
	nop
	add xreg, constF
	brhc m0900_end
	ld scr0, Y
	sbrs scr0, 0
	subi areg, -8
	st Y, areg
	mov areg, scr0
	ld scr0, Y
	sbrs scr0, 1
	subi areg, -4
	add areg, scr0
	st Y, areg
	mov scr0, areg
	in scr1, SREG
	sbrs scr1, SREG_T
	subi areg, -7
	add areg, scr0
	sec
	sbrs scr1, SREG_T
	clc
	adc areg, scr0
	in scr1, SREG 
	bst scr1, SREG_H			;store carry in T
	com areg
	st Y+, areg
	mov scr0, areg
	ld scr0, Y
	sbrs scr0, 0
	subi areg, -8
	st Y, areg
	mov areg, scr0
	ld scr0, Y
	sbrs scr0, 1
	subi areg, -4
	add areg, scr0
	st Y, areg
	mov scr0, areg
	in scr1, SREG
	sbrs scr1, SREG_T
	subi areg, -7
	add areg, scr0
	sec
	sbrs scr1, SREG_T
	clc
	adc areg, scr0
	in scr1, SREG 
	bst scr1, SREG_H			;store carry in T
	com areg
	st Y, areg
	mov scr0, areg
	add YL, const1
	nop
	ldi scr3, 5
	rcall ucWasteTicks			;22tick
	brhc m0900
	nop
	nop
	nop
	rjmp m0900
m0900_end:
	ret
;end m0900

;pass count in scr3, 0 for 256.
ucWasteTicks:		;uses (7 + (scr3 * 3)) ticks, including call(rcall)
    dec scr3		;doesn't affect SREG_C or SREG_H !!!
    brne ucWasteTicks
    nop
ucWaste7:			;rcall to use 7 ticks(rcall + ret)
    ret
;end ucWasteTicks & ucWaste7

;pass count in scr3:scr2(16bit word), 0 for 65536
ucBigWasteTicks:	;uses (7 + (scr3:scr2 * 4)) ticks, including call(rcall)
	sbiw scr3:scr2, 1
	brne ucBigWasteTicks
	nop
	ret
;end ucBigWasteTicks
	
;Z register should be setup
;Y register should be setup
;scr3 has the count in bytes(nybble count / 2).
ucLoadFromRom:	;uses (7 + (scr3 * 14)) ticks, including call(rcall)
	lpm scr1, Z+ 
    mov scr2, scr1
    swap scr2
    andi scr2, 0x0F
    st Y+, scr2
    andi scr1, 0x0F
    st Y+, scr1
	dec scr3
	brne ucLoadFromRom
    nop
    ret
;end ucLoadFromRom

isr_tim0_ov:
	rcall 	EE_READ		;read eeprom addr0

	in 		scr1, EEDR		;store eeprom data to scr1
	sbrc   	scr1, 3	       	;if bit 3 is clear, skip next line
 		ldi     scr0, 0x00  ;set scr0 to 0

	sbrs   	scr1, 3	       	;if bit 3 is set, skip next line
 		ldi    	scr0, 0x08  ;set scr0 to 8

EE_write:
    sbic    EECR, EEPE
    rjmp    EE_write

	ldi 	scr1, 0
	out 	EEARH, scr1
	out 	EEARL, scr1
    out     EEDR, scr0

    sbi     EECR,EEMPE
    sbi     EECR,EEPE

ucDeath:
	nop
	;sbi DDRB, 0
	;sbi PORTB, 0
forever:
	rjmp forever
	
;end ucDeath

EE_READ:
	sbic EECR, EEPE
	rjmp EE_READ

	ldi 	scr1, 0
	out 	EEARH, scr1
	out 	EEARL, scr1
	sbi EECR, EERE
ret


;end isr_tim0_ov
;Keys/Seeds stored as 16bit words, little-endian.
CIC_KEY_DATA:
	.dw 0x3F3F,0x36A5,0xF1C0,0x59D8		;6102
	.dw 0x7878,0x6F58,0x70D4,0x6798		;6103
	.dw 0x8585,0xBA2B,0xE6D4,0x74EB		;6106
	.dw 0x3F3F,0xCC45,0xEE73,0x7A31		;6101
	.dw 0x9191,0x1886,0x5BA4,0xD3C2		;6105		;repeated to allow detection on bit2(see init)
	.dw 0x9191,0x1886,0x5BA4,0xD3C2		;6105
	.dw 0x9191,0x1886,0x5BA4,0xD3C2		;6105
	.dw 0x9191,0x1886,0x5BA4,0xD3C2		;6105
	.dw 0x3F3F,0x36A5,0xF1C0,0x59D8		;7101
	.dw 0x7878,0x6F58,0x70D4,0x6798		;7103
	.dw 0x8585,0xBA2B,0xE6D4,0x74EB		;7106
	.dw 0x3F3F,0xCC45,0xEE73,0x7A31		;7102
	.dw 0x9191,0x1886,0x5BA4,0xD3C2		;7105
	.dw 0x9191,0x1886,0x5BA4,0xD3C2		;7105
	.dw 0x9191,0x1886,0x5BA4,0xD3C2		;7105
	.dw 0x9191,0x1886,0x5BA4,0xD3C2		;7105

CIC_INITIAL_RAM_610x:
	.dw 0x9AE0, 0x5A18, 0xE113, 0xEC0D, 0x140B, 0xB5F8, 0xD67C, 0x981E
	
CIC_INITIAL_RAM_710x:
	.dw 0x4FE0, 0x2151, 0x9871, 0x5A57, 0x120B, 0x823F, 0x9871, 0x5C11

.db "krikzz was here!"

.ESEG
.db 0x08	;set PAL as inital region
;.db 0x00	;set NTSC as initial region
