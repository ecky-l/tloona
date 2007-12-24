#
# implements debug facilities for Tcl
#
#   [breakpoint] set breakpoints in the code
#   [step] step one command forwards from breakpoint
#   [next] step over the next command
#
   
package provide debug 1.0

namespace eval ::debug {
    variable break ""
    variable log ""
    variable enter ""
    variable step ""
    variable argv
    variable argv0

    set argv $::argv
    set argv0 $::argv0
}
proc ::debug::var {name key} {
    if {$key eq ""} {return $name}
    return $name\($key\)
}

proc ::debug::Log {name1 name2 op} {
    switch -- $op {
        read - 
        write {
            eputs "$op [var $name1 $name2]=[uplevel 1 set [var $name1 $name2]]"
        }
        unset {
            eputs "unset [var $name1 $name2]"
            if {[Unlog [var $name1 $name2]]<0} {
                Unlog $name1
                }
        }
        default {error "unknown $op"}
        }
}

proc ::debug::Unlog {name} {
    variable log
    set i [lsearch -exact $log $name]
    if {$i<0} {return -1}
    set log [lreplace $log $i $i]
    catch {
        trace remove variable $name {read write unset} ::debug::Log
    }
    return 0
}

proc ::debug::Store {list elt} {
    if {[lsearch -exact $list $elt]>=0} {return $list}
    lappend list $elt
    return $list
}

proc ::debug::Break {name1 name2 op} {
    switch -- $op {
        read - 
        write {
            eputs "$op [var $name1 $name2]=[uplevel 1 set [var $name1 $name2]]"
            uplevel 1 ::debug::debug
        }
        unset {
            eputs "unset [var $name1 $name2]"
            if {[Unbreak [var $name1 $name2]]<0} {
                Unbreak $name1
                }
        }
        default {error "unknown $op"}
    }
}

proc ::debug::Unbreak {name} {
    variable break
    set i [lsearch -exact $break $name]
    if {$i<0} {return -1}
    set break [lreplace $break $i $i]
    catch {
        trace remove variable $name {read write unset} ::debug::Break
    }
    return 0
}

proc ::debug::Enter {cmdstring op} {
    switch -- $op {
        enter {
            eputs "entering [lindex $cmdstring 0]"
            uplevel 1 ::debug::debug [list $cmdstring]
        }
        default {error "unknown $op"}
    }
}

proc ::debug::Unenter {name} {
    variable enter
    set i [lsearch -exact $enter $name]
    if {$i<0} {return -1}
    set enter [lreplace $enter $i $i]
    catch {
        trace remove execution $name enter ::debug::Enter
    }
    return 0
}

proc ::debug::Step {cmdstring op} {
    switch -- $op {
        enterstep {
            eputs $cmdstring
            uplevel 1 ::debug::debug [list $cmdstring]
        }
        default {error "unknown $op"}
    }
}

proc ::debug::Unstep {name} {
    variable step
    set i [lsearch -exact $step $name]
    if {$i<0} {return -1}
    set step [lreplace $step $i $i]
    catch {
        trace remove execution $name enterstep ::debug::Step
    }
    return 0
}

proc ::debug::assert {expr {message ""}} {
    if {[uplevel 1 expr $expr]} {return}
    if {$message eq ""} {set message "assertion failed: $expr"}
    error $message
}

proc ::debug::p {varname} {
    if {[uplevel 1 array exists $varname]} {
        uplevel 1 parray $varname
        return
    }
    if {[uplevel 1 info exists $varname]} {
        eputs "$varname = [uplevel 1 set $varname]"
    } else {
        eputs "variable $varname does not exist"
    }
}

proc ::debug::Prompt {} {
    return {TclDebugger by S.Arnold. v0.1 2007-09-08}
}

proc ::debug::eputs {str} {puts stderr $str}

proc ::debug::Interact {{cmdstring ""}} {
    debug $cmdstring
}

