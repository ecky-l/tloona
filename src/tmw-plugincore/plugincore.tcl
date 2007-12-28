#
# tmw::plugincore
#
package require Itcl 3.3
catch {namespace import ::itcl::*}

package provide tmw::plugincore 1.0

namespace eval Tmw {
    namespace eval Plugin {
        # @v PluginDir: the directory that contains the plugins
        variable PluginDir [file join $::env(HOME) .tmw]
        
        # @v Registry: array defining host plugins and a list
        # @v Registry: of hosted plugins of them
        variable Registry {}
        variable _currPlugin ""
        
        # @v Extends: array defining guest plugins and a list
        # @v Extends: of their hosts
        variable Extends
        array set Extends {}
        # @v ExtendedBy: array of host plugins
        variable ExtendedBy
        array set ExtendedBy {}
        # @v Instances: list of registered instances to every plugin
        variable Instances
        array set Instances {}
        # @v Extensions: array of extensions for a plugin
        variable Extensions
        array set Extensions {}
        
        if {[info exists ::env(APPDATA)]} {
            set PluginDir [file join $::env(APPDATA) .tmw]
        }
        
        namespace export plugin extends
    }
}

# @c Base class for all plugins
class ::Tmw::Plugin::Plugin {
    public {
        method register {code args} {
            eval $code
        }
    }
}

proc ::Tmw::Plugin::plugin {id} {
    variable Registry
    variable _currPlugin
    variable Instances
    variable Extends
    variable ExtendedBy
    
    if {[lsearch $Registry $id] >= 0} {
        error "plugin $id already registered"
    }
    lappend Registry $id
    set Instances($id) {}
    set Extends($id) {}
    set ExtendedBy($id) {}
    set _currPlugin $id
}

proc ::Tmw::Plugin::extends {plugin code args} {
    variable Registry
    variable _currPlugin
    variable Extends
    variable Extensions
    variable Instances
    variable ExtendedBy
    
    if {[lsearch $Registry $_currPlugin] < 0} {
    }
    if {[lsearch $Registry $plugin] < 0} {
    }
    
    set Extensions($plugin,components) {}
    set Extensions($plugin,buttons) {}
    set Extensions($plugin,menuentries) {}
    foreach {a v} $args {
        switch -- $a {
            -components {
                set Extensions($plugin,components) $v
            }
            -buttons {
                set Extensions($plugin,buttons) $v
            }
            -menuentries {
                set Extensions($plugin,menuentries) $v
            }
        }
    }
    lappend Extends($_currPlugin) $plugin $code
    lappend ExtendedBy($plugin) $_currPlugin $code 0
    
    set i 0
    foreach {inst reg} $Instances($plugin) {
        if {$reg} {
            # already registered with this instance
            continue
        }
        $inst register $code
        lset Instances($plugin) [expr {$i + 1}] 1
        incr i 2
    }
}

# @c loads packages in a directory
proc ::Tmw::Plugin::load_packages {{dir ""}} {
    global auto_path
    variable PluginDir
    
    if {$dir == ""} {
        set dir $PluginDir
    }
    if {![file exists $dir]} {
        file mkdir $dir
        return
    }
    
    set auto_path [concat $dir $auto_path]
    foreach {kit} [glob -nocomplain [file join $dir] *.kit] {
        source $kit
    }
}

proc ::Tmw::Plugin::addinstance {plugin instance} {
    variable Registry
    variable Instances
    variable ExtendedBy
    
    if {[lsearch $Registry $plugin] < 0} {
        error "plugin $plugin does not exist"
    }
    if {[lsearch $Instances($plugin) $instance] >= 0} {
        error "instance $instance already registered for plugin $plugin"
    }
    lappend Instances($plugin) $instance 0
    set i 0
    foreach {plug code reg} $ExtendedBy($plugin) {
        if {$reg} {
            # already registered in this plugin
            continue
        }
        $instance register $code
        
        lset ExtendedBy($plugin) [expr {$i + 2}] 1
        incr i 3
    }
}

namespace import Tmw::Plugin::*
