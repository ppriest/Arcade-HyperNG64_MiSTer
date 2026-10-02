# Read the core's debug probes over JTAG (In-System Sources and Probes).
#
#   python scripts/read_issp.py [instance] [clear] [set N] [pulse N]
#   python scripts/read_issp.py T dump        # the first 4,096 I/O requests since configuration
#
# SignalTap acquisition is GUI-only in Quartus Prime Lite 17.0 -- there are no
# *signaltap* Tcl commands -- so ISSP is what a headless workflow can drive.
#
# The probe bus layout is defined where the bus is BUILT (the issp instance in
# the top-level .sv), not here. Keep the field tables in step with it: a
# silently shifted field decodes as plausible nonsense rather than as an error.
#
# Counters typically SATURATE and count per-cycle events, so they pin almost
# immediately: `clear` first and read again for a rate.

# --- core-specific: edit for this core -------------------------------------
# One table per ISSP instance id, {name lo hi format}; format is dec, sdec
# (signed 16), hex or bit. Bit numbers index the probe bus as the RTL
# concatenates it. Add an entry to the `switch` further down for each table.
# By convention source bit 0 pulsed is the counter clear.
# HyperNG64.sv, instance F: keep in step with the bus built there.
set fields_F {
    {frames           0  15 dec}
    {cpu_requests    16  31 dec}
    {cpu_last_addr   32  63 hex}
    {load_state      64  71 hex}
    {game_reset      64  64 bit}
    {mem_reset       65  65 bit}
    {rom_loaded      66  66 bit}
    {ldr_active      67  67 bit}
    {ldr_done        68  68 bit}
    {ldr_pending     69  69 bit}
    {cfg_valid       70  70 bit}
    {dl0_seen        71  71 bit}
    {faults          72  77 hex}
    {cpu_error       78  78 bit}
    {pll_locked      80  80 bit}
    {cpu_reset       81  81 bit}
    {pause           82  82 bit}
    {mcu_pc          83  98 hex}
    {mcu_insns       99 114 dec}
    {cpu_irq        115 115 bit}
    {cpu_irq_rises  116 127 dec}
}
# HyperNG64.sv, instance G
set fields_G {
    {irq_pending      0  31 hex}
    {irq_level       32  36 dec}
    {irq3_rises      37  48 dec}
    {3d_queued       49  54 dec}
    {3d_state        55  58 dec}
    {3d_dl_busy      59  59 bit}
    {3d_dl_upbusy    60  60 bit}
    {3d_dl_full      61  61 bit}
    {ddr_inflight    62  69 dec}
    {dl_uploads      70  85 dec}
    {triangles       86 101 dec}
    {cpu_req_pending 102 102 bit}
    {cpu_req_waited 103 118 dec}
    {mcu_int0_pulses 119 127 dec}
}
# HyperNG64.sv, instance V: video scheduling and DDR3 requests
set fields_V {
    {frame_start      0   0 bit}
    {line_start       1   1 bit}
    {vbusy            2   2 bit}
    {mixer_busy       3   3 bit}
    {tilemaps_busy    4   7 hex}
    {fetch3d_busy     8   8 bit}
    {sprites_busy     9   9 bit}
    {linepass_busy   10  10 bit}
    {pend            11  11 bit}
    {frame_pend      12  12 bit}
    {late_now        13  13 bit}
    {ddr_rd          14  21 hex}
    {ddr_ready       22  29 hex}
    {w_valid         30  30 bit}
    {w_urgent        31  31 bit}
    {frame_starts    32  47 dec}
    {line_starts     48  63 dec}
    {late_passes     64  79 dec}
    {late_last_frame 80  95 dec}
    {first_late_line 96 104 dec}
    {pass_max_len   105 120 dec}
    {pass_sprites   121 136 dec}
    {pass_tilemaps  137 152 dec}
    {pass_fetch3d   153 168 dec}
    {pass_mixer     169 184 dec}
    {pass_ddr_stall 185 200 dec}
    {pass_3d_writes 201 216 dec}
    {spr_fe_state   217 221 dec}
    {spr_dl_state   222 224 dec}
    {spr_records    225 227 dec}
    {spr_colours    228 233 dec}
    {spr_rows_in    234 240 dec}
    {spr_rows_asked 241 247 dec}
    {spr_ci         248 256 dec}
    {spr_ncand      257 265 dec}
}
# HyperNG64.sv, instance P: the CPU's fetch PC
set fields_P {
    {pc               0  31 hex}
    {epc             32  63 hex}
    {cause           64  95 hex}
    {status          96 127 hex}
    {badvaddr       128 159 hex}
}
# HyperNG64.sv, instance T: one entry; `dump` reads them all
set fields_T {
    {addr             0  31 hex}
    {data            32  63 hex}
    {mask            64  71 hex}
    {read            72  72 bit}
    {req64           73  73 bit}
    {next_slot       80  91 dec}
    {recorded        92 107 dec}
}
# ---------------------------------------------------------------------------

proc bits_to_int {s lo hi} {
    # read_probe_data returns the bus MSB-first, so index from the right.
    set n [string length $s]
    set v 0
    for {set i $hi} {$i >= $lo} {incr i -1} {
        set c [string index $s [expr {$n - 1 - $i}]]
        set v [expr {$v * 2 + ($c eq "1" ? 1 : 0)}]
    }
    return $v
}

set do_clear [expr {[lsearch -exact $argv "clear"] >= 0}]
# `set N`   : write source byte N (decimal) and leave it
# `pulse N` : write N, then 0 -- for the edge-triggered controls
set set_val -1; set pulse_val -1
set i [lsearch -exact $argv "set"];   if {$i >= 0} { set set_val   [lindex $argv [expr {$i+1}]] }
set i [lsearch -exact $argv "pulse"]; if {$i >= 0} { set pulse_val [lindex $argv [expr {$i+1}]] }

