#
# codebrowser.itk
#
package require tmw::filebrowser 1.0
package require tmw::icons 1.0

package provide tloona::codebrowser 1.0

usual CodeBrowser {}
usual CodeOutline {}

# @c This class implements the code browser for Tloona. The codebrowser
# @c is the central point where the code structure of several scripts
# @c is displayed. Each script has a tree of tokens for procedures,
# @c classes, variables and such. At the top is a toolbar displayed, that
# @c contains two buttons for sorting alphanumerical and according to a
# @c sort sequence (first namespaces, then classes, then procedures etc.)
# @c The sort sequence can be configured via a dropwidget that contains
# @c a list of tokens and buttons to change the sequence
class ::Tloona::CodeBrowser {
    inherit Tmw::FileBrowser
    
    # @v sortsequence: overloads the sortsequence parameter
    public variable sortsequence {} {
        if {$sortsequence != {}} {
            setSortValues
        }
    }
    
    public variable sortalpha 1
    
    # @v getfilefromitemcmd: A piece of code to execute to get the file object
    # @v getfilefromitemcmd: for the currently selected code definition
    public variable getfilefromitemcmd {}
    
    # @v ShowingNodes: Array with indicators for Code treenodes to show
    protected variable ShowingNodes
    array set ShowingNodes {}
        
    # @v Filter: variable for filter pattern and widgets
    protected variable Filter
    array set Filter {}
    set Filter(pattern) ""
    set Filter(widgets) {}
    
    # @v CodeTrees: list of all code trees. Used for filtering, so
    # @v CodeTrees: that no code tree gets lost
    protected variable CodeTrees {}
        
    # @v SendCmds: list of commands that are executed to send a code
    # @v SendCmds: definition to one or more foreign interpreters
    protected variable SendCmds {}

    constructor {args} {
        createToolbar
        eval itk_initialize $args
    }
            
    # @c callback for filtering code items. What determines, after
    # @c what to filter.
    #
    # @a what: name for simple filter name pattern. type considers
    # @a what: the ShowingNodes array and shows all types that have 1 there
    public method onFilter {} {
        set CodeTrees [concat $CodeTrees [children {}]]
        
        if {[getExcludeTypes] != {} && $Filter(pattern) != ""} {
            configure -filter [list ::Tmw::Browser::typeExcludeGlobFilter \
                [getExcludeTypes] $Filter(pattern)]
        } elseif {$Filter(pattern) != ""} {
            configure -filter \
                [list ::Tmw::Browser::globFilter $Filter(pattern)]
        } elseif {[getExcludeTypes] != {}} {
            configure -filter \
                [list ::Tmw::Browser::typeExcludeFilter [getExcludeTypes]]
        } else {
            configure -filter ""
        }
                
        remove [children {}]
        add $CodeTrees 1 0
    
    }
    
    # @c Add a command to the list of commands that are used to send
    # @c scripts to foreign interpreters
    public method addSendCmd {cmd} {
        if {[lsearch $SendCmds $cmd] < 0} {
            lappend SendCmds $cmd
        }
    }
    
    # @c Sends a code definition per comm to another interpreter
    # @c This can serve as a callback for a menu entry
    #
    # @a node: the node for which the definition is to send
    # @a type: The sending type, either comm or backend (maybe more somewhen)
    # @a id: The id where to send. For comm, this is the comm id, for
    # @a id: backend, this is the file handle ... If empty, a dialog is
    # @a id: displayed to gather the id
    public method sendDefinition {node type id} {
        if {$node == ""} {
            set node [selection]
        }
        
        switch -- $type {
        comm {
            sendCommDefinition $node $id
        }
        console {
            if {$getfilefromitemcmd == {}} {
                set script [::Tloona::getNodeDefinition $node]
            } else {
                set script [::Tloona::getNodeDefinition $node \
                    [eval $getfilefromitemcmd $node]]
            }
            foreach {cmd} $SendCmds {
                $cmd $script
            }
        }
        }
    }
    
