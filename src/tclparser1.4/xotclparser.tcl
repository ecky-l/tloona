package require parser 1.4
package require Itree 1.0
package require Tclx 8.4
package require log 1.2

package require parser::script 1.0
package require parser::tcl 1.0
package require parser::tcloo 1.0

package provide parser::xotcl 1.0


catch {
    namespace import ::itcl::*
}

namespace eval ::Parser {
    namespace eval Xotcl {}
    
    # @v XotclCoreCommands: A list of core commands for xotcl
    variable XotclCoreCommands {Class Object instproc create alloc instdestroy \
        instfilter instfilterguard instforward instinvar instmixin instparametercmd \
        new parameter parameterclass recreate superclass my self \
        abstract autoname check cleanup contains copy destroy extractConfigureArg \
        filter filtersearch forward getExitHandler hasclass instvar invar isclass \
        ismetaclass ismixin isobject istype mixin move noinit parametercmd procsearch \
        requireNamespace setExitHandler volatile}
    
}


# @c This class represents Attribute nodes for XOTcl. So we can
# @c distinguish them from normal variables
class ::Parser::XotclAttributeNode {
    inherit ::Parser::VarNode
    
    # @v getterproc: The getter method for this attribute
    public variable getterproc {}
    # @v getterproc: The getter method for this attribute
    public variable setterproc {}
    
    constructor {args} {
        eval configure $args
    }
}


# @c This object can deal with pre- and post assertions
class ::Parser::XotclProcNode {
    inherit ::Parser::ProcNode
    
    # @v preassertion: Code that checks pre assertion for xotcl procs
    public variable preassertion ""
    # @v postassertion: Code that checks post assertion
    public variable postassertion ""
    # @v predefoffset: byte offset for preassertion code
    public variable predefrange {}
    # @v postdefoffset: byte offset for postassertion code
    public variable postdefrange {}
    
    constructor {args} {
        eval configure $args
    }
}


class ::Parser::XotclClassNode {
    inherit ::Parser::ClassNode
    
    # @v slotdefinition: Definition for slots. Contains Attributes
    # @v slotdefinition: Used for parsing the attributes
    public variable slotdefinition ""
    
    constructor {args} {eval chain $args} {}
    
}


proc ::Parser::Xotcl::configClassParams {parNode clsNode cTree content slotOffPtr} {
    upvar $slotOffPtr slotOff
    set slotOff -1
    # parse the -superclass parameter and slots
    set classes {}
    set clsStr ""
    for {set i 2} {$i < [llength $cTree]} {incr i} {
        set param [::parse getstring $content [lindex [lindex $cTree $i] 1]]
        switch -- $param {
            -superclass {
                set classes [::parse getstring $content [lindex [lindex $cTree [incr i]] 1]]
            }
            -slots {
                incr i
                set slotOff [lindex [lindex [lindex [lindex [lindex $cTree $i] 2] 0] 1] 0]
                set slotEnd [lindex [lindex [lindex [lindex [lindex $cTree $i] 2] 0] 1] 1]
                $clsNode configure -slotdefinition [::parse getstring $content \
                    [list $slotOff $slotEnd]]
            }
        }
    }
    
    if {$classes == {}} {
        return $clsNode
    }
    
    foreach {iCls} [lindex $classes 0] {
        set nsAll [regsub -all {::} [string trimleft $iCls :] " "]
        set iCls [lindex $nsAll end]
        append clsStr ", [string trimleft $iCls :]"
        if {[llength $nsAll] > 1} {
            # parent class has namespace qualifiers
            set tn [$parNode getTopnode]
            set iNode [$tn lookup $iCls [lrange $nsAll 0 end-1]]
        } else {
            set tn [expr {([$parNode getParent] == "") ? $parNode : [$parNode getParent]}]
            set iNode [$tn lookup $iCls]
        }
        
        if {$iNode != ""} {
            lappend classes $iNode
        }
    }
    $clsNode configure -inherits $classes -inheritstring [string range $clsStr 2 end]
    return $clsNode
}

proc ::Parser::Xotcl::parseClass {node cTree content defOffPtr slotOffPtr} {
    upvar $defOffPtr defOff
    upvar $slotOffPtr slotOff
    
    set idx 1
    set clsName [::parse getstring $content [lindex [lindex $cTree $idx] 1]]
    if {[string match $clsName create]} {
        incr idx
        set clsName [::parse getstring $content [lindex [lindex $cTree $idx] 1]]
    }
    #set nsAll [regsub -all {::} [string trimleft $clsName :] " "]
    #set clsName [lindex $nsAll end]
    
    set nsNode [::Parser::Util::getNamespace $node \
        [lrange [split [regsub -all {::} $clsName ,] ,] 0 end-1]]
    set clsName [namespace tail $clsName]
    #set nsNode [::Parser::Util::getNamespace $node [lrange $nsAll 0 end-1]]
    #set clsNode [$node lookup $clsName $nsNode]
    set clsNode [$nsNode lookup $clsName]
    if {$clsNode != ""} {
        $clsNode configure -isvalid 1
    } else {
        set clsNode [::Parser::XotclClassNode ::#auto -expanded 0 \
                -name $clsName -isvalid 1]
        $nsNode addChild $clsNode
    }
    
    configClassParams $node $clsNode $cTree $content sloto
    set slotOff $sloto
    return $clsNode
    
}

