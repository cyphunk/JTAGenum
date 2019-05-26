#!/usr/bin/env bash
# JTAGenum for Raspberry Pi
#
# Strategically there is no user interface.
# You will probably want to understand and edit things. 
# So, to use, source script and call functions:
#
#     source JTAGenum.sh
#     loopback_check
#     scan
#     scan_idcode
#
# To test without raspberrypi:
#
#     DEBUG=1 scan
#
# Run with verbose output:
#
#     VERBOSE=1 scan

# NOTE:
# This code provides mixed results. Sometimes it works dead-on, others times
# not. Until someone has a chance to thoroughly test you may consider this 
# experimental.

#
# USER DEFINITIONS
#

# define BCM pins (mapped directly to /sys/class/gpio/gpio${pin[N]})
# 5v 5v  g 14 15 18  g 23 24  g 25  8  7  1  g 12  g 16 20 21  
# 3v  2  3  4  g 17 27 22 3v 10  9 11  g  0  5  6 13 19 26  g
    pins=(2 3 4 17 27 22)
pinnames=(pin1 pin2 pin3 pin4 pin5 pin6)
# pinnames are strings used when printing info to console

#
# /USER DEFINITIONS
#


pattern="0110011101001101101000010111001001"

#
# WRAPPER FUNCTIONS
#
# you do not need to change this
      INPUT=in
     OUTPUT=out 
        LOW=0
       HIGH=1
  IGNOREPIN=255
  TAP_RESET="11111"
TAP_SHIFTDR="111110100"
TAP_SHIFTIR="1111101100"
 MAX_DEV_NR=8
 IDCODE_LEN=32
 
function pinMode () {
# /sys does not support pullups. To support this swap
# out this function for a userspace library that does
# support setting pullups.
#
# I just couldn't bring myself to dealing with
# wiringPi again
  local pin=$1 mode=$2 #assume passed either INPUT/OUTPUT define
  test "$DEBUG" && echo -en "\t[$pin$mode] ">&2 && return 0
  test -e /sys/class/gpio/gpio${pin} || \
    echo "$pin"  > /sys/class/gpio/export
  echo "$mode" > /sys/class/gpio/gpio${pin}/direction
}
function digitalWrite () { 
  local pin=$1 val=$2 #assumes passed either HIGH/LOW define
  test "$DEBUG" && echo -n "$pin:$val ">&2 && return 0
  test $pin -ne $IGNOREPIN && \
    echo "$val" > /sys/class/gpio/gpio${pin}/value
}
function digitalRead () {
  local pin=$1
  test "$DEBUG" && echo -n "<$pin ">&2 && echo 1 && return
  cat /sys/class/gpio/gpio${pin}/value
}
#
# /WRAPPER FUNCTIONS
#



##
 # Set the JTAG TAP state machine
 ##
