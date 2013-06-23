
package require parser 1.4
package require Itree 1.0
package require Tclx 8.4
package require log 1.2
package require sugar 0.1

package require parser::script 1.0

package provide parser::itcl 1.0

catch {
    namespace import ::itcl::*
}

##
# Gets the token of a parse tree at specified index
::sugar::macro parse_token {cmd content tree idx} {
    list ::parse getstring $content \[lindex \[lindex $tree $idx\] 1\]
}

sugar::macro getarg {cmd arg args} {
    if {[llength $args] == 1} {
        list expr \{ \[dict exist \$args $arg\] ? \[dict get \$args $arg\] : \"$args\" \}
    } else {
        list expr \{ \[dict exist \$args $arg\] ? \[dict get \$args $arg\] : [list $args] \}
    }
}

##
# Gets the byterange of a definition in a parse tree at specified index
sugar::macro parse_defrange {cmd tree idx} {
    list list \[lindex \[lindex \[lindex \[lindex \[lindex $tree $idx\] 2\] 0\] 1\] 0\] \
        \[lindex \[lindex \[lindex \[lindex \[lindex $tree $idx\] 2\] 0\] 1\] 1\]
}

sugar::macro parse_cmdrange {cmd tree offset} {
    list list \[expr \{\[lindex \[lindex $tree 1\] 0\] + $offset\}\] \
        \[expr \{\[lindex \[lindex $tree 1\] 1\] - 1\}\]
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
    
    class ClassNode {
        inherit ::Parser::Script
        
        constructor {args} {
            eval configure $args
        }
        
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
    
    class ConstructorNode {
    inherit ::Parser::ProcNode
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
    
            #"common" {
            #    set cnNode [parseCommon $node $codeTree $content]
            #}
    
    ##
    # Parse the Access level of a proc, variable or method
    ::sugar::proc parseAccess {node codeTree content cmdRange off args} {
        set secToken [lindex $codeTree 1]
        set range [lindex $secToken 1]
        set realToken [::parse getstring $content \
            [list [lindex $range 0] [lindex $range 1]]]
        set accLev [getarg -access public]
        switch -- $realToken {
            "variable" -
            "common" {
                set dCfOff 0
                set dCgOff 0
                set vNode [::Parser::Tcl::parseVar $node $codeTree $content \
                        $accLev dCfOff dCgOff -vardef $realToken {*}$args]
                if {$vNode != ""} {
                    $vNode configure -byterange $cmdRange -type [set accLev]_[set realToken]
                    ::Parser::parse $vNode [expr {$dCfOff + $off}] [$vNode cget -configcode]
                    ::Parser::parse $vNode [expr {$dCgOff + $off}] [$vNode cget -cgetcode]
                }
            }
            "constructor" {
                set defOff 0
                set csNode [parseConstructor $node $codeTree $content defOff]
                if {$csNode != ""} {
                    $csNode configure -byterange $cmdRange
                    ::Parser::parse $csNode [expr {$off + $defOff}] [$csNode cget -definition]
                }
            }
            "method" {
                set mNode [parseMethod $node $codeTree $content $accLev]
                if {$mNode != ""} {
                    $mNode configure -byterange $cmdRange {*}$args
                    ::Parser::parse $mNode $off [$mNode cget -definition]
                    switch -- [$node cget -type] {
                        "access" {
                            [$node getParent] addMethod $mNode
                        }
                        "class" {
                            $node addMethod $mNode
                        }
                    }
                }
            }
            
            "proc" {
                set pn [::Parser::Tcl::parseProc $node $codeTree $content dummy]
                if {$pn != ""} {
                    $pn configure -byterange $cmdRange
                    ::Parser::parse $pn $off [$pn cget -definition]
                }
            }
            "default" {
                namespace upvar ::Parser CurrentAccess currAccess
                set currAccess $accLev
                set defOff [lindex [lindex [lindex [lindex \
                    [lindex $codeTree 1] 2] 0] 1] 0]
                set defEnd [lindex [lindex [lindex [lindex \
                    [lindex $codeTree 1] 2] 0] 1] 1]
                set newCtn [::parse getstring $content \
                    [lindex [lindex $codeTree 1] 1]]
                set newCtn [string trim $newCtn "\{\}"]
                ::Parser::parse $node [expr {$off + $defOff}] $newCtn {*}$args
                set currAccess ""
            }
        }
        
    }
    
    # @c parses a method body command. The result is
    # @c set as the method/proc definition in the
    # @c corresponding class
    #
    # @a node: The node object to which the new node belongs (e.g. Script)
    # @a cTree: The code tree, as returned by ::parse command
    # @a content: The content of the definition, as string
    # @a defOffPtr: Pointer to the definition offset. Is returned
    #
    # @r The newly created proc/method body node
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
    
    # @c parse a class node and returns it as tree
    proc parseClass {node cTree content defOffPtr {type class}} {
        upvar $defOffPtr defOff
        set nTk [llength $cTree]
        
        foreach {tkn idx} {clsTkn 0 clsName 1 clsDef 2} {
            set range [lindex [lindex $cTree $idx] 1]
            set $tkn [::parse getstring $content [list [lindex $range 0] [lindex $range 1]]]
        }
        
        # get class definition offset
        set defOff [lindex [lindex [lindex [lindex [lindex $cTree 2] 2] 0] 1] 0]
        set defEnd [lindex [lindex [lindex [lindex [lindex $cTree 2] 2] 0] 1] 1]
        
        set nsAll [regsub -all {::} [string trimleft $clsName :] " "]
        set clsName [lindex $nsAll end]
        set clsDef [string trim $clsDef "\{\}"]
        
        set nsNode [::Parser::Util::getNamespace $node [lrange $nsAll 0 end-1]]
        #set clsNode [$node lookup $clsName $nsNode]
        set clsNode [$nsNode lookup $clsName]
        if {$clsNode != ""} {
            $clsNode configure -isvalid 1 -definition $clsDef \
                -defbrange [list $defOff $defEnd] -token $clsTkn
        } else {
            set clsNode [::Parser::ClassNode ::#auto -type class -expanded 0 \
                    -name $clsName -isvalid 1 -definition $clsDef \
                    -defbrange [list $defOff $defEnd] -token $clsTkn]
            $nsNode addChild $clsNode
        }
        
        return $clsNode
    }
    
    
    proc parseCommon {node cTree content} {
    }
    
    ::sugar::proc parseConstructor {node cTree content defOffPtr} {
        upvar $defOffPtr defOff
        set defEnd 0
        
        set nTk [llength $cTree]
        set firstTkn [parse_token $content $cTree 0]
        set argList ""
        set initDef ""
        set initBr {}
        set constDef ""
        set defIdx 2
        if {$nTk == 3} {
            # constructor without access level
            set argList [parse_token $content $cTree 1]
            set constDef [parse_token $content $cTree 2]
            set defIdx 2
        } elseif {$nTk == 4} {
            if {$firstTkn == "constructor"} {
                # Constructor with init Code
                set argList [parse_token $content $cTree 1]
                set initDef [parse_token $content $cTree 2]
                set initBr [parse_defrange $cTree 2]
            } else {
                # access level definition
                set argList [parse_token $content $cTree 2]
            }
            set constDef [parse_token $content $cTree 3]
            set defIdx 3
        } elseif {$nTk == 5} {
            # Constructor with access and init code
            set argList [parse_token $content $cTree 2]
            set initDef [parse_token $content $cTree 3]
            set initBr [parse_defrange $cTree 3]
            set constDef [parse_token $content $cTree 4]
            set defIdx 4
        } else {
            return ""
        }
        
        set defRange [parse_defrange $cTree $defIdx]
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
    
    proc parseDestructor {node cTree content defOffPtr} {
        upvar $defOffPtr defOff
        set defEnd 0
        set dDef ""
        
        if {[llength $cTree] == 2} {
            set range [lindex [lindex $cTree 1] 1]
            set dDef [::parse getstring $content $range]
            set defOff [lindex [lindex [lindex [lindex [lindex $cTree 1] 2] 0] 1] 0]
            set defEnd [lindex [lindex [lindex [lindex [lindex $cTree 1] 2] 0] 1] 1]
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
            
            if {$iCls == "Widget" || $iCls == "Toplevel"} {
                # it is an itk widget
                $node configure -isitk 1
            }
        }
        
        $node configure -inherits $classes -inheritstring [string range $clsStr 2 end]
    }
    
    
    # @c parses a method node
    proc parseMethod {node cTree content accLev} {
        set nTk [llength $cTree]
        set dOff 0
        
        set alev2 ""
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
            set $tkn [::parse getstring $content [lindex [lindex $cTree $idx] 1]]
            if {[string equal $tkn methBody]} {
                set dOff [lindex [lindex [lindex [lindex [lindex $cTree $idx] 2] 0] 1] 0]
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
        
        # return existing method node if already present
        set mNode [$node lookup $methName]
        if {$mNode != "" && [$mNode cget -type] == "[set accLev]_method"} {
            $mNode configure -arglist $argList -definition $methBody -isvalid 1 \
                -defoffset [expr {$dOff - $strt}]
            
            foreach {v d} [$node getVariables] {
                $mNode addVariable $v $d 1
            }
            
            return $mNode
        }
        
        set mNode [::Parser::ProcNode ::#auto -type "[set accLev]_method" \
            -name $methName -arglist $argList -definition $methBody \
            -defoffset [expr {$dOff - $strt}]]
        $node addChild $mNode
        
        # add variables from class definition to the method
        # as variables
        foreach {v d} [$node getVariables] {
            $mNode addVariable $v $d 1
        }
        
        return $mNode
    }

}
