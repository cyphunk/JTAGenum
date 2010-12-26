#!/usr/bin/python

import sys
import re

print "Given a bsdl file as input this will parse the INSTRUCTION_OPCODE"
print "list and output a TCL array that can be used in OpenOCD with the"
print "JTAG DR enumeration scripts.\n"

start = False
values = []
i = 0
for line in open(sys.argv[1]).readlines():
	if re.search('INSTRUCTION_OPCODE', line):
		start = True
		i = 0
		continue

	if re.search('attribute', line):
		start = False

	if start:
		m = re.search("\"\s*(\S+)\s+\(([01]+)\)", line)
		if m:
			name = m.group(1)
			val = m.group(2)
			print "\tset irlist(%d,\"name\")\t%s"%(i, name)
			print "\tset irlist(%d,\"hex\")\t%02x"%(i, int(val,2))
			print "\tset irlist(%d,\"dec\")\t%d"%(i, int(val,2))
			print "\tset irlist(%d,\"bin\")\t%s"%(i, val)
			i += 1

print "\tset irlistlen", i

print "\ncopy this into the irenumlist() function"
