/*
 JTAGenum
 Given a Arduino compatible microcontroller JTAGenum scans
 pins[] for basic JTAG functionality. After programming 
 your microcontroller open a serial terminal with 115200 
 baud and send 'h' to see usage information. 
 
 SETUP:
 Define the pins[] and pinnames[] map of pin names to pins 
 you want to scan with. If you are using a 3.3v board 
 uncomment the CPU_PRESCALE defintions at the top and in 
 the setup() function.
 
 If you plan to use IDCODE, Boundary or IR scan routines
 define the IR_IDCODE, IR_SAMPLE+SCAN_LEN and 
 IR_LEN+CHAIN_LEN values according to suspected or 
 documented values.
 
 Further documentation:
 http://deadhacker.com/2010/02/03/jtag-enumeration/ 
 
 
 AUTHORS & CODE BRANCHES:
 cyphunk  http://github.com/cyphunk/JTAGenum/
 jal2	  http://github.com/jal2/JTAGenum/
 zoobab	  http://new.hackerspace.be/JTAG_pinout_detector
 z1Y2x    https://github.com/z1Y2x/JTAGenum/
 
 Most modifications are merged back into the first URL.
 Check the others for cutting edge or solutions if you 
 run into problems.	 JTAGenum is based on Lekernel's 
 ArduiNull[1] which was itself inspired by Hunz's 
 JTAG Finder[2]. Tested on Arduino Mini Pro, Arduino 
 Mega, Arduino Duemilanove and Teensy++[3].

 [1]http://lekernel.net/blog/?p=319
 [2]http://www.c3a.de/wiki/index.php/JTAG_Finder
 [4]http://www.pjrc.com/teensy/	 

 This code is public domain, use as you wish and at your own risk
*/

//needed to put help strings into flash
//#include <avr/pgmspace.h>

/*
 * BEGIN USER DEFINITIONS
 */

//#define DEBUGTAP
//#define DEBUGIR

// For 3.3v AVR boards. Cuts clock in half. Also see cmd in setup()
#define CPU_PRESCALE(n) (CLKPR = 0x80, CLKPR = (n))

// Setup the pins to be checked
/*
 * ESP32 LOLIN32 v1.0.0: usable digital pins are: 11-13 32-35 21-22 25-27 18-19 23 16-17 2-15 0
 *	 (13 is connected to the LED)
 */
byte       pins[] = {  32 ,  33 ,  34 ,  35 ,  25 ,  26 ,  27 ,  18  };
char * pinnames[] = { "32", "33", "34", "35", "25", "26", "27", "18" };

/*
 * Teensy v3.1: usable digital pins are: A0-A7
 *	 (13 is connected to the LED)
 */
//byte       pins[] = {  A0 ,  A1 ,  A2 ,  A3 ,  A4 ,  A5 ,  A6 ,  A7  };
//char * pinnames[] = { "A0", "A1", "A2", "A3", "A4", "A5", "A6", "A7" };
/*
 * Teensy v2
 */
//byte       pins[] = { PIN_B0, PIN_B1, PIN_B2, PIN_B4, PIN_B5 };
//char * pinnames[] = { "TRST", " TDI", " TMS", " TCK", " TDO" };
/*
 * Arduino Pro: usable digital pins are: 2-12, 14-19 (ANALOG 0-5)
 *	 (0,1 are the serial line, 13 is connected to the LED)
 */
//byte       pins[] = { 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 };
//char * pinnames[] = { "DIG_2", "DIG_3", "DIG_4", "DIG_5", "DIG_6",
//                      "DIG_7", "DIG_8", "DIG_9", "DIG_10", "DIG_11" };

// Once you have found the JTAG pins you can define
// the following to allow for the boundary scan and
// irenum functions to be run. Define the values
// as the index for the pins[] array of the found
// jtag pin:
#define	TCK                      0
#define	TMS                      1
#define	TDO                      2
#define	TDI                      3
#define	TRST                     4

// Pattern used for scan() and loopback() tests
#define PATTERN_LEN              64
// Use something random when trying find JTAG lines:
static char pattern[PATTERN_LEN] = "0110011101001101101000010111001001";
// Use something more determinate when trying to find
// length of the DR register:
//static char pattern[PATTERN_LEN] = "1000000000000000000000000000000000";

