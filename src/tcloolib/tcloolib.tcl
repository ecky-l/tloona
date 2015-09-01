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
    
    method DoCmdGC {oldname newname op} {
        if {[info obj isa object $obj]} {
            trace remove command $obj {rename delete} \
                [list [namespace origin my] DoGC $obj]
            $obj destroy
        }
    }
    
    ## \brief Delete locally created objects
    method DoVarGC {obj name1 name2 op} {
        if {[info obj isa object $obj]} {
            $obj destroy
        }
        uplevel [list trace remove variable $name1 \
            {write unset} [list [namespace origin my] DoVarGC $obj]]
    }
    
    ## \brief Create an object that is linked to a variable
    #
    # Works like create, but instead of a command name, the first argument is 
    # a variable name. It can then be used like any other Tcl variable.
    # Additionally, a variable {write unset} trace is added which automatically
    # destroys the object when the variable is overwritten or unset. This has
    # the side effect that an object which was created using [varcreate] inside
    # a procedure or method is automatically destroyed when the variable is
    # local (but not when the variable is global, it is a namespace variable or
    # hooked up by upvar / namespace upvar). It has also the effect that the
    # objects destructor is called when the object was varcreate'd in a slave
    # interpreter and this interp is deleted.
    # However, other variables that point to the object are not traced, so this
    # is not a full GC
    method varcreate {varName args} {
        upvar $varName obj
        set obj [my new {*}$args]
        my installVars $obj [self] {*}[info class variables [self]]
        uplevel [list trace add variable $varName \
            {write unset} [list [namespace origin my] DoVarGC $obj]]
        return
    }
    
    ## \brief install variable defaults in case there is no (constructor)
    method new {args} {
        set obj [next {*}$args]
        trace add command $obj {rename delete} [list [namespace origin my] DoCmdGC $obj]
        my installVars $obj [self] {*}[info class variables [self]]
        return $obj
    }
    
    ## \brief create named or local objects 
    method create {args} {
        set obj [next {*}$args]
        trace add command $obj {rename delete} [list [namespace origin my] DoCmdGC $obj]
        my installVars $obj [self] {*}[info class variables [self]]
        return $obj
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
