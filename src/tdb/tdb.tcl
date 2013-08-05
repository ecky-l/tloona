
package require parser 1.4.1
package re -exact Itcl 3.4

namespace eval ::Tdb {
    ## \brief Dictionary of original command bodies
    variable OrigBodies {}
}

namespace eval ::Tdb::Cmd {}

proc ::Tdb::Cmd::up {} {
    uplevel 2 {
        ::Tloona::Debug::BreakPoint
    }
}


proc ::Tdb::Cmd::bt {} {
    set l [uplevel info level]
    for {set i $l} {$i > 0} {incr i -1} {
        puts [info level $i]
    }
}

proc ::Tdb::BreakPoint {args} {
    set upLev 1
    set frameLev 1
    foreach {k v} {-uplevel upLev -framelevel frameLev} {
        if {[dict exist $args $k]} {
            set $v [dict get $args $k]
        }
    }
    set level [expr {[info level] - $upLev}]
    if {[dict exists $args -if] && \
            ![uplevel #$level [list expr [dict get $args -if]]]} {
        return
    }
    
    set bpRes ""
    set cmd ""
    while {1} {
        puts -nonewline  ">> ";#$prompt
        flush stdout
        gets stdin line
        
        if {$line == "" && [dict exist $args -prevcmd]} {
            set line [dict get $args -prevcmd]
            if {$line == ""} {
                # if no command was given or put in, nothing needs
                # to be done. This prevents the ugly new line at prompt
                continue
            }
        }
        
        switch -- $line {
        
        n - s {
            set bpRes $line
            break
        }
        bt - up {
            set bpRes [namespace inscope Cmd $line]
        }
        
        default {
            #set bpRes n
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
        
        } ;# end switch
        
    }
    
    return $bpRes
}

proc ::Tdb::ParseToken {content treePtr restPtr} {
    upvar $treePtr tree
    upvar $restPtr rest
    
    set res [::parse command $content {0 end}]
    set tree [lindex $res 3]
    set rest [::parse getstring $content [lindex $res 2]]
    #puts $res
    
    #set tree [lindex $res 3]
    #if {$tree == {}} {
    #    return
    #}
    #puts tt,[llength $tree]
    #foreach {tkn} $tree {
    #    puts [::parse getstring $content [lindex $tkn 1]],$tkn
    #}
    
    ::parse getstring $content [lindex $res 1]
}

proc ::Tdb::SetProcDebug {cmd} {
    set cmdBody [info body $cmd]
    set ns [namespace qualifiers $cmd]
    if {$ns == {}} {
        set ns ::
    }
    uplevel #0 [list namespace eval $ns \
        [list rename $cmd __[namespace tail $cmd]__]]
    uplevel #0 [list namespace eval $ns \
        [list proc [namespace tail $cmd] {args} [list ::Tdb::Execute $cmdBody]]]
}

proc ::Tdb::UnsetProcDebug {cmd} {
    set ns [namespace qualifiers $cmd]
    if {$ns == {}} {
        set ns ::
    }
    uplevel #0 [list namespace eval $ns [list rename [namespace tail $cmd] {}]]
    uplevel #0 [list namespace eval $ns \
        [list rename __[namespace tail $cmd]__ [namespace tail $cmd]]]
}

## \brief Debugger experiments
#
# Try: setup a coroutine that parses the body of a proc or method
# and yields the next command. Process this command in a loop right 
# after a breakpoint (bp) command. From the bp command, a value is
# set via uplevel (__dbg_in) which is then given to the coroutine
# to indicate whether we want to step into or over the next command.
# sets an indicator value that
proc ::Tdb::Execute {cmdBody} {
    coroutine DebugParse apply {{content} {
        yield
        set input n
        while {$content != {}} {
            set cmd [::Tdb::ParseToken $content tree content]
            #append cmd \n bp
            set input [yield $cmd]
            if {$input == "s"} {
                # get out the subcommands. Tcl doesn't support 
                # continuations so we have a problem here: we won't 
                # know in advance to which command the interpreter 
                # will jump next in case of control structures
                puts "step into to be implemented"
            }
        }
        return -code error
    }} $cmdBody
    
    set dbgCmd ""

    # The prompt
    set fr  [info frame]
    set frData [info frame [expr {$fr - 2}]]
    set prompt "Debug "
    switch -- [dict get $frData type] {
        source {
            append prompt [file tail [dict get $frData file]]
            append prompt : [dict get $frData line]
            if {[dict exist $frData proc]} {
                append prompt " ([dict get $frData proc]) "
            } else {
                append prompt " ([lindex [dict get $frData cmd] 0]) "
            }
        }
        proc -
        eval {
            append prompt "line:[dict get $frData line]"
            append prompt " ([dict get $frData cmd])) "
        }
    }
    puts $prompt
    while {![catch {DebugParse $dbgCmd} res]} {
        puts "        [lindex [split $res \n] 0] ..."
        set dbgCmd [::Tdb::BreakPoint -prevcmd $dbgCmd -uplevel 2 -framelevel 3]
        uplevel $res
    }
        
}

proc TestDebug {} {
    coroutine gagga apply {{content} {
        yield
        set input n
        while {$content != {}} {
            set cmd [::Tdb::ParseToken $content tree content]
            #append cmd \n bp
            set input [yield $cmd]
            if {$input == "s"} {
                # get out the subcommands. Tcl doesn't support 
                # continuations so we have a problem here: we won't 
                # know in advance to which command the interpreter 
                # will jump next in case of control structures
            }
        }
        return -code error
    }} {
        set x 0
        for {set i 0} {$i < 5} {incr i} {
            incr x $i
        }
    }
    
    set __dbg_in xxx
    while {![catch {gagga $__dbg_in} res]} {
        puts "[lindex [split $res \n] 0] ..."
        set __dbg_in [::Tdb::BreakPoint]
        eval $res
    }
        
    
}

# \brief Debugger experiment
proc debug {cmd args} {
    set body ""
    if {[::itcl::is object $cmd]} {
        set call [lindex $args 0]
        set args [lrange $args 1 end]
        set body [$cmd info function $call -body]
    } elseif {[info procs $cmd] != {}} {
        # an ordinary proc
        set body [info body $cmd]
    }
    #coroutine dbg apply {{} {
    #}}
}

package provide tdb 0.1
