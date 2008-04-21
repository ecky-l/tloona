
package re parser 1.4

package require Itcl 3.3
package require Itree 1.0
package require Tclx 8.4
package require log 1.2
package require parser::script 1.0

package provide parser::itcl 1.0

catch {
    namespace import ::itcl::*
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
    
}

class ::Parser::ClassNode {
    inherit ::Parser::Script
    
    constructor {args} {
        eval configure $args
    }
    
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

class ::Parser::ItkComponentNode {
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
proc ::Parser::Itcl::parseBody {node cTree content defOffPtr} {
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


proc ::Parser::Itcl::parseItkComponent {node cTree content off dBdPtr} {
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
proc ::Parser::Itcl::parseClass {node cTree content defOffPtr} {
    upvar $defOffPtr defOff
    
    set nTk [llength $cTree]
    
    foreach {tkn idx} {clsName 1 clsDef 2} {
        set range [lindex [lindex $cTree $idx] 1]
        set $tkn [::parse getstring $content [list [lindex $range 0] [lindex $range 1]]]
    }
    
    # get class definition offset
    set defOff [lindex [lindex [lindex [lindex [lindex $cTree 2] 2] 0] 1] 0]
    set defEnd [lindex [lindex [lindex [lindex [lindex $cTree 2] 2] 0] 1] 1]
    
    set nsAll [regsub -all {::} [string trimleft $clsName :] " "]
    set clsName [lindex $nsAll end]
    set clsDef [string trim $clsDef "\{\}"]
    
    # if class already exists, return it
    set clsNode [$node lookup $clsName [lrange $nsAll 0 end-1]]
    if {$clsNode != ""} {
        for {set i 0} {$i < [llength $nsAll]} {incr i} {
            set ct [$node lookup [lindex $nsAll $i] [lrange $nsAll 0 [expr {$i - 1}]]]
            $ct configure -isvalid 1
        }
        
        $clsNode configure -definition $clsDef -defbrange [list $defOff $defEnd]
        return $clsNode
    }
    
    if {[llength $nsAll] > 1} {
        # lookup parent namespaces. Create them if they don't exist
        set nsNode [$node lookup [lindex $nsAll 0]]
        if {$nsNode == ""} {
            set nsNode [::Parser::Script ::#auto -isvalid 1 -expanded 0 \
                    -type "namespace" -name [lindex $nsAll 0]]
            $node addChild $nsNode
        }
        
        set lna [expr {[llength $nsAll] - 1}]
        for {set i 1} {$i < $lna} {incr i} {
            set nnsNode [$node lookup [lindex $nsAll $i] \
                    [lrange $nsAll 0 [expr {$i - 1}]]]
            if {$nnsNode == ""} {
                set nnsNode [::Parser::Script ::#auto -isvalid 1 -expanded 0 \
                        -type "namespace" -name [lindex $nsAll $i]]
                $nsNode addChild $nnsNode
            }
            set nsNode $nnsNode
        }
        
        set clsNode [::Parser::ClassNode ::#auto -type "class" \
                -name $clsName -definition $clsDef -isvalid 1 -expanded 0 \
                -defbrange [list $defOff $defEnd]]
        $nsNode addChild $clsNode
    } else  {
        if {[$node lookup $clsName] != ""} {
            return -code error "class $clsName already exists"
        }
        
        set clsNode [::Parser::ClassNode ::#auto -type "class" -expanded 0 \
                -name $clsName -definition $clsDef -isvalid 1]
        $node addChild $clsNode
    }
    
    return $clsNode
}


proc ::Parser::Itcl::parseCommon {node cTree content} {
}

proc ::Parser::Itcl::parseConstructor {node cTree content defOffPtr} {
    upvar $defOffPtr defOff
    set defEnd 0
    
    set nTk [llength $cTree]
    if {$nTk == 3} {
        # without access level
        set aList {argList 1 constDef 2}
        set defOff [lindex [lindex [lindex [lindex [lindex $cTree 2] 2] 0] 1] 0]
        set defEnd [lindex [lindex [lindex [lindex [lindex $cTree 2] 2] 0] 1] 1]
    } elseif {$nTk == 4} {
        # has access level, but this doesn't matter
        set aList {accLev 0 argList 2 constDef 3}
        set defOff [lindex [lindex [lindex [lindex [lindex $cTree 3] 2] 0] 1] 0]
        set defEnd [lindex [lindex [lindex [lindex [lindex $cTree 3] 2] 0] 1] 1]
    } else {
        return ""
    }
    
    foreach {tkn idx} $aList {
        set range [lindex [lindex $cTree $idx] 1]
        set $tkn [::parse getstring $content $range]
    }
    
    set argList [lindex $argList 0]
    set constDef [string trim $constDef \{\}]
    
    if {[$node cget -type] == "access"} {
        set csNode [[$node getParent] lookup "constructor"]
        if {$csNode == "" || [$csNode cget -type] != "constructor"} {
            set csNode [::Parser::ProcNode ::#auto \
                -type "constructor" -name "constructor" \
                -arglist $argList -definition $constDef]
            [$node getParent] addChild $csNode
        }
        $csNode configure -isvalid 1 -arglist $argList -definition $constDef
        
        return $csNode
    }
    
    # return existing method node if already present
    set csNode [$node lookup "constructor"]
    if {$csNode != "" && [$csNode cget -type] == "constructor"} {
        $csNode configure -arglist $argList -definition $constDef -isvalid 1
        return $csNode
    }
    
    set csNode [::Parser::ProcNode ::#auto -type "constructor" \
        -name "constructor" -arglist $argList -definition $constDef]
    $node addChild $csNode
    
    return $csNode
    
}

proc ::Parser::Itcl::parseDestructor {node cTree content defOffPtr} {
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

proc ::Parser::Itcl::parseInherit {node cTree content} {
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
proc ::Parser::Itcl::parseMethod {node cTree content accLev} {
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