// Max. number of JTAG enabled chips (MAX_DEV_NR) and length
// of the DR register together define the number of
// iterations to run for scan_idcode():
#define MAX_DEV_NR               8
#define IDCODE_LEN               32  

// Target specific, check your documentation or guess 
#define SCAN_LEN                 1890 // used for IR enum. bigger the better
#define IR_LEN                   5
// IR registers must be IR_LEN wide:
#define IR_IDCODE                "01100" // always 011
#define IR_SAMPLE                "10100" // always 101
#define IR_PRELOAD               IR_SAMPLE

/*
 * END USER DEFINITIONS
 */



// TAP TMS states we care to use. NOTE: MSB sent first
// Meaning ALL TAP and IR codes have their leftmost
// bit sent first. This might be the reverse of what
// documentation for your target(s) show.
#define TAP_RESET                "11111"       // looping 1 will return 
                                               // IDCODE if reg available
#define TAP_SHIFTDR              "111110100"
#define TAP_SHIFTIR              "1111101100" // -11111> Reset -0> Idle -1> SelectDR
                                              // -1> SelectIR -0> CaptureIR -0> ShiftIR

// Ignore TCK, TMS use in loopback check:
#define IGNOREPIN                0xFFFF 
// Flags configured by UI:
boolean VERBOSE                  = 0; // 255 = true
boolean DELAY                    = 0;
long    DELAYUS                  = 5000; // 5 Milliseconds
boolean PULLUP                   = 255; 


const byte pinslen               = sizeof(pins)/sizeof(pins[0]);	 


void setup(void)
{
        // Uncomment for 3.3v boards. Cuts clock in half
        // only on avr based arduino & teensy hardware
        CPU_PRESCALE(0x01); 
        Serial.begin(115200);
}



/*
 * Set the JTAG TAP state machine
 */
void tap_state(char tap_state[], int tck, int tms) 
{
#ifdef DEBUGTAP
	Serial.print("tap_state: tms set to: ");
#endif
	while (*tap_state) { // exit when string \0 terminator encountered
		if (DELAY) delayMicroseconds(50);
		digitalWrite(tck, LOW);				   
		digitalWrite(tms, *tap_state - '0'); // conv from ascii pattern
#ifdef DEBUGTAP
		Serial.print(*tap_state - '0',DEC);
#endif
		digitalWrite(tck, HIGH); // rising edge shifts in TMS
		*tap_state++;
	}				 
#ifdef DEBUGTAP
	Serial.println();
#endif
}

static void pulse_tms(int tck, int tms, int s_tms)
{
	if (tck == IGNOREPIN) return;
	digitalWrite(tck, LOW);
	digitalWrite(tms, s_tms); 
	digitalWrite(tck, HIGH);
}
static void pulse_tdi(int tck, int tdi, int s_tdi)
{
	if (DELAY) delayMicroseconds(50);
	if (tck != IGNOREPIN) digitalWrite(tck, LOW);
	digitalWrite(tdi, s_tdi); 
	if (tck != IGNOREPIN) digitalWrite(tck, HIGH);
}
byte pulse_tdo(int tck, int tdo)
{
	byte tdo_read;
	if (DELAY) delayMicroseconds(50);
	digitalWrite(tck, LOW); // read in TDO on falling edge
	tdo_read = digitalRead(tdo);
	digitalWrite(tck, HIGH);
	return tdo_read;
}

/*
 * Initialize all pins to a default state
 * default with no arguments: all pins as INPUTs
 */
void init_pins(int tck = IGNOREPIN, int tms = IGNOREPIN, int tdi = IGNOREPIN, int ntrst = IGNOREPIN) 
{ 
	// default all to INPUT state
	for (int i = 0; i < pinslen; i++) {
		pinMode(pins[i], INPUT);
		// internal pullups default to logic 1:
		if (PULLUP) digitalWrite(pins[i], HIGH); 
	}
	// TCK = output
	if (tck != IGNOREPIN) pinMode(tck, OUTPUT);
	// TMS = output
	if (tms != IGNOREPIN) pinMode(tms, OUTPUT);
	// tdi = output
	if (tdi != IGNOREPIN) pinMode(tdi, OUTPUT);
	// ntrst = output, fixed to 1
	if (ntrst != IGNOREPIN) {
		pinMode(ntrst, OUTPUT);
		digitalWrite(ntrst, HIGH);
	}
}


