# @c A plugin registry for (GUI intensive) Projects.
# 
# @c A plugin provides functionality that can be linked in existing
# @c functionality at runtime. This works through extension points and
# @c extensions. Extension points are procedures of a plugin that can 
# @c be executed everytime when the plugin is completely loaded in an
# @c interp. These procedures know *how* to extend themselves by certain
# @c functionality. Consumer plugins state that they want to extend any
# @c plugin by making a request via [extends]. They provide a list of
# @c arguments via another procedure (or any code fragment that is 
# @c scheduled to be called later). The key point is that the extension
# @c point procedure understands this list and can be called with the
# @c respective arguments (and produces a useful result).
#
# @c The difference to a package is, that the plugin is two fold: Provider
# @c plugins can modify their own appearance and functionality by consumer
# @c plugins without the need to know about these consumer plugins from the 
# @c beginning. As long as the consumer plugin serves the contract - which 
# @c are the correct arguments to extension point procedures, the consumer
# @c plugin does not need to be coded, released or even thought about. Later, 
# @c when the consumer plugin is installed, [plugin load] is called on it, 
# @c which leads to execution of the provider plugin's extension point
# @c procedure with the consumer pugin's arguments. It does everything that 
# @c is necessary to set set up the extended functionality.
if {$tcl_version < 8.5} {
    package require dict
}
package re debug
package provide tmw::plugin 1.0

namespace eval ::Tmw::Plugin {
    # @v A list of plugins, their requirements, extension points and versions
    variable Plugins {}
    # @v Holds the current plugin for extension point creation
    variable CurrPlugin ""
}

# @c Registers a new extensionpoint or redefines an old one
# @c for a given plugin
proc Tmw::Plugin::extensionpoint {name callProc} {
    variable Plugins
    variable CurrPlugin
    set cpl [dict get $Plugins $CurrPlugin]
    dict lappend cpl extensionpoints $name $callProc
    dict set Plugins $CurrPlugin $cpl
}

# @c defines argument proc for extensionpoints for a given plugin
# @c Te plugin is connected to all plugins that provide the requested
# @c extension point - and the proc that is registered with the
# @c extension point is run with the output of the extends proc as
# @c arguments
proc Tmw::Plugin::extends {plugin extPoint argProc} {
    variable Plugins
    variable CurrPlugin
    
    if {![dict exists $Plugins $plugin]} {
        error "Plugin $plugin does not exist"
    }
    if {![dict exists [dict get $Plugins $plugin] extensionpoints]} {
        error "Plugin $plugin does not define extension points"
    }
    set exts [dict get [dict get $Plugins $plugin] extensionpoints]
    if {![dict exists $exts $extPoint]} {
        error "Extension point $extPoint does not exist in $plugin"
    }
    
    set cpl [dict get $Plugins $CurrPlugin]
    if {[dict exists $cpl extends]} {
        set exts [dict get $cpl extends]
        if {[dict exists $exts $plugin]} {
            set dd [dict replace [dict get $exts $plugin] $extPoint $argProc]
            dict set exts $plugin $dd
        } else {
            dict lappend exts $plugin $extPoint $argProc
        }
        dict set cpl extends $exts
        dict set Plugins $CurrPlugin $cpl
        return
    }
    dict set cpl extends $plugin [list $extPoint $argProc]
    dict set Plugins $CurrPlugin $cpl
}

# @c Get the plugin content suitable for [dict]
proc Tmw::Plugin::get {name} {
    variable Plugins
    dict get $Plugins $name
}

# @c usage: plugin provide <name> <ver> <block>
# @c where <block> contains extensionpoint and extens statements
proc Tmw::Plugin::provide {name ver code} {
    variable Plugins
    variable CurrPlugin
    
    dict set Plugins $name [list version $ver]
    set CurrPlugin $name
    eval $code
    set CurrPlugin ""
}

# @c Loads a plugin by executing the procedures that are registered
# @c for the arguments (extends) and for the extension points
proc Tmw::Plugin::load {name} {
    variable Plugins
    if {![dict exists $Plugins $name]} {
        error "Plugin $name does not exist"
    }
    set pl [dict get $Plugins $name]
    if {![dict exists $pl extends]} {
        error "Plugin $name can not be loaded, no extend requests defined"
    }
    
    dict for {extPlug extLst} [dict get $pl extends] {
        set exts [dict get [dict get $Plugins $extPlug] extensionpoints]
        dict for {extPnt argProc} [dict get $extLst] {
            # eval [dict get $exts $extPnt] [eval $argProg]
            puts [dict get $exts $extPnt],$argProc
        }
    }
}

# @c Load required plugins if exist to provide them to a consumer plugin
proc Tmw::Plugin::require {args} {
}

# @c plugin command. Registers plugins (plugin provide) and their
# @c requirements (plugin require).
proc plugin {args} {
    namespace eval ::Tmw::Plugin $args
}
