################################################################################
# iparser.itcl
#
# utilizes tclparser to construct an Itcl tree of (I)tcl code
################################################################################
set dir [file dirname [info script]]
#set auto_path [concat [file join $dir ..] $auto_path]

package require Itree 1.0
package require Tclx 8.4
package require log 1.2

package require parser::macros 1.0
package provide parser::tcl 1.0

##
# Small macro to pop the last value from a list and 
# at the same time return it
::sugar::macro lpop {cmd lv} {
    list lindex \[list \[lindex \[set $lv\] end\] \
        \[set $lv \[lrange \[set $lv\] 0 end-1\]\]\] 0
}


sugar::macro getarg {cmd arg args} {
    if {[llength $args] == 1} {
        list expr \{ \[dict exist \$args $arg\] ? \[dict get \$args $arg\] : \"$args\" \}
    } else {
        list expr \{ \[dict exist \$args $arg\] ? \[dict get \$args $arg\] : [list $args] \}
    }
}


namespace eval ::Parser {
    namespace eval Tcl {}
    
    variable CoreCommands {after append array auto_execok auto_import auto_load \
                auto_load_index auto_qualify binary break case \
                catch cd clock close concat continue dict encoding \
                eof error eval exec exit expr fblocked fconfigure \
                fcopy file fileevent flush for foreach format gets \
                glob global history if incr info interp join lappend \
                librarypath lindex linsert list llength load lrange \
                lreplace lsearch lset lsort namespace open package \
                pid proc puts pwd read rechan regexp regsub rename \
                return scan seek set socket source split string \
                subst switch tclLog tell time trace unknown unset \
                update uplevel upvar variable vwait while else elseif \
                test
    }
            
    class ProcNode {
        inherit ::Parser::Script
        
        constructor {args} {
            eval configure $args
        }
        
        # @v displayformat: overrides the display format for tests
        public variable displayformat {"%s \{%s\}" -name -arglist}
        # @v arglist: list of arguments to the proc
        public variable arglist {} {
            foreach {arg} $arglist {
                if {[llength $arg] > 1} {
                    addVariable [lindex $arg 0] 0
                } else {
                    addVariable $arg 0
                }
            }
        }
        
        # @v access: The access level. Public by default, but some
        # @v access: redefinitions may set this otherwise (itcl)
        public variable access "public"
        # @v sugarized: indicates whether this is a sugar::proc (with macros)
        public variable sugarized no
        # @v runtimens: the namespace where this proc is defined
        # @v runtimens: at runtime
        public variable runtimens ""
        # @v bodyextern: indicates whether the body is defined
        # @v bodyextern: externally via itcl::body
        public variable bodyextern 0
        # @v defoffset: The definition offset, counted from the 
        # @v defoffset: beginning of the whole definition
        public variable defoffset 0
        
    }
    
    class VarNode {
        inherit ::Parser::Script
        
        public {
            # @v displayformat: overrides the display format for tests
            variable displayformat {"%s = %s" -name -shortdefinition}
            # @v definition: overrides the variable definition
            variable definition "" {
                if {[string length $definition] > 20} {
                    configure -shortdefinition [string range $definition 0 20]...
                } else {
                    configure -shortdefinition $definition
                }
            }
            
            # @v shortdefinition: an abbreviation of the init definition
            variable shortdefinition ""
            # @v configcode: code that is associated with the
            # @v configcode: configure command in Itcl objects
            variable configcode ""
            # @v configcode: code that is associated with the
            # @v configcode: cget command in Itcl objects
            variable cgetcode ""
            # @v configbrange: byte range for the config code
            variable configbrange {}
            # @v cgetbrange: byte range for the cget code
            variable cgetbrange {}
        }
        
        constructor {args} {
            eval configure $args
        }
        
    }
    
    class PackageNode {
        inherit ::Parser::Script
        
        #public variable name "" {} {
        #    return "$name $version"
        #}
        public variable name "" {}
        public variable version ""
        # @v version: the package version
        
        constructor {args} {
            eval configure $args
        }
    }
    
    # @c This class represents a Tcl test. Tests are special commands that
    # @c have a -setup code, a -cleanup code (both optional) and a -result
    # @c They also have a description, but no arguments.
    class TclTestNode {
        inherit ::Parser::Script
        
        constructor {args} {
            eval configure $args
        }
        
        public {
            # @v description: Test description
            variable description ""
            # @v setupbrange: the byte range of the setup code
            variable setupbrange {}
            # @v setupdef: setup code definition
            variable setupdef ""
            # @v cleanupbrange: byte range of the cleanup code
            variable cleanupbrange {}
            # @v cleanupdef: The cleanup definition
            variable cleanupdef ""
            # @v resultbrange: byte range for the result definition
            variable resultbrange {}
            # @v resultdef: result definition
            variable resultdef ""
            # @v displayformat: overrides the display format for tests
            variable displayformat {"%s: %s" -name -description}
        }
        
    }


}

namespace eval ::Parser::Tcl {
        
    # @c parses a package definition. If "package require"
    proc parsePkg {node cTree content cmdRange off} {
        set nTk [llength $cTree]
        if {$nTk == 5} {
            set aList {pkgSub 1 pkgSwitch 2 pkgName 3 pkgVer 4}
        } elseif {$nTk == 4} {
            set aList {pkgSub 1 pkgName 2 pkgVer 3}
        } elseif {$nTk == 3} {
            set aList {pkgSub 1 pkgName 2}
            set pkgVer ""
        } else {
            return ""
        }
        
        foreach {tkn idx} $aList {
            set range [lindex [lindex $cTree $idx] 1]
            set $tkn [::parse getstring $content $range]
        }
        
        if {![regexp {^re} $pkgSub]} {
            return
        }
        
        # insert the package import into a special package imports node
        if {[set pkgImp [$node lookup "Package Imports"]] == ""} {
            set pkgImp [$node addChild [::Parser::Script ::#auto \
                -type "package" -name "Package Imports" -expanded 0]]
        }
        $pkgImp configure -isvalid 1
        
        set fakeName "$pkgName $pkgVer"
        set pkgNode [$pkgImp lookup $fakeName]
        if {$pkgNode != ""} {
            $pkgNode configure -isvalid 1
            return $pkgNode
        }
        
        set pkgNode [::Parser::PackageNode ::#auto -type "package" \
                -name $pkgName -version $pkgVer]
        $pkgImp addChild $pkgNode
        $pkgNode configure -byterange $cmdRange
        return $pkgNode
    }
    
    ## \brief Parses a namespace node
    ::sugar::proc parseNs {node cTree content defOffPtr} {
        upvar $defOffPtr defOff
        
        set nTk [llength $cTree]
        if {$nTk != 4} {
            return ""
        }
        
        foreach {tkn idx} {subCmd 1 nsName 2 nsDef 3} {
            set range [lindex [lindex $cTree $idx] 1]
            set $tkn [::parse getstring $content [list [lindex $range 0] [lindex $range 1]]]
        }
        
        if {$subCmd != "eval"} {
            return ""
        }
        
        # get definition range
        lassign [m-parse-defrange $cTree 3] defOff defEnd
        
        set nsAll [regsub -all {::} [string trimleft $nsName :] " "]
        set nsName [lindex $nsAll end]
        
        # add the namespace to this node.
        # First, look if it already exists
        set pnode [$node lookup [lindex $nsAll 0]]
        if {$pnode == ""} {
            # namespace does not exist yet
            set pnode [::Parser::Script ::#auto -name [lindex $nsAll 0] \
                    -type "namespace" -expanded 0]
            $node addChild $pnode
        }
        $pnode configure -isvalid 1
        
        for {set j 1} {$j < [llength $nsAll]} {incr j} {
            # add subsequent namespaces, if they don't exist
            set newnode [$node lookup [lindex $nsAll $j] \
                [lrange $nsAll 0 [expr {$j - 1}]]]
            if {$newnode == ""} {
                set newnode [::Parser::Script ::#auto -type "namespace" \
                    -name [lindex $nsAll $j] -defbrange [list $defOff $defEnd] \
                    -expanded 0]
                $pnode addChild $newnode
            }
            
            $newnode configure -isvalid 1
            set pnode $newnode
        }
        
        set nsDef [string trim $nsDef "\{\}"]
        $pnode configure -definition $nsDef -type "namespace"    
        return $pnode
    }
    
    ## \brief Parses a proc node. 
    # 
    # This method is called from [parse] when proc nodes are encountered
    # 
    # \paran[in] cTree
    #    code tree, the list returned from the [::parse] command
    # \param[in] nTk
    #    number of tokens in the code tree
    # \param[in] content
    #    String content. The content to parse as the proc. Proc is at offsets
    #    in the code tree
    ::sugar::proc parseProc {node cTree content cmdRange off args} {
        #upvar $defOffPtr defOff
        set nTk [llength $cTree]
        #set accLev [getarg -access]
        if {$nTk == 5} {
            # we are in a class and have access qualifier
            set aList {procDef 1 procName 2 argList 3 procBody 4}
        } elseif {$nTk == 4} {
            # if this is a node of type class, it could be that
            # it is a proc definition with access token (public,
            # private, protected) We will check this later
            set aList {procDef 0 procName 1 argList 2 procBody 3}
        } elseif {$nTk == 3} {
            # only proc definition in a class
            set aList {procDef 0 procName 1 argList 2}
            set procBody ""
        }
        
        set defOff 0
        set defEnd 0
        set strt [lindex [lindex [lindex $cTree 0] 1] 0]
        foreach {tkn idx} $aList {
            set $tkn [m-parse-token $content $cTree $idx]
        }
        
        if {[dict exist $aList procBody]} {
            set defOff [lindex \
                [m-parse-defrange $cTree [dict get $aList procBody]] 0]
        }
        
        set rtns [namespace qualifiers $procName]
        set nsAll [regsub -all {::} [string trimleft $procName :] " "]
        set procName [lpop nsAll]
        set procBody [string trim $procBody "\{\}"]
        set argList [lindex $argList 0]
        set node [::Parser::Util::getNamespace $node $nsAll]
        
        # add the procedure name to the top node, so that
        # it is accessible from there
        set topNode [$node getTopnode ::Parser::Script]
        
        set pn [$node lookup $procName]
        if {$pn == "" || [$pn cget -type] != "proc"} {
            set pn [::Parser::ProcNode ::#auto -name $procName -type proc]
            #set pn [::Parser::ProcNode ::#auto -name $procName -type proc \
            #    -definition $procBody  -defoffset [expr {$defOff - $strt}] \
            #    -runtimens $rtns -arglist $argList]
            $node addChild $pn
        }
        
        set sugarized no
        if {[string eq [string trim $procDef :] sugar::proc]} {
            set sugarized yes
        }
        
        $pn configure -name $procName -type proc -sugarized $sugarized \
            -definition $procBody -defoffset [expr {$defOff - $strt}] \
            -runtimens $rtns -arglist $argList -isvalid 1 \
            -byterange $cmdRange {*}$args
        # Set proc type
        switch -glob -- $procDef {
            *macro {
            $pn configure -type macro
            }
            <substproc> {
            $pn configure -type webcmd
            }
        }
        
        #$pn configure -arglist $argList -byterange $cmdRange \
        #    -isvalid 1 -sugarized $sugarized {*}$args
        ::Parser::parse $pn [expr {$defOff + $off}] $procBody
        
        $pn configure -isvalid 1
        return $pn
    }
    
    # @c parses a variable node
    ::sugar::proc parseVar {node cTree content accLev dCfOffPtr dCgOffPtr args} {
        upvar $dCfOffPtr dCfOff
        upvar $dCgOffPtr dCgOff
        
        set nTk [llength $cTree]
        set alev2 ""
        set vDef ""
        set vConf ""
        set vCget ""
        if {$nTk == 6} {
            set aList {vName 2 vDef 3 vConf 4 vCget 5}
        } elseif {$nTk == 5} {
            #set aList {vName 1 vDef 2 vConf 3 vCget 4}
            set aList {alev2 0 vName 1 vDef 2 vConf 3 vCget 4}
        } elseif {$nTk == 4} {
            #set aList {vName 1 vDef 2 vConf 3}
            set aList {alev2 0 vName 1 vDef 2 vConf 3}
        } elseif {$nTk == 3} {
            #set aList {vName 1 vDef 2}
            set aList {alev2 0 vName 1 vDef 2}
        } elseif {$nTk == 2} {
            set aList {vName 1}
            set aList {alev2 0 vName 1}
        }
        
        set dCfOff 0
        set dCfEnd 0
        set dCgOff 0
        set dCgEnd 0
        foreach {tkn idx} $aList {
            set range [lindex [lindex $cTree $idx] 1]
            set $tkn [::parse getstring $content [list [lindex $range 0] [lindex $range 1]]]
            
            # get config/cget definition range
            if {$tkn == "vConf"} {
                set dCfOff [lindex [lindex [lindex [lindex [lindex $cTree $idx] 2] 0] 1] 0]
                set dCfEnd [lindex [lindex [lindex [lindex [lindex $cTree $idx] 2] 0] 1] 1]
                
            } elseif {$tkn == "vCget"} {
                set dCgOff [lindex [lindex [lindex [lindex [lindex $cTree $idx] 2] 0] 1] 0]
                set dCgEnd [lindex [lindex [lindex [lindex [lindex $cTree $idx] 2] 0] 1] 1]
            }
        }
        
        switch -- $alev2 {
            public -
            protected -
            private {
                # definition contained access level. Move other
                # attributes one behind
                set accLev $alev2
                set vName $vDef
                set vDef $vConf
                set vConf $vCget
                set vCget ""
            }
        }
        
        set nsAll [regsub -all {::} [string trimleft $vName :] " "]
        set vName [lindex $nsAll end]
        set vConf [string trim $vConf "\{\}"]
        set vCget [string trim $vCget "\{\}"]
        
        switch -- [$node cget -type] {
            class -
            namespace {
                set varDef [getarg -vardef variable]
                set accLev [getarg -access protected]
                #if {$accLev == ""} {
                #    set accLev protected
                #} elseif {[$node cget -type] == "namespace"} {
                #    set accLev public
                #}
                $node addVariable $vName 0 1
                # if var already exists, return it
                set vNode [$node lookup $vName]
                if {$vNode != "" && [$vNode cget -type] == "[set accLev]_[set varDef]"} {
                    $vNode configure -configcode $vConf -cgetcode $vCget \
                        -definition $vDef -configbrange [list $dCfOff $dCfEnd] \
                        -cgetbrange [list $dCgOff $dCgEnd] -isvalid 1 \
                        -type [set accLev]_[set varDef]
                    return $vNode
                }
                
                set vNode [$node addChild [::Parser::VarNode ::#auto \
                        -type [set accLev]_[set varDef] -name $vName -definition $vDef \
                        -configcode $vConf -cgetcode $vCget \
                        -configbrange [list $dCfOff $dCfEnd] \
                        -cgetbrange [list $dCgOff $dCgEnd]]]
                return $vNode
            }
            proc -
            method {
                # TODO: handle when a variable definition is inside proc or method
                $node addVariable $vName $vDef 1
                return ""
            }
        }
    
        # not a class variable
        set vNode [$node lookup $vName [lrange $nsAll 0 end-1]]
        if {$vNode != ""} {
            for {set i 0} {$i < [llength $nsAll]} {incr i} {
                set ct [$node lookup [lindex $nsAll $i] \
                    [lrange $nsAll 0 [expr {$i - 1}]]]
                $ct configure -isvalid 1
            }
            return $vNode
        }
        
        set vNode [::Parser::VarNode ::#auto -type "variable" -definition $vDef -name $vName]
        
        if {[llength $nsAll] > 1} {
            set lastQual [lindex $nsAll end-1]
            set paren [$node lookup $lastQual [lrange $nsAll 0 end-2]]
            if {$paren == ""} {
                # parent namespace does not exist
                set retNs [join [lrange $nsAll 0 end-1] ::]
                return -code error "namespace $retNs not found"
            }
            $paren addChild $vNode
            #$paren addVariable $vName $vDef 1
        } else  {
            $node addChild $vNode
            #addVariable $vName $vDef 1
        }
        
        return $vNode
    }
    
    
    proc parseLclVar {node cTree content off} {
        foreach {tkn idx} {varName 1 varDef 2} {
            set range [lindex [lindex $cTree $idx] 1]
            set $tkn [::parse getstring $content $range]
        }
        
        set doff [lindex [lindex [lindex [lindex [lindex $cTree 1] 2] 0] 1] 0]
        $node addVariable $varName [expr {$doff + $off}]
    }
    
    proc parseForeach {node cTree content off} {
        foreach {tkn idx} {varSect 1 fDef 3} {
            set range [lindex [lindex $cTree $idx] 1]
            set $tkn [::parse getstring $content \
                    [list [lindex $range 0] [lindex $range 1]]]
        }
        
        # offset in variable def section of foreach
        set do0 [lindex [lindex [lindex [lindex [lindex $cTree 1] 2] 0] 1] 0]
        # offset in definition section
        set defOff [lindex [lindex [lindex [lindex [lindex $cTree 3] 2] 0] 1] 0]
        
        foreach {var} [lindex $varSect 0] {
            $node addVariable $var [expr {$off + $do0}]
        }
        set fDef [string trim $fDef "\{\}"]
        if {$fDef == ""} {
            return
        }
        ::Parser::parse $node [expr {$off + $defOff}] $fDef
    }
    
    proc parseFor {node cTree content off} {
        foreach {tkn doff idx} {v1 v1o 1 v2 v2o 2 v3 v3o 3 forDef forDefo 4} {
            set range [lindex [lindex $cTree $idx] 1]
            set $tkn [::parse getstring $content \
                    [list [lindex $range 0] [lindex $range 1]]]
            
            set $doff [lindex [lindex [lindex [lindex \
                [lindex $cTree $idx] 2] 0] 1] 0]
        }
        
        set lst [list [lindex $v1 0] $v1o [lindex $v2 0] $v2o \
            [lindex $v3 0] $v3o [lindex $forDef 0] $forDefo]
        
        foreach {elem doff} $lst {
            if {$elem == ""} {
                continue
            }
            
            ::Parser::parse $node [expr {$doff + $off}] $elem
        }
    }
    
    proc parseIf {node cTree content off} {
        for {set i 1} {$i < [llength $cTree]} {incr i} {
            set rg [lindex [lindex $cTree $i] 1]
            set iDef [::parse getstring $content \
                [list [lindex $rg 0] [lindex $rg 1]]]
            set iDefOff [lindex [lindex [lindex [lindex \
                [lindex $cTree $i] 2] 0] 1] 0]
            
            switch -- $iDef {
                "else" -
                "elseif" {
                    # nothing
                }
                default {
                    set iDef [string trim $iDef "\{\}"]
                    if {$iDef != "" && [catch {
                            ::Parser::parse $node [expr {$off + $iDefOff}] $iDef
                        } msg]} {
                            #puts "$msg"
                    }
                }
            }
        }
    }
    
    proc parseSwitch {node cTree content off} {
        set range [lindex [lindex $cTree end] 1]
        set sDef [::parse getstring $content \
            [list [lindex $range 0] [lindex $range 1]]]
        set sDefOff [lindex [lindex [lindex [lindex \
            [lindex $cTree end] 2] 0] 1] 0]
        
        set sDef [lindex $sDef 0]
        incr off $sDefOff
        while {1} {
            set res [::parse command $sDef {0 end}]
            set ct [lindex $res 3]
            if {$ct == ""} {
                return
            }
            
            incr off [lindex [lindex [lindex [lindex [lindex $ct end] end] 0] 1] 0]
                
            set rg [lindex [lindex $ct end] 1]
            set def [::parse getstring $sDef [list [lindex $rg 0] [lindex $rg 1]]]
            
            # parse the definitions
            set def [lindex $def 0]
            if {$def != ""} {
                ::Parser::parse $node $off $def
            }
            
            set idx [lindex [lindex $res 2] 0]
            incr off [lindex [lindex [lindex $ct end] 1] 1]
            set sDef [::parse getstring $sDef [list $idx end]]
            
        }
    }
    
    proc parseWhile {node cTree content off} {
        set range [lindex [lindex $cTree end] 1]
        set wDef [::parse getstring $content \
            [list [lindex $range 0] [lindex $range 1]]]
        set wDefOff [lindex [lindex [lindex [lindex \
            [lindex $cTree end] 2] 0] 1] 0]
        
        set wDef [lindex $wDef 0]
        if {$wDef != ""} {
            ::Parser::parse $node [expr {$off + $wDefOff}] $wDef
        }
    }
    
    
    # @c parses a test command
    proc parseTest {node cTree content setupOffPtr bodyOffPtr cleanupOffPtr} {
        upvar $setupOffPtr setupOff
        upvar $bodyOffPtr bodyOff
        upvar $cleanupOffPtr cleanupOff
        
        set testName [::parse getstring $content [lindex [lindex $cTree 1] 1]]
        set testDesc [::parse getstring $content [lindex [lindex $cTree 2] 1]]
        
        set setupDef ""
        set setupEnd 0
        set bodyDef ""
        set bodyEnd 0
        set cleanupDef ""
        set cleanupEnd 0
        set resultDef ""
        set resultOff 0
        set resultEnd 0
        for {set i 3} {$i < [llength $cTree]} {incr i} {
            set key [::parse getstring $content [lindex [lindex $cTree $i] 1]]
            switch -- $key {
                -setup {
                    incr i
                    set setupDef [string trim [::parse getstring $content \
                        [lindex [lindex $cTree $i] 1]] "\{\}"]
                    set setupOff [lindex [lindex [lindex [lindex [lindex $cTree $i] 2] 0] 1] 0]
                    set setupEnd [lindex [lindex [lindex [lindex [lindex $cTree $i] 2] 0] 1] 1]
                }
                -body {
                    incr i
                    set bodyDef [string trim [::parse getstring $content \
                        [lindex [lindex $cTree $i] 1]] "\{\}"]
                    set bodyOff [lindex [lindex [lindex \
                        [lindex [lindex $cTree $i] 2] 0] 1] 0]
                    set bodyEnd [lindex [lindex [lindex \
                        [lindex [lindex $cTree $i] 2] 0] 1] 1]
                }
                -cleanup {
                    incr i
                    set cleanupDef [string trim [::parse getstring $content \
                        [lindex [lindex $cTree $i] 1]] "\{\}"]
                    set cleanupOff [lindex [lindex [lindex \
                        [lindex [lindex $cTree $i] 2] 0] 1] 0]
                    set cleanupEnd [lindex [lindex [lindex \
                        [lindex [lindex $cTree $i] 2] 0] 1] 1]
                }
                -result {
                    incr i
                    set resultDef [string trim [::parse getstring $content \
                        [lindex [lindex $cTree $i] 1]] "\{\}"]
                    set resultOff [lindex [lindex [lindex \
                        [lindex [lindex $cTree $i] 2] 0] 1] 0]
                    set resultEnd [lindex [lindex [lindex \
                        [lindex [lindex $cTree $i] 2] 0] 1] 1]
                }
            }
            
        }
        
        if {[set testNode [$node lookup $testName]] == ""} {
            set testNode [$node addChild [::Parser::TclTestNode ::#auto \
                -name $testName -type tcltest]]
        }
        $testNode configure -isvalid 1 -description $testDesc \
            -definition $bodyDef -defbrange [list $bodyOff $bodyEnd] \
            -setupdef $setupDef -setupbrange [list $setupOff $setupEnd] \
            -cleanupdef $cleanupDef -cleanupbrange [list $cleanupOff $cleanupEnd] \
            -resultdef $resultDef -resultbrange [list $resultOff $resultEnd]
        
        return $testNode
    }
    
}

namespace eval ::Parser::Util {
    # Returns the parent namespace in which a definition is to be created
    # ns is a qualified namespace of the form ::a::b::c. It is split into
    # a list of namespaces and for every part is checked, whether a namespace 
    # node of that name already exists in "node". If not, these nodes are
    # created. The node of the last identifier in ns is returned
    proc getNamespace {node nsList} {
        foreach {ns} $nsList {
            set nsNode [$node lookup $ns]
            if {$nsNode == ""} {
                set nsNode [::Parser::Script ::#auto -isvalid 1 -expanded 0 \
                        -type "namespace" -name [lindex $nsList 0]]
                $node addChild $nsNode
            }
            $nsNode configure -isvalid 1
            set node $nsNode
        }
        
        return $node
    }
    
    # Checks whether a fully qualified namespace with all elements in nsList
    # exists inside node
    proc checkNamespace {node nsList} {
        foreach {ns} $nsList {
            set nsNode [$node lookup $ns]
            if {$nsNode == ""} {
                return no
            }
            set node $nsNode
        }
        return yes
    }
}

