#
# snit parser
#
package require parser 1.4
package require Itree 1.0
package require Tclx 8.4
package require log 1.2
package require parser::script 1.0
package require parser::tcloo 1.0
package require parser::tcl 1.0

package provide parser::snit 1.0

catch {
    namespace import ::itcl::*
}

namespace eval ::Parser {
    
    ## \brief A snit type (class) node. It behaves slightly other than a class node
    class SnitTypeNode {
        inherit ClassNode
        constructor {args} {chain {*}$args} {}
        
        public method updatePTokens {} {
        }
    }
    
    class SnitWidgetNode {
        inherit SnitTypeNode
        constructor {args} {chain {*}$args} {}
    }
    class SnitDelegateNode {
        inherit ::Parser::Script
        constructor {args} {chain {*}$args} {}
    }
    class SnitOptionNode {
        inherit ::Parser::Script
        public variable namespec {}
        public variable readonly 0
        public variable otype {}
        public variable cgetmethod {}
        public variable configuremethod {}
        public variable validatemethod {}
        constructor {args} {chain {*}$args} {}
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
        #set nsAll [regsub -all {::} [string trimleft $clsName :] " "]
        #set clsName [lindex $nsAll end]
        set clsDef [string trim $clsDef "\{\}"]
        
        set nsNode [::Parser::Util::getNamespace $node \
            [lrange [split [regsub -all {::} $clsName ,] ,] 0 end-1]]
        set clsName [namespace tail $clsName]
        #set nsNode [::Parser::Util::getNamespace $node [lrange $nsAll 0 end-1]]
        #set clsNode [$node lookup $clsName $nsNode]
        set clsNode [$nsNode lookup $clsName]
        if {$clsNode != ""} {
            $clsNode configure -isvalid 1 -definition $clsDef \
                -defbrange $defRange -token class
        } else {
            switch -glob -- $token {
            *widget -
            *widgetadaptor {
                set clsNode [::Parser::SnitWidgetNode ::#auto -expanded 0 \
                    -name $clsName -isvalid 1 -definition $clsDef \
                    -defbrange $defRange -token $token]
            }
            default {
                set clsNode [::Parser::SnitTypeNode ::#auto -expanded 0 \
                    -name $clsName -isvalid 1 -definition $clsDef \
                    -defbrange $defRange -token $token]
            }
            }
            $nsNode addChild $clsNode
        }
        
        switch -glob -- $token {
        *widget -
        *widgetadaptor {
            $clsNode addVariable win 0 1
            $clsNode addVariable hull 0 1
        }
        }
        
        $clsNode addVariable self 0 1
        $clsNode addVariable selfns 0 1
        $clsNode addVariable options 0 1
        
        $clsNode addProcName myvar
        $clsNode addProcName mytypevar
        $clsNode addProcName mymethod
        $clsNode addProcName mytypemethod
        $clsNode addProcName myproc
        $clsNode addProcName install
        $clsNode addProcName installhull
        $clsNode addProcName configure
        $clsNode addProcName configurelist
        $clsNode addProcName cget
        
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
        
        set dNode [::Parser::OOProcNode ::#auto -definition $dDef \
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
        set methBody [string trim $methBody "\{\}"]
        set accLev [expr {
            [string is upper [string index $methName 0]] ? "private" : "public"
        }]
        set argList [lindex $argList 0]
        set strt [lindex [lindex [lindex $cTree 0] 1] 0]
        
        # return existing method node if already present
        set mNode [$node lookup $methName]
        if {$mNode == "" || [$mNode cget -type] != "[set accLev]_method"} {
            set mNode [::Parser::OOProcNode ::#auto -type "[set accLev]_method" \
                -name $methName -arglist $argList -definition $methBody \
                -defoffset [expr {$dOff - $strt}]]
            $node addChild $mNode
        }
        $mNode configure -arglist $argList -definition $methBody -isvalid 1 \
            -defoffset [expr {$dOff - $strt}]
        
        # parse the content to find variables
        ::Parser::parse $mNode [expr {$dOff + $offset}] $methBody
        return $mNode
    }
    
