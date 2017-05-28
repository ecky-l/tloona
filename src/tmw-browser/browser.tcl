## browser.tcl (created by Tloona here)

set auto_path [linsert $auto_path 0 [file join [pwd] .. .. lib] [file join [pwd] ..]]

package require tmw::toolbarframe 2.0.0

namespace eval ::Tmw {

snit::widgetadaptor browser {
    
    ### options
    
    ## \brief indicates whether sorting after a sequence should take place.
    option -dosortseq 1
    
    ## \brief The sequence after which to sort.
    option -sortsequence {}
    
    ## \brief sort alphanumeric
    option -sortalpha 1
    
    ## \brief a text format for the nodes
    option -nodeformat {"%s" -name}
    
    ## \brief indicates whether the tree view is to be syncronized with another view
    option -syncronize 1
    
    option {-filter filterCmd Command} -default ""
    
    ### Variables
    
    ## \brief a list of icons for the nodes. Contains node type and image icon
    variable NodeIcons
    array set NodeIcons {}
    
    ## \brief A list of code fragments to be executed when the selection changes
    variable SelectHandlers {}
    
    ### Components
    
    component treeview
    delegate method selection to treeview
    delegate method item to treeview
    delegate method children to treeview
    delegate method exists to treeview
    delegate method heading to treeview
    delegate method column to treeview
    
    delegate method identify to treeview
    
    delegate option -show to treeview
    delegate option -padding to treeview
    delegate option -columns to treeview
   
    component vscroll
    
    delegate method childsite to hull
    delegate method toolbar to hull
    delegate method toolbutton to hull
    delegate method dropframe to hull
    delegate option * to hull
    
    constructor {args} {
        installhull using Tmw::toolbarframe
        install treeview using ttk::treeview [$self childsite].treeview
        install vscroll using ttk::scrollbar [$self childsite].vscroll -command "$treeview yview"
        
        bind $treeview <<TreeviewOpen>> [mymethod expand 1]
        bind $treeview <<TreeviewClose>> [mymethod expand 0]
        #$T column #0 -stretch y -minwidth 250 -width 250
        #$T heading #1 -text State
        #$T configure -show headings
        
        $treeview configure -yscrollcommand "$vscroll set"
    
        grid $treeview -row 0 -column 0 -sticky news
        grid $vscroll -row 0 -column 1 -sticky nse
    
        grid columnconfigure [$self childsite] 0 -weight 1
        grid rowconfigure [$self childsite] 0 -weight 1
        
        $self configure -padding 0
        $self configurelist $args
    }
    
    method treeview {} {
        return $treeview
    }
    
    # @c add or refresh itree nodes
    method add {nodes recursive refresh args} {
        foreach {node} $nodes {
            if {[$self exists $node]} {
                if {$refresh} {
                    $self remove $node
                } else {
                    continue
                }
            }
            $self DisplayTreeNode $node $recursive {*}$args
        }
    }
    
    # @c remove itree nodes
    method remove {nodes {delete no}} {
        if {[string equal $nodes all]} {
            set nodes [$self children ""]
        }
        
        foreach itm $nodes {
            if {![$self exists $itm]} {
                continue
            }
            $treeview delete $itm
            catch {$itm configure -displayed 0}
        }
        
        if {$delete} {
            foreach {itm} $nodes {
                catch {destroy $itm}
            }
        }
    }
    
    # @c set several node icons by type
    method setNodeIcons {icons} {
        array set NodeIcons $icons
    }
    
    # @r the node icons currently set for the browser
    method getNodeIcons {} {
        return [array get NodeIcons]
    }
    
    # @c (re)sorts the browser if a sort sequence is given or
    # @c sortalpha is true
    method sort {} {
        if {$options(-sortsequence) == {} && ! $options(-sortalpha)} {
            return
        }
        set topTrees [$self children {}]
        $self remove $topTrees
        $self add $topTrees 1 0
    }
    
    # @c expands/unexpands items. As side effect, the -opencmd is
    # @c executed
    #
    # @a open: whether to expand or to close
    # @a item: the item. If it is "", the current selection is used
    method expand {open {item ""}} {
        if {$item == ""} {
            set item [$self selection]
        }
        
        if {![$self exists $item]} {
            return
        }
        
        if {$open} {
            $self item $item -open 1
            $item configure -expanded 1
        } else {
            $self item $item -open 0
            $item configure -expanded 0
        }
    }
    
    # @c Expandss all items beneath the given node in the browser 
    # @c recursively
    #
    # @a node: a tree node. If "", all items beneath the root item 
    # @a node: are expanded
    method expandAll {{node ""}} {
        $self IntExpandAll $node
        if {[set ch1 [lindex [$self children $node] 0]] != ""} {
            $self see $ch1
        }
    }
    
    # @c Collapses all items beneath the given node in the browser 
    # @c recursively
    #
    # @a node: a tree node. If "", all items beneath the root item 
    # @a node: are collapsed
    method collapseAll {{node ""}} {
        $self IntCollapseAll $node
        if {[set ch1 [lindex [$self children $node] 0]] != ""} {
            $self see $ch1
        }
    }
    
    # @c delegate to ttk::treeview
    method see {item} {
        $treeview see $item
        set parent [$item getParent]
        while {$parent != ""} {
            $parent configure -expanded 1
            set parent [$parent getParent]
        }
    }
    
    ## \brief Get the item at specified location of {} if there is none 
    method getItemForIndex {x y} {
        set itm [$self identify $x $y]
        set realItem {}
        switch -- [lindex $itm 0] {
            nothing {
                return
            }
            item {
                set realItem [lindex $itm 1]
            }
        }
        return $realItem
    }

    # @c Adds a select handler
    method addSelectHandler {code} {
        if {[lsearch $SelectHandlers $code] < 0} {
            lappend SelectHandlers $code
        }
    }
    
    ## \brief Display a tree node
    method DisplayTreeNode {node recursive args} {
        set nargs $args
        array set aargs $args
        
        if {![$self ApplyFilter $node]} {
            return
        }
        
        # handle special case of sugarized procs
        set type [$node cget -type]
        if {![info exists aargs(-image)] && [info exists NodeIcons($type)]} {
            set aargs(-image) $NodeIcons($type)
        }
        
        if {![info exists aargs(-text)]} {
            set dspFmt [$node cget -displayformat]
            if {$dspFmt == ""} {
                set dspFmt $options(-nodeformat)
            }
            
            set cmd [list format [lindex $dspFmt 0]]
            foreach {var} [lrange $dspFmt 1 end] {
                lappend cmd [$node cget $var]
            }
            set aargs(-text) [eval $cmd]
        }
        
        set args [array get aargs]
        set parentNode [$node getParent]
        if {![$treeview exists $parentNode]} {
            set parentNode ""
        }
        
        set i 0
        set j 0
        set tChilds [$self children $parentNode]
        set insPos [llength $tChilds]
        if {$options(-dosortseq)} {
            foreach {elem} $options(-sortsequence) {
                set j $i
                if {[set sib [lindex $tChilds $i]] == ""} {
                    break
                }
                while {$sib != "" && [$sib cget -type] == $elem} {
                    set sib [lindex $tChilds [incr i]]
                }
                if {$elem == [$node cget -type]} {
                    set insPos $i
                    break
                }
            }
        }
        
        if {$options(-sortalpha)} {
            # find the lexicographical correct position
            if {$i == 0} {
                set i $insPos
            }
            incr i -1
            while {$i >= $j} {
                set sib [lindex $tChilds $i]
                if {$sib == ""} {
                    break
                }
                set sibName [$sib cget -name]
                if {[string compare [$node cget -name] $sibName] >= 0} {
                    break
                }
                incr insPos -1
                incr i -1
            }
        }
    
        
        $treeview insert $parentNode $insPos -id $node
        $self item $node {*}$args
        $self item $node -open [$node cget -expanded]
        
        # insert node data into the columns if necessary
        # TODO: change -data to -coldata when tree node is transferred
        if {[set colData [$node cget -data]] != {}} {
            set colLen [llength [$treeview cget -columns]]
            if {[llength $colData] == $colLen} {
                for {set i 0} {$i < [llength $colData]} {incr i} {
                    set cdt [lindex $colData $i]
                    if {[string length $cdt] > 20} {
                        set cdt [string range $cdt 0 20]
                    }
                    $treeview set $node $i $cdt
                }
            }
        }
        
        if {$recursive} {
            foreach child [$node getChildren] {
                $self DisplayTreeNode $child $recursive {*}$nargs
            }
        }
        $node configure -displayed 1
    }
    
    ## \brief Apply a filter procedure to the items for display
    method ApplyFilter {node} {
        # if no filter command is given, the filter is always passed
        if {$options(-filter) == ""} {
            return 1
        }
        
        set res 0
        foreach {child} [$node getChildren] {
            set res [expr {$res || [$self ApplyFilter $child]}]
        }
        
        return [expr {$res || [eval $options(-filter) $node]}]
    }
    
    ## \brief recursively expand all nodes
    method IntExpandAll {node} {
        foreach {child} [$self children $node] {
            $self item $child -open 1
            $child configure -expanded 1
            $self IntExpandAll $child
        }
    }
    
    ## \brief recursively collapse all nodes
    method IntCollapseAll {node} {
        foreach {child} [$self children $node] {
            $self item $child -open 0
            $child configure -expanded 0
            $self IntCollapseAll $child
        }
    }
    
} ;# browser

namespace eval Browser {

# @c This is a default filter that matches a pattern against a node
# @c name. It uses regular expression filtering and can be used as 
# @c -filter option for the browser.
#
# @a pattern: the pattern to check
# @a node: the Itree node
#
# @r 1 for success, 0 for decline
proc regexFilter {pattern node} {
    regexp $pattern [$node cget -name]
}

# @c This is a default filter that matches a pattern against a node
# @c name. It uses glob expression filtering and can be used as 
# @c -filter option for the browser.
#
# @a pattern: the pattern to check
# @a node: the Itree node
#
# @r 1 for success, 0 for decline
proc globFilter {pattern node} {
    string match $pattern [$node cget -name]
}

# @c This is a filter that matches an exclude list to the node. If
# @c the node type is in the exclude list, the result is false, if it
# @c is not in the exclude list, the result is true. By this, it is
# @c possible to display only nodes of the type that are not to be excluded
#
# @a excludeList: a list of types that are to be excluded
# @a node: the node in question
#
# @r 1 for success, 0 for decline
proc typeExcludeFilter {excludeList node} {
    expr {[lsearch $excludeList [$node cget -type]] < 0}
}

# @c This filter procedure matches an exclude list of types and a glob
# @c pattern on -name
#
# @a excludeList: a list of types that are to be excluded
# @a pattern: the pattern to check against -name
# @a node: the node in question
# 
# @r 1 for success, 0 for decline
proc typeExcludeGlobFilter {excludeList pattern node} {
    expr {[typeExcludeFilter $excludeList $node] && [globFilter $pattern $node]}
}
    
} ;# namespace Browser


} ;# namespace Tmw

package provide tmw::browser 2.0.0

### test code
package re Tk
Tmw::browser .b
pack .b -expand y -fill both
