
package re parser 1.4
package require parser::script 1.0
package require parser::tcl 1.0
package require parser::itcl 1.0
package require parser::xotcl 1.0
package require parser::web 1.0

package provide parser::parse 1.0

namespace eval ::Parser {
    variable CurrAccessLevel ""
}

# @c build a tree. If not content is given (content = ""),
# @c the object definition is taken as parse content.
# @c brVar is the name of the variable where the byte
# @c range is stored, that the content ocupies. Per
# @c default (brVar = "") it is the -byterange variable
#
# @a off: offset in the original content. While setting the
# @a off: range variables, this is added to the range offsets
# @a off: that come out of parsing
# @a content: the content to parse or ""
proc ::Parser::parse {node off content} {
    variable CurrAccessLevel
    
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
        set fToken [lindex $codeTree 0]
        set token [::parse getstring $content [lindex $fToken 1]]
        switch -glob -- $token {
            
            "package" {
                set pkgNode [Tcl::parsePkg $node $codeTree $content]
                if {$pkgNode != ""} {
                    $pkgNode configure -byterange $cmdRange
                }
            }
            
            "namespace" {
                set defOff 0
                set nsn [Tcl::parseNs $node $codeTree $content defOff]
                if {$nsn != ""} {
                    $nsn configure -byterange $cmdRange
                    parse $nsn [expr {$off + $defOff}] [$nsn cget -definition]
                }
            }
            
            "proc" -
            "::sugar::proc" -
            "sugar::proc" -
            "::sugar::macro" -
            "sugar::macro" -
            "macro" -
            "<substproc>" {
                set defOff 0
                set pn [Tcl::parseProc $node $codeTree $content "" defOff]
                
                if {$pn != ""} {
                    switch -glob -- $token {
                        *macro {
                        $pn configure -type macro
                        }
                        <substproc> {
                        $pn configure -type webcmd
                        }
                    }
                    $pn configure -byterange $cmdRange
                    parse $pn [expr {$defOff + $off}] [$pn cget -definition]
                }
            }
            
            "command" -
            "web::command" {
                set defOff 0
                set pn [Web::parseWebCmd $node $codeTree $content defOff]
                if {$pn != ""} {
                    $pn configure -byterange $cmdRange
                    parse $pn [expr {$defOff + $off}] [$pn cget -definition]
                }
            }
            
            "class" {
                # Itcl class
                set defOff 0
                set cnode [Itcl::parseClass $node $codeTree $content defOff]
                if {$cnode != ""} {
                    $cnode configure -byterange $cmdRange
                    parse $cnode [expr {$off + $defOff}] [$cnode cget -definition]
                    $cnode addVariable this 0 1
                    if {[$cnode cget -isitk]} {
                        $cnode addVariable itk_interior 0 1
                        $cnode addVariable itk_option 0 1
                    }
                    $cnode updatePTokens
                }
            }
            
            "Class" {
                # XOTcl class
                set defOff 0
                set slotOff -1
                set cnode [Xotcl::parseClass $node $codeTree $content defOff slotOff]
                if {$cnode != ""} {
                    $cnode configure -byterange $cmdRange
                    if {$slotOff >= 0} {
                        parse $cnode [expr {$off + $slotOff}] [$cnode cget -slotdefinition]
                    }
                }
            }
            
            "*Attribute" -
            "xotcl::Attribute" -
            "::xotcl::Attribute" {
                set defOff 0
                switch -- [$node cget -type] {
                class {
                    set anode [Xotcl::parseAttribute $node $codeTree $content defOff]
                    if {$anode != {}} {
                        $anode configure -byterange $cmdRange
                    }
                }
                default {
                    # These could be xotcl classes. Try to parse instprocs, procs etc.
                    # inst/proc to a derived attribute
                    set defOff -1
                    set preOff -1
                    set postOff -1
                    
                    set nm [::parse getstring $content [lindex [lindex $codeTree 0] 1]]
                    set nsAll [regsub -all {::} [string trimleft $nm :] " "]
                    set nm [lindex $nsAll end]
                    set tn [[$node getTopnode ::Parser::Script] lookup $nm [lrange $nsAll 0 end-1]]
                    set iNode [Xotcl::parseInstCmd $tn $codeTree $content defOff preOff postOff]
                    puts $iNode,[$iNode cget -definition]
                    if {$iNode != ""} {
                        $iNode configure -byterange $cmdRange
                        parse $iNode [expr {$off + $defOff}] [$iNode cget -definition]
                        parse $iNode [expr {$off + $preOff}] [$iNode cget -preassertion]
                        parse $iNode [expr {$off + $postOff}] [$iNode cget -postassertion]
                    }
                }
                
                }
            }
            
            "public" -
            "protected" -
            "private" {
                set secToken [lindex $codeTree 1]
                set range [lindex $secToken 1]
                set realToken [::parse getstring $content \
                    [list [lindex $range 0] [lindex $range 1]]]
                switch -- $realToken {
                    "variable" {
                        set dCfOff 0
                        set dCgOff 0
                        set vNode [Tcl::parseVar $node $codeTree $content \
                                $token dCfOff dCgOff]
                        if {$vNode != ""} {
                            $vNode configure -byterange $cmdRange
                            parse $vNode [expr {$dCfOff + $off}] [$vNode cget -configcode]
                            parse $vNode [expr {$dCgOff + $off}] [$vNode cget -cgetcode]
                        }
                    }
                    "common" {
                        set cnNode [Itcl::parseCommon $node $codeTree $content]
                    }
                    "method" {
                        set mNode [Itcl::parseMethod $node $codeTree $content \
                                $token]
                        if {$mNode != ""} {
                            $mNode configure -byterange $cmdRange
                            parse $mNode $off [$mNode cget -definition]
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
                        set pn [Tcl::parseProc $node $codeTree $content dummy]
                        if {$pn != ""} {
                            $pn configure -byterange $cmdRange
                            parse $pn $off [$pn cget -definition]
                        }
                    }
                    "default" {
                        set CurrAccessLevel $token
                        set defOff [lindex [lindex [lindex [lindex \
                            [lindex $codeTree 1] 2] 0] 1] 0]
                        set defEnd [lindex [lindex [lindex [lindex \
                            [lindex $codeTree 1] 2] 0] 1] 1]
                        set newCtn [::parse getstring $content \
                            [lindex [lindex $codeTree 1] 1]]
                        set newCtn [string trim $newCtn "\{\}"]
                        parse $node [expr {$off + $defOff}] $newCtn
                        set CurrAccessLevel ""
                    }
                }
            }
            
            "method" {
                set mNode [Itcl::parseMethod $node $codeTree $content \
                    $CurrAccessLevel]
                if {$mNode != ""} {
                    $mNode configure -byterange $cmdRange
                    parse $mNode $off [$mNode cget -definition]
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
            
            "constructor" {
                set defOff 0
                set csNode [Itcl::parseConstructor $node $codeTree $content defOff]
                if {$csNode != ""} {
                    $csNode configure -byterange $cmdRange
                    parse $csNode [expr {$off + $defOff}] [$csNode cget -definition]
                }
            }
            
            "destructor" {
                set defOff 0
                set dNode [Itcl::parseDestructor $node $codeTree $content defOff]
                if {$dNode != ""} {
                    $dNode configure -byterange $cmdRange
                    parse $dNode [expr {$off + $defOff}] [$dNode cget -definition]
                }
            }
            
            "variable" {
                set dCfOff 0
                set dCgOff 0
                set vNode [Tcl::parseVar $node $codeTree $content \
                    $CurrAccessLevel dCgOff dCfOff]
                if {$vNode != ""} {
                    $vNode configure -byterange $cmdRange
                    parse $vNode [expr {$dCfOff + $off}] [$vNode cget -configcode]
                    parse $vNode [expr {$dCgOff + $off}] [$vNode cget -cgetcode]
                }
            }
            
            "common" {
            }
            
            "set" {
                Tcl::parseLclVar $node $codeTree $content $off
            }
            
            "foreach" {
                Tcl::parseForeach $node $codeTree $content $off
            }
            
            "for" {
                Tcl::parseFor $node $codeTree $content $off
            }
            
            "if" {
                Tcl::parseIf $node $codeTree $content $off
            }
            
            "switch" {
                Tcl::parseSwitch $node $codeTree $content $off
            }
            
            "while" {
                Tcl::parseWhile $node $codeTree $content $off
            }
            
            "inherit" {
                Itcl::parseInherit $node $codeTree $content
            }
            
            "body" -
            "itcl::body" -
            "::itcl::body" {
                set defOff 0
                if {[catch {
                        Itcl::parseBody $node $codeTree $content defOff
                    } bNode]} {
                    
                    set bNode ""
                }
                if {$bNode != ""} {
                    $bNode configure -defbrange [$bNode cget -byterange]
                    $bNode configure -byterange $cmdRange
                    parse $bNode [expr {$off + $defOff}] [$bNode cget -definition]
                }
            }
            
            itk_component {
                set dBdOff 0
                set compNode [Itcl::parseItkComponent $node $codeTree $content \
                    $off dBdOff]
                if {$compNode != ""} {
                    $compNode configure -byterange $cmdRange
                }
            }
            
            tcltest::test -
            test {
                set setupOff 0
                set bodyOff 0
                set cleanupOff 0
                set testNode [Tcl::parseTest $node $codeTree $content \
                    setupOff bodyOff cleanupOff]
                if {$testNode != ""} {
                    $testNode configure -byterange $cmdRange
                    parse $testNode [expr {$off + $setupOff}] [$testNode cget -setupdef]
                    parse $testNode [expr {$off + $bodyOff}] [$testNode cget -definition]
                    parse $testNode [expr {$off + $cleanupOff}] [$testNode cget -cleanupdef]
                }
            }
            
            default {
                set nm [::parse getstring $content [lindex [lindex $codeTree 0] 1]]
                set nsAll [regsub -all {::} [string trimleft $nm :] " "]
                set nm [lindex $nsAll end]
                set tn [[$node getTopnode ::Parser::Script] lookup $nm [lrange $nsAll 0 end-1]]
                if {$tn != {} && [$tn isa ::Parser::XotclClassNode]} {
                    # These could be xotcl classes. Try to parse instprocs, procs etc.
                    set defOff -1
                    set preOff -1
                    set postOff -1
                    set iNode [Xotcl::parseInstCmd $tn $codeTree $content defOff preOff postOff]
                    if {$iNode != ""} {
                        $iNode configure -byterange $cmdRange
                        parse $iNode [expr {$off + $defOff}] [$iNode cget -definition]
                        parse $iNode [expr {$off + $preOff}] [$iNode cget -preassertion]
                        parse $iNode [expr {$off + $postOff}] [$iNode cget -postassertion]
                    }
                } elseif {[regexp {Class$} $nm]} {
                    # This is our special handler for Xotcl meta classes. If their name ends
                    # on "Class", then we are able to parse them. Otherwise not!
                    set defOff 0
                    set slotOff -1
                    set cnode [Xotcl::parseClass $node $codeTree $content defOff slotOff]
                    if {$cnode != ""} {
                        $cnode configure -byterange $cmdRange
                        if {$slotOff >= 0} {
                            parse $cnode [expr {$off + $slotOff}] [$cnode cget -slotdefinition]
                        }
                    }
                }
            }
            
        }
        # step forward in the content
        set idx [lindex [lindex $res 2] 0]
        incr off $idx
        set content [::parse getstring $content [list $idx end]]
    }
    
    
}

# @c reparses the tree, given content. The newNodesPtr and
# @c oldNodesPtr are filled with a list of nodes that are
# @c newly created and a list of nodes that are obsolete,
# @c respectively
proc ::Parser::reparse {node content newNodesPtr oldNodesPtr} {
    upvar $newNodesPtr newNodes
    upvar $oldNodesPtr oldNodes
    set aChBefore [$node getChildren 1]
    foreach child $aChBefore {
        $child configure -isvalid 0
        $child removeVariables
    }
    
    $node removeVariables
    $node configure -definition $content
    ::Parser::parse $node 0 $content
    
    foreach child [$node getChildren 1] {
        if {[$child cget -isvalid]} {
            if {![lcontain $aChBefore $child]} {
                lappend newNodes $child
            }
            continue
        }
        set par [$child getParent]
        if {$par != ""} {
            $par removeChild $child
            lappend oldNodes $child
        }
    }
}

