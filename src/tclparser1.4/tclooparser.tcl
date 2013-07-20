## \brief Parser package for TclOO

package require parser 1.4
package require parser::script 1.0
package require Itree 1.0
package require Tclx 8.4
package require log 1.2
package require sugar 0.1
package require parser::tcl 1.0


namespace eval ::Parser {
    class ::Parser::OOClassNode {
        inherit ClassNode
        constructor {args} {eval chain $args} {}
    }
}

## \brief Contains class and procedures for parsing TclOO code
namespace eval ::Parser::TclOO {
    
    ## \brief Create a class from previously parsed name and definition
    proc createClass {node clsName clsDef defRange} {
        set nsAll [regsub -all {::} [string trimleft $clsName :] " "]
        set clsName [lindex $nsAll end]
        set nsNode [::Parser::Util::getNamespace $node [lrange $nsAll 0 end-1]]
        set clsNode [$nsNode lookup $clsName]
        if {$clsNode == ""} {
            set clsNode [::Parser::OOClassNode ::#auto -expanded 0 \
                    -name $clsName -isvalid 1 -token class]
            $nsNode addChild $clsNode
        }
        $clsNode configure -isvalid 1 -definition [string trim $clsDef "{}"] \
            -defbrange $defRange -token class 
        return $clsNode
    }
}

package provide parser::tcloo 1.0