    # @c fills the local toolbar
    protected method createToolbar {} {
        global Icons
        
        # create a toolbar with codebrowser specific actions
        set toolBar [toolbar tools -pos n -compound none]
        toolbutton sortalpha -toolbar tools -image $Tmw::Icons(SortAlpha) \
            -type checkbutton -variable [scope sortalpha] -separate 0 \
            -command [code $this sort]
        toolbutton sortseq -toolbar tools -image $Icons(SortSeq) \
            -type checkbutton -variable [scope dosortseq] -separate 0 \
            -command [code $this sort]
        set f [dropframe sortseqcfg -toolbar tools -image $Icons(SortSeqCfg) \
            -separate 0 -hidecmd [code $this updateSortSeq] -relpos 0]
        createSortList $f
        set f [dropframe showcfg -toolbar tools -image $Tmw::Icons(ActWatch) \
            -separate 1  -hidecmd [code $this onFilter] -relpos 0]
        createShowButtons $f
    
        set Filter(pattern) ""
        ttk::entry $toolBar.efilter -textvariable [scope Filter(pattern)] -width 15
        set Filter(widgets) $toolBar.efilter
        toolbutton filter -toolbar tools -image $Tmw::Icons(ActFilter) \
            -type command -separate 0 -command [code $this onFilter] \
            -stickto back
        pack $toolBar.efilter -expand n -fill none -side right -padx 2 -pady 1
        bind $toolBar.efilter <Return> [code $this onFilter]
        
        # the filter-by-type variables
        set ShowingNodes(package) 1
        set ShowingNodes(variable) 1
        set ShowingNodes(proc) 1
        set ShowingNodes(itk_components) 1
        set ShowingNodes(const_dest) 1
        set ShowingNodes(public) 1
        set ShowingNodes(protected) 1
        set ShowingNodes(private) 1
    }
        
    # @c creates the listbox and associated widgets for the sort
    # @c sequence configuration and fills the listbox
    #
    # @a parent: the parent frame. A dropframe, created by toolbar
    protected method createSortList {parent} {
        itk_component add sortlist {
            listbox $parent.sortlist -height 18 -width 16 -background white \
                -borderwidth 1 -relief flat
        }
        
        set bup [ttk::button $parent.up -image $Tmw::Icons(NavUp) -style Toolbutton \
            -command [code $this moveSortConfig up]]
        set bdown [ttk::button $parent.down -image $Tmw::Icons(NavDown) \
            -style Toolbutton -command [code $this moveSortConfig down]]
        
        grid [component sortlist] -row 0 -column 0 -rowspan 2 -sticky news
        grid $bup -row 0 -column 1 -sticky swe -padx 1
        grid $bdown -row 1 -column 1 -sticky nwe -padx 1
    }
        
    # @c set the sortlist values to the listbox
    protected method setSortValues {} {
        set sseq [cget -sortsequence]
        if {$sseq == {}} {
            set sseq {package \
                macro \
                variable \
                class \
                itk_components \
                public_component \
                private_component \
                constructor \
                destructor \
                public_variable \
                protected_variable \
                private_variable \
                public_method \
                xo_instproc \
                protected_method \
                private_method \
                proc \
                xo_proc \
                namespace
            }
        }
        
        component sortlist delete 0 end
        component sortlist configure -height [llength $sseq]
        foreach {c} $sseq {
            component sortlist insert end $c
        }
    }
        
    # @c creates checkbuttons in a parent frame that trigger filter
    # @c expressions for showing and hiding particular code tree types
    #
    # @a parent: the parent frame
    protected method createShowButtons {parent} {
        global Icons
        
        ttk::checkbutton $parent.package -variable [scope ShowingNodes(package)] \
            -text "package imports" -image $Icons(TclPkg) -compound left
        ttk::checkbutton $parent.variable -variable [scope ShowingNodes(variable)] \
            -text "variables" -image $Icons(TclVar) -compound left
        ttk::checkbutton $parent.proc -variable [scope ShowingNodes(proc)] \
            -text "procedures" -image $Icons(TclProc) -compound left
        ttk::checkbutton $parent.itk_components -variable [scope ShowingNodes(itk_components)] \
            -text "Itk Components" -image $Icons(ItkComponents) -compound left
        ttk::checkbutton $parent.const_dest -variable [scope ShowingNodes(const_dest)] \
            -text "constructors/destructors" -image $Icons(TclConstructor) -compound left
        ttk::checkbutton $parent.public -variable [scope ShowingNodes(public)] \
            -text "public members" -image $Icons(TclPublic) -compound left
        ttk::checkbutton $parent.protected -variable [scope ShowingNodes(protected)] \
            -text "protected members" -image $Icons(TclProtected) -compound left
        ttk::checkbutton $parent.private -variable [scope ShowingNodes(private)] \
            -text "private members" -image $Icons(TclPrivate) -compound left
        
        pack $parent.package $parent.variable $parent.proc $parent.itk_components \
            $parent.const_dest $parent.public $parent.protected $parent.private \
            -side top -expand n -fill none -padx 2 -pady 0 -anchor w
    }
        
