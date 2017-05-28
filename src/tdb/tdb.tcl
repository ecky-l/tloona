
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
    namespace export CoroName Into
}


## \brief Create unique Coro names
proc ::Tdb::Step::CoroName {} {
    return "coro[string range [format %2.2x [clock milliseconds]] 6 10]"
}

## \brief Next Step coroutine
#
# This is a coroutine that is set up with a script content as context.
# While the script has a next command, it yields a list containig this 
# command and a coroutine which can be used to step into the command. 
# If a step into is not possible, the second list element is empty. 
# Callers of a contextuated coroutine with this proc can process the 
# yielded results and decide on their own, whether to step into the 
# command or step over. However they are responsible of deleting the 
# returned coroutine either by processing it or by renaming it to {}.
proc ::Tdb::Step::Into {content} {
    namespace upvar ::Tdb DebugCmd DebugCmd
    yield [info coroutine]
    
    while {$content != {}} {
        set res [::parse command $content {0 end}]
        set nextCmd [::parse getstring $content [lindex $res 1]]
        set coroStep {}
        
        set pRes [::parse command $nextCmd {0 end}]
        set tree [lindex $pRes 3]
        set cmd1 [::parse getstring $nextCmd [lindex [lindex $tree 0] 1]]
        if {[info procs $cmd1] != {}} {
            # TODO: setup proc for debugging step. Take into account that
            # proc might exist in the current namespace only or that it is 
            # a method
            
        } else {
            switch -- $cmd1 {
                if - while - for - foreach - switch {
                    set cmd Cmd::
                    append cmd [string tou [string in $cmd1 0]] \
                        [string ra $cmd1 1 end]
                    set coroStep [coroutine [CoroName] $cmd $nextCmd]
                }
                default {
                    # Build a coro that performs command and variable 
                    # substitutions by looking into the parse tree
                    set coroStep [coroutine [CoroName] \
                        ::Tdb::Step::Cmd::Substitute $nextCmd]
                }
            }
        }
        set content [::parse getstring $content [lindex $res 2]]
        yield [list $nextCmd $coroStep]
    }
}


namespace eval ::Tdb::Step::Cmd {
    namespace import ::Tdb::Step::*
}

## \brief Perform Command and variable substitution.
#
# This procedure constructs a new command from content by stepwise
# substitution of words ([commands] and $variables) on step into
proc ::Tdb::Step::Cmd::Substitute {content} {
    yield [info coroutine]
    
    set res [::parse command $content {0 end}]
    set tree [lindex $res 3]
    foreach {elem} $tree {
        if {[lindex $elem 0] != "word"} {
            continue
        }
        set elemTrees [lindex $elem end]
        foreach {elemTree} [lindex $elem end] {
            switch -- [lindex $elemTree 0] {
                variable {
                    set varName [::parse getstring $content \
                        [lindex [lindex [lindex $elemTree end] 0] 1]]
                    set var [::parse getstring $content [lindex $elemTree 1]]
                    set $varName [yield [list [list subst $var] {}]]
                }
                command {
                    set cmdName [::parse getstring $content [lindex $elemTree 1]]
                    set cmd [string range $cmdName 1 end-1]
                    set $cmdName [yield [list $cmd [coroutine [CoroName] ::Tdb::Step::Into $cmd]]]
                    set cmdNameRE $cmdName
                    foreach {c} {{\[} {\]} {\$}} {
                        set cmdNameRE [regsub -all $c $cmdNameRE \\$c]
                    }
                    set content [regsub $cmdNameRE $content "\$\{$cmdName\}"]
                }
            }
        }
    }
    yield [list [subst $content] {}]
    return
}
proc ::Tdb::Step::Cmd::If {content} {
    yield [info coroutine]
}

proc ::Tdb::Step::Cmd::While {content} {
    yield [info coroutine]
}

