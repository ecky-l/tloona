#
# snit parser
#
package require parser 1.4
package require Itree 1.0
package require Tclx 8.4
package require log 1.2
package require parser::script 1.0
package require parser::itcl 1.0

package provide parser::snit 1.0

catch {
    namespace import ::itcl::*
}

namespace eval ::Parser::Snit {
    
    # @v CoreCommands: commands available for Tcl core and Itcl
    variable SnitCoreCommands {
        method
        macro 
        stringtype 
        window
        integer
        compile
        pixels
        widgetadaptor
        fpixels
        boolean
        type
        double
        widget
        enum
        listtype
    }
    
    class Type {
    }
    
    proc ParseBody {} {
    }
    
}

