# Generic OpenOCD utilitis
# 
# dumploop <address> <length> <block_size>
#     all values provided in hex. Dumps memory from
#     <address> until <address>+<length> to files of
#     <block_size>.
#
# e.g.
# dumploop 0 0x10000000 0x100000

proc dumploop {address length block_size} {
   set limit [expr $address+$length ]
   for {set i $address} {$i < $limit } {set i [expr $i+$block_size]} {
    set filename [format "dump_%08x.bin" $i ] 
	set addr [format "0x%x" $i]
	halt
	#sleep 200
    puts "dump_image $filename $addr $block_size"
	if { [catch {dump_image $filename $addr $block_size} error] } {
        puts "error $error"
        sleep 4000
        # roll back and restart last block:
        set i [expr $i-$block_size]
    } else {
        puts "all good"
        resume
    }
	#sleep 1000
   }
}

# dumpscan <from> <until> <iterative> <block_size>
#     scans from address <from> to <until> dumping <block_size> bytes
#     does this iterating the address <iterative> until we reach <until>
# e.g.
# dumpscan 0 0xA0000000 0x10000000 0x1000
proc dumpscan {from until iterative block_size} {
    puts "dumpscan <$from> <$until> <$iterative> <$block_size>"
    #set i $from
    for {set i $from} {$i <= $until } {set i [expr $i+$iterative]} {
        set filename [format "dumpscan_%08x.bin" $i ] 
        set addr [format "0x%x" $i]
        halt
        puts "dump_image $filename $addr $block_size"
    	if { [catch {dump_image $filename $addr $block_size} error] } {
            puts "scan error $error"
            sleep 2000
        } else {
            puts "scan all good"
            resume
            sleep 100
        }
    }
}