/*
 * send pattern[] to TDI and check for output on TDO
 * This is used for both loopback, and Shift-IR testing, i.e.
 * the pattern may show up with some delay.
 * return: 0 = no match
 *		   1 = match 
 *		   2 or greater = no pattern found but line appears active
 *
 * if retval == 1, *reglen returns the length of the register
 */
static int check_data(char pattern[], int iterations, int tck, int tdi, int tdo,
                      int *reg_len)
{
	int i;
        int w          = 0;
	int plen       = strlen(pattern);
	char tdo_read;
	char tdo_prev;
	int nr_toggle  = 0; // count how often tdo toggled
	/* we store the last plen (<=PATTERN_LEN) bits,
	 *  rcv[0] contains the oldest bit */
	char rcv[PATTERN_LEN];
	
	tdo_prev = '0' + (digitalRead(tdo) == HIGH);

	for(i = 0; i < iterations; i++) {
		
		/* output pattern and incr write index */
		pulse_tdi(tck, tdi, pattern[w++] - '0');
		if (!pattern[w])
			w = 0;

		/* read from TDO and put it into rcv[] */
		tdo_read  =  '0' + (digitalRead(tdo) == HIGH);

		nr_toggle += (tdo_read != tdo_prev);
		tdo_prev  =  tdo_read;

		if (i < plen)
			rcv[i] = tdo_read;
		else 
		{
			memmove(rcv, rcv + 1, plen - 1);
			rcv[plen-1] = tdo_read;
		}
				
		/* check if we got the pattern in rcv[] */
		if (i >= (plen - 1) ) {
			if (!memcmp(pattern, rcv, plen)) {
				*reg_len = i + 1 - plen;
				return 1;
			}
		}
	} /* for(i=0; ... ) */
  
	*reg_len = 0;
	return nr_toggle > 1 ? nr_toggle : 0;
}

static void print_pins(int tck, int tms, int tdo, int tdi, int ntrst)
{
	if (ntrst != IGNOREPIN) {
		Serial.print(" ntrst:");
		Serial.print(pinnames[ntrst]);
	}
	Serial.print(" tck:");
	Serial.print(pinnames[tck]);
	Serial.print(" tms:");
	Serial.print(pinnames[tms]);
	Serial.print(" tdo:");
	Serial.print(pinnames[tdo]);
	if (tdi != IGNOREPIN) {
		Serial.print(" tdi:");
		Serial.print(pinnames[tdi]);
	}
}

/*
 * Shift JTAG TAP to ShiftIR state. Send pattern to TDI and check
 * for output on TDO
 */
