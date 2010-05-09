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


 This code is an extensive modification and port to Arduino 
 of Lekernel's ArduiNull [1] which was itself inspired by
 Hunz's JTAG Finder (aka jtagscanner) [2]. The advantage
 of using Arduino is that the code can be quickly programmed
 to any microcontroller supported by the platform (including
 PIC[3], AT90USB[4], others) with little to no modification
 required. While The Law Of Leaky Abstractions [5] still 
 applies using Arduino might be helpful for engineers with 
 tight deadlines.
 
 [1]http://lekernel.net/blog/?p=319
 [2]http://www.c3a.de/wiki/index.php/JTAG_Finder
 [3]http://www.create.ucsb.edu/~dano/CUI/
 [4]http://www.pjrc.com/teensy/  
 [5]http://joelonsoftware.com/articles/LeakyAbstractions.html

 TODO: add support for longer chains when using TAP_SHIFIR


 Copyright 2009 Nathan Fain

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


/*
 * BEGIN USER DEFINITIONS
 */

//#define DEBUGTAP
//#define DEBUGIR

// For 3.3v AVR boards. Cuts clock in half. Also see cmd in setup()
#define CPU_PRESCALE(n) (CLKPR = 0x80, CLKPR = (n))

// Setup the pins to be checked
// The first (currently commented out) is an example broad scan
// used to determine which pins from a set are meant for JTAG.
// The second (uncommented) is used when you know the JTAG pins
// already.
//byte pins[] = { 
//        PIN_B7,  PIN_D0,  PIN_D1,  PIN_D2,  PIN_D3,  PIN_D4,/*PIN_D5*/ PIN_D6, /*PIN_D7*/
//        PIN_B6,  PIN_B5,  PIN_B4,  PIN_B3,  PIN_B2,  PIN_B1,  PIN_B0 /*PIN_E7*//*PIN_E6*/
//};
//char * pinnames[] = {
//          " 3",    " 6",    "10",    "17",    "19",    "21",  /*"24"*/   "26", /*"PIN_D7"*/
//          " 2",    " 5",    " 9",    "13",    "18",    "20",    "22"   /*"25"*//*"PIN_E6"*/
//};
byte       pins[] = {   2, 3, 4, 5, 6, 7 };
char * pinnames[] = { "DIG_2", "DIG_3", "DIG_4", "DIG_5", "DIG_6", "DIG_7" };

// Pattern used for scan() and loopback() tests
#define PATTERN_LEN 64
// Use something random when trying find JTAG lines:
static char pattern[PATTERN_LEN] = "0110011101001101101000010111001001";
// Use something more determinate when trying to find
// length of the DR register:
//static char pattern[PATTERN_LEN] = "1000000000000000000000000000000000";

// Number of JTAG enabled chips (CHAIN_LEN) and length
// of the DR register together define the number of
// iterations to run for scan_idcode():
#define CHAIN_LEN                 2 
#define DR_LEN                    32  
#define IR_IDCODE_ITERATIONS      CHAIN_LEN*DR_LEN

// Target specific, check your documentation or guess 
#define SCAN_LEN                  1890 // used for IR enum. bigger the better
#define IR_LEN                    10  
// IR registers must be IR_LEN wide:
#define IR_IDCODE                 "0110000000" // always 011
#define IR_SAMPLE                 "1010000000" // always 101
#define IR_PRELOAD                IR_SAMPLE

/*
 * END USER DEFINITIONS
 */



// TAP TMS states we care to use. NOTE: MSB sent first
// Meaning ALL TAP and IR codes have their leftmost
// bit sent first. This might be the reverse of what
// documentation for your target(s) show.
#define TAP_RESET        "11111"      // looping 1 will return 
                                      // IDCODE if reg available
#define TAP_SHIFTDR      "111110100"
#define TAP_SHIFTIR      "1111101100"

// how many bits must change in scan_idcode() in order to print?
// in some cases pulling a bit high or low might change the state
// of other pins, having nothing to do with JTAG. So 2 is likely
// a good number. Note: these first two bit changes, will not be
// printed to the console.
int IDCODETHRESHOLD = 2; 