    ## \brief Parses the component command
    # 
    # Has the form 
    #    component name ?-public <method name>? ?-inherit flag?
    # 
    # Will be put inside the class node under a node "Components"
    sugar::proc parseComponent {node cTree content off dBdPtr} {
        upvar $dBdPtr dBdOff
        set dBdEnd 0
        
        set cName [m-parse-token $content $cTree 1]
        lassign [m-parse-defrange $cTree 1] dBdOff dBdEnd
        
        # Components are usually created in constructors or methods, 
        # get the class where the component belongs to.
        set clsNode [$node findParent -type class]
        set cmpn [$clsNode lookup "Components"]
        if {$cmpn == ""} {
            set cmpn [$clsNode addChild [::Parser::Script ::#auto \
                -type itk_components -name "Components" -expanded 0]]
        }
        $cmpn configure -isvalid 1
        
        set compNode [$cmpn lookup $cName]
        if {$compNode == ""} {
            set compNode [::Parser::ItkComponentNode ::#auto]
            $cmpn addChild $compNode
        }
        
        $compNode configure -type public_component -name $cName -isvalid 1
        
        return $compNode
    }
    
    ## \brief Parses the delegate statement inside a snit definition
    #
    # Which has the form
    #    delegate method name to component as othername 
    #    delegate method name to component using {other} 
    #    delegate option -name to component as -othername 
    #    delegate method|option * to component 
    sugar::proc parseDelegate {node cTree content off dBdPtr} {
        upvar $dBdPtr dBdOff
        set dBdEnd 0
        
        set moro [m-parse-token $content $cTree 1]
        set dtype [expr {
            $moro == "method" ? "snit_delegate" : "snit_delegate_option"
        }]
        
        set cName [m-parse-token $content $cTree 2]
        set dargs [list -isvalid 1 -type $dtype -name $cName]
        set def {}
        for {set i 3} {$i < [llength $cTree]-1} {incr i 2} {
            lappend def [m-parse-token $content $cTree $i] \
                [m-parse-token $content $cTree [expr {$i + 1}]]
        }
        lappend dargs -definition $def
        
        set clsNode [$node findParent -type class]
        #set cmpn [$clsNode lookup Delegates]
        set cmpn [$clsNode findChildren -name Delegates]
        if {$cmpn == ""} {
            set cmpn [$node addChild [::Parser::Script ::#auto \
                -type snit_delegates -name Delegates -expanded 0]]
        }
        $cmpn configure -isvalid 1
        
        #set result [$cmpn lookup $cName]
        set result [$cmpn findChildren -type $dtype -name $cName]
        if {$result == ""} {
            set result [::Parser::SnitDelegateNode ::#auto \
                -displayformat {"%s %s" -name -definition}]
            $cmpn addChild $result
        }
        $result configure {*}$dargs
        return $result
    }
    
    ## \brief Parses an option statement
    # 
    # Has the form
    #    option nameSpec ?default? 
    #    option nameSpec ?options?
    # with
    #    nameSpec: either "-name" or {-name name Name} (with resources and class)
    #    options: something of -default <value>, -readonly <flag>, -type <value>, 
    #                          -cgetmethod <method>, -configuremethod <method>,
    #                          -validatemethod <method>
    sugar::proc parseOption {node cTree content off dBdPtr} {
        upvar $dBdPtr dBdOff
        set dBdEnd 0
        
        set nameSpec [m-parse-token $content $cTree 1]
        set cName [lindex $nameSpec 0]
        set oArgs [list -name $cName -namespec $nameSpec]
        switch -- [llength $cTree] {
        2 {
            # just "option -name"
        }
        3 {
            # one of "option -name value" or "option nameSpec value"
            lappend oArgs -definition [m-parse-token $content $cTree 2]
        }
        default {
            # contains more options
            for {set i 2} {$i < [llength $cTree]-1} {incr i 2} {
                set j [expr {$i + 1}]
                set o [m-parse-token $content $cTree $i]
                set v [m-parse-token $content $cTree $j]
                if {[string match $o -default]} {
                    lappend oArgs -definition $v
                } elseif {[string match $o -type]} {
                    lappend oArgs -otype $v
                } else {
                    lappend oArgs $o $v
                }
            }
        }
        }
        
        set clsNode [$node findParent -type class]
        set cmpn [$clsNode lookup Options]
        if {$cmpn == ""} {
            set cmpn [$node addChild [::Parser::Script ::#auto \
                -type snit_options -name Options -expanded 0]]
        }
        $cmpn configure -isvalid 1
        
        set result [$cmpn lookup $cName]
        if {$result == ""} {
            set result [::Parser::SnitOptionNode ::#auto -type snit_option \
                -displayformat {"%s = %s" -namespec -definition}]
            $cmpn addChild $result
        }
        $result configure -isvalid 1 {*}$oArgs 
        return $result
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
                
                superclass {
                    # inheritance is possible in snit3.
                    parseInherit $node $codeTree $content
                    
                }
                
                typemethod -
                proc {
                    set pNode [::Parser::Tcl::parseProc $node $codeTree $content $cmdRange $off]
                    $node addProc $pNode
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
                    $node addMethod $csNode
                }
                
                destructor {
                    set defOff 0
                    set dNode [parseDestructor $node $codeTree $content defOff]
                    $dNode configure -byterange $cmdRange
                    ::Parser::parse $dNode [expr {$off + $defOff}] [$dNode cget -definition]
                    $node addMethod $csNode
                }
                
                variable -
                typevariable {
                    set vNode [::Parser::Tcl::parseVar $node $codeTree $content $off]
                    if {$vNode != ""} {
                        $vNode configure -byterange $cmdRange -type private_variable
                        $node addVariable [$vNode cget -name] 0 1
                    }
                }
                
                component -
                typecomponent {
                    set dBdOff 0
                    set compNode [parseComponent $node $codeTree $content $off dBdOff]
                    if {$compNode != ""} {
                        $compNode configure -byterange $cmdRange
                        $node addVariable [$compNode cget -name] 0 1
                    }
                }
                
                delegate {
                    set dBdOff 0
                    set delNode [parseDelegate $node $codeTree $content $off dBdOff]
                    if {$delNode != ""} {
                        $delNode configure -byterange $cmdRange
                    }
                }
                
                option {
                    set dBdOff 0
                    set optNode [parseOption $node $codeTree $content $off dBdOff]
                    if {$optNode != ""} {
                        $optNode configure -byterange $cmdRange
                        $node addVariable options([lindex [$optNode cget -name] 0]) 0 1
                    }
                }
                
            }
            
            # step forward in the content
            set idx [lindex [lindex $res 2] 0]
            incr off $idx
            set content [::parse getstring $content [list $idx end]]
        }
        
        $node updateVariables
        $node updateCommands
    }
    
    
    
}

