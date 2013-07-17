# This file is sourced intoa backend Tclsh process. It contains
# procedures to step through the backend process and return the
# variable and stack trace info as well as the currently executed
# code place.
# All this info is printed to stdout in a defined protocol and can
# be read from there
#package require atkdebugger 0.21

package provide tmw::debugger 1.0

namespace eval TloonaDbg {}

proc ::TloonaDbg::escapeFunnyChars {input} {
    regsub -all {<} $input {\&lt;} input
    regsub -all {>} $input {\&gt;} input
    return $input
}

# @c This procedure prints the debug info to stdout in an XML structure
# @c The XML can be read from a frontend process (using IO pipes or any
# @c other communication mechanism) and parsed into whatever form is
# @c necessary.
proc ::TloonaDbg::putsDebuginfo {} {
    global errorInfo
    
    uplevel {
    puts -nonewline $TloonaDbg_channel "<debuginfo "
    if {[atk::wasError]} {
        global errorInfo
        puts $TloonaDbg_channel "type=\"error\">"
        puts $TloonaDbg_channel "<errorinfo>"
        puts $TloonaDbg_channel $errorInfo
        puts $TloonaDbg_channel "</errorinfo>"
    } else {
        puts $TloonaDbg_channel "type=\"breakpoint\">"
    }
    
    puts $TloonaDbg_channel "<stacktrace>"
    for {set TloonaDbg_i 0} {$TloonaDbg_i <= [atk::debuglevel]} {incr TloonaDbg_i} {
        set TloonaDbg_place [atk::runplace $TloonaDbg_i]
        puts -nonewline $TloonaDbg_channel "<callframe level=\"$TloonaDbg_i\" "
        puts -nonewline $TloonaDbg_channel "offset=\"[lindex $TloonaDbg_place 1]\" "
        puts $TloonaDbg_channel "length=\"[lindex $TloonaDbg_place 2]\">"
        if {$TloonaDbg_i > 0} {
            puts $TloonaDbg_channel " <command>[info level $TloonaDbg_i]</command>"
        }
        set fi [lindex $TloonaDbg_place 1]
        set ni [expr {$fi + [lindex $TloonaDbg_place 2]}]
        unset TloonaDbg_place fi ni
        
        # local variables
        foreach {TloonaDbg_var} [uplevel #$TloonaDbg_i info locals] {
            if {[string match TloonaDbg* $TloonaDbg_var]} {
                # ignore local variables from the debugger
                continue
            }
            puts -nonewline $TloonaDbg_channel "<variable scope=\"local\" name=\"$TloonaDbg_var\" "
            if {[uplevel #$TloonaDbg_i array exists $TloonaDbg_var]} {
                puts -nonewline $TloonaDbg_channel "type=\"array\">"
                puts -nonewline $TloonaDbg_channel \{[TloonaDbg::escapeFunnyChars \
                    [uplevel #$TloonaDbg_i array get $TloonaDbg_var]]\}
            } else {
                if {[llength [uplevel #$TloonaDbg_i set $TloonaDbg_var]] > 1} {
                    puts -nonewline $TloonaDbg_channel "type=\"list\">"
                } else {
                    puts -nonewline $TloonaDbg_channel "type=\"string\">"
                }
                #puts -nonewline "type=\"string/list\">"
                puts -nonewline $TloonaDbg_channel \{[TloonaDbg::escapeFunnyChars \
                    [uplevel #$TloonaDbg_i set $TloonaDbg_var]]\}
            }
            
            puts $TloonaDbg_channel "</variable>"
        }
        
        # global variables
        foreach {TloonaDbg_var} [info globals] {
            if {[string match TloonaDbg* $TloonaDbg_var] ||
                    [string equal errorInfo $TloonaDbg_var]} {
                # ignore local variables from the debugger
                continue
            }
            puts -nonewline $TloonaDbg_channel "<variable scope=\"global\" name=\"$TloonaDbg_var\" "
            if {[uplevel #0 array exists $TloonaDbg_var]} {
                puts -nonewline $TloonaDbg_channel "type=\"array\">"
                puts -nonewline $TloonaDbg_channel \{[TloonaDbg::escapeFunnyChars \
                    [uplevel #0 array get $TloonaDbg_var]]\}
            } else {
                if {[llength [uplevel #0 set $TloonaDbg_var]] > 1} {
                    puts -nonewline $TloonaDbg_channel "type=\"list\">"
                } else {
                    puts -nonewline $TloonaDbg_channel "type=\"string\">"
                }
                #puts -nonewline "type=\"string/list\">"
                puts -nonewline $TloonaDbg_channel \{[TloonaDbg::escapeFunnyChars \
                    [uplevel #0 set $TloonaDbg_var]]\}
            }
            puts $TloonaDbg_channel "</variable>"
        }
        puts $TloonaDbg_channel "</callframe>"
    }
    
    puts $TloonaDbg_channel "</stacktrace>"
    puts $TloonaDbg_channel "</debuginfo>"
    }
}

atk::debugByError no

atk::debugproc {
    global errorInfo
    set TloonaDbg_channel stdout
    while {1} {
        if {[catch {TloonaDbg::putsDebuginfo} msg]} {
            puts $errorInfo
        }
        
        switch -- [gets stdin] {
            s - step {
                atk::stepInto
                break
            }
            n - next {
                atk::stepOver
                break
            }
            c - continue {
                break
            }
        }
    }
    
}
