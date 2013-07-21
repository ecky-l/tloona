## \brief Parser package for TclOO

package require parser 1.4
package require parser::script 1.0
package require Itree 1.0
package require Tclx 8.4
package require log 1.2
package require sugar 0.1
package require parser::tcl 1.0
package require parser::macros 1.0

namespace eval ::Parser {
    
    ## \brief The base class for all OO systems.
    class ClassNode {
        inherit ::Parser::Script
        constructor {args} {
            eval configure $args
            addVariable this 0 1
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
        
        ## \brief Update all methods with the class variables.
        public method updateVariables {} {
            set vs [getVariables 1]
            foreach {m} [getProcs] {
                foreach {v} $vs {
                    $m addVariable $v
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
    
    ::sugar::proc parseConstructor {node cTree content defOffPtr} {
        upvar $defOffPtr defOff
        set defEnd 0
        
        set nTk [llength $cTree]
        set firstTkn [m-parse-token $content $cTree 0]
        set argList ""
        set initDef ""
        set initBr {}
        set constDef ""
        set defIdx 2
        if {$nTk == 3} {
            # constructor without access level
            set argList [m-parse-token $content $cTree 1]
            set constDef [m-parse-token $content $cTree 2]
            set defIdx 2
        } elseif {$nTk == 4} {
            if {$firstTkn == "constructor"} {
                # Constructor with init Code
                set argList [m-parse-token $content $cTree 1]
                set initDef [m-parse-token $content $cTree 2]
                set initBr [m-parse-defrange $cTree 2]
            } else {
                # access level definition
                set argList [m-parse-token $content $cTree 2]
            }
            set constDef [m-parse-token $content $cTree 3]
            set defIdx 3
        } elseif {$nTk == 5} {
            # Constructor with access and init code
            set argList [m-parse-token $content $cTree 2]
            set initDef [m-parse-token $content $cTree 3]
            set initBr [m-parse-defrange $cTree 3]
            set constDef [m-parse-token $content $cTree 4]
            set defIdx 4
        } else {
            return ""
        }
        
        set defRange [m-parse-defrange $cTree $defIdx]
        set defOff [lindex $defRange 0]

        set argList [lindex $argList 0]
        set constDef [string trim $constDef \{\}]
        
        # return existing method node if already present
        set csNode [$node lookup "constructor"]
        if {$csNode != "" && [$csNode cget -type] == "constructor"} {
            $csNode configure -arglist $argList -definition $constDef -isvalid 1 \
                -initdefinition $initDef -initbrange $initBr
            return $csNode
        }
        
        set csNode [::Parser::ConstructorNode ::#auto -type "constructor" \
            -name "constructor" -arglist $argList -definition $constDef \
                -initdefinition $initDef -initbrange $initBr]
        $node addChild $csNode
        
        return $csNode
        
    }
    
    ::sugar::proc parseDestructor {node cTree content defOffPtr} {
        upvar $defOffPtr defOff
        set defEnd 0
        set dDef ""
        
        if {[llength $cTree] == 2} {
            set range [lindex [lindex $cTree 1] 1]
            set dDef [::parse getstring $content $range]
            lassign [m-parse-defrange $cTree 1] defOff defEnd
        } else {
            # TODO: for access level
            return
        }
        
        set dNode [$node lookup "destructor"]
        if {$dNode != "" && [$dNode cget -type] == "destructor"} {
            $dNode configure -definition $dDef -isvalid 1
            
            return $dNode
        }
        
        set dNode [::Parser::ProcNode ::#auto -definition $dDef \
            -type "destructor" -name "destructor"]
        $node addChild $dNode
        
        return $dNode
        
    }
    
    proc parseInherit {node cTree content} {
        set classes {}
        set clsStr ""
        for {set i 1} {$i < [llength $cTree]} {incr i} {
            set range [lindex [lindex $cTree $i] 1]
            set iCls [::parse getstring $content $range]
            append clsStr ", [string trimleft $iCls :]"
            
            set nsAll [regsub -all {::} [string trimleft $iCls :] " "]
            set iCls [lindex $nsAll end]
            set iNode ""
            if {[llength $nsAll] > 1} {
                # parent class has namespace qualifiers
                set tn [$node getTopnode]
                set iNode [$tn lookup $iCls [lrange $nsAll 0 end-1]]
            } else {
                set iNode [[$node getParent] lookup $iCls]
            }
            
            if {$iNode != ""} {
                lappend classes $iNode
            }
            
        }
        
        $node configure -inherits $classes -inheritstring [string range $clsStr 2 end]
    }
    
    
    ## \brief Parses a method node inside Itcl classes.
    #
    # Given a token list, the method node can be one of the following:
    # <ul>
    # <li>(public|protected|private) method bla {args} {def}</li>
    # <li>(public|protected|private) method bla {args}</li>
    # <li>method bla {args} {def}</li>
    # <li>method bla {args}</li>
    # </ul>
    # When no definition is given, the definition is outside via the itcl::body
    # command or the method is virtual (needs to be overridden by derived classes).
    # This method tries to grasp all posibilities and creates a Parser::ProcNode
    # describing the method found in the source. It then parses the Node and sets
    # all variables found in the class definition to the body, so that code
    # completion will find them.
    #
    # \param[in] node
    #    The parent class node
    # \param[in] cTree
    #    The code tree where the method definition is at first place
    # \param[in] content
    #    The content string with the definition
    # \param[in] offset
    #    Byte offset in the current file. Important for definition parsing
    # \param[in] accLev
    #    The access level, one of public, protected or private
    ::sugar::proc parseMethod {node cTree content offset} {
        set nTk [llength $cTree]
        set dOff 0
        
        # method blubb {args} {body}
        foreach {tkn idx} {def 0 methName 1 argList 2 methBody 3} {
            set $tkn [m-parse-token $content $cTree $idx]
        }
        lassign [m-parse-defrange $cTree 3] dOff dEnd
        set accLev public
        if {![regexp {^[a-z]} $methName]} {
            set accLev protected
        }
        set argList [lindex $argList 0]
        set strt [lindex [lindex [lindex $cTree 0] 1] 0]
        
        # return existing method node if already present
        set mNode [$node lookup $methName]
        if {$mNode == "" || [$mNode cget -type] != "[set accLev]_method"} {
            set mNode [::Parser::ProcNode ::#auto -type "[set accLev]_method" \
                -name $methName -arglist $argList -definition $methBody \
                -defoffset [expr {$dOff - $strt}]]
            $node addChild $mNode
        }
        $mNode configure -arglist $argList -definition $methBody -isvalid 1 \
            -defoffset [expr {$dOff - $strt}]
        
        return $mNode
    }

    ## \brief Parse a class node and returns it as tree
    ::sugar::proc parseClassDef {node off content} {
        
        if {$content == ""} {
            return
        }
        set size [::parse getrange $content]
        
        while {1} {
            # if this step fails, we must not proceed
            if {[catch {::parse command $content {0 end}} res]} {
                return
            }
            set codeTree [lindex $res 3]
            if {$codeTree == ""} {
                return
            }
            # get and adjust offset and line
            set cmdRange [lindex $res 1]
            lset cmdRange 0 [expr {[lindex $cmdRange 0] + $off}]
            lset cmdRange 1 [expr {[lindex $cmdRange 1] - 1}]
            
            # get the first token and decide further operation
            set token [m-parse-token $content $codeTree 0]
            switch -glob -- $token {
                superclass {
                    parseInherit $node $codeTree $content
                }
                
                method {
                    set mNode [parseMethod $node $codeTree $content $off]
                    $mNode configure -byterange $cmdRange
                    ::Parser::parse $mNode $off [$mNode cget -definition]
                    $node addMethod $mNode
                }
                
                constructor {
                    set defOff 0
                    set csNode [parseConstructor $node $codeTree $content defOff]
                    $csNode configure -byterange $cmdRange
                    ::Parser::parse $csNode [expr {$off + $defOff}] [$csNode cget -definition]
                }
                
                destructor {
                    set defOff 0
                    set dNode [parseDestructor $node $codeTree $content defOff]
                    $dNode configure -byterange $cmdRange
                    ::Parser::parse $dNode [expr {$off + $defOff}] [$dNode cget -definition]
                }
                
                variable {
                    set vNode [::Parser::Tcl::parseVar $node $codeTree $content]
                    if {$vNode != ""} {
                        $vNode configure -byterange $cmdRange
                    }
                }
                
            }
            
            # step forward in the content
            set idx [lindex [lindex $res 2] 0]
            incr off $idx
            set content [::parse getstring $content [list $idx end]]
        }
        
        $node updateVariables
        if {[$node cget -isitk]} {
            $node addVariable itk_interior 0 1
            $node addVariable itk_option 0 1
        }
        $node updatePTokens
        $node addVariable this 0 1
    }
    
    
}

package provide parser::tcloo 1.0
