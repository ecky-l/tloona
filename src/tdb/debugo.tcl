package provide debugo 1.0

proc up {} {
    uplevel 2 {
        bp
    }
}

proc down {} {
    return -code continue
}


proc bp {args} {
    array set aargs $args
    # conditional breakpoints
    if {[info exists aargs(-if)] && ![uplevel expr $aargs(-if)]} {
        return
    }

    set cmd ""
    set level [expr {[info level]-1}]
    set prc [lindex [info level $level] 0]
    
    set fr  [info frame]
    array set frData [info frame [expr {$fr - 1}]]
    set rompt "Debug ($frData(type) "
    switch -- $frData(type) {
        source {
            set f [lindex [file split $frData(file)] end]
            append rompt "$f:$frData(line) ($frData(proc))) "
        }
        proc -
        eval {
            append rompt "line:$frData(line) ($frData(cmd))) "
        }
    }
    while {1} {
        puts -nonewline $rompt
        flush stdout
        set line [gets stdin]
        append cmd $line \n
        if {[info complete $cmd]} {
            set code [catch {uplevel #$level $cmd} result]
            if {$code == 0 && [string length $result] > 0} {
                puts $result
            } elseif {$code == 3} {
                break
            } elseif {$code == 4} {
                # continue
                return $result
            } else {
                puts stderr $result
            }
            set cmd ""
        } else {
            set rompt "    "
        }
        continue
    }
    return
}