proc ::debug::debug {{cmdstring ""}} {
    set help {Commands are:
        h or ?      prints this message
        a or >      prints the command being executed
        p               prints the current level proc
        e or !      evals a command
        =           prints the content of each variable name
        var         watchs the modifications of some variables
        log     logs all modifications to stderr
        break   adds breakpoint for writes
        info    prints all variables being watched for
        clear   clears logging and breaks
        cmd
        enter   set a break point for the entering of a command
        step    steps through the command
        clear   clear break points (using glob patterns)
        c       continue execution
        r       restarts the program
        x or q  exit the debugger}
    set help [Prompt]\n$help
    while 1 {
        puts -nonewline stderr "dbg> "
        flush stderr
        gets stdin line
        switch -- [lindex $line 0] {
            h - 
            ? {
                eputs $help
            }
            e - 
            ! {
                if {[catch {eputs [uplevel 1 [lrange $line 1 end]]} msg]} {
                    eputs "error: $msg"
                }
            }
            a - 
            > {
                eputs $cmdstring
            }
            p {
                eputs [uplevel 1 info level 0]
            }
            = {
                foreach var [lrange $line 1 end] {uplevel 1 ::debug::p $var}
            }
            var {
                assert {[llength $line]<=3} "bad syntax, $line has more than 3 tokens"
                foreach {subcmd value} [lrange $line 1 end] {
                    break
                }
                switch -- $subcmd {
                    log {
                        variable log
                        set log [Store $log $value]
                        uplevel 1 [list trace add variable $value {read write unset} ::debug::Log]
                    }
                    break {
                        variable break
                        set break [Store $break $value]
                        uplevel 1 [list trace add variable $value {read write unset} ::debug::Break]
                    }
                    info {
                        foreach {n t} {log Logged break "Breaks at"} {
                            variable $n
                            eputs "=== $t: ==="
                            eputs [set $n]
                            eputs "----"
                        }
                    }
                    clear {
                        foreach {v t cmd} {log Logged Unlog break "Breaks at" Unbreak} {
                            eputs "clearing $t..."
                            variable $v
                            foreach i [set $v] {
                                if {[string match $value $i]]} {
                                    eputs $i
                                    # unlogs or unbreaks the variable
                                    ::debug::$cmd $i
                                }
                            }
                        }
                    }
                    default {
                        error "no such subcommand: $subcmd"
                    }
                }
            }
            cmd {
                assert {[llength $line]<=3} "bad syntax, $line has more than 3 tokens"
                foreach {subcmd value} [lrange $line 1 end] {break}
                switch -- $subcmd {
                    enter {
                        variable enter
                        set enter [Store $enter $value]
                        trace add execution $value enter ::debug::Enter
                            }
                            step {
                                variable step
                                set step [Store $step $value]
                                trace add execution $value enterstep ::debug::Step
                            }
                            info {
                                foreach {n t} {enter Enters step Stepping} {
                                    variable $n
                                    eputs "=== $t: ==="
                                    eputs [set $n]
                                    eputs "----"
                                    }
                            }
                            clear {
                                foreach {v t cmd} {enter Enters Unenter step Stepping Unstep} {
                                    eputs "clearing $t..."
                                    variable $v
                                    foreach i [set $v] {
                                        if {[string match $value $i]} {
                                            eputs $i
                                            # 'unenters' or 'unstep' the command
                                            ::debug::$cmd $i
                                                    }
                                            }
                                    }
                            }
                            default {
                                error "no such subcommand: $subcmd"
                            }
                    }
            }
            c {
                return
            }
            r {
                variable argv0
                variable argv
                eval exec [list [info nameofexecutable] $argv0] $argv
                exit
            }
            x - q {
                exit
            }
            }
    }
}
proc ::debug::prepare {} {
    global argv argv0
    # Start the program!
    set argv0 [lindex $argv 0]
    set argv [lrange $argv 1 end]
    # Prompts
    puts stderr [debug::Prompt]
    puts stderr "type h to the prompt to get help"
    if {![file exists $argv0]} {
        set argv0 [auto_execok $argv0]
        }
}

debug::prepare

proc up {} {
    uplevel 2 {
        breakpoint
    }
}

proc down {} {
    return -code continue
}


proc breakpoint {condition {code 0} {result ""}} {
    if {$code > 1} {
        return -code $code $result
    }

    set cmd ""
    set level [expr {[info level]-1}]
    set prompt "Debug ($level) % "
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
            set prompt "Debug ($level) % "
            set cmd ""
        } else {
            set prompt "    "
        }
    }    
}

proc wbreak {} {
    
}