set hw ""
foreach h [get_hardware_names] { if {$hw eq ""} { set hw $h } }
if {$hw eq ""} { puts "NO JTAG HARDWARE FOUND"; exit 1 }
puts "hardware: $hw"

set dev ""
foreach d [get_device_names -hardware_name $hw] {
    if {[string match "*5CSEBA6*" $d] || [string match "*5CSE*" $d] || $dev eq ""} {
        set dev $d
    }
}
if {$dev eq ""} { puts "NO DEVICE FOUND"; exit 1 }
puts "device:   $dev"

# Query instance info BEFORE opening a session: with a session already active
# this fails with "There is already an active In-System Sources and Probes
# session started."
set insts [get_insystem_source_probe_instance_info -hardware_name $hw -device_name $dev]
if {[llength $insts] == 0} {
    puts "NO ISSP INSTANCES -- is this an instrumented build?"
    exit 1
}
foreach i $insts { puts "instance: $i" }

# Take the first instance unless one is named on the command line (a single
# argument that is not a keyword or a keyword's value).
set want ""
set skip 0
foreach a $argv {
    if {$skip} { set skip 0; continue }
    if {$a eq "set" || $a eq "pulse" || $a eq "from" || $a eq "count"} { set skip 1; continue }
    if {$a ne "clear" && $a ne "dump" && $a ne "ring"} { set want $a }
}
set idx [lindex [lindex $insts 0] 0]
set inst_id [lindex [lindex $insts 0] 3]
if {$want ne ""} {
    foreach i $insts {
        if {[lindex $i 3] eq $want} { set idx [lindex $i 0]; set inst_id $want }
    }
}

# The field table belongs to the INSTANCE. An unrecognised id stops rather
# than guesses.
switch -- $inst_id {
    F       { set fields $fields_F }
    G       { set fields $fields_G }
    T       { set fields $fields_T }
    P       { set fields $fields_P }
    V       { set fields $fields_V }
    default {
        puts "instance id '$inst_id' has no field table -- add one before reading it"
        exit 1
    }
}
puts "decoding instance $inst_id"

start_insystem_source_probe -device_name $dev -hardware_name $hw

# T dump: stop the capture, read the entries in order, let it run again. `ring` reads a ring
# capture (source bit 11) oldest first; otherwise the one-shot capture from entry 0.
if {$inst_id eq "T" && [lsearch $argv dump] >= 0} {
    proc tsrc {idx v} { write_source_data -instance_index $idx -value [format %X $v] -value_in_hex }
    set mode [expr {[lsearch $argv ring] >= 0 ? 8192 : 0}]
    tsrc $idx [expr {$mode | 4096}]
    set raw [read_probe_data -instance_index $idx]
    set next [bits_to_int $raw 80 91]
    set n [bits_to_int $raw 92 107]
    set count [expr {$n < 4096 ? $n : 4096}]
    set first [expr {($mode && $n >= 4096) ? $next : 0}]
    # `from F count C`: a window of the capture, for reading it in chunks
    set k0 0
    set i [lsearch -exact $argv "from"];  if {$i >= 0} { set k0 [lindex $argv [expr {$i+1}]] }
    set i [lsearch -exact $argv "count"]; if {$i >= 0} { set count [expr {min($count, $k0 + [lindex $argv [expr {$i+1}]])}] }
    puts "trace: $n requests recorded, $k0 to [expr {$count - 1}] read out"
    puts "  #     rw  address     data        mask  64"
    for {set k $k0} {$k < $count} {incr k} {
        set slot [expr {($first + $k) & 4095}]
        tsrc $idx [expr {$mode | 4096 | $slot}]
        tsrc $idx [expr {$mode | 4096 | $slot}]
        set e [read_probe_data -instance_index $idx]
        puts [format "  %4d  %s  0x%08X  0x%08X  %02X    %d" $k \
            [expr {[bits_to_int $e 72 72] ? "r" : "w"}] [bits_to_int $e 0 31] [bits_to_int $e 32 63] \
            [bits_to_int $e 64 71] [bits_to_int $e 73 73]]
    }
    tsrc $idx $mode
    end_insystem_source_probe
    exit 0
}
set raw [read_probe_data -instance_index $idx]
puts "raw ([string length $raw] bits): $raw"
puts ""

foreach f $fields {
    lassign $f name lo hi fmt
    set v [bits_to_int $raw $lo $hi]
    switch $fmt {
        sdec { if {$v >= 32768} { set v [expr {$v - 65536}] }; puts [format "  %-16s %d" $name $v] }
        hex  { puts [format "  %-16s 0x%08X" $name $v] }
        bit  { puts [format "  %-16s %s"     $name [expr {$v ? "yes" : "no"}]] }
        default { puts [format "  %-16s %d"  $name $v] }
    }
}

# write_source_data takes a BINARY STRING unless -value_in_hex is given; a
# decimal "8" is silently rejected. Every write goes through this, in hex.
proc write_src {idx v} { write_source_data -instance_index $idx -value [format %X $v] -value_in_hex }
if {$set_val >= 0}   { write_src $idx $set_val;   puts "source set to $set_val (reads back 0x[read_source_data -instance_index $idx -value_in_hex])" }
if {$pulse_val >= 0} { write_src $idx $pulse_val; write_src $idx 0; puts "source pulsed $pulse_val" }

if {$do_clear} {
    # Source bit 0 is the counter clear, by convention; the counters are
    # deliberately not reset by the core's own reset.
    write_src $idx 1
    write_src $idx 0
    puts "\ncounters cleared"
}

end_insystem_source_probe
