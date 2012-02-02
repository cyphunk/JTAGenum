# Generic OpenOCD utilitis
# 
# dumploop <address> <length> <block_size>
#     all values provided in hex. Dumps memory from
#     <address> until <address>+<length> to files of
#     <block_size>.
#

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
