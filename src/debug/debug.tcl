
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
    if {[info exists aargs(-if)] && ![expr $aargs(-if)]} {
        return
    }

    set cmd ""
    set level [expr {[info level]-1}]
    set prc [lindex [info level $level] 0]
    
    set fr  [info frame]
    array set frData [info frame [expr {$fr - 1}]]
    set prompt "Debug ($frData(type) "
    switch -- $frData(type) {
        source {
            set f [lindex [file split $frData(file)] end]
            append prompt "$f:$frData(line) ($frData(proc))) "
        }
        proc -
        eval {
            append prompt "line:$frData(line) ($frData(cmd))) "
        }
    }
    
    while {1} {
        puts -nonewline $prompt
        flush stdout
        gets stdin line
        append cmd $line\n
        if {[info complete $cmd]} {
            set code [catch {uplevel #$level $cmd} result]
            if {$code == 0 && [string length $result]} {
                puts stdout $result
            } elseif {$code == 3} {
                break
                #error "aborted debugger"
            } elseif {$code == 4} {
                # continue
                return $result
            } else {
                puts stderr $result
            }
            #set prompt "Debug ($level) % "
            set cmd ""
        } else {
            set prompt "    "
        }
    }    
}
