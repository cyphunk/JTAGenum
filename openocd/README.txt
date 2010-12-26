These scripts can be used within OpenOCD to enumerate the Instruction
Register. Include in openocd.cfg with:
    script "irenumerate.tcl"

"irenum" function iterates through a range of possible instruction
registers.

"irenumlist" uses a list of instruction registers. This list can be 
generated with the "bsdltoscanarray.py" script.

Detail:
   irenum <tap> <IRmax>
	tap    = the name of the JTAG TAP as defined in OpenOCD config
	IRmax  = the last instruction register (hex) you want checked
	         code will loop from IR=0 to IR=IRmax

   irenumlist <tap>
	a list must first be generated of all the IR's to be attempted.
	For example, if you have the BSDL file for the target chip, it
	should contain a list of IR's.  The bsdltoscanarray.py script
	can be used to parse the BSDL IR list into an array that can be
	copied into the irenumlist code.

	sampleloop <tap> <IR> <drlen> <iterations>
		provided the SAMPLE (boundary scan) IR code will read the
		boundary scan register (length defined by drlen) N times 
	(defined by iterations)
