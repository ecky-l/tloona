
package require starkit

if {[starkit::startup] eq "sourced"} {
    set r [file dirname [file normalize [info script]]]
    set ::auto_path [concat $r $::auto_path]
}