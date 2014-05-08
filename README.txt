This document can also be found at:
 http://deadhacker.com/2010/02/03/jtag-enumeration/ 
authors and code branches:
 cyphunk  http://github.com/cyphunk/JTAGenum/
 jal2     http://github.com/jal2/JTAGenum/
 zoobab   http://new.hackerspace.be/JTAG_pinout_detector
 z1Y2x    https://github.com/z1Y2x/JTAGenum/

For questions, help, changes, repository write access or 
interesting targets: cyphunk@gmail.com with gpg 0x490F3380


Hardware
........

To use JTAGenum you need an arduino compatible microcontroller.
Arduino (http://arduino.cc/en/Main/Software) is a simple development
enviornment (IDE) for various microcontrollers. At the moment AVR
and PIC variants are available and can be purchased anywhere from
$10 to $50. Ive tested JTAGenum on the official Arduino Duemilanove
(http://arduino.cc/en/Main/ArduinoBoardDuemilanove), RBBB clone
(http://www.moderndevice.com/products/rbbb-kit) and Teensy++
(http://www.pjrc.com/teensy/index.html). When picking your
microcontroller platform consider two issues: 1. How many pins do
you want to check on your target. 2. what voltage level does your
target device require.  Concerning voltage most Arduinos work at 5
volts. Some are switchable but even those that are not can be
modified. For example revision 1.0 of the Teensy++ with over 30
pins of i/o can be modified by hand to operate at 3.3 volts. I show
where to cut lines and install a voltage regulator over here:
http://www.flickr.com/photos/deadhacker/4152517331/. For voltages
other than 3.3v and 5v there are a variety of solutions
(http://chiphacker.com/questions/622/bi-directional-step-up-and-step-down-3-3v-5-etc)
that depend on if you need uni-directional or bi-directional support
on your i/o lines.

When connecting the microcontroller to the pins of your target one
thing to be aware of is possible cross-talk between wires. Ive been
using a patch cable from Amontec that has a lot of cross talk.
JTAGenum has a mode that helps check for this which I will get into
more detail later.

It's a good idea to insert resistors into the wires to protect the output
drivers of both the Arduino and the investigated system. 400-800 Ohm should be fine.


Usage
.....

Download the JTAGenum code
(http://github.com/cyphunk/sectk/tree/master/often/JTAG/JTAGenum)
and open it in the Arduino IDE. The following needs to be changed
in the code depending on your microcontroller:

pins[] define which pins on the microcontroller are being used to
connect to the target pinname[] is a convent way to map the pins
to names which correspond to the names of pins on your target IR_LEN
defines the length of the JTAG instruction register. If you change
this you should also add 0s to each of the coresponding IR_**
instruction definitions. You can find the IR_LEN in the documentation
for your target. If you cannot find it just guess. (10 is the current
value, 8 is also common) Upload the sketch to your microcontroller
and open the serial console with a baud of 115200.  Sending a h to
the console will print usage information that describes each function.
Each function is enacted by sending the defined one character code:

v > verbose

Toggles verbose output. At times verbose might present too much
information or without it too little.

l > loopback check

Find loopback pairs that will generate false-positives for other
tests. After running you should remove any loopback pairs from your
pins[]/pinnames[]. Looback pairs are found by sending a predetermined
pattern[] to all possible pins while checking all pins for matching
output.  Because the JTAG clock (TCK) and state (TMS) pins are NOT
being stimulated the input/output pairs where the pattern is found
represent loopbacks. NOTE: you should probably run this once with
and without internal pull-up resistors set (r) to avoid problems
of cross-talk which is discussed in detail later.

s > scan

This routine is used to check all possible pins and find JTAG  clock,
state, input and output pins lines (TCK,TMS,TDI,TDO). This is done
by setting the JTAG state (TMS) into Shift_IR mode and then sending
pattern[] to TDI and checking for it on TDO while clocking TCK.
This check is run for every possible pin combination and it is
important that you remove loopback pins before running. While this
scan is meant to determine all of the JTAG pins required it is
possible that the  TMS pin found is incorrect.  This depends on if
the target uses the bypass register by default (described later).
If an IDCODE register is present then bypass mode is not the default
and you can assume that the pin this scan defines as TMS is correct.
Otherwise, only the TCK, TDI and TDO pins can be determined.  NOTE:
run with pull-ups on (r) as any cross-talk might result in
false-positives.

y > brute force IR search

This will set the instruction register (IR) to all possible values
and check the output. This can be used to find undocumented
instructions and examine their results via the data register (DR).
To run this scan you should have already determined the 4 JTAG pins
and define pins[] as such: [0]=TCK [1]=TMS [2]=TDO [3]=TDI.  NOTE:
run with pull-ups on (r) as any cross-talk might result in
false-positives.

x > boundary scan

This will return the state of all the pins on the target.  Actually
it is not just the pins but the contents of the scan/sample register.
This should be a rather large register and is defined in the code
by SCAN_LEN+100. You can check your targets documentation and specify
this or just leave it as a large number (currently 1800). To run
this scan you should have already determined the 4 JTAG pins and
define pins[] as such: [0]=TCK [1]=TMS [2]=TDO [3]=TDI.  NOTE: run
with pull-ups on (r) as any cross-talk might result in false-positives.

i > idcode scan

The JTAG standards specify that if an idcode register is present
it should be set as the default data register (DR) and attached to
output (TDO) by default. Meaning, regardless of the state of the
JTAG chip (set with TMS line) and regardless of input being sent
to the chip (TDI) by clocking the chip (TCK) it should return the
contents of the idcode to the output (TDO). Hence, this routine
iterates through all possible TCK,TDO pairs of pins and prints the
output when it changes (we assume an idcode will not be all 0s or
1s). You should examine the documentation of your target(s) to see
if the idcode matches. NOTE: run with pull-ups on (r) as any
cross-talk might result in false-positives.

b > shift_bypass

Broken atm (need to add TCK enumeration). The JTAG standards specify
that if and idcode register is NOT present on the chip then the
bypass register (length of 1) should be the default DR. Essentially
this means what is sent to the input (TDI) should come out on the
output (TDI) with a one clock delay (TCK). It is important that you
remove loopbacks before running this test otherwise the loopback
pins will look like valid JTAG lines. NOTE: run with pull-ups on
(r) as any cross-talk might result in false-positives.

r > set pull-up resistors & cross-talk

If like me the cables you use to connect between JTAGenum to your
targets are flimsy or uninsulated you might run into issues of
cross-talk whereby when one pin is transmitting a nearby pin picks
up the transmission even though they are not connected. To avoid
this you can turn on the internal pull-up resistors which will force
the pin to a default state. If for some reason you continue to have
sporadic issues run the following in sequence to check if the problem
is the cable, target or other:

	1. Disconnect the cables between your target and JTAGenum.
	Disconnected them entirely from JTAGenum as well.

	2. Run a loopback check (l) with pull-ups off. In this state
	the pins are in open mode and might fluctuate.  Youll notice
	that as you move the microcontroller around, turn lights
	on and off or move other devices close to or away from it
	that the results change.

	3. Turn on pull-ups (r) and run the test again. The results
	should now be consistent. If they arent, then let me know.

	4. Now attach your cables to JTAGenum but not the target.
	Run steps 2 and 3 again. Step 2 will give you a feel for
	how much inconsistency the cable may add. If the loopback
	check results in actual pattern matches then your cable has
	cross-talk. Step 3 should still result in a consistent state
	of either all high (1s) or all low (0s) and if it doesnt
	then your cross-talk issues are such that all JTAGenum tests
	are going to be buggy at best. Feel free to give me an email
	and I will happily try to help solve the problem.


A bit about JTAG
................

Basic understanding of how JTAG works will be helpful when using
JTAGenum. There are 4 lines/pins: TDO=output, TDI=input, TCK=clock,
TMS=state machine control.  Say you want to read the ID of the chip.
First you would send the IDCODE instruction to the instruction
register (IR). The JTAG controller then places the actual id code
value of the chip in a data register which you could then read out.
You would think that it would be enough to have one input line going
to the IR and one output coming from the DR but JTAG also supports
writing to the DR. As apposed to adding another input line specific
to the DR instead JTAG works by moving the input and output lines
between IR and DR. The TMS line is used to switch TDI/TDO to IR
when you want to place an instruction and back to DR when you want
to read or write data. With all operations, be it state change (TMS)
reading (TDI) or writing (TDO), the clock line must be cycled once
(TCK) for every bit or change. This was a brutal and drastic
simplification but with that understood reading the Usage section
should be comprehensible.
