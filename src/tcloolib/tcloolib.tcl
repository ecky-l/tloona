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
    
    ## \brief Installs handlers for oo::define before creating the class
    constructor {args} {
        set _Defaults {}
        lmap cmd [info commands ::oo::define::*] {
            set cmd [namespace tail $cmd]
            oo::define [self class] method \
                $cmd {args} "oo::define \[self\] $cmd {*}\$args"
        }
        
        set myns [self namespace]::ns
        interp alias {} ::oo::define::Variable {} [self] Variable
        interp alias {} [set myns]::Variable {} [self] Variable
        
        foreach {cmd} [info o methods [self] -all] {
            if {$cmd ni {new create destroy}} {
                interp alias {} [set myns]::[set cmd] {} [self] $cmd
            }
        }
        tailcall namespace eval $myns {*}$args
    }
    
    ## \brief installs the variables defined by class in the object
    method new {args} {
        set o [next {*}$args]
        my InstallVars $o {*}[info class variables [self]]
        return $o
    }
    
    ## \brief The Variable with default command.
    #
    # Is executed with a definition script after [create] (from the 
    # constructor) or with calls to oo::define <cls> Variable. 
    # Arranges for the default to be installed in all existing 
    # or new instances of this class.
    method Variable {args} {
        ::oo::define [self] variable [lindex $args 0]
        if {[llength $args] == 2} {
            lappend _Defaults {*}$args
        }
        lmap o [info class inst [self]] {
            my InstallVars $o [lindex $args 0]
        }
        return ""
    }
    
    ## \brief Checks whether there is a default value.
    #
    # If there is one, returns true and sets the value in valPtr
    # Otherwise leaves valPtr as it is and returns false.
    method VarDefault {var valPtr} {
        upvar $valPtr val
        if {[dict exists $_Defaults $var]} {
            set val [dict get $_Defaults $var]
            return 1
        }
        return 0
    }
    
    ## \brief Installs variables from the args list in an object obj.
    method InstallVars {obj args} {
        set ov [info obj vars $obj]
        set ns [namespace which $obj]
        lmap v [lmap x $args {expr {($x in $ov) ? [continue] : $x}}] {
            if {[my VarDefault $v val]} {
                namespace eval $ns [list variable $v $val]
            } else {
                namespace eval $ns [list variable $v]
            }
        }
    }
    
    export Variable
}


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

# from here on, *every* class that is created in this interp can have
# variable defaults via the [Variable] definer
#define class mixin defaultvars

} ;# namespace ::oo

package provide tcloolib 0.1