    # @c moves the selected item in the sort config listbox up or down
    # 
    # @a updown: up or down
    protected method moveSortConfig {where} {
        set L [component sortlist]
        set actIdx [$L index active]
        set sel [$L get active]
        
        switch -- $where {
            "up" {
                incr actIdx -1
                if {$actIdx == -1} {
                    return
                }
            }
            "down" {
                incr actIdx
                if {$actIdx == [llength [$L get 0 end]]} {
                    return
                }
            }
        }
        
        $L delete active
        $L insert $actIdx $sel
        $L activate $actIdx
        $L selection set $actIdx
        
    }
        
    # @c updates the sort sequence from sort listbox and triggers
    # @c resorting
    protected method updateSortSeq {} {
        configure -sortsequence [component sortlist get 0 end] \
            -sortalpha $sortalpha
        sort
        event generate [namespace tail $this] <<SortSeqChanged>>
    }
        
    # @r a list of exclude types, based on the values in ShowingNodes array
    protected method getExcludeTypes {} {
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
    
    # @c Sends the definition of a node via comm to an interpreter
    private method sendCommDefinition {node id} {
        set mw [cget -mainwindow]
        if {![$mw isa ::Tloona::Mainapp]} {
            return
        }
        
        set msg "This Comm ID does not exist"
        if {$id == ""} {
            while {1} {
                set id [Tmw::input [cget -mainwindow] "Comm ID:" okcancel]
                if {$id == ""} {
                    return
                }
                if {[$mw addCommID $id]} {
                    break
                }
                set rr [Tmw::message $mw "Wrong Comm Id" okcancel $msg]
                if {$rr == "cancel"} {
                    return
                }
            }
        }
        
        if {$getfilefromitemcmd == {}} {
            set script [::Tloona::getNodeDefinition $node]
        } else {
            set script [::Tloona::getNodeDefinition $node \
                [eval $getfilefromitemcmd $node]]
        }
        
        #puts $script
        if {[catch {comm::comm send $id $script} m]} {
            Tmw::message $mw "Error from $id" ok \
                "The application at $id raised an error: $m"
        }
    }
}

proc ::Tloona::codebrowser {path args} {
    uplevel ::Tloona::CodeBrowser $path $args
}

# @c Represents an outline of code. This is different in respect to that
# @c not files or complete Code trees are displayed, but the children of
# @c code trees in one window. Since these children are the same children
# @c as for other browsers (or might be the same), it needs special 
# @c implementations of several methods
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
    
    # @c Overrides remove in browser. Removes children of trees
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
        
    # @c Overrides add in browser
    public method add {nodes recursive refresh args} {
        set nnodes {}
        foreach {node} $nodes {
            set nnodes [concat $nnodes [$node getChildren]]
        }
        eval chain [list $nnodes] $recursive $refresh $args
    }
    
    # @c Overrides createToolbar in Codebrowser. Adds an collapse button
    protected method createToolbar {} {
        global Icons
        
        chain
        toolbutton collapse -toolbar tools -image $Icons(Collapse) \
            -type command -separate 0 -command [code $this collapseAll]
    }
    
    # @c Creates a contextmenu and displays it
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

# @c Gets the node definition of a proc or class item and constructs
# @c a script to be send to other interpreters
#
# @a node: the node, a parser object
# @r the script to be sent
proc ::Tloona::getNodeDefinition {node {file {}}} {
    if {$node == {}} {
        return
    }
    
    set script ""
    switch -glob -- [$node cget -type] {
        *method {
            append script "body "
        }
        
        macro {
            append script "::sugar::macro "
        }
        
        proc {
            append script "::sugar::proc "
        }
        
        variable -
        namespace -
        webcmd -
        xo_* -
        class {
            # this can be done directly from the file definition
            # Get the definition of this node in the file and return
            #append script "proc "
            if {[$node isa ::Parser::XotclAttributeNode]} {
                # If this is an attribute of XOTcl class, we will likely
                # want to send the class definition itself, since Attributes
                # can not be sent
                set node [$node getParent]
                
            }
            if {$file == {}} {
                return
            }
            return [$file flashCode $node]
        }
        default {
            # not implemented
            return
        }
    }
    
    # flash the code for consistency
    if {$file != {}} {
        $file flashCode $node
    }
    
    # get fully qualified name
    set name [$node cget -name]
    set parent [$node getParent]
    while {$parent != "" && [$parent isa ::Parser::StructuredFile]} {
        set name [$parent cget -name]::[set name]
        set parent [$parent getParent]
    }
    
    append script "$name [list [$node cget -arglist]] {"
    append script [string trim [$node cget -definition] "{}"]
    append script "}"
    return $script
}

proc ::Tloona::codeoutline {path args} {
    uplevel ::Tloona::CodeOutline $path $args
}
