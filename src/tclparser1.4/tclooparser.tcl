## \brief Parser package for TclOO

package require parser 1.4
package require parser::script 1.0
package require Itree 1.0
package require Tclx 8.4
package require log 1.2
package require sugar 0.1
package require parser::tcl 1.0
package require parser::macros 1.0

::sugar::macro m-exist-node {cmd pNode name class} {
    list expr \{\[lsearch \[lmap o \[$pNode lookupAll $name\] \[list \
        expr \{\[\$o isa $class \] && \[\$o cget -name\] eq $name\}\]\] 1\] >= 0\}
}

namespace eval ::Parser {
    
    ## \brief The base class for all OO systems.
    class ClassNode {
        inherit ::Parser::Script
        constructor {args} {chain {*}$args} {
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
                set pNode [findChildren -name $m]
                if {$pNode == "" || ![itcl::is object $pNode]} {
                    continue
                }
                foreach {v} $vs {
                    $pNode addVariable $v 0 1
                }
            }
            
        }
        
        ## \brief Update all methods with command names
        public method updateCommands {} {
            set cs [getProcs]
            foreach {p} $cs {
                set pNode [findChildren -name $p]
                if {$pNode == "" || ![itcl::is object $pNode]} {
                    continue
                }
                foreach {pp} $cs {
                    $pNode addProcName $pp
                }
            }
        }
        
    }
    
    ## \brief A specialized proc for representing methods and class procs
    class OOProcNode {
        inherit ::Parser::ProcNode
        constructor {args} {chain {*}$args} {}
        
        ## \brief Indicates whether the body is defined externally
        public variable bodyextern 0
        
        ## \brief The declaration of Proc or methods. This might be separate
        #         from the definition.
        public variable declaration ""
        
        ## \brief The declaration bytecode range
        public variable decbrange {}
        
    }
    
    class TclOOClassNode {
        inherit ClassNode
        constructor {args} {chain {*}$args} {}
    }
}

## \brief Contains class and procedures for parsing TclOO code
namespace eval ::Parser::TclOO {
    
    ## \brief Create a class from previously parsed name and definition
    proc createClass {node clsName clsDef defRange} {
        #set nsAll [regsub -all {::} [string trimleft $clsName :] " "]
        #set clsName [lindex $nsAll end]
        set nsNode [::Parser::Util::getNamespace $node \
            [lrange [split [regsub -all {::} $clsName ,] ,] 0 end-1]]
        set clsName [namespace tail $clsName]
        #set nsNode [::Parser::Util::getNamespace $node [lrange $nsAll 0 end-1]]
        set clsNode [$nsNode lookup $clsName]
        if {$clsNode == ""} {
            set clsNode [::Parser::TclOOClassNode ::#auto -expanded 0 \
                    -name $clsName -isvalid 1 -token class]
            $nsNode addChild $clsNode
        }
        $clsNode configure -isvalid 1 -definition [string trim $clsDef "{}"] \
            -defbrange $defRange -token class -inherits {} -inheritstring {}
        return $clsNode
    }
    
    ::sugar::proc parseConstructor {node cTree content mdo defOffPtr} {
        upvar $defOffPtr defOff
        set defEnd 0
        
        set defLst [list cDef $mdo argList [incr mdo] cBody [incr mdo]]
        foreach {tkn idx} $defLst {
            set $tkn [m-parse-token $content $cTree $idx]
        }
        lassign [m-parse-defrange $cTree $mdo] defOff defEnd
        set argList [lindex $argList 0]
        set cBody [string trim $cBody \{\}]
        
        # return existing method node if already present
        set csNode [$node lookup "constructor"]
        if {$csNode == "" || [$csNode cget -type] != "constructor"} {
            set csNode [::Parser::ConstructorNode ::#auto -type "constructor" \
                -name "constructor" -arglist $argList -definition $cBody]
            $node addChild $csNode
        }
        $csNode configure -arglist $argList -definition $cBody -isvalid 1
        return $csNode
    }
    
