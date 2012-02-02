#
# enumerate the IR/DR pairs
#
# include in openocd.cfg with:
#    script "irenumerate.tcl"
#
# main functions are:
#    irenum <tap> <IRmax>
#	tap    = the name of the JTAG TAP as defined in OpenOCD config
#	IRmax  = the last instruction register (hex) you want checked
#	         code will loop from IR=0 to IR=IRmax
#
#    irenumlist <tap>
#	a list must first be generated of all the IR's to be attempted.
#       For example, if you have the BSDL file for the target chip, it
#       should contain a list of IR's.  The bsdltoscanarray.py script
#       can be used to parse the BSDL IR list into an array that can be
#       copied into the irenumlist code.
#
#	sampleloop <tap> <IR> <drlen> <iterations>
#		provided the SAMPLE (boundary scan) IR code will read the
#		boundary scan register (length defined by drlen) N times 
#       (defined by iterations)
#


set padlen 800
# padlen = default max length to shift through
proc drlen { tap IR } {
    global padlen
	irscan $tap $IR -endstate IRPAUSE

	#puts "putting padding in DR"
	for {set i 0} {$i < $padlen} {set i [expr $i+1]} {
		drscan $tap 1 1 -endstate DRPAUSE	
	}

	#puts "shifting through 0"
	for {set i 0} {$i < $padlen} {set i [expr $i+1]} {
		if [ drscan $tap 1 0 -endstate DRPAUSE ] {
			#puts "returned 1"
		} else {
			#puts "returned 0"
			break
		}
	}

	if { $i >= $padlen } {
		puts [format "%02x: %d+\t\t\tdeadnotfound" $IR $i]
	} elseif { $i == 0 } {
		puts [format "%02x: %d\t\t\treadonlyoridle" $IR $i]
		# test read
		irscan $tap $IR -endstate IRPAUSE
		set ret [ drscan $tap $padlen 0 -endstate DRPAUSE ] 
		if ![ isall0or1 $ret ] {
			puts "                         1/3 read $padlen bits:" 
			putspad $ret 64 25
		}
		# test write
	####irscan $tap $IR -endstate IRPAUSE
	####set ret [ drscan $tap $padlen 0xDEAD -endstate DRPAUSE ]
	####if ![ isall0or1 $ret ] {
	####	puts "                         2 readwrite 0xdead:" 
	####	putspad $ret 64 25
	####}
		# test read
		irscan $tap $IR -endstate IRPAUSE
		set ret [ drscan $tap $padlen 0 -endstate DRPAUSE ] 
		if ![ isall0or1 $ret ] {
			puts "                         3 read $padlen bits:" 
			putspad $ret 64 25
		}
	} elseif { $i == 1 } {
		puts [format "%02x: %d\t\t\tbypass" $IR $i]
	} elseif { $i == 32 } {
		puts [format "%02x: %d\t\t\tidcode?" $IR $i]
		# test write
	####irscan $tap $IR -endstate IRPAUSE
	####set ret [ drscan $tap 32 0xDEAD -endstate DRPAUSE ]
	####if ![ isall0or1 $ret ] {
	####	puts "                         1/2 readwrite 0xdead:  $ret" 
	####}
		# test read
		irscan $tap $IR -endstate IRPAUSE
		set ret [ drscan $tap 32 0 -endstate DRPAUSE ]
		if ![ isall0or1 $ret ] {
			puts "                         2 read 32:             $ret"
		}
	} else {
		puts [format "%02x: %d" $IR $i]
		# test write
	####irscan $tap $IR -endstate IRPAUSE
	####set ret [ drscan $tap $i 0xDEAD -endstate DRPAUSE ]
	####if ![ isall0or1 $ret ] {
	####	puts "                         1/2 readwrite 0xdead:  $ret" 
	####}
		# test read
		irscan $tap $IR -endstate IRPAUSE
		set ret [ drscan $tap $i 0 -endstate DRPAUSE ]
		if ![ isall0or1 $ret ] {
			puts "                         2 read $i:"
			putspad $ret 64 25
		}
	}
}

# pass ir max (its IRLEN ** 2)
proc irenum { tap irmax } {
	puts "IR: drlen\t\t\tinfo"
	puts "---------\t\t\t------------------"
	for {set i 0} {$i < $irmax } {set i [expr $i+1]} {
		drlen $tap $i
	}
}

proc putspad { str width padding } {
	set len [string length $str]
	for {set i 0} {$i < $len} {set i [expr $i+$width]} {
		set endchar [expr $i+$width]
		set s [ string range $str $i $endchar]
		set linewidth [expr $padding + $width]
		puts -nonewline [format "%*s" $padding " "]
		puts $s
	}
}
proc isall0or1 { str } {
		set zeros [string repeat 0 [string length $str]]
		set ones [string repeat 1 [string length $str]]
		if [string match $zeros $str ] {
			return 1
		} 
		if [string match $ones $str ] {
			return 1
		} 
		return 0
}

proc sampleloop {tap IR drlen iterations} {
	for {set i 0} {$i < $iterations} {set i [expr $i+1]} {
		irscan $tap $IR -endstate IRPAUSE
		set ret [ drscan $tap $drlen 0 -endstate DRPAUSE ]
		puts "$i "
		puts $ret
	}
}
# 
# use defined Array of IR OPCODES parsed from BSDL:
# use bsdltoscanarray.py to generate
#
proc irenumlist { tap } {
	puts "filtered ir list"

	# example (replace with output from .py script):
	#set irlistlen 2
	#set irlist(0,"dec")	1	
	#set irlist(1,"dec")	2

	puts "name                 IR: drlen\t\t\tinfo"
	puts "------------------   ---------\t\t\t------------------"
	for {set i 0} {$i < $irlistlen } {set i [expr $i+1]} {
		puts -nonewline [format "%-20s " $irlist($i,"name")]
		set ret [ drlen $tap $irlist($i,"dec") ]
	}
}

