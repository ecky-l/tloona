## tcloolib.tcl (created by Tloona here)

namespace eval ::tcloolib {

## \brief A mixin object that defines "public variable" behaviour of Itcl.
# 
# Defines methods [configure] and [cget], which are used to set and get the 
# values of public variables. This is done by calls like
# [obj configure -varname1 value -varname2 value] and [obj cget -varname] 
# respectively (with a dash in front of the variable name). The configuration
# or cget occurs on an object variable name without the dash.
# 
# Constructors can also be called with the variables, and usually there is a 
# traditional call to [eval configure $args] in every constructor of an Itcl
# object. Since this has been repetitive all the time, we can now let
# the mixin object do it automatically.
::oo::class create confcget {
    
    ## \brief does automatically [configure -var value] pairs.
    # 
    # But only if the args list is expressible as -var value pairs.
    # If not (the list is not even or any of the keys does not contain 
    # a dash as first character), then no configuration is done!
    constructor {args} {
        if { [llength $args] % 2 == 0
               && [lsearch [lmap _x [dict keys $args] {string comp -l 1 $_x -}] 1] < 0 } {
            my configure {*}$args
        }
        if {[self next] != {}} {
            next {*}$args
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

## \brief A meta class for default variable assignment and inheritance
#
# When defining classes, it is almost always very convenient to assigns 
# default values, like 
# 
# 'variable varname value'
# 'variabel varname {}'
#
# These default values should be assigned during object construction, so
# that they are available in every method if not defined to be something 
# else and it is not always necessary to check for existence before using
# the variables.
# Additionally the variables and defaults shall be installed automatically
# in derived classes (but not in mixins)
::oo::class create (class) {
    superclass ::oo::class
    variable _Defaults
    variable _SetGet
    variable _RefVars
    
    ## \brief Installs handlers for oo::define before creating the class
    constructor {args} {
        set _Defaults {}
        set _SetGet {}
        interp alias {} ::oo::define::(variable) {} [self] (variable)
        interp alias {} ::oo::define::(superclass) {} [self] (superclass)
        interp alias {} ::oo::define::(constructor) {} [self] (constructor)
        ::oo::define [self] mixin ::tcloolib::confcget
        next {*}$args
    }
    
    ## \brief Delete locally created objects
    method DoGC {obj name1 name2 op} {
        if {![info obj isa object $obj]} {
            uplevel [list trace remove variable $name1 \
                {write unset} [list [namespace origin my] DoGC $obj]]
            return
        }
        
        # look for other references to the object. This is not quite stable
        foreach {var} [uplevel info vars] {
            if {![uplevel info exists $var]} {
                continue
            }
            if {[uplevel array exists $var]} {
                # maybe
            } elseif {[uplevel set $var] eq $obj} {
                if {[lsearch [dict get $_RefVars $obj] $var] >= 0} {
                    continue
                }
                dict lappend _RefVars $obj $var
                uplevel [list trace add variable $var \
                    {write unset} [list [namespace origin my] DoGC $obj]]
            }
        }
        
        set rv [dict get $_RefVars $obj]
        set idx [lsearch $rv $name1]
        if {$idx >= 0} {
            dict set _RefVars $obj [lreplace $rv $idx $idx]
            uplevel [list trace remove variable $name1 \
                {write unset} [list [namespace origin my] DoGC $obj]]
        }
        if {[dict get $_RefVars $obj] == {}} {
            dict unset _RefVars $obj
            $obj destroy
        }
    }
    
    ## \brief Some experimentation for GC objects
    #
    # GC can occur by destroying an object as soon as all references (variables)
    # that point to it are unset. Start here with a write/unset trace on the 
    # first variable for the object, which does GC (see DoGC).
    # Once the trace is added, it is easy. The hard part is to keep track of 
    # all variables that point to the object, especially on global / namespace 
    # level and when objects are part of other objects. Because of this it is
    # not really functional right now.
    method creategc {args} {
        set varName [lindex $args 0]
        upvar $varName obj
        set obj [my new {*}[lrange $args 1 end]]
        my installVars $obj [self] {*}[info class variables [self]]
        dict set _RefVars $obj $varName
        uplevel [list trace add variable $varName \
            {write unset} [list [namespace origin my] DoGC $obj]]
        return $obj
    }
    
    ## \brief install variable defaults in case there is no (constructor)
    method new {args} {
        set o [next {*}$args]
        my installVars $o [self] {*}[info class variables [self]]
        return $o
    }
    
    ## \brief create named or local objects 
    method create {args} {
        set o [next {*}$args]
        my installVars $o [self] {*}[info class variables [self]]
        return $o
    }
    
    ## \brief Installs variables from superclass in this class
    #
    # Can be used instead of [superclass] to have the variables from 
    # superclass and defaults defined in this class and all its objects.
    # Private variables are denoted by preceeding underscore _ and
    # filtered out here.
    method (superclass) {args} {
        ::oo::define [self] superclass {*}$args
        
        set filterExpr {expr { [string comp -l 1 $x _] ? $x : [continue] }}
        lmap c [info cl superclass [self]] {
            lmap v [lmap x [info cl var $c] $filterExpr] {
                if {[$c varDefault $v val]} {
                    ::oo::define [self] (variable) $v {*}$val
                } else {
                    ::oo::define [self] (variable) $v
                }
            }
        }
        return ""
    }
    
    ## \brief Defines the constructor and installs variables
    #
    # Prepend some code in front of the constructor body, which takes the
    # vars from the class definition and installs the corresponding defaults
    # into the newly created object.
    # If a constructor is defined, it needs access to the variables and defaults.
    # Prepend code to install the variables in front of the constructor body, so
    # that the variable defaults are installed first, before anything else. 
    method (constructor) {args} {
        append cbody apply " \{ " 
        append cbody [info cl definition [self class] installVars] \n " \}"
        append cbody " " {[self] [self class] {*}[info class variables [self class]]} 
        append cbody [lindex $args 1]
        ::oo::define [self] constructor [lindex $args 0] $cbody
    }
    
    ## \brief The Variable with default command.
    #
    # Is executed with a definition script after [create] (from the 
    # constructor) or with calls to oo::define <cls> (variable). 
    # Arranges for the default to be installed in all existing 
    # or new instances of this class.
    # For private and protected variables there is additional support
    # for automatic getter and setter generation. If one or both of
    # the switches {-set, -get} are in the arguments after the value,
    # methods {"setVarname", "getVarname"} are created. The name is
    # constructed from the varname (uppercase first letter for 
    # peotected, underscore _ for private). This happens only if there
    # are no methods of the same name already defined.
    method (variable) {args} {
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
            my installVars $o [self] [lindex $args 0]
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
    method installVars {obj cls args} {
        set ov [info obj vars $obj]
        set ns [info obj namespace $obj]
        lmap v [lmap x $args {expr {($x in $ov) ? [continue] : $x}}] {
            if {[$cls varDefault $v val]} {
                namespace eval $ns [list variable $v [lindex $val 0]]
            } else {
                namespace eval $ns [list variable $v]
            }
        }
    }
    
    export (variable) (superclass) (constructor)
    
} ;# defaultvars


} ;# namespace ::oo

package provide tcloolib 0.1
