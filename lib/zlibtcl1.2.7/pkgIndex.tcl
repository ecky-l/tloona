
# @@ Meta Begin
# Package zlibtcl 1.2.7
# Meta activestatetags ActiveTcl Public
# Meta as::author      {Jan Nijtmans}
# Meta as::build::date 2013-01-07
# Meta as::origin      http://sourceforge.net/projects/tkimg
# Meta description     A variant of the libz system library made suitable
# Meta description     for direct loading as a Tcl package.
# Meta license         BSD
# Meta platform        win32-ix86
# Meta require         {Tcl 8.4}
# Meta summary         zlib Support
# @@ Meta End


if {![package vsatisfies [package provide Tcl] 8.4]} return

package ifneeded zlibtcl 1.2.7 [string map [list @ $dir] {
        # ACTIVESTATE TEAPOT-PKG BEGIN REQUIREMENTS

        package require Tcl 8.4

        # ACTIVESTATE TEAPOT-PKG END REQUIREMENTS

            load [file join {@} zlibtcl127.dll]

        # ACTIVESTATE TEAPOT-PKG BEGIN DECLARE

        package provide zlibtcl 1.2.7

        # ACTIVESTATE TEAPOT-PKG END DECLARE
    }]
