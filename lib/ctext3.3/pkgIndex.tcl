
# @@ Meta Begin
# Package ctext 3.3
# Meta activestatetags ActiveTcl Public Tklib
# Meta as::build::date 2014-06-25
# Meta as::origin      http://sourceforge.net/projects/tcllib
# Meta category        Ctext a text widget with highlighting support
# Meta description     Ctext a text widget with highlighting support
# Meta license         BSD
# Meta platform        tcl
# Meta recommend       {Tk 8.5}
# Meta subject         widget text {syntax highlighting}
# Meta summary         ctext
# @@ Meta End


if {![package vsatisfies [package provide Tcl] 8.4]} return

package ifneeded ctext 3.3 [string map [list @ $dir] {
            source [file join {@} ctext.tcl]

        # ACTIVESTATE TEAPOT-PKG BEGIN DECLARE

        package provide ctext 3.3

        # ACTIVESTATE TEAPOT-PKG END DECLARE
    }]
