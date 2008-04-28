
package require parser 1.4
package require parser::script 1.0
package require Itcl 3.3
package require Itree 1.0
package require Tclx 8.4

package provide parser::web 1.0

catch {
    namespace import ::itcl::*
}

namespace eval ::Parser {
    namespace eval Web {}
}

class ::Parser::WebCmdNode {
    inherit ::Parser::Script
    
    constructor {args} {
        eval configure $args
    }
    
    # @v displayformat: overrides the display format for tests
    public variable displayformat {"%s" -name}
    # @v runtimens: the namespace where this proc is defined
    # @v runtimens: at runtime
    public variable runtimens ""
    # @v defoffset: The definition offset, counted from the 
    # @v defoffset: beginning of the whole definition
    public variable defoffset 0
    
}


# @c parse Web command as issued by websh
proc ::Parser::Web::parseWebCmd {node cTree content defOffPtr} {
    upvar $defOffPtr defOff
    if {[llength $cTree] != 3} {
        error "wrong number of args for web::command"
    }
    
    # parse the name
    set cmdName [::parse getstring $content [lindex [lindex $cTree 1] 1]]
    set cmdBody [::parse getstring $content [lindex [lindex $cTree 2] 1]]
    set defOff [lindex [lindex [lindex [lindex [lindex $cTree 2] 2] 0] 1] 0]
    set defEnd [lindex [lindex [lindex [lindex [lindex $cTree 2] 2] 0] 1] 1]
    
    set strt [lindex [lindex [lindex $cTree 0] 1] 0]
    set rtns [namespace qualifiers $cmdName]
    set nsAll [regsub -all {::} [string trimleft $cmdName :] " "]
    set cmdName [lindex $nsAll end]
    set cmdBody [string trim $cmdBody "\{\}"]
    
    set topNode [$node getTopnode ::Parser::Script]
    set cn [$node lookup $cmdName [lrange $nsAll 0 end-1]]
    # If the webcmd already exists, just return it and mark all its parent
    # namespaces as valid
    if {$cn != "" && [$cn cget -type] == "webcmd"} {
        # set valid flag for context
        for {set i 0} {$i < [llength $nsAll]} {incr i} {
            set ct [$node lookup [lindex $nsAll $i] \
                [lrange $nsAll 0 [expr {$i - 1}]]]
            $ct configure -isvalid 1
        }
        
        $cn configure -definition $cmdBody -defoffset [expr {$defOff - $strt}]
        $topNode addChild $cn
        return $cn
    }
    set pn [::Parser::WebCmdNode ::#auto -name $cmdName -type webcmd \
        -definition $cmdBody -defoffset [expr {$defOff - $strt}] -runtimens $rtns]
    # Lookup the webcmd in its namespace. If the namespace does not exist
    # completely yet, create it in the parent node
    set nnsp $node
    for {set i 0} {$i < [expr {[llength $nsAll]-1}]} {incr i} {
        set nns [$node lookup [lindex $nsAll $i] [lrange $nsAll 0 [expr {$i - 1}]]]
        if {$nns == ""} {
            set nns [::Parser::Script ::#auto -type "namespace" -name [lindex $nsAll $i]]
        }
        $nnsp addChild $nns
        set nnsp $nns
    }
    $nnsp addChild $pn
    return $pn
}