static void scan()
{
	int tck, tms, tdo, tdi, ntrst;
	int checkdataret = 0;
	int len;
	int reg_len;
	printProgStr(PSTR("================================\r\n"
	                  "Starting scan for pattern:"));
	Serial.println(pattern);
	for(ntrst=0;ntrst<pinslen;ntrst++) {
		for(tck=0;tck<pinslen;tck++) {
			if(tck == ntrst) continue;
			for(tms=0;tms<pinslen;tms++) {
				if(tms == ntrst) continue;
				if(tms == tck  ) continue;
				for(tdo=0;tdo<pinslen;tdo++) {
					if(tdo == ntrst) continue;
					if(tdo == tck  ) continue;
					if(tdo == tms  ) continue;
					for(tdi=0;tdi<pinslen;tdi++) {
						if(tdi == ntrst) continue;
						if(tdi == tck  ) continue;
						if(tdi == tms  ) continue;
						if(tdi == tdo  ) continue;
						if(VERBOSE) {
							print_pins(tck, tms, tdo, tdi, ntrst);
							Serial.print("	  ");
						}
						init_pins(pins[tck], pins[tms], pins[tdi], pins[ntrst]);
						tap_state(TAP_SHIFTIR, pins[tck], pins[tms]);
						checkdataret = check_data(pattern, (2*PATTERN_LEN), 
						                pins[tck], pins[tdi], pins[tdo], &reg_len); 
						if(checkdataret == 1) {
							Serial.print("FOUND! ");
							print_pins(tck, tms, tdo, tdi, ntrst);
							Serial.print(" IR length: ");
							Serial.println(reg_len, DEC);
						}
						else if(checkdataret > 1) {
							Serial.print("active ");
							print_pins(tck, tms, tdo, tdi, ntrst);
							Serial.print("	bits toggled:");
							Serial.println(checkdataret);
						}
						else if(VERBOSE) Serial.println();										  
					} /* for(tdi=0; ... ) */
				} /* for(tdo=0; ... ) */
			} /* for(tms=0; ... ) */
		} /* for(tck=0; ... ) */
	} /* for(ntrst=0; ... ) */
	printProgStr(PSTR("================================\r\n"));
}
/*
 * Check for pins that pass pattern[] between tdi and tdo
 * regardless of JTAG TAP state (tms, tck ignored).
 *
 * TDO, TDI pairs that match indicate possible shorts between
 * pins. Pins that do not match but are active might indicate
 * that the patch cable used is not shielded well enough. Run
 * the test again without the cable connected between controller
 * and target. Run with the verbose flag to examine closely.
 */
static void loopback_check()
{
	int tdo, tdi;
	int checkdataret = 0;
	int reg_len;

	printProgStr(PSTR("================================\r\n"
	                  "Starting loopback check...\r\n"));
	for(tdo=0;tdo<pinslen;tdo++) {
		for(tdi=0;tdi<pinslen;tdi++) {
			if(tdi == tdo) continue;
	
			if(VERBOSE) {
				Serial.print(" tdo:");
				Serial.print(pinnames[tdo]);
				Serial.print(" tdi:");
				Serial.print(pinnames[tdi]);
				Serial.print("	  ");
			}
			init_pins(IGNOREPIN/*tck*/, IGNOREPIN/*tck*/, pins[tdi], IGNOREPIN /*ntrst*/);
			checkdataret = check_data(pattern, (2*PATTERN_LEN), IGNOREPIN, pins[tdi], pins[tdo], &reg_len);
			if(checkdataret == 1) {
				Serial.print("FOUND! ");
				Serial.print(" tdo:");
				Serial.print(pinnames[tdo]);
				Serial.print(" tdi:");
				Serial.print(pinnames[tdi]);
				Serial.print(" reglen:");
				Serial.println(reg_len);
			}
			else if(checkdataret > 1) {
				Serial.print("active ");
				Serial.print(" tdo:");
				Serial.print(pinnames[tdo]);
				Serial.print(" tdi:");
				Serial.print(pinnames[tdi]);
				Serial.print("	bits toggled:");
				Serial.println(checkdataret);
			}
			else if(VERBOSE) Serial.println();
		}
	}
	printProgStr(PSTR("================================\r\n"));
}

/*
 * Scan TDO for IDCODE. Handle MAX_DEV_NR many devices.
 * We feed zeros into TDI and wait for the first 32 of them to come out at TDO (after n * 32 bit).
 * As IEEE 1149.1 requires bit 0 of an IDCODE to be a "1", we check this bit.
 * We record the first bit from the idcodes into bit0.
 * (oppposite to the old code).
 * If we get an IDCODE of all ones, we assume that the pins are wrong.
 */
