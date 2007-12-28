#
# Tcl package index file
#

set library ""
switch -- $::tcl_version {
    8.4 {
        set library atkdebugger021-84[info sharedlibext]
    }
    8.5 {
        set library atkdebugger021-85[info sharedlibext]
    }
}

if {$library == ""} {
    error "atkdebugger not supported on this version, need 8.4/8.5"
}

package ifneeded atkdebugger 0.21 [list load [file join $dir $library] atkdebugger]
package ifneeded tmw::debugger 1.0 [list source [file join $dir debug.tcl]]
