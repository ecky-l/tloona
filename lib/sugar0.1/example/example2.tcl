package require sugar

sugar::macro inlist {name list element} {
    list expr "\{\[lsearch -exact $list $element\] != -1\}"
}

sugar::proc test {} {
    set list {tcl c ada python scheme forth joy smalltalk}
    foreach lang {pascal scheme php ada tcl} {
	if {[inlist $list $lang]} {
	    puts "$lang is in the list"
	} else {
	    puts "$lang is not in the list"
	}
    }
}

test
