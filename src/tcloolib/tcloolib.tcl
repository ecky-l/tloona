## tcloolib.tcl (created by Tloona here)

namespace eval ::tcloolib {

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
::oo::class create confcget {
    
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

## \brief A meta class mixin for default variable assignment
#
# When defining classes, it is almost always very convenient to assigns 
# default values, like 
# 
# 'variable varname value'
# 'variabel varname {}'
#
# These default values should be assigned during object construction 
# and use, so that it is not necessary to have [a] useful defaults at
# hand if nothing else was defined and [b] not always check for existence
# of an object variable before using it.
# 
# Since TclOO does not support this concept, we have to tweak it to do so.
# Here is a way via an object that is designed to be mixed in meta classes
# or the ::oo::class command itself:
# 
# 'oo::define oo::class mixin defaultvars'
# 
# It provides a new command 'Variable' (note the uppercase first letter!) 
# as an object command and an accompanying ::oo::define::Variable. Both 
# together are used in '::oo::class create' resp '::oo::define ... Variable'
# statements to install the variable and its default into the class.
# The variables with defaults are then installed into every new object
# that is created from this class.
::oo::class create defaultvars {
    variable _Defaults
    variable _SetGet
    
    ## \brief Installs handlers for oo::define before creating the class
    constructor {args} {
        set _Defaults {}
        set _SetGet {}
        interp alias {} ::oo::define::Variable {} [self] Variable
        interp alias {} ::oo::define::Superclass {} [self] Superclass
        next {*}$args
    }
    
    ## \brief installs the variables defined by class in the object
    method new {args} {
        set o [next {*}$args]
        my installVars $o {*}[info class variables [self]]
        return $o
    }
    
    ## \brief Installs variables from superclass in this class
    #
    # This definer can be used instead of [superclass] to have
    # the variables from the superclass defined with defaults in
    # this class and all its objects.
    # Filter private variables by preceeding underscore _
    method Superclass {args} {
        ::oo::define [self] superclass {*}$args
        
        set filterExpr {expr { [string comp -l 1 $x _] ? $x : [continue] }}
        lmap c [info cl superclass [self]] {
            lmap v [lmap x [info cl var $c] $filterExpr] {
                if {[$c varDefault $v val]} {
                    ::oo::define [self] Variable $v {*}$val
                } else {
                    ::oo::define [self] Variable $v
                }
            }
        }
        return ""
    }
    
    ## \brief The Variable with default command.
    #
    # Is executed with a definition script after [create] (from the 
    # constructor) or with calls to oo::define <cls> Variable. 
    # Arranges for the default to be installed in all existing 
    # or new instances of this class.
    # For private and protected variables there is additional support
    # for automatic getter and setter generation. If one or both of
    # the switches {-set, -get} are in the arguments after the value,
    # methods {"setVarname", "getVarname"} are created. The name is
    # constructed from the varname (mind: uppercase first letter for 
    # peotected, underscore _ for private). This happens only if there
    # are no methods of the same name already defined.
    method Variable {args} {
        ::oo::define [self] variable [lindex $args 0]
        if {[llength $args] >= 2} {
            dict set _Defaults [lindex $args 0] [lrange $args 1 end]
        }
        
        # install getters and setters for private/protected variables
        set vn [string index [lindex $args 0] 0]
        if {[string match $vn _] || [string is upper $vn] 
                && [llength $args] >=3} {
            set rem [lrange $args 2 end]
            set varName [lindex $args 0]
            if {[lsearch $rem -get] >= 0 && 
                    [lsearch [info cl methods [self]] get[set varName]] < 0} {
                ::oo::define [self] method \
                    get[set varName] {} " return \$$varName "
            }
            if {[lsearch $rem -set] >= 0 &&
                    [lsearch [info cl methods [self]] set[set varName]] < 0} {
                ::oo::define [self] method \
                    set[set varName] {value} " set $varName \$value "
            }
        }
        
        lmap o [info class inst [self]] {
            my installVars $o [lindex $args 0]
        }
        return
    }
    
    ## \brief Checks whether there is a default value.
    #
    # If there is one, returns true and sets the value in valPtr
    # Otherwise leaves valPtr as it is and returns false.
    method varDefault {var valPtr} {
        upvar $valPtr val
        if {[dict exists $_Defaults $var]} {
            set val [dict get $_Defaults $var]
            return 1
        }
        return 0
    }
    
    ## \brief Installs variables from the args list in an object obj.
    method installVars {obj args} {
        set ov [info obj vars $obj]
        set ns [namespace which $obj]
        lmap v [lmap x $args {expr {($x in $ov) ? [continue] : $x}}] {
            if {[my varDefault $v val]} {
                namespace eval $ns [list variable $v [lindex $val 0]]
            } else {
                namespace eval $ns [list variable $v]
            }
        }
    }
    
    export Variable Superclass
    
} ;# defaultvars


## \brief use the named mixin
#
# Some (one) of the classes are designed to be mixins for oo::class. 
# If they are mixed in to oo::class, this will last forever, until 
# the interp is deleted or the mixin is removed.
# This procedure makes it easy to use a particular mixin by name.
proc usemixin {name} {
    set name [namespace tail $name]
    tailcall ::oo::define ::oo::class mixin [namespace current]::[set name]
}


} ;# namespace ::oo

package provide tcloolib 0.1