static void scan_idcode()
{
	int tck, tms, tdo, tdi, ntrst;
	int i, j;
	int nr; /* number of devices */
	int tdo_read;
	uint32_t idcodes[MAX_DEV_NR];
	printProgStr(PSTR("================================\r\n"
	                  "Starting scan for IDCODE...\r\n"));
	char idcodestr[] = "								";
	int idcode_i = 31; // TODO: artifact that might need to be configurable
	uint32_t idcode;
	for(ntrst=0;ntrst<pinslen;ntrst++) {
		for(tck=0;tck<pinslen;tck++) {
			if(tck == ntrst) continue;
			for(tms=0;tms<pinslen;tms++) {
				if(tms == ntrst) continue;
				if(tms == tck  ) continue;
				for(tdo=0;tdo<pinslen;tdo++) {
					if(tdo == ntrst) continue;
					if(tdo == tck  ) continue;
					if(tdo == tms  ) continue;
					for(tdi=0;tdi<pinslen;tdi++) {
						if(tdi == ntrst) continue;
						if(tdi == tck  ) continue;
						if(tdi == tms  ) continue;
						if(tdi == tdo  ) continue;
						if(VERBOSE) {
							print_pins(tck, tms, tdo, tdi, ntrst);
							Serial.print("	  ");
						}
						init_pins(pins[tck], pins[tms], pins[tdi], pins[ntrst]);

						/* we hope that IDCODE is the default DR after reset */
						tap_state(TAP_RESET, pins[tck], pins[tms]);
						tap_state(TAP_SHIFTDR, pins[tck], pins[tms]);
						
						/* j is the number of bits we pulse into TDI and read from TDO */
						for(i = 0; i < MAX_DEV_NR; i++) {
							idcodes[i] = 0;
							for(j = 0; j < IDCODE_LEN;j++) {
								/* we send '0' in */
								pulse_tdi(pins[tck], pins[tdi], 0);
								tdo_read = digitalRead(pins[tdo]);
								if (tdo_read)
									idcodes[i] |= ( (uint32_t) 1 ) << j;
	
								if (VERBOSE)
									Serial.print(tdo_read,DEC);
							} /* for(j=0; ... ) */
							if (VERBOSE) {
								Serial.print(" ");
								Serial.println(idcodes[i],HEX);
							}
							/* save time: break at the first idcode with bit0 != 1 */
							if (!(idcodes[i] & 1) || idcodes[i] == 0xffffffff)
								break;
						} /* for(i=0; ...) */
	
						if (i > 0) {
							print_pins(tck,tms,tdo,tdi,ntrst);
							Serial.print("	devices: ");
							Serial.println(i,DEC);
							for(j = 0; j < i; j++) {
								Serial.print("	0x");
								Serial.println(idcodes[j],HEX);
							}
						} /* if (i > 0) */
					} /* for(tdo=0; ... ) */
				} /* for(tdi=0; ...) */
			} /* for(tms=0; ...) */
		} /* for(tck=0; ...) */
	} /* for(trst=0; ...) */

	printProgStr(PSTR("================================\r\n"));
}

static void shift_bypass()
{
	int tdi, tdo, tck;
	int checkdataret;
	int reg_len;

	printProgStr(PSTR("================================\r\n"
	                  "Starting shift of pattern through bypass...\r\n"
	                  "Assumes bypass is the default DR on reset.\r\n"
	                  "Hence, no need to check for TMS. Also, currently\r\n"
	                  "not checking for nTRST, which might not work\r\n"));
	for(tck=0;tck<pinslen;tck++) {
		for(tdi=0;tdi<pinslen;tdi++) {
			if(tdi == tck) continue;
			for(tdo=0;tdo<pinslen;tdo++) {
				if(tdo == tck) continue;
				if(tdo == tdi) continue;
				if(VERBOSE) {
					Serial.print(" tck:");
					Serial.print(pinnames[tck]);
					Serial.print(" tdi:");
					Serial.print(pinnames[tdi]);
					Serial.print(" tdo:");
					Serial.print(pinnames[tdo]);
					Serial.print("	  ");
				}

				init_pins(pins[tck], IGNOREPIN/*tms*/,pins[tdi], IGNOREPIN /*ntrst*/);
				// if bypass is default on start, no need to init TAP state
				checkdataret = check_data(pattern, (2*PATTERN_LEN), pins[tck], pins[tdi], pins[tdo], &reg_len);
				if(checkdataret == 1) {
					Serial.print("FOUND! ");
					Serial.print(" tck:");
					Serial.print(pinnames[tck]);
					Serial.print(" tdo:");
					Serial.print(pinnames[tdo]);
					Serial.print(" tdi:");
					Serial.println(pinnames[tdi]);
				}
				else if(checkdataret > 1) {
					Serial.print("active ");
					Serial.print(" tck:");
					Serial.print(pinnames[tck]);
					Serial.print(" tdo:");
					Serial.print(pinnames[tdo]);
					Serial.print(" tdi:");
					Serial.print(pinnames[tdi]);
					Serial.print("	bits toggled:");
					Serial.println(checkdataret);
				}
				else if(VERBOSE) Serial.println();
			}
		}
	}
	printProgStr(PSTR("================================\r\n"));
}
/* ir_state()
 * Set TAP to Reset then ShiftIR. 
 * Shift in state[] as IR value.
 * Switch to ShiftDR state and end.
 */
