package provide topoSort 1.0

namespace eval topoSort {
  namespace export topoSort
################################################################
# proc topoSort {nodes}--
#    Return a sorted list of indices
# Arguments
#   nodes:  A list of edges - 
#  {{node1 {edge1.2 edge1.3}} {node2 {edge2.3 edge2.4}} {node3 {} }}
# 
# Results
#   Returns a list of nodes in sorted order.
# 
proc topoSort {nodes} {
    set sortlst ""
    set rtnList ""
    set nodes [cleanit $nodes]

    while {[llength $nodes] > 0} {
        set l1 [findTerminal $nodes]
	if {[string match $l1 ""]} {
	    foreach n $nodes {
	        lappend rtnList [lindex $n 0]
	    }
	    break;
	}
	set nodes [purge $nodes $l1]
	append rtnList " " $l1
    }
    return $rtnList
}

proc cleanit {list} {
    set rtnList {}
    foreach i $list {
        lappend nodes [lindex $i 0]
    }
    foreach i $list {
        set l3 ""
	set i0 [lindex $i 0]
        foreach i1 [lindex $i 1] {
	    if {([lsearch $nodes $i1] >= 0) &&
	        (![string match $i1 $i0])} {
	        lappend l3 $i1
	    }
	}
	lappend rtnList [list $i0 $l3]
    }
    return $rtnList
}

proc findTerminal {list } {
    set emptys ""

    foreach l $list {
        if {[llength [lindex $l 1]] == 0} {
	    lappend emptys [lindex $l 0]
	}
    }
    
    return $emptys
}

proc purge {list1 list2} {
    set l3 ""
    foreach l1 $list1 {
        set l [lindex $l1 1]
        foreach l2 $list2 {
	    if {[set pos [lsearch $l $l2 ]] >= 0} {
	        set l [lreplace $l $pos $pos]
	    }
	}
	if {[lsearch $list2 [lindex $l1 0]] < 0} {
	    # puts "lsearch $list2 [lindex $l1 0] [lsearch $list2 [lindex $l1 0]] "
	    lappend l3 [list [lindex $l1 0] $l]
	}
    }
return $l3
}

}

