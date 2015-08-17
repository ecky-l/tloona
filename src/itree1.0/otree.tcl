## otree.tcl (created by Tloona here)
## The itree::Node as tcloo implementation

namespace eval ::oo {

## \brief A mixin object that defines "public variable" behaviour of Itcl.
# 
# Every Itcl object defines methods [configure] and [cget], which are used
# to set and get the values of public variables. This is done by calls like
# [obj configure -varname1 value -varname2 value] and [obj cget -varname] 
# respectively (note the dash in front of the variable name). The configuration
# or cget occurs on an object variable name without the dash.
# 
# This style is so helpful that I don't want to miss it :-). I also think that
# it can safely be applied to the ::oo::class object, as long as you know what
# configure and cget means
# 
# Constructors can also be called with the variables, and usually there is a 
# traditional call to [eval configure $args] in every constructor of an Itcl
# object. Since this has been very repetitive all the time, we can now let
# the mixin object do it automatically.
class create confcget {
    
    ## \brief does automatically [configure -var value] pairs.
    # 
    # But only if the args list is expressible as -var value pairs.
    # If not (the list is not even or any of the keys does not contain 
    # a dash as first character), then no configuration is done!
    constructor {args} {
        if {[self next] != {}} {
            next {*}$args
        }
        if { [llength $args] % 2 == 0
               && [lsearch [lmap _x [dict keys $args] {string comp -l 1 $_x -}] 1] < 0 } {
            my configure {*}$args
        }
    }
    
    ## \brief setting -var value pairs
    method configure {args} {
        if {[llength $args] % 2 != 0
              || [lsearch [lmap _x [dict keys $args] {string comp -l 1 $_x -}] 1] >= 0 } {
            error "not var/value pairs: $args"
        }
        foreach {var val} $args {
            set var [string range $var 1 end]
            if {[string is upper [string index $var 0]]} {
                error "$var seems to be a private variable"
            }
            my variable $var
            set $var $val
        }
    }
    
    ## \brief get the value of -variable
    method cget {var} {
        if {[string compare -length 1 $var -] != 0} {
            error "Usage: obj cget -var"
        }
        set var [string range $var 1 end]
        if {[string is upper [string index $var 0]]} {
            error "$var seems to be a private variable"
        }
        my variable $var
        return [set $var]
    }
    
}

## \brief Helper class to install the ccget object in every ::oo::class
class create confcgetc {
    method create {args} {
        set r [next {*}$args]
        ::oo::define $r mixin confcget
        return $r
    }
}

# from here on, *every* class that is created in this interp is capable
# to do the "public variable style" of Itcl.
define class mixin confcgetc

} ;# namespace ::oo


namespace eval ::otree {

::oo::class create Node {
    
    ## \brief the node name, which is also displayed
    variable name

    ## \brief image: an image to display in front of the name.
    variable image
    
    ## \brief depth of this node in a tree hierarchy
    variable level
    
    ## \brief Display format list. 
    # Contains a string as accepted by [format] (e.g. %s) followed by 
    # the attributes that are to be displayed, e.g. -name. E.g. {%s -name}. 
    # The resulting string is displayed as the node's name in a tree display
    variable displayformat
    
    ## \brief indicates whether the node is displayed
    variable displayed
    
    ## \brief A type associated with the node. Makes image display in a browser easy
    variable type
    
    ## \brief Whether the item is expanded on a display
    variable expanded
    
    ## \brief columnData that is associated with an item.
    # When the node is displayed in a Ttk browser, this is the data that goes in the 
    # columns. The list must match the column count.
    variable coldata
    
    ## \brief indicates that this node should be deleted when it is removed from its parent.
    variable dynamic
    
    ## \brief the child nodes
    variable Children
    
    ## \brief The parent node
    variable Parent
    
    constructor {args} {
        set name ""
        set image ""
        set level 0
        set displayformat {}
        set displayed no
        set type ""
        set expanded no
        set coldata {}
        set dynamic no
        set Children {}
        set Parent {}
    }
    
    destructor {
        my removeChildren
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

} ;# namespace ::otree