    ::sugar::proc parseDestructor {node cTree content mdo defOffPtr} {
        upvar $defOffPtr defOff
        set defEnd 0
        set dDef ""
        
        foreach {tkn idx} [list dDef $mdo dBody [incr mdo]] {
            set $tkn [m-parse-token $content $cTree $idx]
        }
        lassign [m-parse-defrange $cTree $mdo] defOff defEnd
        
        set dNode [$node lookup "destructor"]
        if {$dNode == "" || [$dNode cget -type] != "destructor"} {
            set dNode [::Parser::OOProcNode ::#auto -type destructor -name destructor]
            $node addChild $dNode
        }
        $dNode configure -definition $dBody -isvalid 1
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
    # This method tries to grasp all posibilities and creates a Parser::OOProcNode
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
    # \param[in] mdo
    #    The method definition offset, defines where to find the "method" keyword
    #    in the parse tree. If parseMethod was called from a class
    #    definition, it is zero (the default). If it is called from an oo::define
    #    statement, the "method" keyord is at position 2
    # \param[out] defOffPtr Pointer to definition offset
    ::sugar::proc parseMethod {node cTree content offset mdo defOffPtr} {
        upvar $defOffPtr defOff
        set nTk [llength $cTree]
        set dOff 0
        
        # method blubb {args} {body}
        
        foreach {tkn idx} [list def $mdo methName [incr mdo] \
                argList [incr mdo] methBody [incr mdo]] {
            set $tkn [m-parse-token $content $cTree $idx]
        }
        lassign [m-parse-defrange $cTree $mdo] defOff dEnd
        set methBody [string trim $methBody "\{\}"]
        set accLev public
        if {![regexp {^[a-z]} $methName]} {
            set accLev protected
        }
        set argList [lindex $argList 0]
        set strt [lindex [lindex [lindex $cTree 0] 1] 0]
        
        # return existing method node if already present
        set mNode [$node lookup $methName]
        if {$mNode == "" || [$mNode cget -type] != "[set accLev]_method"} {
            set mNode [::Parser::OOProcNode ::#auto -type "[set accLev]_method" \
                -name $methName -arglist $argList -definition $methBody \
                -defoffset [expr {$defOff - $strt}]]
            $node addChild $mNode
        }
        $mNode configure -arglist $argList -definition $methBody -isvalid 1 \
            -defoffset [expr {$defOff - $strt}]
        
        # setup local variables for code completion
        ::Parser::parse $mNode [expr {$defOff + $offset}] $methBody
        
        return $mNode
    }
    
    ## \brief Parse variables
    ::sugar::proc parseVar {node cTree content off {mdo 0}} {
        set vNode [::Parser::Tcl::parseVar $node $cTree $content $off $mdo]
        if {$vNode ne ""} {
            set t private_variable
            set n [string index [$vNode cget -name] 0]
            if {[string is lower $n]} {
                set t public_variable
            } elseif {[string is upper $n]} {
                set t protected_variable
            }
            $vNode configure -type $t
        }
        return $vNode
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
                break
            }
            set codeTree [lindex $res 3]
            if {$codeTree == ""} {
                break
            }
            # get and adjust offset and line
            set cmdRange [lindex $res 1]
            lset cmdRange 0 [expr {[lindex $cmdRange 0] + $off}]
            lset cmdRange 1 [expr {[lindex $cmdRange 1] - 1}]
            
            # get the first token and decide further operation
            set token [m-parse-token $content $codeTree 0]
            switch -glob -- $token {
                superclass - (superclass) {
                    parseInherit $node $codeTree $content
                }
                
                method {
                    set defOff 0
                    set mNode [parseMethod $node $codeTree $content $off 0 defOff]
                    $mNode configure -token $token -byterange $cmdRange
                    ::Parser::parse $mNode $off [$mNode cget -definition]
                    $node addMethod $mNode
                }
                
                constructor - (constructor) {
                    set defOff 0
                    set csNode [parseConstructor $node $codeTree $content 0 defOff]
                    $csNode configure -token $token -byterange $cmdRange
                    ::Parser::parse $csNode [expr {$off + $defOff}] [$csNode cget -definition]
                }
                
                destructor {
                    set defOff 0
                    set dNode [parseDestructor $node $codeTree $content 0 defOff]
                    $dNode configure -token $token -byterange $cmdRange
                    ::Parser::parse $dNode [expr {$off + $defOff}] [$dNode cget -definition]
                }
                
                variable - (variable) {
                    set vNode [parseVar $node $codeTree $content $off 0]
                    if {$vNode != ""} {
                        $vNode configure -token $token -byterange $cmdRange
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
    
    ## \brief Parses the oo::define command to alter class definitions.
    ::sugar::proc parseDefine {node cTree content cmdRange off} {
        # Get associated class node
        set cls [m-parse-token $content $cTree 1]
        set nsNode [::Parser::Util::getNamespace $node \
            [lrange [split [regsub -all {::} $cls ,] ,] 0 end-1]]
        set cls [namespace tail $cls]
        set clsNode [$nsNode lookupAll $cls ::Parser::TclOOClassNode]
        if {$clsNode == ""} {
            set clsNode [::Parser::TclOOClassNode ::#auto -expanded 0 \
                    -name $cls -isvalid 1 -token class]
            $nsNode addChild $clsNode
        }
        # get defined token and decide what to do
        set token [m-parse-token $content $cTree 2]
        switch -- $token {
        constructor {
            set defOff 0
            set csNode [parseConstructor $clsNode $cTree $content 2 defOff]
            $csNode configure -byterange $cmdRange
            ::Parser::parse $csNode [expr {$off + $defOff}] [$csNode cget -definition]
        }
        destructor {
            set defOff 0
            set dNode [parseDestructor $clsNode $cTree $content 2 defOff]
            $dNode configure -byterange $cmdRange
            ::Parser::parse $dNode [expr {$off + $defOff}] [$dNode cget -definition]
        }
        method {
            set defOff 0
            set mNode [parseMethod $clsNode $cTree $content $off 2 defOff]
            $mNode configure -byterange $cmdRange
            ::Parser::parse $mNode [expr {$off + $defOff}] [$mNode cget -definition]
        }
        variable {
            set vNode [parseVar $clsNode $cTree $content $off 2]
            $vNode configure -byterange $cmdRange
        }
        
        }
    }
}

package provide parser::tcloo 1.0
