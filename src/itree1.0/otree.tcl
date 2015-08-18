## otree.tcl (created by Tloona here)
## The itree::Node as tcloo implementation
package require tcloolib 0.1

tcloolib::usemixin defaultvars

namespace eval ::otree {

::oo::class create Node {
    superclass ::tcloolib::confcget
    
    ## \brief the node name, which is also displayed
    Variable name ""

    ## \brief image: an image to display in front of the name.
    Variable image balla
    
    ## \brief depth of this node in a tree hierarchy
    Variable level 0
    
    ## \brief Display format list. 
    # Contains a string as accepted by [format] (e.g. %s) followed by 
    # the attributes that are to be displayed, e.g. -name. E.g. {%s -name}. 
    # The resulting string is displayed as the node's name in a tree display
    Variable displayformat ""
    
    ## \brief indicates whether the node is displayed
    Variable displayed no
    
    ## \brief A type associated with the node. Makes image display in a browser easy
    Variable type
    
    ## \brief Whether the item is expanded on a display
    Variable expanded
    
    ## \brief columnData that is associated with an item.
    # When the node is displayed in a Ttk browser, this is the data that goes in the 
    # columns. The list must match the column count.
    Variable coldata
    
    ## \brief indicates that this node should be deleted when it is removed from its parent.
    Variable dynamic
    
    ## \brief the child nodes
    Variable Children {}
    
    ## \brief The parent node
    Variable Parent {}
    
    Variable _PrivateVar ""
    
    destructor {
        my removeChildren
    }
    
    method getname {} {
        my variable name
        return $name
    }
    
    method setParent {other} {
        set Parent $other
    }
    
    method addChild {child} {
        if {[lsearch $Children $child] >= 0} {
            return
        }
        lappend Children $child
        $child setParent [self]
        return $child
    }
    
    method removeChildren {} {
        foreach {child} $Children {
            if {[$child cget -dynamic]} {
                $child destroy
            }
        }
    }
}

::oo::class create Cnode {
    Superclass ::otree::Node
    Variable x ""
}

} ;# namespace ::otree
