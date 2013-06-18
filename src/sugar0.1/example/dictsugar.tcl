# Syntax sugar for [dict].
# Copyright(C) 2004 Salvatore Sanfilippo
#
# Performed expansions:
#
# From:
#   mydict<-a.$b.c $newval
#
# To:
#   dict set mydict a $b c $newval
#
# This expansion only works if the "<-" form is the first argument
# of a command.
#
# From:
#   puts $mydict->a.$b.c
#
# To:
#   puts [dict get $mydict a $b c]
#
# This expansion only works if the "->" form is one argument
# of a command in any position, but not with general interpolation.
# To use the "->" form in any case, like inside "" quotation, use
# [format], like in:
#
# puts "[format %s%s $mydict->a $mydict->b]"

package require sugar
package require Tcl 8.5

sugar::syntaxmacro dictsugar args {
    for {set i 0} {$i < [llength $args]} {incr i} {
	set tok [lindex $args $i]
	set level 0
	set idx {}
	set keyidx {}
	for {set j 0} {$j < [string length $tok]} {incr j} {
	    set current [string index $tok $j]
	    set next [string index $tok [expr {$j+1}]]
	    switch -- $current {
		"\\" {incr j}
		"\[" {incr level}
		"\]" {if {$level > 0} {incr level -1}}
		"-" {
		    if {$level == 0 && [llength $idx] == 0 && $next eq {>}} {
			set idx $j
			set type get
		    }
		}
		"<" {
		    if {$level == 0 && [llength $idx] == 0 && $next eq {-}} {
			set idx $j
			set type set
		    }
		}
		"." {
		    if {$level == 0 && [llength $idx]} {
			lappend keyidx [expr {$j-$idx-3}]
		    }
		}
	    }
	}
	if {[llength $idx]} {
	    lappend keyidx [expr {$j-$idx-3}]
	    set left [string range $tok 0 [expr {$idx-1}]]
	    set right [string range $tok [expr {$idx+2}] end]
	    #puts "$left ... $type ... $right ($keyidx)"

	    set keypath {}
	    set startidx 0
	    foreach k $keyidx {
		lappend keypath [string range $right $startidx $k]
		set startidx [expr {$k+2}]
	    }
	    if {$type eq {get}} {
		lset args $i "\[dict get $left [join $keypath]\]"
	    } elseif {$type eq {set} && $i == 0} {
		set value [lindex $args [expr {$i+1}]]
		set args [list dict set $left]
		foreach k $keypath {
		    lappend args $k
		}
		lappend args $value
	    }
	}
    }
    return $args
}

sugar::proc test {} {
    foreach k {foo bar foobar helloworld} {
	dict<-$k "Hello $k"
	puts $dict->$k
    }
}

test
