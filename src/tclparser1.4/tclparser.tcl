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
    
    variable CoreCommands {
        after append apply array auto_execok auto_import auto_load auto_load_index 
        auto_qualify binary break case catch cd chan clock close concat continue 
        coroutine countlines dict encoding eof error eval exec exit expr fblocked 
        fconfigure fcopy file fileevent flush for foreach format getNsCmd gets glob 
        global if incr info interp join lappend lassign lindex linsert list llength 
        lmap load lrange lrepeat lreplace lreverse lsearch lset lsort namespace open 
        package pid pkg_mkIndex proc puts pwd read regexp regsub rename return scan 
        seek set socket source split string subst switch tailcall tclLog tclPkgSetup 
        tclPkgUnknown tell throw time trace try unknown unload unset update uplevel 
        upvar variable vwait while yield yieldto zlib
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
            set $tkn [m-parse-token $content $cTree $idx]
            #set range [lindex [lindex $cTree $idx] 1]
            #set $tkn [::parse getstring $content [list [lindex $range 0] [lindex $range 1]]]
        }
        
        if {$subCmd != "eval"} {
            return ""
        }
        
        # get definition range
        lassign [m-parse-defrange $cTree 3] defOff defEnd
        
        #set nsAll [regsub -all {::} [string trimleft $nsName :] " "]
        #set nsName [lindex $nsAll end]
        
        set nsNode [::Parser::Util::getNamespace $node \
            [split [regsub -all {::} $nsName ,] ,]]
        #set nsName [namespace tail $nsName]
        #set nsNode [::Parser::Util::getNamespace $node $nsAll]
        $nsNode configure -isvalid 1 -definition [string trim $nsDef "{}"] \
            -defbrange [list $defOff $defEnd]
        return $nsNode
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
        #set nsAll [regsub -all {::} [string trimleft $procName :] " "]
        #set procName [lpop nsAll]
        set procBody [string trim $procBody "\{\}"]
        set argList [lindex $argList 0]
        #set node [::Parser::Util::getNamespace $node $nsAll]
        
        set nsNode [::Parser::Util::getNamespace $node \
            [lrange [split [regsub -all {::} $procName ,] ,] 0 end-1]]
        set procName [namespace tail $procName]
        # add the procedure name to the top node, so that
        # it is accessible from there
        #set topNode [$node getTopnode ::Parser::Script]
        
        set pn [$nsNode lookup $procName]
        if {$pn == "" || [$pn cget -type] != "proc"} {
            set pn [::Parser::ProcNode ::#auto -name $procName -type proc]
            $nsNode addChild $pn
        }
        
        set sugarized no
        if {[string eq [string trim $procDef :] sugar::proc]} {
            set sugarized yes
        }
        
        $pn configure -name $procName -type proc -sugarized $sugarized \
            -definition $procBody -defoffset [expr {$defOff - $strt}] \
            -runtimens $rtns -arglist $argList -isvalid 1 \
            -byterange $cmdRange
        # Set proc type
        switch -glob -- $procDef {
            *macro {
            $pn configure -type macro
            }
            <substproc> {
            $pn configure -type webcmd
            }
        }
        
        ::Parser::parse $pn [expr {$defOff + $off}] $procBody
        
        $pn configure -isvalid 1
        return $pn
    }
    
    ## \brief Parses a Tcl namespace variable
    ::sugar::proc parseVar {node cTree content} {
        if {[$node isa ::Parser::ProcNode]} {
            # we don't want to show variable definitions in procs
            return
        }
        
        lassign {variable "" ""} varDef vName vDef
        set tokens {varDef 0 vName 1 vDef 2}
        foreach {tkn idx} $tokens {
            if {$idx >= [llength $cTree]} {
                break
            }
            set $tkn [m-parse-token $content $cTree $idx]
        }
        
        set nsNode [::Parser::Util::getNamespace $node \
            [lrange [split [regsub -all {::} $vName ,] ,] 0 end-1]]
        set vName [namespace tail $vName]
        set vNode [$nsNode lookup $vName]
        if {$vNode == ""} {
            set vNode [::Parser::VarNode ::#auto -type "variable" \
                -definition $vDef -name $vName -isvalid 1]
            $nsNode addChild $vNode
        }
        $vNode configure -definition $vDef -name $vName -isvalid 1
        return $vNode
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

namespace eval ::Parser::Tcl::ParseLocal {
    
    ::sugar::proc _set {node cTree content off} {
        foreach {tkn idx} {varName 1 varDef 2} {
            set $tkn [m-parse-token $content $cTree $idx]
        }
        
        lassign [m-parse-defrange $cTree 1] doff
        $node addVariable $varName [expr {$doff + $off}]
    }
    
    ::sugar::proc _foreach {node cTree content off} {
        foreach {tkn idx} {varSect 1 fDef 3} {
            set $tkn [m-parse-token $content $cTree $idx]
        }
        
        # offset in variable def section of foreach and definition
        lassign [m-parse-defrange $cTree 1] do0
        lassign [m-parse-defrange $cTree 3] defOff
        
        foreach {var} [lindex $varSect 0] {
            $node addVariable $var [expr {$off + $do0}]
        }
        set fDef [string trim $fDef "\{\}"]
        if {$fDef == ""} {
            return
        }
        ::Parser::parse $node [expr {$off + $defOff}] $fDef
    }
    
    proc _for {node cTree content off} {
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
    
    proc _if {node cTree content off} {
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
    
    proc _switch {node cTree content off} {
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
    
    proc _while {node cTree content off} {
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
    
    ::sugar::proc _lassign {node cTree content off} {
        for {set i 2} {$i < [llength $cTree]} {incr i} {
            set nv [m-parse-token $content $cTree $i]
            lassign [m-parse-defrange $cTree 1] doff
            $node addVariable $nv [expr {$doff + $off}]
        }
    }

}

namespace eval ::Parser::Util {
    # Returns the parent namespace in which a definition is to be created
    # ns is a qualified namespace of the form ::a::b::c. It is split into
    # a list of namespaces and for every part is checked, whether a namespace 
    # node of that name already exists in "node". If not, these nodes are
    # created. The node of the last identifier in ns is returned
    proc getNamespace {node nsList} {
        if {[llength $nsList] > 0 && [lindex $nsList 0] == {}} {
            # resolving from global namespace
            set node [$node getTopnode ::Parser::Script]
            set nsList [lrange $nsList 1 end]
        }
        foreach {ns} $nsList {
            set nsNodes [$node lookupAll $ns]
            set nsNode {}
            foreach {nnode} $nsNodes {
                if {[$nnode cget -type] eq "namespace"} {
                    $nnode configure -isvalid 1
                    set nsNode $nnode
                    break
                }
            }
            if {$nsNode == {}} {
                set nsNode [::Parser::Script ::#auto -isvalid 1 -expanded 0 \
                    -type "namespace" -name $ns -isvalid 1]
                $node addChild $nsNode
            }
            #if {$nsNode == "" || [$nsNode cget -type] ne "namespace"} {
            #}
            $nsNode configure -isvalid 1
            set node $nsNode
        }
        
        return $node
    }
    
    # Checks whether a fully qualified namespace with all elements in nsList
    # exists inside node
    proc checkNamespace {node nsList} {
        if {[llength $nsList] == 0} {
            # the global namespace
            return yes
        }
        
        if {[llength $nsList] > 0 && [lindex $nsList 0] == {}} {
            # resolving from global namespace
            set node [$node getTopnode ::Parser::Script]
            set nsList [lrange $nsList 1 end]
        }
        
        foreach {ns} $nsList {
            foreach {nnode} [$node lookupAll $ns] {
                if {[$nnode cget -type] eq "namespace"} {
                    return yes
                }
            }
        }
        return no
        #foreach {ns} $nsList {
        #    set nsNode [$node lookup $ns]
        #    if {$nsNode == "" || [$nsNode cget -type] ne "namespace"} {
        #        return no
        #    }
        #    set node $nsNode
        #}
        #return yes
    }
}