function tap_state () {
  local state=$1 tck=$2 tms=$3
  for (( i=0; i<${#state}; i++ )); do
    digitalWrite $tck $LOW
    digitalWrite $tms ${state:$i:1}
    digitalWrite $tck $HIGH
  done
}
function pulse_tms () {
  local tck=$1 tms=$2 s_tms=$3
  test $tck -ne $IGNOREPIN && digitalWrite $tck $LOW
  digitalWrite $tms $s_tms
  test $tck -ne $IGNOREPIN && digitalWrite $tck $HIGH
} 
function pulse_tdo () {
  local tck=$1 tdo=$2 tdo_read=0
  digitalWrite $tck $LOW
  tdo_read=$(digitalRead $tdo)
  digitalWrite $tck $HIGH
  echo $tdo_read
}
function pulse_tdi () {
  local tck=$1 tdi=$2 s_tdi=$3
  digitalWrite $tck $LOW
  test $tck -ne $IGNOREPIN && digitalWrite $tck $LOW
  digitalWrite $tdi $s_tdi
  test $tck -ne $IGNOREPIN && digitalWrite $tck $HIGH
}
function init_pins () {
  local tck=$1 tms=$2 tdi=$3 ntrst=$4
  for (( i=0; i<${#pins[@]}; i++ )); do
    pinMode ${pins[$i]} $INPUT
  done
  test $tck -ne $IGNOREPIN && pinMode $tck $OUTPUT
  test $tms -ne $IGNOREPIN && pinMode $tms $OUTPUT
  test $tdi -ne $IGNOREPIN && pinMode $tdi $OUTPUT
  test $ntrst -ne $IGNOREPIN \
    && pinMode $ntrst $OUTPUT \
    && digitalWrite $ntrst $HIGH
  return 0
}

# send pattern, check if we get it back on tdo
# return 0 = no match, 1 = match, 
#        2+ no pattern but line is active
# on match sets global reg_len to the lengt of the
# register between TDI and TDO 
function check_data () {
  local pattern=$1 iterations=$2 tck=$3 tdi=$4 tdo=$5
  w=0
  tdo_prev=255
  nr_toggle=0
  rcv=""
  echo "" > /tmp/reg_len
  for (( i=0; i<$iterations; i++ )); do
    
    pulse_tdi $tck $tdi ${pattern:$w:1}
    w=$(($w+1))
    test $w -eq ${#pattern} && w=0
    
    tdo_read=$(digitalRead $tdo)
    test $tdo_read -ne $tdo_prev \
      && nr_toggle=$(($nr_toggle+1))
    tdo_prev=$tdo_read
    
    if [[ $i -lt ${#pattern} ]]; then
      rcv="${rcv}${tdo_read}"
    else
      rcv="${rcv:1}${tdo_read}"
    fi
    
    if [[ $i -ge ${#pattern} ]]; then
      if [[ "$rcv" = "$pattern" ]]; then
        reg_len=$(($i+1-${#pattern}))
        # check_data called by parent with $()
        # cant modify parents global var's so...
        echo $reg_len > /tmp/reg_len
        echo 1
        return
      fi
    fi
  done
  
  test $nr_toggle -gt 1 \
    && echo $nr_toggle \
    || echo 0
}

function print_pins () {
  local tck=$1 tms=$2 tdo=$3 tdi=$4 ntrst=$5
  test $ntrst -ne $IGNOREPIN \
    && echo -n " ntrst:${pinnames[$ntrst]}"
  echo -n " tck:${pinnames[$tck]}"
  echo -n " tms:${pinnames[$tms]}"
  echo -n " tdo:${pinnames[$tdo]}"
  test $tdi -ne $IGNOREPIN \
    && echo -n " tdi:${pinnames[$tdi]}"
}

function scan () {
  echo "================================"
  echo "Starting scan for pattern: $pattern"
  for (( ntrst=0; ntrst<${#pins[@]}; ntrst++ )); do
    for (( tck=0; tck<${#pins[@]}; tck++ )); do
      test $tck -eq $ntrst && continue
      for (( tms=0; tms<${#pins[@]}; tms++ )); do
        test $tms -eq $ntrst && continue
        test $tms -eq $tck && continue
        for (( tdo=0; tdo<${#pins[@]}; tdo++ )); do
          test $tdo -eq $ntrst && continue
          test $tdo -eq $tck && continue
          test $tdo -eq $tms && continue
          for (( tdi=0; tdi<${#pins[@]}; tdi++ )); do
            test $tdi -eq $ntrst && continue
            test $tdi -eq $tck && continue
            test $tdi -eq $tms && continue
            test $tdi -eq $tdo && continue
            test -n "$VERBOSE" \
              && print_pins $tck $tms $tdo $tdi $ntrst \
              && echo -n "    "
            init_pins ${pins[$tck]} ${pins[$tms]} ${pins[$tdi]} ${pins[$ntrst]}
            tap_state $TAP_SHIFTIR ${pins[$tck]} ${pins[$tms]}
            checkdatret=$(check_data $pattern $((2*${#pattern})) ${pins[$tck]} ${pins[$tdi]} ${pins[$tdo]})
            if [[ $checkdatret -eq 1 ]]; then
              echo -n "FOUND! "
              print_pins $tck $tms $tdo $tdi $ntrst
              echo " IR length: $(cat /tmp/reg_len 2>/dev/null)"
            elif [[ $checkdatret -gt 1 ]]; then
              echo -n "active "
              print_pins $tck $tms $tdo $tdi $ntrst
              echo " bits toggled:$checkdatret"
            elif [[ -n "$VERBOSE" ]]; then
              echo ""
            fi
          done
        done
      done
    done
  done
  echo "================================"
}

function loopback_check () {
  echo "================================"
  echo "Starting loopback check..."
  for (( tdo=0; tdo<${#pins[@]}; tdo++ )); do
    for (( tdi=0; tdi<${#pins[@]}; tdi++ )); do
      test $tdi -eq $tdo && continue
      test -n "$VERBOSE" \
        && echo -n " tdo:${pinnames[$tdo]} tdi:${pinnames[$tdi]}    "
      init_pins $IGNOREPIN $IGNOREPIN ${pins[$tdi]} $IGNOREPIN
      checkdatret=$(check_data $pattern $((2*${#pattern})) $IGNOREPIN ${pins[$tdi]} ${pins[$tdo]})
      if [[ $checkdatret -eq 1 ]]; then
        echo "FOUND! tdo: ${pinnames[$tdo]} tdi:${pinnames[$tdi]} reglen:$(cat /tmp/reg_len 2>/dev/null)"
      elif [[ $checkdatret -gt 1 ]]; then
        echo "active tdo: ${pinnames[$tdo]} tdi:${pinnames[$tdi]} bits toggled:$checkdatret"
      elif [[ -n "$VERBOSE" ]]; then
        echo ""
      fi
    done
  done
  echo "================================"
}

function scan_idcode () {
  echo "================================"
  echo "Starting scan for IDCODE..."
  echo "(assumes IDCODE default DR)"

   tdo_read=255
    idcodes=()
   
  for (( ntrst=0; ntrst<${#pins[@]}; ntrst++ )); do
    for (( tck=0; tck<${#pins[@]}; tck++ )); do
      test $tck -eq $ntrst && continue
      for (( tms=0; tms<${#pins[@]}; tms++ )); do
        test $tms -eq $ntrst && continue
        test $tms -eq $tck && continue
        for (( tdo=0; tdo<${#pins[@]}; tdo++ )); do
          test $tdo -eq $ntrst && continue
          test $tdo -eq $tck && continue
          test $tdo -eq $tms && continue
          for (( tdi=0; tdi<${#pins[@]}; tdi++ )); do
            test $tdi -eq $ntrst && continue
            test $tdi -eq $tck && continue
            test $tdi -eq $tms && continue
            test $tdi -eq $tdo && continue
            test -n "$VERBOSE" \
              && print_pins $tck $tms $tdo $tdi $ntrst \
              && echo -n "    "
            init_pins ${pins[$tck]} ${pins[$tms]} ${pins[$tdi]} ${pins[$ntrst]}
            
            tap_state $TAP_RESET ${pins[$tck]} ${pins[$tms]}
            tap_state $TAP_SHIFTDR ${pins[$tck]} ${pins[$tms]}
            
            for (( i=0; i<MAX_DEV_NR; i++ )); do
              idcodes[$i]=0
              for (( j=0; j<IDCODE_LEN; j++ )); do
                pulse_tdi ${pins[$tck]} ${pins[$tdi]} 0
                tdo_read=$(digitalRead ${pins[$tdo]})
                test $tdo_read -ge 1 \
                  && idcodes[$i]=$(( ${idcodes[$i]} | (1<<j) ))
                  
                test -n "$VERBOSE" \
                  && echo -n "$tdo_read"
              done
              test -n "$VERBOSE" \
                && printf " %8x\n" ${idcodes[$i]}
              # this probably just means we return on first idcode:
              # FIXME or test at least on chained target
              if [[ $((${idcodes[$i]} & 1)) -ne 1 ]] \
                 || [[ ${idcodes[$i]} = $((0xffffffff))  ]]; then
                break 
              fi
            done
            
            if [[ $i -gt 0 ]]; then
              print_pins $tck $tms $tdo $tdi $ntrst
              echo "  devices: $i" 
              for (( j=0; j<i; j++ )); do
                printf "  0x%08x\n" ${idcodes[$j]}
              done
            fi
          done
        done
      done
    done
  done
  echo "================================"
}

#set -e #exit on any error
# loopback_check
# scan
# scan_idcode