proc ::Parser::Xotcl::parseAttribute {node cTree content defOff} {
    set vName [::parse getstring $content [lindex [lindex $cTree 1] 1]]
    set vDef {}
    for {set i 2} {$i < [llength $cTree]} {incr i} {
        set param [::parse getstring $content [lindex [lindex $cTree $i] 1]]
        switch -- $param {
            -default {
                set vDef [::parse getstring $content [lindex [lindex $cTree [incr i]] 1]]
            }
        }
    }
    
    set vNode [$node lookup $vName]
    if {$vNode != ""} {
        $vNode configure -isvalid 1 -type variable -definition $vDef -name $vName
        return $vNode
    }
    
    set vNode [::Parser::XotclAttributeNode ::#auto -type "variable" -definition $vDef \
        -name $vName -isvalid 1]
    $node addChild $vNode
}

proc ::Parser::Xotcl::parseInstCmd {node cTree content defOffPtr preOffPtr postOffPtr} {
    upvar $defOffPtr cmdDefOff
    upvar $preOffPtr preOff
    upvar $postOffPtr postOff
    set cmd [::parse getstring $content [lindex [lindex $cTree 1] 1]]
    switch -- $cmd {
    instproc -
    proc {
        set thisType [expr {[string match $cmd proc] ? "xo_proc" : "xo_instproc"}]
        set strt [lindex [lindex [lindex $cTree 0] 1] 0]
        
        set cmdName [::parse getstring $content [lindex [lindex $cTree 2] 1]]
        set cmdArgs [lindex [::parse getstring $content [lindex [lindex $cTree 3] 1]] 0]
        set cmdDef {}
        if {[llength $cTree] > 4} {
            set cmdDef [string trim [::parse getstring $content \
                [lindex [lindex $cTree 4] 1]] "\{\}"]
            set cmdDefOff [lindex [lindex [lindex [lindex [lindex $cTree 4] 2] 0] 1] 0]
        }
        
        set preAss {}
        set preOff -1
        set preEnd -1
        set postAss {}
        set postOff -1
        set postEnd -1
        if {[llength $cTree] > 5} {
            set preAss [string trim [::parse getstring $content [lindex [lindex $cTree 5] 1]] "\{\}"]
            set preOff [lindex [lindex [lindex [lindex [lindex $cTree 5] 2] 0] 1] 0]
            set preEnd [lindex [lindex [lindex [lindex [lindex $cTree 5] 2] 0] 1] 1]
        }
        if {[llength $cTree] > 6} {
            set postAss [string trim [::parse getstring $content [lindex [lindex $cTree 6] 1]] "\{\}"]
            set postOff [lindex [lindex [lindex [lindex [lindex $cTree 6] 2] 0] 1] 0]
            set postEnd [lindex [lindex [lindex [lindex [lindex $cTree 6] 2] 0] 1] 1]
        }
        # Lookup existing cmd definition
        set cmdNode [$node lookup $cmdName]
        if {$cmdNode == {}} {
            set cmdNode [::Parser::XotclProcNode ::#auto -type $thisType \
                -name $cmdName -arglist $cmdArgs -definition $cmdDef \
                -defoffset [expr {$cmdDefOff - $strt}] -preassertion $preAss \
                -postassertion $postAss -predefrange [list $preOff $postOff] \
                -postdefrange [list $postOff $postEnd]]
            $node addChild $cmdNode
            
            # add variables from class definition to the method
            # as variables
            foreach {v d} [$node getVariables] {
                $cmdNode addVariable $v $d 1
            }
            
            return $cmdNode
        }
        
        # The node exists already. Check whether it is a (inst)proc or the 
        # getter/setter for an Attribute. They need special treatment, since
        # the attribute might be there anyway and just gets a proc in addition.
        # This proc must be however child of the class as well.
        if {[string eq [$cmdNode cget -type] $thisType]} {
            $cmdNode configure -arglist $cmdArgs -definition $cmdDef -isvalid 1 \
                -defoffset [expr {$cmdDefOff - $strt}] -preassertion $preAss \
                -postassertion $postAss -predefrange [list $preOff $postOff] \
                -postdefrange [list $postOff $postEnd]
            
            foreach {v d} [$node getVariables] {
                $cmdNode addVariable $v $d 1
            }
            
            return $cmdNode
        } elseif {[$cmdNode isa Parser::XotclAttributeNode]} {
            # This is a overwritten method for get/set attributes. We create a proc
            # node as usual, but configure it as variable for the Attribute. If it
            # exists already, we configure it as valid and return it.
            
            if {[set gs [$cmdNode cget -getterproc]] != {}} {
                $gs configure -arglist $cmdArgs -definition $cmdDef -isvalid 1 \
                    -defoffset [expr {$cmdDefOff - $strt}] -preassertion $preAss \
                    -postassertion $postAss -predefrange [list $preOff $postOff] \
                    -postdefrange [list $postOff $postEnd]
                $cmdNode configure -isvalid yes
                return $gs
            }
            
            set gs [::Parser::XotclProcNode ::#auto -type $thisType -name $cmdName \
                -arglist $cmdArgs -definition $cmdDef -defoffset [expr {$cmdDefOff - $strt}] \
                -preassertion $preAss -postassertion $postAss -predefrange [list $preOff $postOff] \
                -postdefrange [list $postOff $postEnd]]
            $node addChild $gs
            $cmdNode configure -getterproc $gs -setterproc $gs
            foreach {v d} [$node getVariables] {
                $gs addVariable $v $d 1
            }
            return $gs
            
        }
        
    }
    }
}
