package require sugar

sugar::tailrecproc printlist l {
    if {[llength $l]} {
	puts [lindex $l 0]
	printlist [lrange $l 1 end]
    }
}

printlist {1 2 3 4}
