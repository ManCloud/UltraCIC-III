#Caller Makefile to set Build variables on beforehand
#usage
#  "make attiny25" --> builds UltraCIC-III for attiny25
#  "make clean"    --> cleans all .hex/.obj files

attiny25: export CPU = attiny25
attiny25: export AVRDUDE_CPU = t25

attiny45: export CPU = attiny45
attiny45: export AVRDUDE_CPU = t45

attiny85: export CPU = attiny85
attiny85: export AVRDUDE_CPU = t85

attiny%: 
	+make -f UltraCIC-III.mk
	
clean:
	+make -f UltraCIC-III.mk clean