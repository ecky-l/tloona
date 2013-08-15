
package require tloona::codebrowser 1.0

package provide tloona::projectoutline 1.0

namespace eval ::Tloona {}

usual CodeOutline {}
usual ProjectOutline {}

## \brief Represents an outline of code. 
# 
# This is different in respect to that not files or complete Code trees are displayed, 
# but the children of code trees in one window. Since these children are the same children
# as for other browsers (or might be the same), it needs special implementations of several 
# methods
class ::Tloona::CodeOutline {
    inherit ::Tloona::CodeBrowser
    
    constructor {args} {
        eval itk_initialize $args
        if {[tk windowingsystem] eq "aqua"} {
            # On Mac the right mouse button is Button-2
            bind [component treeview] <Button-2> [code $this contextMenu %X %Y %x %y]
        } else {
            bind [component treeview] <Button-3> [code $this contextMenu %X %Y %x %y]
        }
    }
    
    ## \brief Overrides remove in browser. Removes children of trees
    public method remove {nodes {delete no}} {
        if {[string equal $nodes all]} {
            chain all
            return
        }
        
        set nnodes {}
        foreach {node} $nodes {
            set nnodes [concat $nnodes [$node getChildren]]
        }
        chain $nnodes
    }
        
    ## \brief Overrides add in browser
    public method add {nodes recursive refresh args} {
        set nnodes {}
        foreach {node} $nodes {
            set nnodes [concat $nnodes [$node getChildren]]
        }
        eval chain [list $nnodes] $recursive $refresh $args
    }
    
    ## \brief Overrides createToolbar in Codebrowser. Adds an collapse button
    protected method createToolbar {} {
        global Icons
        
        chain
        toolbutton collapse -toolbar tools -image $Icons(Collapse) \
            -type command -separate 0 -command [code $this collapseAll]
    }
    
    ## \brief Creates a contextmenu and displays it
    protected method contextMenu {xr yr x y} {
        set itm [component treeview identify $x $y]
        set realItem ""
        switch -- [lindex $itm 0] {
            "nothing" {
                return
            }
            "item" {
                set realItem [lindex $itm 1]
            }
        }
        
        if {$realItem == ""} {
            return
        }
        
        Tmw::Browser::selection set $realItem
        # create context menu
        if {[winfo exists .outlinecmenu]} {
            destroy .outlinecmenu
        }
        menu .outlinecmenu -tearoff no
        menu .outlinecmenu.commm -tearoff no
        .outlinecmenu add cascade -label "Send to Comm" -menu .outlinecmenu.commm
        if {[set mw [cget -mainwindow]] != "" &&
                [$mw isa ::Tloona::Mainapp] && 
                [$mw getCommIDs] != {}} {
                
            foreach {cid} [$mw getCommIDs] {
                .outlinecmenu.commm add command -label "Comm $cid" \
                    -command [code $this sendDefinition $realItem comm $cid]
            }
            .outlinecmenu.commm add separator
        }
        .outlinecmenu.commm add command -label "New Comm ID" \
            -command [code $this sendDefinition $realItem comm ""]
        
        tk_popup .outlinecmenu $xr $yr
    }
    
}

proc ::Tloona::codeoutline {path args} {
    uplevel ::Tloona::CodeOutline $path $args
}

## \brief A project viewer
#
# This is intented to be a browser that displays all namespaces, classes, procs
# etc. in a particular project in that hierarchy. Files are not displayed.
class ::Tloona::ProjectOutline {
    inherit CodeBrowser
    
    constructor {args} {chain {*}$args} {
    }
}

proc ::Tloona::projectoutline {path args} {
    uplevel ::Tloona::ProjectOutline $path $args
}
