## otree.tcl (created by Tloona here)
## The itree::Node as tcloo implementation

#package require tcloolib 0.1
source ../tcloolib/tcloolib.tcl

#tcloolib::usemixin defaultvars

namespace eval ::otree {

::tcloolib::(class) create node {
    
    ## \brief the node name, which is also displayed
    (variable) name ""

    ## \brief image: an image to display in front of the name.
    (variable) image {}
    
    ## \brief depth of this node in a tree hierarchy
    (variable) level 0
    
    ## \brief Display format list. 
    # Contains a string as accepted by [format] (e.g. %s) followed by 
    # the attributes that are to be displayed, e.g. -name. E.g. {%s -name}. 
    # The resulting string is displayed as the node's name in a tree display
    (variable) displayformat ""
    
    ## \brief indicates whether the node is displayed
    (variable) displayed no
    
    ## \brief A type associated with the node. Makes image display in a browser easy
    (variable) type
    
    ## \brief Whether the item is expanded on a display
    (variable) expanded
    
    ## \brief columnData that is associated with an item.
    # When the node is displayed in a Ttk browser, this is the data that goes in the 
    # columns. The list must match the column count.
    (variable) coldata
    
    ## \brief indicates that this node should be deleted when it is removed from its parent.
    (variable) dynamic 0
    
    ## \brief the child nodes
    (variable) Children {}
    
    ## \brief The parent node
    (variable) Parent {} -get -set
    
    destructor {
        my removeChildren
    }
    
    ## \brief Get the parent node
    method addChild {child} {
        if {[lsearch $Children $child] >= 0} {
            return
        }
        lappend Children $child
        $child setParent [self]
        return $child
    }
    
    method addChildren {args} {
        set nl [lmap c $args \
            {expr {[lsearch $Children $c] >= 0 ? [continue] : $c}}]
        foreach cc $nl {
            $cc setParent [self]
            lappend Children $cc
        }
        return $nl
    }
    
    ## \brief Removes a child, evtl. destroy it
    method removeChild {child} {
        if {[set i [lsearch $Children $child]] < 0} {
            return
        }
        if {[$child cget -dynamic]} {
            $child destroy
        }
        set Children [lreplace $Children $i $i]
        return $child
    }
    
    ## \brief Removes all children, evtl. destroy them
    method removeChildren {args} {
        if {[llength $args] == 0} {
            set args $Children
        }
        set newChilds {}
        foreach {c} $Children {
            if {$c ni $args} {
                lappend newChilds $c
                continue
            }
            if {[$c cget -dynamic]} {
                $c destroy
            }
        }
        set Children $newChilds
    }
    
    ## \brief Return children (recursive if deep is true)
    method getChildren {{deep 0}} {
        if {! $deep || $Children == {}} {
            return $Children
        }
        set lst $Children
        foreach ch $Children {
            set lst [concat $lst [$ch getChildren 1]]
        }
        return $lst
    }
    
    ## \brief Returns the next sibling (neighbour to the right) node 
    method nextSibling {} {
        if {$Parent == {}} {
            return
        }
        set ach [$Parent getChildren]
        set idx [lsearch $ach [self]]
        lindex $ach [incr idx]
    }
    
    ## \brief Returns the previous sibling (neighbour to the left) node 
    method prevSibling {} {
        if {$Parent == {}} {
            return
        }
        set ach [$Parent getChildren]
        set idx [lsearch $ach [self]]
        lindex $ach [incr idx -1]
    }
    
    ## \brief Lookup children using a filter
    # 
    # The filter is a proc or lambda expression that evaluates to a
    # boolean result: 1 if the node is to be returned, 0 otherwise.
    # It takes exactly one argument: the node itself. Example:
    # 
    # proc ::filter {node} {
    #    expr {[$node cget -name] eq "the_name"}
    # }
    # set nodesWith_the_name [$parentNode findChildren ::filter]
    #
    # set lambda [list apply {{n} { expr {[$n cget -name] eq "the_name"} }}]
    # set nodesWith_the_name [$parentNode findChildren $lambda]
    # 
    method findChildren {filter {recursive 0}} {
        lmap c [my getChildren $recursive] \
            { expr {[eval $filter $c] ? $c : [continue]} }
    }
    
    ## \brief Lookup parent nodes by name
    method findParents {filter {all 1}} {
        set p [my getParent]
        set result {}
        while {$p ne ""} {
            if {[eval $filter $p]} {
                lappend result $p
                if {! $all} {
                    break
                }
            }
            set p [$p getParent]
        }
        return $result
    }
}

::tcloolib::(class) create cnode {
    (superclass) ::otree::node
    (variable) x ""
}

} ;# namespace ::otree

package provide otree 1.0
