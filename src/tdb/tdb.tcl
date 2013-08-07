
package require parser 1.4.1
package require sugar 0.1
package re -exact Itcl 3.4

## \brief Gets the token of a parse tree at specified index
::sugar::macro m-parse-token {cmd content tree idx} {
    list string trim \[::parse getstring $content \[lindex \[lindex $tree $idx\] 1\]\] \"{}\"
}

namespace eval ::Tdb {
    ## \brief Dictionary of original command bodies
    variable OrigBodies {}
    
    variable DebugCmd n
    
    variable LastResult ""
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
namespace eval ::Tdb::Step {
    
    variable Continuations {
        if {{1 2} 3} 
        for {1 {2 4} 3 1} 
        foreach { {[lassign 2 {*}1] != {}} 3}
    }
}

## \brief Create unique Coro names
proc ::Tdb::Step::CoroName {} {
    return "coro[string range [format %2.2x [clock milliseconds]] 6 10]"
}

## \brief Coroutine for step next
proc ::Tdb::Step::StepNext {content} {
    namespace upvar ::Tdb DebugCmd debugCmd
    
    yield
    #puts $content
    while {$content != {}} {
        set res [::parse command $content {0 end}]
        set cmd [::parse getstring $content [lindex $res 1]]
        set content [::parse getstring $content [lindex $res 2]]
        yield [list $cmd "[lindex [split $cmd \n] 0] ..." y]
    }
    return -code break
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
::sugar::proc ::Tdb::Step::StepInto {content} {
    yield
    
    set res [::parse command $content {0 end}]
    set cTree [lindex $res 3]
    set cmd [m-parse-token $content $cTree 0]
    switch -- $cmd {
        if {
        }
        while {
        }
        for {
            set init [m-parse-token $content $cTree 1]
            set initPuts "for {$init} {...} {...}"
            set eval [list expr [m-parse-token $content $cTree 2]]
            set evalPuts "for {...} {[m-parse-token $content $cTree 2]} {...}"
            set step [m-parse-token $content $cTree 3]
            set stepPuts "for {...} {...} {$step}"
            set body [m-parse-token $content $cTree 4]
            for {yield [list $init $initPuts y]} {[yield [list $eval $evalPuts y]]} \
                        {yield [list $step $stepPuts y]} {
                # set up an inner coroutine that returns the body in pieces
                #coroutine eatBody StepNext $body
                set bodyi $body
                while {$bodyi != {}} {
                    set resi [::parse command $bodyi {0 end}]
                    set cmdi [::parse getstring $bodyi [lindex $resi 1]]
                    set bodyi [::parse getstring $bodyi [lindex $resi 2]]
                    yield [list $cmdi "[lindex [split $cmdi \n] 0] ..." y]
                }
                
            }
        }
        foreach {
        }
        switch {
        }
        
        default {
            # TODO: find a way to turn s into n for the commands that cannot
            # be stepped into
            coroutine eatBody StepNext $content
            set evalRes ""
            while {[catch {eatBody $evalRes} innerCmd] != 42} {
                yield $innerCmd
            }
        }
    }
    return -code 42
}

## \brief Coroutine for step next
proc ::Tdb::Step::NextCmd {content treePtr restPtr} {
    upvar $treePtr tree
    upvar $restPtr rest
    
    #puts $content
    while {$content != {}} {
        set res [::parse command $content {0 end}]
        set tree [lindex $res 3]
        puts $res
        set cmd [::parse getstring $content [lindex $res 1]]
        puts $cmd
        set rest [::parse getstring $content [lindex $res 2]]
        uplevel [list yield [list $cmd "[lindex [split $cmd \n] 0] ..." y]]
    }
    #return -code 42
}


proc ::Tdb::BreakPoint {args} {
    variable DebugCmd
    set upLev 1
    if {[dict exist $args -uplevel]} {
        set upLev [dict get $args -uplevel]
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
        
        if {$line == ""} {
            set line $DebugCmd
            if {$line == ""} {
                # if no command was given or put in, nothing needs
                # to be done. This prevents the ugly new line at prompt
                continue
            }
        }
        
        switch -- $line {
        
        n - s {
            set DebugCmd $line
            break
        }
        bt - up {
            set DebugCmd $line
            namespace inscope Cmd $line
            break
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
                    return $result
                } else {
                    puts stderr $result
                }
                set DebugCmd $line
                set cmd ""
            }
        }
        
        } ;# end switch
        
    }
    
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

namespace eval ::Tdb::Step::Cmd {
}

proc ::Tdb::Step::Cmd::If {content} {
    yield [info coroutine]
    return -code break
}

proc ::Tdb::Step::Cmd::While {content} {
    yield [info coroutine]
    return -code break
}

::sugar::proc ::Tdb::Step::Cmd::For {content} {
    namespace upvar ::Tdb LastResult evalRes
    yield [info coroutine]
    puts heyho
    set res [::parse command $content {0 end}]
    set tree [lindex $res 3]
    
    set init [m-parse-token $content $tree 1]
    set eval [list expr [m-parse-token $content $tree 2]]
    set step [m-parse-token $content $tree 3]
    set body [m-parse-token $content $tree 4]
    
    yield $init
    while {1} {
        yield $eval
        puts $evalRes
        if {! $evalRes} {
            break
        }
        set coro [coroutine [::Tdb::Step::CoroName] ::Tdb::Step::Next $body]
        while {[info commands $coro] != {}} {
            yieldto $coro
        }
        
        yield $step
    }
}

proc ::Tdb::Step::Cmd::Foreach {content} {
    yield [info coroutine]
    return -code break
}

proc ::Tdb::Step::Cmd::Switch {content} {
    yield [info coroutine]
    return -code break
}

proc ::Tdb::Step::InnerStep {content} {
    yield [info coroutine]
    while {$content != {}} {
        set res [::parse command $content {0 end}]
        set cmd [::parse getstring $content [lindex $res 1]]
        set content [::parse getstring $content [lindex $res 2]]
        yield $cmd
    }
}

proc ::Tdb::Step::Next {content} {
    namespace upvar ::Tdb DebugCmd DebugCmd
    yield [info coroutine]
    
    set coro [coroutine [CoroName] InnerStep $content]
    while {[info commands $coro] != {}} {
        set nextCmd [$coro]
        yield $nextCmd
        if {$DebugCmd == "s"} {
            #set nextCmd [$coro]
            set pRes [::parse command $nextCmd {0 end}]
            set tree [lindex $pRes 3]
            set cmd1 [::parse getstring $nextCmd [lindex [lindex $tree 0] 1]]
            switch -- $cmd1 {
                if - while - for - foreach - switch {
                    set cmd Cmd::
                    append cmd [string tou [string in $cmd1 0]] \
                        [string ra $cmd1 1 end]
                    set coroStep [coroutine [CoroName] $cmd $nextCmd]
                    while {[info commands $coroStep] != {}} {
                        yieldto $coroStep
                    }
                }
                default {
                    yield $nextCmd
                }
            }
            #yield $nextCmd
        
        }
        
    }
}

proc ::Tdb::Execute {cmdBody} {
    variable DebugCmd
    variable LastResult
    
    set coro [coroutine [Step::CoroName] Step::Next $cmdBody]
    puts [Prompt]
    set evalResult ""
    set DebugCmd n
    while {[info commands $coro] != {}} {
        set nextCmd [$coro]
        if {[string trim $nextCmd] == ""} {
            continue
        }
        puts "    [lindex [split $nextCmd \n] 0] ..."
        BreakPoint -uplevel 2
        if {$DebugCmd == "s"} {
            set evalResult ""
            continue
        }
        if {[string trim $nextCmd] != ""} {
            set LastResult [uplevel $nextCmd]
        }
        
    }
}

## \brief Debugger experiments
#
# Try: setup a coroutine that parses the body of a proc or method
# and yields the next command. Process this command in a loop right 
# after a breakpoint (bp) command. From the bp command, a value is
# set via uplevel (__dbg_in) which is then given to the coroutine
# to indicate whether we want to step into or over the next command.
# sets an indicator value that
proc ::Tdb::Execute2 {cmdBody} {
    variable DebugCmd
    
    set coroStack {}
    set coro [Step::CoroName]
    lappend coroStack $coro
    coroutine $coro Step::StepNext $cmdBody
    
    puts [Prompt]
    set dbgCmd ""
    set evalResult {}
    while {1} {
        set coro [lindex $coroStack 0]
        if {[catch {$coro $evalResult} nextCmd] == 42} {
            set coroStack [lrange $coroStack 1 end]
        }
        
        set canStep [lindex $nextCmd 2]
        if {$canStep == {}} {
            set canStep n
        }
        set lineP [string repeat "    " [llength $coroStack]]
        append lineP [lindex $nextCmd 1]
        puts $lineP
        set nextCmd [lindex $nextCmd 0]
        BreakPoint -uplevel 2
        
        if {$DebugCmd == "s" && $canStep} {
            # setup a new coroutine context for step into
            set coro [Step::CoroName]
            set coroStack [linsert $coroStack 0 $coro]
            coroutine $coro Step::StepInto $nextCmd
            continue
        }
        if {[string trim $nextCmd] != ""} {
            if {[catch {uplevel $nextCmd} evalResult]} {
                puts $evalResult,$nextCmd
                BreakPoint -uplevel 2
            }
            #set evalResult [uplevel $nextCmd]
        }
        
        if {$coroStack == {}} {
            break
        }
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