void ir_state(char state[], int tck, int tms, int tdi) 
{
#ifdef DEBUGIR
	Serial.println("ir_state: set TAP to ShiftIR:");
#endif
	tap_state(TAP_SHIFTIR, tck, tms);
#ifdef DEBUGIR
	Serial.print("ir_state: pulse_tdi to: ");
#endif
	for (int i=0; i < IR_LEN; i++) {
		if (DELAY) delayMicroseconds(50);
		// TAP/TMS changes to Exit IR state (1) must be executed
		// at same time that the last TDI bit is sent:
		if (i == IR_LEN-1) {
			digitalWrite(tms, HIGH); // ExitIR
#ifdef DEBUGIR
			Serial.print(" (will be in ExitIR after next bit) ");
#endif
		}
		pulse_tdi(tck, tdi, *state-'0');
#ifdef DEBUGIR
		Serial.print(*state-'0', DEC);
#endif
		// TMS already set to 0 "shiftir" state to shift in bit to IR
		*state++;
	}
#ifdef DEBUGIR
	Serial.println("\r\nir_state: Change TAP from ExitIR to ShiftDR:");
#endif
	// a reset would cause IDCODE instruction to be selected again
	tap_state("1100", tck, tms); // -1> UpdateIR -1> SelectDR -0> CaptureDR -0> ShiftDR
}
static void sample(int iterations, int tck, int tms, int tdi, int tdo, int ntrst=IGNOREPIN)
{
	printProgStr(PSTR("================================\r\n"
	                  "Starting sample (boundary scan)...\r\n")); 
	init_pins(tck, tms ,tdi, ntrst);  

	// send instruction and go to ShiftDR
	ir_state(IR_SAMPLE, tck, tms, tdi);

	// Tell TAP to go to shiftout of selected data register (DR)
	// is determined by the instruction we sent, in our case 
	// SAMPLE/boundary scan
	for (int i = 0; i < iterations; i++) {
		// no need to set TMS. It's set to the '0' state to 
		// force a Shift DR by the TAP
		Serial.print(pulse_tdo(tck, tdo),DEC);
		if (i % 32  == 31 ) Serial.print(" ");
		if (i % 128 == 127) Serial.println();
	}
}

char ir_buf[IR_LEN+1];
static void brute_ir(int iterations, int tck, int tms, int tdi, int tdo, int ntrst=IGNOREPIN)
{
	printProgStr(PSTR("================================\r\n"
	                  "Starting brute force scan of IR instructions...\r\n"
	                  "NOTE: If Verbose mode is off output is only printed\r\n"
	                  "      after activity (bit changes) are noticed and\r\n"
	                  "      you might not see the first bit of output.\r\n"
	                  "IR_LEN set to ")); 
	Serial.println(IR_LEN,DEC);

	init_pins(tck, tms ,tdi, ntrst);  
	int iractive;
	byte tdo_read;
	byte prevread;
	for (uint32_t ir = 0; ir < (1UL << IR_LEN); ir++) { 
		iractive=0;
		// send instruction and go to ShiftDR (ir_state() does this already)
		// convert ir to string.
		for (int i = 0; i < IR_LEN; i++) 
			ir_buf[i]=bitRead(ir, i)+'0';
		ir_buf[IR_LEN]=0;// terminate
		ir_state(ir_buf, tck, tms, tdi);
		// we are now in TAP_SHIFTDR state

		prevread = pulse_tdo(tck, tdo);
		for (int i = 0; i < iterations-1; i++) {
			// no need to set TMS. It's set to the '0' state to force a Shift DR by the TAP
			tdo_read = pulse_tdo(tck, tdo);
			if (tdo_read != prevread) iractive++;
			
			if (iractive || VERBOSE) {
				Serial.print(prevread,DEC);
				if (i%16 == 15) Serial.print(" ");
				if (i%128 == 127) Serial.println();
			}
			prevread = tdo_read;
		}
		if (iractive || VERBOSE) {
			Serial.print(prevread,DEC);
			Serial.print("	Ir ");
			Serial.print(ir_buf);
			Serial.print("	bits changed ");
			Serial.println(iractive, DEC);
		}
	}
}

