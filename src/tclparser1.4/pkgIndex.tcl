package ifneeded parser 1.4 [list load [file join $dir libtclparser1.4[info sharedlibext]]]

package ifneeded parser::structuredfile 1.4  [list source [file join $dir structuredfile.itcl]]
package ifneeded parser::tcl 1.4  [list source [file join $dir tclparser.itcl]]
