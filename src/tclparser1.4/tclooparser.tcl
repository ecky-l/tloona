## \brief Parser package for TclOO

package require parser 1.4
package require parser::script 1.0
package require Itree 1.0
package require Tclx 8.4
package require log 1.2
package require sugar 0.1
package require parser::tcl 1.0


namespace eval ::Parser {
    
    ## \brief The base class for all OO systems.
    class ClassNode {
        inherit ::Parser::Script
        constructor {args} {
            eval configure $args
        }
        
        ## \brief The type is always "class"
        public variable type class
        
        # The token that defines the script (e.g. eval, namespace, type, class...)
        public variable token ""
        
        public variable inherits {}
        public variable isitk 0
        
        # @v inheritstring: A string containing the base classes of this
        # @v inheritstring: class comma separated. Used for displayformat
        public variable inheritstring ""
        # @v displayformat: overrides the display format for tests
        public variable displayformat {"%s : %s" -name -inheritstring}
            
        # @c insert the public and protected identifiers
        # @c (methods and variables) to this class
        public method updatePTokens {} {
            foreach {cls} $inherits {
                foreach {al} {public protected} {
                    set aln [$cls lookup $al]
                    if {$aln == ""} {
                        continue
                    }
                    foreach {chd} [$aln getChildren] {
                        switch -- [$chd cget -type] {
                            "method" {
                                addMethod $chd
                            }
                            "variable" {
                                set vName [$chd cget -name]
                                addVariable $vName 0 1
                            }
                        }
                    }
                }
            }
        }
    }
    
    class OOClassNode {
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