void set_pattern()
{
	int i;
	char c;

	Serial.print("Enter new pattern of 1's or 0's (terminate with new line or '.'):\r\n"
	             "> ");
	i = 0;
	while(1) {
		c = Serial.read();
		switch(c) {
		case '0':
		case '1':
			if(i < (PATTERN_LEN - 1) ) {
				pattern[i++] = c;
				Serial.print(c);
			}
			break;
		case '\n':
		case '\r':
		case '.': // bah. for the arduino serial console which does not pass us \n
			pattern[i] = 0;
			Serial.println();
			Serial.print("new pattern set [");
			Serial.print(pattern);
			Serial.println("]");
			return;
		}
	}
}

// given a PROGMEM string, use Serial.print() to send it out
void printProgStr(const char *str)
{
	char c;
	if(!str) return;
	while((c = pgm_read_byte(str++)))
		Serial.print(c);
}

void help()
{
	printProgStr(PSTR(	
			"Short and long form commands can be used.\r\n"
			"\r\n"
			"SCANS\r\n"
			"-----\r\n"
			"s > pattern scan\r\n"
			"	 Scans for all JTAG pins. Attempts to set TAP state to\r\n"
			"	 DR_SHIFT and then shift the pattern through the DR.\r\n"
			"p > pattern set\r\n"
			"	 currently: ["));
	Serial.print(pattern);
	printProgStr(PSTR("]\r\n"
			"\r\n"
			"i > idcode scan\r\n"
			"	 Assumes IDCODE is default DR on reset. Ignores TDI.\r\n"
			"	 Sets TAP state to DR_SHIFT and prints TDO to console\r\n"
			"	 when TDO appears active. Human examination required to\r\n"
			"	 determine if actual IDCODE is present. Run several\r\n"
			"	 times to check for consistancy or compare against\r\n"
			"	 active tdo lines found with loopback test.\r\n"
			"\r\n"
			"b > bypass scan\r\n"
			"	 Assumes BYPASS is default DR on reset. Ignores TMS and\r\n"
			"	 shifts pattern[] through TDI/TDO using TCK for clock.\r\n"
			"\r\n"
			"ERATTA\r\n"
			"------\r\n"
			"l > loopback check\r\n"
			"	 ignores tck,tms. if patterns passed to tdo pins are\r\n"
			"	 connected there is a short or a false-possitive\r\n"
			"	 condition exists that should be taken into account\r\n"
			"r > pullups\r\n"
			"	 internal pullups on inputs, on/off. might increase\r\n"
							"	 stability when using a bad patch cable.\r\n"
			"v > verbose\r\n"
			"	 on/off. print tdo bits to console during testing. will slow\r\n"
			"	 down scan.\r\n"
			"d > delay\r\n"
			"	 on/off. will slow down scan.\r\n"
			"- > delay -\r\n"
							"	 reduce delay by 1000us\r\n"
			"+ > delay +\r\n"
							"h > help\r\n"
			"\r\n"
			"OTHER JTAG TESTS\r\n"
			"----------------\r\n"
			"Each of the following will not scan/find JTAG and require\r\n"
			"that you manually set the JTAG pins. See their respective\r\n"
			"call from the loop() function of code to set.\r\n"
			"\r\n"
			"1 > pattern scan single\r\n"
			"	 runs a full check on one code-defined tdi<>tdo pair.\r\n"
			"	 look at the main()/loop() code to specify pins.\r\n"
			"x > boundary scan\r\n"
			"	 checks code defined tdo for 4000+ bits.\r\n"
			"	 look at the main()/loop() code to specify pins.\r\n"
			"y > irenum\r\n"
			"	 sets every possible Instruction Register and then\r\n"
			"	 checks the output of the Data Register.\r\n"
			"	 look at the main()/loop() code to specify pins.\r\n"
			));
}
/*
 * main()
 */
