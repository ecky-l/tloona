## projectoutline.tcl (created by Tloona here)
package require snit 2.3.2
package require tloona::codebrowser 2.0.0

namespace eval Tloona {

## \brief Represents an outline of code. 
# 
# This is different in respect to that not files or complete Code trees are displayed, 
# but the children of code trees in one window. Since these children are the same children
# as for other browsers (or might be the same), it needs special implementations of several 
# methods
snit::widgetadaptor codeoutline {
    
    ### Options
    
    ### Components
    delegate method * to hull except {add remove createToolbar}
    delegate option * to hull
    
    ### Variables
    
    ## \brief List of code items (procs, classes etc.) shown in the browser
    variable CodeTrees {}
    
    ## \brief Array with indicators for Code treenodes to show
    variable ShowingNodes
    array set ShowingNodes {}
    
    ## \brief variable for filter pattern and widgets
    variable Filter
    array set Filter {}
    set Filter(pattern) ""
    set Filter(widgets) {}
    
    constructor {args} {
        installhull using Tloona::codebrowser
        $self createToolbar
        $self configure -filtercmd [mymethod filterCmd]
        
        set T [$self treeview]
        if {[tk windowingsystem] eq "aqua"} {
            # On Mac the right mouse button is Button-2
            bind $T <Button-2> [mymethod ContextMenu %X %Y %x %y]
        } else {
            bind $T <Button-3> [mymethod ContextMenu %X %Y %x %y]
        }
        $self configurelist $args
    }
    
    ## \brief Overrides remove in browser. Removes children of trees
    method remove {nodes {delete no}} {
        if {[string equal $nodes all]} {
            $hull remove all
            return
        }
        
        set nnodes {}
        foreach {node} $nodes {
            set nnodes [concat $nnodes [$node getChildren]]
        }
        $hull remove $nnodes
    }
        
    ## \brief Overrides add in browser
    method add {nodes recursive refresh args} {
        set nnodes {}
        foreach {node} $nodes {
            set nnodes [concat $nnodes [$node getChildren]]
        }
        $hull add $nnodes $recursive $refresh {*}$args
    }
    
    ## \brief callback for filtering code items. 
    method filterCmd {pattern} {
        set exCludes [$self GetExcludeTypes]
        set f ""
        if {$pattern != {} && $exCludes != {}} {
            set f [list ::Tmw::Browser::typeExcludeGlobFilter $exCludes $pattern]
        } elseif {$pattern != {}} {
            set f [list ::Tmw::Browser::globFilter $pattern]
        } elseif {$exCludes != {}} {
            set f [list ::Tmw::Browser::typeExcludeFilter $exCludes]
        }
        $self configure -filter $f
        
        set CodeTrees [lsort -unique [concat $CodeTrees [$self children {}]]]
        $self remove [$self children {}]
        $self add $CodeTrees 1 0
    }
    
    ## \brief Overrides createToolbar in Codebrowser. Adds an collapse button
    method createToolbar {} {
        global Icons
        set f [$self dropframe showcfg -toolbar tools -image $Tmw::Icons(ActWatch) \
            -tip "Show Config" -separate 1  -hidecmd [mymethod onFilter] -relpos 0]
        $self CreateShowButtons $f
        
        # the filter-by-type variables
        set ShowingNodes(package) 1
        set ShowingNodes(variable) 1
        set ShowingNodes(proc) 1
        set ShowingNodes(itk_components) 1
        set ShowingNodes(const_dest) 1
        set ShowingNodes(public) 1
        set ShowingNodes(protected) 1
        set ShowingNodes(private) 1
        
        $self toolbutton collapse -toolbar tools -image $Icons(Collapse) \
            -tip "Collapse" -type command -separate 0 -command [mymethod collapseAll]
    }
    
    ## \brief Creates a contextmenu and displays it
    method ContextMenu {xr yr x y} {
        global TloonaApplication
        
        set itm [$self identify $x $y]
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
        
        $self selection set $realItem
        # create context menu
        if {[winfo exists .outlinecmenu]} {
            destroy .outlinecmenu
        }
        menu .outlinecmenu -tearoff no
        menu .outlinecmenu.commm -tearoff no
        
        .outlinecmenu add command -label "Send to Console" -command \
                [mymethod sendDefinition $realItem console ""]
         
        .outlinecmenu add cascade -label "Send to Comm" -menu .outlinecmenu.commm
        set mw $TloonaApplication
        if {$mw != "" && [$mw getCommIDs] != {}} {
            foreach {cid} [$mw getCommIDs] {
                .outlinecmenu.commm add command -label "Comm $cid" \
                    -command [mymethod sendDefinition $realItem comm $cid]
            }
            .outlinecmenu.commm add separator
        }
        .outlinecmenu.commm add command -label "New Comm ID" \
            -command [mymethod sendDefinition $realItem comm ""]
        
        tk_popup .outlinecmenu $xr $yr
    }

    # @c creates checkbuttons in a parent frame that trigger filter
    # @c expressions for showing and hiding particular code tree types
    #
    # @a parent: the parent frame
    method CreateShowButtons {parent} {
        global Icons
        
        ttk::checkbutton $parent.package -variable [myvar ShowingNodes(package)] \
            -text "package imports" -image $Icons(TclPkg) -compound left
        ttk::checkbutton $parent.variable -variable [myvar ShowingNodes(variable)] \
            -text "variables" -image $Icons(TclVar) -compound left
        ttk::checkbutton $parent.proc -variable [myvar ShowingNodes(proc)] \
            -text "procedures" -image $Icons(TclProc) -compound left
        ttk::checkbutton $parent.itk_components -variable [myvar ShowingNodes(itk_components)] \
            -text "Itk Components" -image $Icons(ItkComponents) -compound left
        ttk::checkbutton $parent.const_dest -variable [myvar ShowingNodes(const_dest)] \
            -text "constructors/destructors" -image $Icons(TclConstructor) -compound left
        ttk::checkbutton $parent.public -variable [myvar ShowingNodes(public)] \
            -text "public members" -image $Icons(TclPublic) -compound left
        ttk::checkbutton $parent.protected -variable [myvar ShowingNodes(protected)] \
            -text "protected members" -image $Icons(TclProtected) -compound left
        ttk::checkbutton $parent.private -variable [myvar ShowingNodes(private)] \
            -text "private members" -image $Icons(TclPrivate) -compound left
        
        pack $parent.package $parent.variable $parent.proc $parent.itk_components \
            $parent.const_dest $parent.public $parent.protected $parent.private \
            -side top -expand n -fill none -padx 2 -pady 0 -anchor w
    }
    
    # @r a list of exclude types, based on the values in ShowingNodes array
    method GetExcludeTypes {} {
        set excludes {}
        foreach {v} {package variable proc} {
            if {! $ShowingNodes($v)} {
                lappend excludes $v
            }
        }
        foreach {v} {public protected private} {
            if {! $ShowingNodes($v)} {
                lappend excludes [set v]_method [set v]_variable
            }
        }
        if {!$ShowingNodes(public) && !$ShowingNodes(protected) \
                && !$ShowingNodes(private)} {
            lappend excludes class
        }
        if {! $ShowingNodes(const_dest)} {
            lappend excludes constructor destructor
        }
        if {! $ShowingNodes(itk_components)} {
            lappend excludes itk_components public_component private_component
        }
        
        return $excludes
    }
    
} ;# codeoutline

} ;# namespace Tloona

package provide tloona::projectoutline 2.0.0
