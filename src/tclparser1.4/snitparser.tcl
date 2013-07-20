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

namespace eval ::Parser {
    class SnitTypeNode {
        inherit ClassNode
        constructor {args} {eval chain $args} {}
    }
    class SnitWidgetNode {
        inherit SnitTypeNode
        constructor {args} {eval chain $args} {}
    }
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
    
    proc ParseBody {} {
    }
    
    ## \brief Create a Snit type or widget from predefined 
    proc createType {node clsName clsDef token defRange} {
        set nsAll [regsub -all {::} [string trimleft $clsName :] " "]
        set clsName [lindex $nsAll end]
        set clsDef [string trim $clsDef "\{\}"]
        
        set nsNode [::Parser::Util::getNamespace $node [lrange $nsAll 0 end-1]]
        #set clsNode [$node lookup $clsName $nsNode]
        set clsNode [$nsNode lookup $clsName]
        if {$clsNode != ""} {
            $clsNode configure -isvalid 1 -definition $clsDef \
                -defbrange $defRange -token class
        } else {
            set clsNode [::Parser::SnitTypeNode ::#auto -expanded 0 \
                    -name $clsName -isvalid 1 -definition $clsDef \
                    -defbrange $defRange -token $token]
            $nsNode addChild $clsNode
        }
        
        return $clsNode
    }
}