## \brief Step into coroutine for the ::for command
::sugar::proc ::Tdb::Step::Cmd::For {content} {
    namespace upvar ::Tdb LastResult evalRes
    yield [info coroutine]
    set res [::parse command $content {0 end}]
    set tree [lindex $res 3]
    
    set init [m-parse-token $content $tree 1]
    set eval [list expr [m-parse-token $content $tree 2]]
    set step [m-parse-token $content $tree 3]
    set body [m-parse-token $content $tree 4]
    
    yield [list $init [coroutine [CoroName] ::Tdb::Step::Into $init]]
    while {1} {
        set evr [yield [list $eval {}]]
        if {! $evalRes} {
            break
        }
        yield [list $body [coroutine [CoroName] ::Tdb::Step::Into $body]]
        yield [list $step [coroutine [CoroName] ::Tdb::Step::Into $step]]
    }
}

proc ::Tdb::Step::Cmd::Foreach {content} {
    yield [info coroutine]
}

proc ::Tdb::Step::Cmd::Switch {content} {
    yield [info coroutine]
}

## \brief A breakpoint for command line use
#
# This simple breakpoint command lets users evaluate commands in 
# the script context that they debug
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
        
        n - s - o {
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


proc ::Tdb::Execute {nextCmd} {
    variable DebugCmd
    variable LastResult
    
    set cmdStack {}
    set stepCoro [coroutine [Step::CoroName] Step::Into $nextCmd]
    while {1} {
        if {$nextCmd != ""} {
            puts "   [string trim [lindex [split $nextCmd \n] 0]] ..."
            BreakPoint -uplevel 2
            if {$DebugCmd == "s" && $stepCoro != {} && [info commands $stepCoro] != {}} {
                # Backup the nextCmd and stepCoro as next one to use on "n" or 
                # "o". Then update nextCmd and get the new stepCoro. After 
                # that proceed to the beginning of loop, where nextCmd will be
                # break'ed again.
                set cmdStack [linsert $cmdStack 0 $nextCmd $stepCoro]
                lassign [$stepCoro $LastResult] nextCmd stepCoro
                continue
            }
            if {[string trim $nextCmd] != ""} {
                set LastResult [uplevel $nextCmd]
            }
        }
        # important: if the last command was "s" and the command in this step is "n",
        # the stepCoro assigned in the previous step is not used and needs to be deleted
        if {$stepCoro != {} && [info commands $stepCoro] != {}} {
            rename $stepCoro {}
        }
        # nothing more to do if the cmdStack is empty
        if {$cmdStack == {}} {
            break
        }
        
        # cmdStack is not empty. Get nextCmd from the first values in
        # the stack
        set cCoro [lindex $cmdStack 1]
        lassign [$cCoro $LastResult] nextCmd stepCoro
        
        # This is the place to eventually get out of a currently executed
        # step. Process all remaining commands in the current stack without
        # breakpoint, then assign the first command in the stack to nextCmd.
        # The stack will be reduced afterwards since cCoro does not longer 
        # exist.
        if {$DebugCmd == "o"} {
            # step out
            while {[info commands $cCoro] != {}} {
                set LastResult [uplevel $nextCmd]
                if {$stepCoro != {}} {
                    rename $stepCoro {}
                }
                lassign [$cCoro $LastResult] nextCmd stepCoro
            }
            #set cmdStack [lassign $cmdStack nextCmd stepCoro]
            set cmdStack [lrange $cmdStack 2 end]
            set cCoro [lindex $cmdStack 1]
            lassign [$cCoro $LastResult] nextCmd stepCoro
            
            #set nextCmd [lindex $cmdStack 0]
            #set stepCoro [lindex $cmdStack 1]
            puts outwith,$nextCmd
        }
        
        # Pop current cmd and coro from the stack, if there are no 
        # commands left
        if {[info commands $cCoro] == {}} {
            set cmdStack [lrange $cmdStack 2 end]
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
}

package provide tdb 0.1