#define CMDLEN 20
char command[CMDLEN];
int dummy;
void loop() 
{
	if (Serial.available())
	{
		// READ COMMAND
		delay(5); // hoping read buffer is idle after 5 ms
		int i = 0;
		while (Serial.available() && i < CMDLEN-1) 
			command[i++] = Serial.read();
	
		Serial.flush();
		command[i] = 0; // terminate string
		Serial.println(command); // echo back
	
		// EXECUTE COMMAND
		if     (strcmp(command, "pattern scan") == 0                     || strcmp(command, "s") == 0)
			scan();
		else if(strcmp(command, "pattern scan single") == 0              || strcmp(command, "1") == 0) 
		{
			init_pins(pins[TCK], pins[TMS], pins[TDI], pins[TRST] /*ntrst*/);
			tap_state(TAP_SHIFTIR, pins[TCK], pins[TMS]);
			if (check_data(pattern, (2*PATTERN_LEN), pins[TCK], pins[TDI], pins[TDO], &dummy))
				Serial.println("found pattern or other");
			else
				Serial.println("no pattern found");
		}
		else if(strcmp(command, "pattern set") == 0                      || strcmp(command, "p") == 0)
			set_pattern();
		else if(strcmp(command, "loopback check") == 0                   || strcmp(command, "l") == 0)
			loopback_check();
		else if(strcmp(command, "idcode scan") == 0                      || strcmp(command, "i") == 0)
			scan_idcode();
		else if(strcmp(command, "bypass scan") == 0                      || strcmp(command, "b") == 0)
			shift_bypass();
		else if(strcmp(command, "boundary scan") == 0                    || strcmp(command, "x") == 0)
		{
			Serial.print("pins");
			print_pins(TCK, TMS, TDO, TDI, TRST);
			Serial.println();
			sample(SCAN_LEN+100, pins[TCK], pins[TMS], pins[TDI], pins[TDO], pins[TRST]);
		}
		else if(strcmp(command, "irenum") == 0                           || strcmp(command, "y") == 0)
			brute_ir(SCAN_LEN,	 pins[TCK], pins[TMS], pins[TDI], pins[TDO], pins[TRST]);
		else if(strcmp(command, "verbose") == 0                          || strcmp(command, "v") == 0)
		{
			VERBOSE = ~VERBOSE;
			Serial.println(VERBOSE ? "Verbose ON" : "Verbose OFF");
		}
		else if(strcmp(command, "delay") == 0                            || strcmp(command, "d") == 0)
		{
			DELAY = ~DELAY;
			Serial.println(DELAY ? "Delay ON" : "Delay OFF");
		}
		else if(strcmp(command, "delay -") == 0                          || strcmp(command, "-") == 0)
		{
			Serial.print("Delay microseconds: ");
			if (DELAYUS != 0 && DELAYUS > 1000) DELAYUS-=1000;
			else if (DELAYUS != 0 && DELAYUS <= 1000) DELAYUS-=100;
			Serial.println(DELAYUS,DEC);
		}
		else if(strcmp(command, "delay +") == 0                          || strcmp(command, "+") == 0)
		{
			Serial.print("Delay microseconds: ");
			if (DELAYUS < 1000) DELAYUS+=100;
			else DELAYUS+=1000;
			Serial.println(DELAYUS,DEC);
		}
		else if(strcmp(command, "pullups") == 0                          || strcmp(command, "r") == 0)
		{
			PULLUP = ~PULLUP;
			Serial.println(PULLUP ? "Pullups ON" : "Pullups OFF");
		}
		else if(strcmp(command, "help") == 0                             || strcmp(command, "h") == 0)
			help();
		else 
		{
			Serial.println("unknown command");
			help();
		}
		Serial.print("\n> ");
	} 
}
