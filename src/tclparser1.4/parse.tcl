


package require parser 1.4
package require parser::macros 1.0
package require parser::script 1.0
package require parser::tcl 1.0
package require parser::itcl 1.0
package require parser::snit 1.0
package require parser::tcloo 1.0
package require parser::nx 1.0
package require parser::xotcl 1.0
package require parser::web 1.0

package require sugar 0.1
sugar::macro getarg {cmd arg args} {
    if {[llength $args] == 1} {
        list expr \{ \[dict exist \$args $arg\] ? \[dict get \$args $arg\] : \"$args\" \}
    } else {
        list expr \{ \[dict exist \$args $arg\] ? \[dict get \$args $arg\] : [list $args] \}
    }
}


namespace eval ::Parser {
    variable CurrentAccess ""
    
    
    ## \brief Parse a class node and returns it as tree.
    #
    # This method creates class nodes depending on the definition
    ::sugar::proc parseClass {node cTree content byteRange off defOffPtr {type class}} {
        upvar $defOffPtr defOff
        set nTk [llength $cTree]
        
        if {[llength $cTree] == 3} {
            # either an Itcl class or a TclOO/XOTcl class without definition
            # We try to find out:
            foreach {tkn idx} {clsTkn 0 clsName 1 clsDef 2} {
                set range [lindex [lindex $cTree $idx] 1]
                set $tkn [::parse getstring $content \
                    [list [lindex $range 0] [lindex $range 1]]]
            }
            # depending on the token length of clsDef, it is a name or Itcl 
            # definition.
            # We cannot rely on the second token be "create", because it might
            # be a class that is named "create"
            if {[llength [string trim $clsDef "{}"]] > 1} {
                lassign [m-parse-defrange $cTree 2] defOff defEnd
                switch -glob -- $clsTkn {
                    *class {
                        return [Itcl::createClass $node $clsName \
                            $clsDef [list $defOff $defEnd]]
                    }
                    *type -
                    *widget {
                        return [Snit::createType $node $clsName \
                            $clsDef $clsTkn [list $defOff $defEnd]]
                    }
                }
            } elseif {[string match *class $clsTkn] && [string eq $clsName create]} {
                return [TclOO::createClass $node $clsDef {} {}]
            } elseif {[string match *Class $clsTkn]} {
                # XOTcl
                set cnode [Xotcl::parseClass $node $cTree $content defOff slotOff]
                if {$cnode != ""} {
                    #$cnode configure -byterange $cmdRange
                    if {$slotOff >= 0} {
                        parse $cnode [expr {$off + $slotOff}] [$cnode cget -slotdefinition]
                    }
                }
                return $cnode
            } else {
                # some funny guy has invented yet another OO system that
                # we don't know and don't support as of now
                return
            }
        } elseif {[llength $cTree] == 4} {
            # Scrape out TclOO class with definition.
            foreach {tkn idx} {clsTkn 0 clsCreate 1 clsName 2 clsDef 3} {
                set range [lindex [lindex $cTree $idx] 1]
                set $tkn [::parse getstring $content \
                    [list [lindex $range 0] [lindex $range 1]]]
            }
            
            # if this condition holds true, we have a TclOO class with
            # definition. Otherwise we fall through and parse NX classes
            # or XOTcl classes
            if {[string eq $clsCreate create] && [string match *class $clsTkn]} {
               lassign [m-parse-defrange $cTree 3] defOff defEnd
               return [TclOO::createClass $node $clsName \
                   $clsDef [list $defOff $defEnd]]
            }
        }
        
        # XOTcl or NX. The only half way reliable method is to check whether
        # the first subcommand after Class is "create". This means, that XOTcl
        # classes with the name "create" will be threated as NX classes and will
        # not be correctly parsed.
        # We could also check for nx::Class in the clsTkn, but if people do
        # namespace import nx::* and use Class instead of nx::Class, that will
        # fail. It's more likely that users will import namespace than naming 
        # their class "create"
        foreach {tkn idx} {clsTkn 0 clsCreate 1} {
            set range [lindex [lindex $cTree $idx] 1]
            set $tkn [::parse getstring $content \
                [list [lindex $range 0] [lindex $range 1]]]
        }
        
        if {[string match *nx:: $clsTkn] || [string eq $clsCreate create]} {
            set defOff 0
            set slotOff -1
            set cnode [Nx::parseClass $node $cTree $content defOff slotOff]
            if {$cnode ne ""} {
                $cnode configure -byterange $byteRange
                if {$slotOff >= 0} {
                    parse $cnode [expr {$off + $slotOff}] \
                        [$cnode cget -slotdefinition]
                }
                set def [$cnode cget -definition]
                #puts defbrange=[$cnode cget -defbrange]
                Nx::parseScriptedBody $cnode [expr {$off + $defOff}] $def
            }
            return $cnode                       
        }

        # Finally, an XOTcl class
        set defOff 0
        set slotOff -1
        set cnode [Xotcl::parseClass $node $cTree $content defOff slotOff]
        if {$cnode != ""} {
            $cnode configure -byterange $byteRange
            if {$slotOff >= 0} {
                parse $cnode [expr {$off + $slotOff}] [$cnode cget -slotdefinition]
            }
        }
        return $cnode
    }
    

    ## \brief Build a tree of commands (tokens) in a Tcl script. 
    #
    # If not content is given (content = ""), the object definition is taken as 
    # parse content. brVar is the name of the variable where the byte range is stored, 
    # that the content ocupies. Per default (brVar = "") it is the -byterange variable
    #
    # \param[in] node
    #    The parent node of the script. This can be a namespace, class proc or
    #    anything else that contains a Tcl script
    # \param[in] off
    #    offset in the original content. While setting the range variables, this is 
    #    added to the range offsets that come out of parsing
    # \param[in] content
    #    The content to parse or ""
    sugar::proc parse {node off content args} {
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
                    Tcl::parsePkg $node $codeTree $content $cmdRange $off
                }
                
                "namespace" {
                    variable CurrentAccess
                    set CurrentAccess public
                    set defOff 0
                    set nsn [Tcl::parseNs $node $codeTree $content defOff]
                    if {$nsn != ""} {
                        $nsn configure -byterange $cmdRange
                        parse $nsn [expr {$off + $defOff}] [$nsn cget -definition]
                    }
                    set CurrentAccess ""
                }
                
                "proc" -
                "::sugar::proc" -
                "sugar::proc" -
                "::sugar::macro" -
                "sugar::macro" -
                "macro" -
                "<substproc>" {
                    Tcl::parseProc $node $codeTree $content $cmdRange $off {*}$args
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
                
                type -
                snit::type -
                ::snit::type -
                widget -
                snit::widget -
                ::snit::widget -
                class -
                itcl::class -
                ::itcl::class -
                *Class {
                    # Itcl class
                    variable CurrentAccess
                    set CurrentAccess public
                    set defOff 0
                    #set cnode [Itcl::parseClass $node $codeTree $content defOff]
                    set cnode [parseClass $node $codeTree $content $cmdRange $off defOff]
                    if {$cnode != ""} {
                        $cnode configure -byterange $cmdRange
                        parse $cnode [expr {$off + $defOff}] [$cnode cget -definition]
                        $cnode addVariable this 0 1
                        if {[$cnode cget -isitk]} {
                            $cnode addVariable itk_interior 0 1
                            $cnode addVariable itk_option 0 1
                        }
                        #$cnode updatePTokens
                    }
                    set CurrentAccess ""
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
                        #puts $iNode,[$iNode cget -definition]
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
                    Itcl::parseAccess $node $codeTree $content $cmdRange $off \
                        -access $token {*}$args
                }
                
                "method" {
                    set acc [getarg -access public]
                    set mNode [Itcl::parseMethod $node $codeTree $content $off $acc]
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
                
                "variable" -
                "common" {
                    set dCfOff 0
                    set dCgOff 0
                    #set acc [getarg -access]
                    variable CurrentAccess
                    set vNode [Tcl::parseVar $node $codeTree $content "" dCgOff dCfOff \
                        -vardef $token -access $CurrentAccess]
                    if {$vNode != ""} {
                        $vNode configure -byterange $cmdRange
                        parse $vNode [expr {$dCfOff + $off}] [$vNode cget -configcode]
                        parse $vNode [expr {$dCgOff + $off}] [$vNode cget -cgetcode]
                    }
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
                
                "inherit" -
                superclass {
                    Itcl::parseInherit $node $codeTree $content
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
                    #puts $token
                    set nsAll [regsub -all {::} [string trimleft $token :] " "]
                    set ns [lrange $nsAll 0 end-1]
                    if {[Util::checkNamespace $node $ns]} {
                        set lclNode [Util::getNamespace $node $ns]
                        set tn [$lclNode lookup [lindex $nsAll end]]
                        if {$tn != "" && [$tn isa ::Parser::ClassNode]} {
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
    
    ## \brief reparses the tree, given content. 
    #
    # The newNodesPtr and oldNodesPtr are filled with a list of nodes that 
    # are newly created and a list of nodes that are obsolete, respectively
    proc reparse {node content newNodesPtr oldNodesPtr} {
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
    
        
}

package provide parser::parse 1.0

