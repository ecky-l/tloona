
package require parser 1.4
package require parser::macros 1.0
package require parser::script 1.0
package require parser::tcloo 1.0
package require Itree 1.0
package require Tclx 8.4
package require log 1.2
package require sugar 0.1


package provide parser::itcl 1.0

catch {
    namespace import ::itcl::*
}

sugar::macro getarg {cmd arg args} {
    if {[llength $args] == 1} {
        list expr \{ \[dict exist \$args $arg\] ? \[dict get \$args $arg\] : \"$args\" \}
    } else {
        list expr \{ \[dict exist \$args $arg\] ? \[dict get \$args $arg\] : [list $args] \}
    }
}


namespace eval ::Parser {
    namespace eval Itcl {}
    
    # @v CoreCommands: commands available for Tcl core and Itcl
    variable ItclCoreCommands {auto_mkindex auto_mkindex_old auto_reset body \
                cgetbody class code configbody delete delete_helper \
                ensemble find local pkg_compareExtension pkg_mkIndex \
                scope tclPkgSetup tclPkgUnknown tcl_findLibrary \
                public private protected method inherit constructor \
                destructor \
                usual component itk_component itk_option
    }
    
    class ItclClassNode {
        inherit ::Parser::ClassNode
        
        constructor {args} {eval chain $args} {}
    }
    
    class ConstructorNode {
    inherit ::Parser::OOProcNode
    public {
        variable initdefinition ""
        variable initbrange {}
        
        constructor {args} {
            eval configure $args
        }
    }
    }
    
    class ItkComponentNode {
        inherit ::Parser::Script
        
        constructor {args} {
            eval configure $args
        }
        
        public {
            # @v accesslevel: Components can have -private accesslevel. By 
            # @v accesslevel: default, the accesslevel is public
            variable accesslevel "public"
            # @v argdefinition: the definition for options (rename, keep etc.)
            variable argdefinition ""
        }
        
    }

}

namespace eval ::Parser::Itcl {
    
    ## \brief The current access level. 
    #
    # This variable is set during the parsing to determine the current
    # access level.
    variable CurrentAccess ""
    
    ## \brief Parse the Access level of a proc, variable or method.
    ::sugar::proc parseAccess {node codeTree content cmdRange off accLev} {
        set realToken [m-parse-token $content $codeTree 1]
        switch -- $realToken {
            variable -
            common {
                set dCfOff 0
                set dCgOff 0
                set vNode [parseVar $node $codeTree $content dCfOff dCgOff]
                if {$vNode != ""} {
                    $vNode configure -byterange $cmdRange -type [set accLev]_[set realToken]
                    ::Parser::parse $vNode [expr {$dCfOff + $off}] [$vNode cget -configcode]
                    ::Parser::parse $vNode [expr {$dCgOff + $off}] [$vNode cget -cgetcode]
                }
            }
            constructor {
                set defOff 0
                set csNode [parseConstructor $node $codeTree $content defOff]
                if {$csNode != ""} {
                    $csNode configure -byterange $cmdRange
                    ::Parser::parse $csNode [expr {$off + $defOff}] [$csNode cget -definition]
                }
            }
            method - proc {
                set defOff 0
                set mNode [parseMethod $node $codeTree $content $off $accLev defOff]
                if {$mNode != ""} {
                    $mNode configure -byterange $cmdRange -access $accLev
                    ::Parser::parse $mNode [expr {$off + $defOff}] [$mNode cget -definition]
                    $node addMethod $mNode
                }
            }
            
            
        }
        
    }
    
    ## \brief Parses a method body command. 
    #
    # The result is set as the method/proc definition in the corresponding 
    # class
    #
    # \param[in] node
    #    The node object to which the new node belongs (e.g. Script)
    # \param[in] cTree 
    #    The code tree, as returned by ::parse command
    # \param[in] content
    #    The content of the definition, as string
    # \param[in] defOffPtr 
    #    Pointer to the definition offset. Is returned
    #
    # \return The newly created proc/method body node
    proc parseBody {node cTree content defOffPtr} {
        upvar $defOffPtr defOff
        set nTk [llength $cTree]
        if {$nTk != 4} {
            return -code error "wrong args to body command"
        }
        
        # The real start of the method, after comments, spaces etc.
        set strt [lindex [lindex [lindex $cTree 0] 1] 0]
        foreach {tkn idx} {bName 1 bArgs 2 bDef 3} {
            set range [lindex [lindex $cTree $idx] 1]
            #set $tkn [::parse getstring $content \
            #    [list [lindex $range 0] [lindex $range 1]]]
            set $tkn [::parse getstring $content $range]
        }
        
        set defOff [lindex [lindex [lindex [lindex [lindex $cTree 3] 2] 0] 1] 0]
        
        # split body name and look it up in the context
        # last part is the method/proc name, one before
        # last is a class, all other parts are namespaces
        set nsAll [regsub -all {::} [string trimleft $bName :] " "]
        set bName [lindex $nsAll end]
        set clsName [lindex $nsAll end-1]
        set bDef [string trim $bDef "\{\}"]
        
        set pNode ""
        set pNode [$node lookup $bName [concat [lrange $nsAll 0 end-1]]]
        if {$pNode == ""} {
            set ns [join [lrange $nsAll 0 end-1] ::]
            return -code error "$bName not found in context $ns"
        }
        
        $pNode configure -definition $bDef -bodyextern 1 \
            -defoffset [expr {$defOff - $strt}]
        return $pNode
    }
    
    
    proc parseItkComponent {node cTree content off dBdPtr} {
        upvar $dBdPtr dBdOff
        set dBdEnd 0
        
        set cCmd ""
        set cPriv "-"
        set cName ""
        set cBody ""
        set cArgDef ""
        switch -- [llength $cTree] {
            6 {
                # itk_component add -private name body argdef
                set aList {cCmd 1 cPriv 2 cName 3 cBody 4 cArgDef 5}
            }
            5 {
                # itk_component add -private name body or
                # itk_component add name body argdef
                set aList {cCmd 1 cPriv 2 cName 3 cBody 4}
            }
            4 {
                # itk_component add name body
                set aList {cCmd 1 cName 2 cBody 3}
            }
            default {
                #puts "error in component parsing, arg is not 5|4"
                return
            }
        }
        
        foreach {tkn idx} $aList {
            set range [lindex [lindex $cTree $idx] 1]
            set $tkn [::parse getstring $content [list [lindex $range 0] \
                [lindex $range 1]]]
            
            # get config/cget definition range
            if {[string match $tkn cBody]} {
                set dBdOff [lindex [lindex [lindex \
                        [lindex [lindex $cTree $idx] 2] 0] 1] 0]
                set dBdEnd [lindex [lindex [lindex \
                        [lindex [lindex $cTree $idx] 2] 0] 1] 1]
            } elseif {[string match $tkn cArgDef]} {
                set dAdOff [lindex [lindex [lindex \
                        [lindex [lindex $cTree $idx] 2] 0] 1] 0]
                set dAdEnd [lindex [lindex [lindex \
                        [lindex [lindex $cTree $idx] 2] 0] 1] 1]
            }
            
        }
        
        if {![string match $cCmd add]} {
            #puts "error in component parsing, $cCmd not known"
            return
        }
        
        # it could be that cPriv contains the cName
        if {[string index $cPriv 0] != "-"} {
            set cArgDef $cBody
            set cBody $cName
            set cName $cPriv
            set cPriv "-"
        }
        
        # Components are usually created in constructors or methods, 
        # get the class where the component belongs to.
        set clsNode [$node getParent]
        while {$clsNode != {} && [$clsNode cget -type] != "class"} {
            set clsNode [$clsNode getParent]
        }
        if {$clsNode == {}} {
            set clsNode $node
        }
        
        set cmpn [$clsNode lookup "Itk Components"]
        if {$cmpn == ""} {
            set cmpn [$clsNode addChild [::Parser::Script ::#auto \
                -type itk_components -name "Itk Components" -expanded 0]]
        }
        $cmpn configure -isvalid 1
        
        set compNode [$cmpn lookup $cName]
        if {$compNode == ""} {
            set compNode [::Parser::ItkComponentNode ::#auto]
            $cmpn addChild $compNode
        }
        
        set t [expr {($cPriv == "-") ? "public_component" : "private_component"}]
        $compNode configure -type $t -name $cName -isvalid 1
        
        return $compNode
    }
    
    ## \brief Create a class from previously parsed tokens
    ::sugar::proc createClass {node clsName clsDef defRange} {
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
            set clsNode [::Parser::ItclClassNode ::#auto -expanded 0 \
                    -name $clsName -isvalid 1 -definition $clsDef \
                    -defbrange $defRange -token class]
            $nsNode addChild $clsNode
        }
        
        return $clsNode
        
    }
    
    ## \brief Parse a class node and returns it as tree
    ::sugar::proc parseClassDef {node off content} {
        variable CurrentAccess
        
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
                inherit {
                    parseInherit $node $codeTree $content
                }
                
                public -
                protected -
                private {
                    set CurrentAccess $token
                    if {[llength $codeTree] == 2} {
                        # access definition for a script of methods etc.
                        lassign [m-parse-defrange $codeTree 1] do de
                        set accDef [string trim [m-parse-token $content $codeTree 1] "{}"]
                        parseClassDef $node [expr {$off + $do}] $accDef
                    } else {
                        # access qualified method, variable etc.
                        parseAccess $node $codeTree $content $cmdRange $off $token
                    }
                    set CurrentAccess ""
                }
                
                method - proc {
                    set tmpAcc $CurrentAccess
                    if {$CurrentAccess == ""} {
                        set CurrentAccess public
                    }
                    set defOff 0
                    set mNode [parseMethod $node $codeTree $content $off $CurrentAccess defOff]
                    $mNode configure -byterange $cmdRange
                    ::Parser::parse $mNode [expr {$off + $defOff}] [$mNode cget -definition]
                    $node addMethod $mNode
                    set CurrentAccess $tmpAcc
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
                
                variable -
                common {
                    set tmpAcc $CurrentAccess
                    if {$CurrentAccess == ""} {
                        set CurrentAccess protected
                    }
                    set dCfOff 0
                    set dCgOff 0
                    set vNode [parseVar $node $codeTree $content dCgOff dCfOff]
                    $vNode configure -byterange $cmdRange
                    ::Parser::parse $vNode [expr {$dCfOff + $off}] [$vNode cget -configcode]
                    ::Parser::parse $vNode [expr {$dCgOff + $off}] [$vNode cget -cgetcode]
                    set CurrentAccess $tmpAcc
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
    
    proc parseCommon {node cTree content} {
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
            
            if {$iCls == "Widget" || $iCls == "Toplevel"} {
                # it is an itk widget
                $node configure -isitk 1
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
    ::sugar::proc parseMethod {node cTree content offset accLev defOffPtr} {
        upvar $defOffPtr defOff
        #set dOff 0
        
        set alev2 ""
        set nTk [llength $cTree]
        if {$nTk == 5} {
            # complete declaration and definition, 
            # including access level
            set aList {methName 2 argList 3 methBody 4}
        } elseif {$nTk == 4} {
            # declaration and definition, without access level
            set aList {alev2 0 methName 1 argList 2 methBody 3}
            
        } elseif {$nTk == 3} {
            # just declaration. There will be a body definition
            set aList {methName 1 argList 2}
            set methBody ""
        }
        
        # The real start of the method, after comments, spaces etc.
        set strt [lindex [lindex [lindex $cTree 0] 1] 0]
        foreach {tkn idx} $aList {
            set $tkn [m-parse-token $content $cTree $idx]
            #set $tkn [::parse getstring $content [lindex [lindex $cTree $idx] 1]]
            if {[string equal $tkn methBody]} {
                lassign [m-parse-defrange $cTree $idx] defOff
                #set dOff [lindex [lindex [lindex [lindex [lindex $cTree $idx] 2] 0] 1] 0]
            }
        }
        
        # Adjust the access level. If it is one of public, private or
        # protected, it is the real access level. Otherwise, it's the
        # methods name.
        switch -- $alev2 {
        public -
        protected -
        private {
            set accLev $alev2
            set methName $argList
            set argList $methBody
        }
        }
        
        set argList [lindex $argList 0]
        
        if {$accLev == ""} {
            # defaults to public
            set accLev public
        }
        
        set methBody [string trim $methBody "{}"]
        set strt 0
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
        
        return $mNode
    }
    
    ## \brief Parses a variable node.
    #
    # Itcl variables can contain access qualifier (which is previously set by 
    # parseClassDef when found) and in addition code fragments that are executed
    # on configure and cget. This makes them different from normal Tcl namespace
    # variables
    #
    # \param[in] node The class node
    # \param[in] cTree The parsed code tree as returned py ::parse
    # \param[in] content The content to parse and get tokens from 
    # \param[out] cfOffPtr Pointer to the byte offset of config code
    # \param[out] cgOffPtr Pointer to the byte offset of cget code
    ::sugar::proc parseVar {node cTree content cfOffPtr cgOffPtr} {
        variable CurrentAccess
        upvar $cfOffPtr cfOff
        upvar $cgOffPtr cgOff
        
        lassign {variable "" "" "" "" {} {}} varDef vName vDef vConf vCget confRange cgetRange
        set ftok [m-parse-token $content $cTree 0]
        set tokens {varDef 0 vName 1 vDef 2 vConf 3 confRange 3 vCget 4 cgetRange 4}
        switch -- $ftok {
            public - protected - private {
                set tokens {varDef 1 vName 2 vDef 3 vConf 4 confRange 4 vCget 5 cgetRange 5}
            }
        }
        foreach {tkn idx} $tokens {
            if {$idx >= [llength $cTree]} {
                break
            }
            switch -- $tkn {
                confRange - cgetRange {
                    set $tkn [m-parse-defrange $cTree $idx]
                }
                default {
                    set $tkn [m-parse-token $content $cTree $idx]
                }
            }
        }
        
        set vConf [string trim $vConf "\{\}"]
        set vCget [string trim $vCget "\{\}"]
        set cfOff [expr {$confRange != {} ? [lindex $confRange 0] : 0}]
        set cgOff [expr {$cgetRange != {} ? [lindex $cgetRange 0] : 0}]
        
        $node addVariable $vName 0 1
        # if var already exists, return it
        set vNode [$node lookup $vName]
        if {$vNode == "" || [$vNode cget -type] != "[set CurrentAccess]_[set varDef]"} {
            set vNode [$node addChild [::Parser::VarNode ::#auto \
                    -type [set CurrentAccess]_[set varDef] -name $vName
        }
        
        $vNode configure -definition $vDef -configcode $vConf -cgetcode $vCget \
                    -configbrange $confRange -cgetbrange $cgetRange -isvalid 1
        return $vNode
        
    }

}