// Ignore TCK, TMS use in loopback check:
#define IGNOREPIN 0xFFFF 
// Flags configured by UI:
boolean VERBOSE = 0; // 255 = true
boolean DELAY = 0;
long DELAYUS = 5000; // 5 Milliseconds
boolean PULLUP = 255; 


byte pinslen = sizeof(pins);   


void setup(void)
{
        // Uncomment for 3.3v boards. Cuts clock in half
        CPU_PRESCALE(0x01); 
        Serial.begin(115200);
}



/*
 * Set the JTAG TAP state machine
 */
void tap_state(char tap_state[], int tck, int tms) 
{
#ifdef DEBUGTAP
        Serial.print("tms set to: ");
#endif
        while (*tap_state) { // exit when string \0 terminator encountered
                if (DELAY) delayMicroseconds(50);
                digitalWrite(tck, LOW);                
                digitalWrite(tms, *tap_state-'0'); // conv from ascii pattern
#ifdef DEBUGTAP
                Serial.print(*tap_state-'0',DEC);
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
void init_pins (int tck=IGNOREPIN, int tms=IGNOREPIN, int tdi=IGNOREPIN) 
{ 
        // default all to INPUT state
        for (int i=0; i<pinslen; i++) {
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
}


/*
 * send pattern[] to TDI and check for output on TDO
 * This is used for both loopback, and Shift-IR testing, i.e.
 * the pattern may show up with some delay.
 * return: 0 = no match
 *         1 = match 
 *         2 or greater = no pattern found but line appears active
 *
 * if retval == 1, *reglen returns the length of the register
 */
static int check_data(char pattern[], int iterations, int tck, int tdi, int tdo,
		       int *reg_len)
{
	int i,w=0;
	int plen=strlen(pattern);
	char tdo_read;
	char tdo_prev;
	int nr_toggle=0; // count how often tdo toggled
	/* we store the last plen (<=PATTERN_LEN) bits,
           rcv[0] contains the oldest bit */
	char rcv[PATTERN_LEN];
	
	tdo_prev = '0' + (digitalRead(tdo) == HIGH);

	for(i=0; i < iterations; i++) {
		
		/* output pattern and incr write index */
		pulse_tdi(tck, tdi, pattern[w++]-'0');
		if (!pattern[w])
			w=0;

		/* read from TDO and put it into rcv[] */
		tdo_read = '0' + (digitalRead(tdo) == HIGH);

		nr_toggle += (tdo_read != tdo_prev);
		tdo_prev = tdo_read;

		if (i < plen)
			rcv[i] = tdo_read;
		else {
			memmove(rcv, rcv+1, plen-1);
			rcv[plen-1] = tdo_read;
                }
                
                /* check if we got the pattern in rcv[] */
                if (i >=(plen-1)) {
			if (!memcmp(pattern, rcv, plen)) {
				*reg_len = i+1-plen;
				return 1;
  			}
  		}
	} /* for(i=0; ... ) */
  
	*reg_len = 0;
	return nr_toggle > 1 ? nr_toggle : 0;
}

/*
 * Shift JTAG TAP to ShiftIR state. Send pattern to TDI and check
 * for output on TDO
 */
static void scan()
{
        int tck, tms, tdo, tdi;
        int checkdataret=0;
	int len;
	int reg_len;
        Serial.print(
        	"================================\n"
                "Starting scan for pattern:\n");
        Serial.println(pattern);
        for(tck=0;tck<pinslen;tck++) {
                for(tms=0;tms<pinslen;tms++) {
                        if(tms == tck) continue;
                        for(tdo=0;tdo<pinslen;tdo++) {
                                if(tdo == tck) continue;
                                if(tdo == tms) continue;
                                for(tdi=0;tdi<pinslen;tdi++) {
                                        if(tdi == tck) continue;
                                        if(tdi == tms) continue;
                                        if(tdi == tdo) continue;
                                        if(VERBOSE) {
                                                Serial.print(" tck:");
                                                Serial.print(pinnames[tck]);
                                                Serial.print(" tms:");
                                                Serial.print(pinnames[tms]);
                                                Serial.print(" tdo:");
                                                Serial.print(pinnames[tdo]);
                                                Serial.print(" tdi:");
                                                Serial.print(pinnames[tdi]);
                                                Serial.print("    ");
                                        }
                                        init_pins(pins[tck], pins[tms], pins[tdi]);
                                        tap_state(TAP_SHIFTIR, pins[tck], pins[tms]);
					checkdataret = check_data(pattern, (2*PATTERN_LEN), 
 								  pins[tck], pins[tdi], pins[tdo], &reg_len); 
                                        if(checkdataret == 1) {
                                                Serial.print("FOUND! ");
                                                Serial.print(" tck:");
                                                Serial.print(pinnames[tck]);
                                                Serial.print(" tms:");
                                                Serial.print(pinnames[tms]);
                                                Serial.print(" tdo:");
                                                Serial.print(pinnames[tdo]);
                                                Serial.print(" tdi:");
                                                Serial.println(pinnames[tdi]);
						Serial.print(" IR length: ");
						Serial.print(reg_len, DEC);
                                        }
                                        else if(checkdataret > 1) {
                                                Serial.print("active ");
                                                Serial.print(" tck:");
                                                Serial.print(pinnames[tck]);
                                                Serial.print(" tms:");
                                                Serial.print(pinnames[tms]);
                                                Serial.print(" tdo:");
                                                Serial.print(pinnames[tdo]);
                                                Serial.print(" tdi:");
                                                Serial.print(pinnames[tdi]);
                                                Serial.print("  bits toggled:");
                                                Serial.println(checkdataret);
                                        }
                                        else if(VERBOSE) Serial.println();                                        
                                }
                        }
                }
        }
        Serial.print("================================\n");
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
        int checkdataret=0;
	int reg_len;

        Serial.print(
        	"================================\n"
                "Starting loopback check...\n");
        for(tdo=0;tdo<pinslen;tdo++) {
                for(tdi=0;tdi<pinslen;tdi++) {
                        if(tdi == tdo) continue;

                        if(VERBOSE) {
                                Serial.print(" tdo:");
                                Serial.print(pinnames[tdo]);
                                Serial.print(" tdi:");
                                Serial.print(pinnames[tdi]);
                                Serial.print("    ");
                        }
                        init_pins(IGNOREPIN/*tck*/, IGNOREPIN/*tck*/, pins[tdi]);
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
                                Serial.print("  bits toggled:");
                                Serial.println(checkdataret);
                        }
                        else if(VERBOSE) Serial.println();
                }
        }
        Serial.print("================================\n");
}
/*
 * Scan TDI for IDCODE
 * no need for TDO stimulation
 */
static void scan_idcode()
{
        int tck, tms, tdo, i;
        int bitstoggled;
        byte prevbit, tdo_read;

        Serial.print(
        	"================================\n"
                "Starting scan for IDCODE...\n"
                //"(if activity found, examine for IDCODE. Pits printed in shift right order with MSB first)\n"
	);
        char idcodestr[] = "                                ";
        int idcode_i=31; // TODO: artifact that might need to be configurable
        uint32_t idcode;
        for(tck=0;tck<pinslen;tck++) {
                for(tms=0;tms<pinslen;tms++) {
                        if(tms == tck) continue;
                        for(tdo=0;tdo<pinslen;tdo++) {
                                if(tdo == tck) continue;
                                if(tdo == tms) continue;

                                if(VERBOSE) {
                                        Serial.print(" tck:");
                                        Serial.print(pinnames[tck]);
                                        Serial.print(" tms:");
                                        Serial.print(pinnames[tms]);
                                        Serial.print(" tdo:");
                                        Serial.print(pinnames[tdo]);
                                        Serial.print("    ");
                                }

                                init_pins(pins[tck], pins[tms],IGNOREPIN/*tdi*/);
                                tap_state(TAP_SHIFTDR, pins[tck], pins[tms]);

                                /* read tdo. print if active. 
                                   human examination required to determine if if idcode found */
                                prevbit=digitalRead(tdo); //default state before we pulse tdo
                                for(i=0, bitstoggled=0, idcode=31; i<IR_IDCODE_ITERATIONS ;i++) {
                                        tdo_read = pulse_tdo(pins[tck], pins[tdo]);
                                        if (tdo_read != prevbit)
                                                bitstoggled++;

                                        // hand first active bit (previous bit)
                                        if (bitstoggled == 1) {
                                                idcode = prevbit;  //lsb                  
                                                idcodestr[idcode_i--] = prevbit+'0'; // msb
                                                Serial.print(prevbit,DEC);
                                        }

                                        if (bitstoggled > 0) {
                                                idcode |= ((uint32_t)tdo_read) << (31-idcode_i);
                                                idcodestr[idcode_i--] = tdo_read+'0';
                                                Serial.print(tdo_read,DEC);
                                                if (i % 32 == 31) Serial.print(" ");

                                        }
                                        prevbit = tdo_read;
                                }

                                if(bitstoggled >= IDCODETHRESHOLD) {
                                        Serial.print("\n tck:");
                                        Serial.print(pinnames[tck]);
                                        Serial.print(" tms:");
                                        Serial.print(pinnames[tms]);
                                        Serial.print(" tdo:");
                                        Serial.print(pinnames[tdo]);
                                        Serial.print("\n bits toggled:");
                                        Serial.print(bitstoggled);
                                        Serial.print("\n idcode buffer: ");
                                        Serial.print(idcodestr);
                                        Serial.print("  0x");
                                        Serial.println(idcode,HEX);
                                }
                                else if (bitstoggled || VERBOSE)
                                        Serial.println();


                        }
                }
        }
        Serial.print("================================\n");
}

static void shift_bypass()
{
        int tdi, tdo;
        int checkdataret;
	int reg_len;

        Serial.print(
        	"================================\n"
                "Starting shift of pattern through bypass...\n"
                "(assuming TDI->bypassreg->TDO state (no tck or tms))\n");
        for(tdi=0;tdi<pinslen;tdi++) {
                for(tdo=0;tdo<pinslen;tdo++) {
                        if(tdo == tdi) continue;
                        if(VERBOSE) {
                                Serial.print(" tdi:");
                                Serial.print(pinnames[tdi]);
                                Serial.print(" tdo:");
                                Serial.print(pinnames[tdo]);
                                Serial.print("    ");
                        }

                        init_pins(IGNOREPIN/*tck*/, IGNOREPIN/*tms*/,pins[tdi]);
                        // if bypass is default on start, no need to init TAP state
                        checkdataret = check_data(pattern, (2*PATTERN_LEN), IGNOREPIN/*tck*/, pins[tdi], pins[tdo], &reg_len);
                        if(checkdataret == 1) {
                                Serial.print("FOUND! ");
                                Serial.print(" tdo:");
                                Serial.print(pinnames[tdo]);
                                Serial.print(" tdi:");
                                Serial.println(pinnames[tdi]);
                        }
                        else if(checkdataret > 1) {
                                Serial.print("active ");
                                Serial.print(" tdo:");
                                Serial.print(pinnames[tdo]);
                                Serial.print(" tdi:");
                                Serial.print(pinnames[tdi]);
                                Serial.print("  bits toggled:");
                                Serial.println(checkdataret);
                        }
                        else if(VERBOSE) Serial.println();
                }
        }
        Serial.print("================================\n");
}
void ir_state(char state[], int tck, int tms, int tdi) 
{
        tap_state(TAP_SHIFTIR, tck, tms);
#ifdef DEBUGIR
        Serial.print("ir set to: ");
#endif
        for (int i=0; i < IR_LEN; i++) {
                if (DELAY) delayMicroseconds(50);
                // TAP/TMS changes to Exit IR state (1) must be executed
                // at same time that the last TDI bit is sent:
                if (i == IR_LEN-1) {
                        digitalWrite(tms, HIGH); // ExitIR
#ifdef DEBUGIR
                        Serial.print("ExitIR");
#endif
                }
                pulse_tdi(tck, tdi, *state-'0');
                //                digitalWrite(tck, LOW);                
                //                digitalWrite(tdi, *state-'0'); // conv from ascii pattern
#ifdef DEBUGIR
                Serial.print(*state-'0', DEC);
#endif
                // TMS already set to 0 "shiftir" state to shift in bit to IR
                *state++;
        }
#ifdef DEBUGIR
        Serial.print("\nUpdateIR with ");
#endif
        // a reset would cause IDCODE instruction to be selected again
        tap_state("11", tck, tms); // UpdateIR & SelectDR
        tap_state("00", tck, tms); // CaptureDR & ShiftDR

}
static void sample(int iterations, int tck, int tms, int tdi, int tdo)
{
        Serial.print("================================\n"
                     "Starting sample (boundary scan)...\n"); 
        init_pins(tck, tms ,tdi);  

        // send instruction and go to ShiftDR
        ir_state(IR_SAMPLE, tck, tms, tdi);

        // Tell TAP to go to shiftout of selected data register (DR)
        // is determined by the instruction we sent, in our case 
        // SAMPLE/boundary scan
        for (int i=0; i<iterations; i++) {
                // no need to set TMS. It's set to the '0' state to 
                // force a Shift DR by the TAP
                Serial.print(pulse_tdo(tck, tdo),DEC);
                if (i%32 == 31) Serial.print(" ");
                if (i%128 == 127) Serial.println();
        }
}

char ir_buf[IR_LEN+1];
static void brute_ir(int iterations, int tck, int tms, int tdi, int tdo)
{
        Serial.print("================================\n"
                "Starting brute force scan of IR instructions...\n"
                "IR_LEN set to "); 
        Serial.println(IR_LEN,DEC);

        init_pins(tck, tms ,tdi);  
        int iractive;
        byte tdo_read;
        byte prevread;
        for (uint32_t ir=0; ir<(1UL<<IR_LEN); ir++) { 
                iractive=0;
                // send instruction and go to ShiftDR (ir_state() does this already)
                // convert ir to string.
                for (int i=0; i<IR_LEN; i++) ir_buf[i]=bitRead(ir, i)+'0';
                ir_buf[IR_LEN]=0;// terminate
                ir_state(ir_buf, tck, tms, tdi);
		// we are now in TAP_SHIFTDR state

                prevread = digitalRead(tdo);

                for (int i=0; i<iterations; i++) {
                        // no need to set TMS. It's set to the '0' state to force a Shift DR by the TAP
                        tdo_read = pulse_tdo(tck, tdo);
                        if (tdo_read != prevread) iractive++;
                        
                        if (iractive || VERBOSE) {
                                Serial.print(tdo_read,DEC);
                                if (i%16 == 15) Serial.print(" ");
                                if (i%128 == 127) Serial.println();
                        }
                        prevread = tdo_read;
                }
                if (iractive || VERBOSE) {
                        Serial.print("  Ir ");
                        Serial.print(ir_buf);
                        Serial.print("  bits changed ");
                        Serial.println(iractive, DEC);
                }
        }
}

void set_pattern()
{
        int i;
        char c;

        Serial.print("Enter new pattern (terminate with new line or '.'):\n"
                "> ");
        i = 0;
        while(1) {
                c = Serial.read();
                switch(c) {
                case '0':
                case '1':
                        if(i < (PATTERN_LEN-1)) {
                                pattern[i++] = c;
                                Serial.print(c);
                        }
                        break;
                case '\n':
                case '\r':
                case '.': // bah. for the arduino serial console
                        pattern[i] = 0;
                        Serial.println();
                        Serial.print("new pattern set [");
                        Serial.print(pattern);
                        Serial.println("]");
                        return;
                }
        }
}

/*
 * main()
 */
void loop() {
        char c;
	int dummy;
        if (Serial.available() > 0) {   
                c = Serial.read();
                byte result = 0;
                Serial.println(c);
                switch (c) {
                case 's':
                        scan();
                        break;
                case 'p':
                        set_pattern();
                        break;
                case '1':
                        init_pins(pins[0], pins[1], pins[2]);
                        Serial.println(check_data(pattern, (2*PATTERN_LEN), pins[1], pins[2], pins[3], &dummy) 
                                ? "found pattern or other" : "no pattern found");
                        init_pins(pins[0], pins[1], pins[3]);
                        Serial.println(check_data(pattern, (2*PATTERN_LEN), pins[1], pins[3], pins[2], &dummy) 
                                ? "found pattern or other" : "no pattern found");
                        break;
                case 'l':
                        loopback_check();
                        break;
                case 'i':
                        scan_idcode();
                        break;
                case 'b':
                        shift_bypass();
                        break;
                case 'x':
                        Serial.print("pins tck tms tdi tdo: ");
                        Serial.print(pinnames[0]); 
                        Serial.print(pinnames[1]); 
                        Serial.print(pinnames[3]);
                        Serial.println(pinnames[2]);
                        sample(SCAN_LEN+100, pins[0]/*tck*/, pins[1]/*tms*/, pins[3]/*tdi*/, pins[2]/*tdo*/);
                        break;
                case 'y':
                        brute_ir(SCAN_LEN, pins[0]/*tck*/, pins[1]/*tms*/, pins[3]/*tdi*/, pins[2]/*tdo*/);
                        break;
                case 'v':
                        VERBOSE = ~VERBOSE;
                        Serial.println(VERBOSE ? "Verbose ON" : "Verbose OFF");
                        break;
                case 'd':
                        DELAY = ~DELAY;
                        Serial.println(DELAY ? "Delay ON" : "Delay OFF");
                        break;
                case '-':
                        Serial.print("Delay microseconds: ");
                        if (DELAYUS != 0 && DELAYUS > 1000) DELAYUS-=1000;
                        else if (DELAYUS != 0 && DELAYUS <= 1000) DELAYUS-=100;
                        Serial.println(DELAYUS,DEC);
                        break;
                case '+':
                        Serial.print("Delay microseconds: ");
                        if (DELAYUS < 1000) DELAYUS+=100;
                        else DELAYUS+=1000;
                        Serial.println(DELAYUS,DEC);
                        break;
                case 'r':
                        PULLUP = ~PULLUP;
                        Serial.println(PULLUP ? "Pullups ON" : "Pullups OFF");
                        break;
                default:
                        Serial.println("unknown command");
                case 'h':
                        Serial.print("\n"
                                "s > scan\n"
                                "\n"
                                "l > loopback\n"
                                "    ignores tck,tms. if patterns passed to tdo pins are\n"
                                "    connected there is a short or a false-possitive\n"
                                "    condition exists that should be taken into account\n"
                                "\n"
                                "i > idcode scan\n"
                                "    ignores tdi. assumes IDCODE is default on reset state.\n"
                                "    sets TAP state to DR_SHIFT and prints TDO to console\n"
                                "    if TDO appears active. Human examination required to\n"
                                "    determine if actual IDCODE is present. Run several\n"
                                "    times to check for consistancy or compare against\n"
                                "    active tdo lines found with loopback test.\n"
                                "\n"
                                "b > shift_bypass\n"
                                "    currently broken. need to add tck\n"
                                "\n"
                                "x > sample (aka boundary scan)\n"
                                "\n"
                                "y > brute force IR search\n"
                                "\n"
                                "1 > single check\n"
                                "    runs a full check on one code-defined tdi<>tdo pair and\n"
                                "    you will need to look at the main()/loop() code to specify.\n"
                                "r > pullup resistors on inputs on/off\n"
                                "    might increase stability when using a bad patch cable.\n"
                                "v > verbose on/off\n"
                                "    print tdo bits to console during testing. will slow\n"
                                "    down scan.\n"
                                "d > delay on/off\n"
                                "    will slow down scan.\n"
                                "- > delay - 1000us (or 100us)\n"
                                "+ > delay + 1000us\n"
                                "p > set pattern ["
                                );
                        Serial.print(pattern);
                        Serial.println("]\n\n"
                                "h > help");
                        break;
                }
                Serial.print("\n> ");
        }
}
