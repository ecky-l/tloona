
package require parser 1.4.1
package re -exact Itcl 3.4

namespace eval ::Tdb {
    ## \brief Dictionary of original command bodies
    variable OrigBodies {}
}

## \brief Implements some debugger specific commands
namespace eval ::Tdb::Cmd {}

## \brief The command to switch stack level
proc ::Tdb::Cmd::up {} {
    uplevel 2 {
        ::Tloona::Debug::BreakPoint
    }
}

## \brief The command to get backtraces
proc ::Tdb::Cmd::bt {} {
    set l [uplevel info level]
    for {set i $l} {$i > 0} {incr i -1} {
        puts [info level $i]
    }
}

## \brief The parser commands.
#
# These are mostly coroutines that are setup with specific content during
# the debugging session
namespace eval ::Tdb::Parser {
    
    variable Continuations {
        if {{1 2} 3} 
        for {1 {2 4} 3 1} 
        foreach { {[lassign 2 {*}1] != {}} 3}
    }
}

## \brief Create unique Coro names
proc ::Tdb::Parser::CoroName {} {
    return "coro[string range [format %2.2x [clock milliseconds]] 6 10]"
}

## \brief Coroutine for step next
proc ::Tdb::Parser::StepNext {content} {
    yield
    while {$content != {}} {
        set res [::parse command $content {0 end}]
        set cmd [::parse getstring $content [lindex $res 1]]
        set content [::parse getstring $content [lindex $res 2]]
        yield $cmd
    }
    return {}
}

## \brief Coroutine for step into.
#
# Since Tcl doesn't support call/cc we need to keep an array of
# all available control structures and the next continuation for them.
# We match the first token of the parse tree against this array to 
# find out where to proceed in the tree, yield every command in there
# to be evaluated in the debugger context and take the result. Based on 
# the result we eventually set the next continuation and start the yield 
# process for that.<br>
# If the first token is a Tcl proc or method, we set it up for debugging
# so that it all can start at a new stack level. 
proc ::Tdb::Parser::StepInto {content} {
    yield
    
    variable Continuations
    
    set res [::parse command $content {0 end}]
    set cTree [lindex $res 3]
    set cmd [::parse getstring $content [lindex [lindex $cTree 0] 1]]
    puts $cmd
    return {}
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
        puts -nonewline  "(tdb) ";#$prompt
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

## \brief setup a proc for debugging
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

## \brief Returns a prompt for command line debugging
proc ::Tdb::Prompt {} {
    # The prompt
    set fr  [info frame]
    set frData [info frame [expr {$fr - 3}]]
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
    return $prompt
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
    set coroStack {}
    set coro [Parser::CoroName]
    lappend coroStack $coro
    coroutine $coro Parser::StepNext $cmdBody
    
    puts [Prompt]
    set dbgCmd ""
    set evalResult {}
    while {1} {
        set coro [lindex $coroStack 0]
        set nextCmd [$coro $evalResult]
        if {$nextCmd == {}} {
            set coroStack [lrange $coroStack 1 end]
        }
        
        puts "        [lindex [split $nextCmd \n] 0] ..."
        set dbgCmd [::Tdb::BreakPoint -prevcmd $dbgCmd -uplevel 2 -framelevel 3]
        
        if {$dbgCmd == "s"} {
            # setup a new coroutine context for step into
            set coro [Parser::CoroName]
            set coroStack [linsert $coroStack 0 $coro]
            coroutine $coro Parser::StepInto $nextCmd
            continue
        }
        set evalResult [uplevel $nextCmd]
        
        if {$coroStack == {}} {
            break
        }
    }
    
    #while {![catch {[lindex $coroStack 0] $dbgCmd} res]} {
    #    puts "        [lindex [split $res \n] 0] ..."
    #    set dbgCmd [::Tdb::BreakPoint -prevcmd $dbgCmd -uplevel 2 -framelevel 3]
    #    uplevel $res
    #}
        
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
