## codebrowser.tcl (created by Tloona here)
package require snit 2.3.2
package require tmw::filebrowser 2.0.0

namespace eval Tloona {

##\brief The code browser for Tloona. 
# The central point where the code structure of several scripts is displayed. Each 
# script has a tree of tokens for procedures, classes, variables and such. At the 
# top is a toolbar displayed, that contains two buttons for sorting alphanumerical 
# and according to a sort sequence (first namespaces, then classes, then procedures 
# etc.) The sort sequence can be configured via a dropwidget that contains a list 
# of tokens and buttons to change the sequence
snit::widgetadaptor codebrowser {
    
    #### Options
    option -sortsequence -default {} -configuremethod ConfigSortSequence -cgetmethod CgetHullOption
    option -sortalpha -default 1 -configuremethod ConfigHullOption -cgetmethod CgetHullOption
    option -dosortseq -default 1 -configuremethod ConfigHullOption -cgetmethod CgetHullOption
    option -getfilefromitemcmd {}
    option -filtercmd {}
    
    #### Components
    component sortlist
    
    delegate method * to hull
    delegate option * to hull except { -sortsequence -sortalpha }
    
    #### Variables
    
    ## \brief list of all code trees. Used for filtering, so that no code tree 
    # gets lost
    variable CodeTrees {}
    
    ## \brief list of commands that are executed to send a code definition to 
    # one or more foreign interpreters
    variable SendCmds {}

    ## \brief variable for filter pattern and widgets
    variable Filter
    array set Filter {}
    set Filter(pattern) ""
    set Filter(widgets) {}
    
    constructor {args} {
        installhull using Tmw::filebrowser
        $self createToolbar
        $self configurelist $args
    }
    
    ## \brief Callback for sort. Configures the options first, then sorts
    method onSort {} {
        $hull configure -sortsequence $options(-sortsequence) \
            -sortalpha $options(-sortalpha) -dosortseq $options(-dosortseq)
        $self sort
    }
    
    method onFilter {} {
        if {$options(-filtercmd) != {}} {
            uplevel #0 $options(-filtercmd) [list $Filter(pattern)]
        }
    }
    
    # @c fills the local toolbar
    method createToolbar {} {
        global Icons
        
        # create a toolbar with codebrowser specific actions
        set toolBar [$self toolbar tools -pos n -compound none]
        $self toolbutton sortalpha -toolbar tools -image $Tmw::Icons(SortAlpha) \
            -type checkbutton -variable [myvar options(-sortalpha)] -separate 0 \
            -command [mymethod onSort]
        $self toolbutton sortseq -toolbar tools -image $Icons(SortSeq) \
            -type checkbutton -variable [myvar options(-dosortseq)] -separate 0 \
            -command [mymethod onSort]
        set f [$self dropframe sortseqcfg -toolbar tools -image $Icons(SortSeqCfg) \
            -separate 0 -hidecmd [mymethod UpdateSortSeq] -relpos 0]
        
        $self CreateSortList $f
        
        #$self toolbutton syncronize -toolbar tools -image $Icons(Syncronize) \
        #    -type checkbutton -variable [myvar Syncronize] -separate 0 \
        #    -command [mymethod onSyncronize]
        #$self toolbutton collapse -toolbar tools -image $Icons(Collapse) \
        #    -type command -separate 0 -command [mymethod collapseAll]
            
        set Filter(pattern) ""
        ttk::entry $toolBar.efilter -textvariable [myvar Filter(pattern)] -width 15
        set Filter(widgets) $toolBar.efilter
        $self toolbutton filter -toolbar tools -image $Tmw::Icons(ActFilter) \
            -type command -separate 0 -command [mymethod onFilter] -stickto back
        pack $toolBar.efilter -expand n -fill none -side right -padx 2 -pady 1
        bind $toolBar.efilter <Return> [mymethod onFilter]
    }
    
    # @c Add a command to the list of commands that are used to send
    # @c scripts to foreign interpreters
    method addSendCmd {cmd} {
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
    method sendDefinition {node typ id} {
        if {$node == ""} {
            set node [$self selection]
        }
        
        switch -- $typ {
        comm {
            $self SendCommDefinition $node $id
        }
        console {
            if {$options(-getfilefromitemcmd) == {}} {
                set script [::Tloona::getNodeDefinition $node]
            } else {
                set script [::Tloona::getNodeDefinition $node \
                    [uplevel #0 $options(-getfilefromitemcmd) $node]]
            }
            foreach {cmd} $SendCmds {
                uplevel #0 $cmd [list $script]
            }
        }
        }
    }
    
    # @c creates the listbox and associated widgets for the sort
    # @c sequence configuration and fills the listbox
    #
    # @a parent: the parent frame. A dropframe, created by toolbar
    method CreateSortList {parent} {
        install sortlist using listbox $parent.sortlist -height 18 -width 16 \
            -background white -borderwidth 1 -relief flat
        
        set bup [ttk::button $parent.up -image $Tmw::Icons(NavUp) -style Toolbutton \
            -command [mymethod MoveSortConfig up]]
        set bdown [ttk::button $parent.down -image $Tmw::Icons(NavDown) \
            -style Toolbutton -command [mymethod MoveSortConfig down]]
        
        grid $sortlist -row 0 -column 0 -rowspan 2 -sticky news
        grid $bup -row 0 -column 1 -sticky swe -padx 1
        grid $bdown -row 1 -column 1 -sticky nwe -padx 1
    }
    
    # @c moves the selected item in the sort config listbox up or down
    # 
    # @a updown: up or down
    method MoveSortConfig {where} {
        set actIdx [$sortlist index active]
        set sel [$sortlist get active]
        
        switch -- $where {
        "up" {
            incr actIdx -1
            if {$actIdx == -1} {
                return
            }
        }
        "down" {
            incr actIdx
            if {$actIdx == [llength [$sortlist get 0 end]]} {
                return
            }
        }
        }
        
        $sortlist delete active
        $sortlist insert $actIdx $sel
        $sortlist activate $actIdx
        $sortlist selection set $actIdx
    }
        
    # @c updates the sort sequence from sort listbox and triggers
    # @c resorting
    method UpdateSortSeq {} {
        $self configure -sortsequence [$sortlist get 0 end] -sortalpha $options(-sortalpha) 
        $self sort
        event generate $win <<SortSeqChanged>>
    }
    
    # @c Sends the definition of a node via comm to an interpreter
    method SendCommDefinition {node id} {
        set mw [$self cget -mainwindow]
        
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
                [uplevel #0 $getfilefromitemcmd $node]]
        }
        
        #puts $script
        if {[catch {comm::comm send $id $script} m]} {
            Tmw::message $mw "Error from $id" ok \
                "The application at $id raised an error: $m"
        }
    }
    
    ## \brief config method for the sort sequence
    method ConfigSortSequence {option value} {
        set options($option) $value
        $hull configure -sortsequence $value
        #set options($option) $value
        if {$value == {}} {
            set value {package \
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
        
        $sortlist delete 0 end
        $sortlist configure -height [llength $value]
        foreach {c} $value {
            $sortlist insert end $c
        }
    }
    
    method ConfigHullOption {option value} {
        set options($option) $value
        $hull configure -sortalpha $value
    }
    
    method CgetHullOption {option} {
        $hull cget $option
    }
    
} ;# codebrowser

## \brief A basic project browser.
#
# This is the base class for kit browser and project outline
snit::widgetadaptor projectbrowser {
    
    #### Options
    
    ## \brief a piece of code that is executed to open files
    option {-newfilecmd newFileCmd Command} -default ""
    ## \brief a piece of code that is executed to open files
    option {-openfilecmd openFileCmd Command} -default ""
    ## \brief a piece of code that is executed to close files
    option {-closefilecmd closeFileCmd Command} -default ""
    ## \brief a piece of code to determine whether a file is open
    option {-isopencmd isOpenCmd Command} -default ""
    ## \brief a command that is executed when a code fragment is selected
    option {-selectcodecmd selectCodeCmd Command} -default ""
    
    ### Components
    
    delegate method * to hull except {onFilter createToolbar}
    delegate option * to hull
    
    #### Variables
    
    ## \brief A list of File systems
    variable Starkits {}
    ## \brief A scope variable for the checkbutton to synchronize with editor
    variable Syncronize 1
    
    constructor {args} {
        installhull using codebrowser
        $self createToolbar
        $self configure -filtercmd [mymethod onFilter]
        $self configurelist $args
    }
    
    ## \brief selects the code definition of Itcl methods. 
    # 
    # Essentially, dispatches to the -selectcodecmd option.
    method selectCode {x y def} {
        if {$options(-selectcodecmd) == ""} {
            return
        }
        uplevel #0 $options(-selectcodecmd) $self $x $y $def
    }
    
    # @c Callback for collapse the tree view
    method onSyncronize {} {
        $self configure -syncronize $Syncronize
    }
    
    method onFilter {pattern} {
        $self configure -filter [expr { 
            ($pattern == {}) ? "" : [list ::Tmw::Browser::globFilter $pattern]
        }]
        $self remove [$self children {}]
        $self add $Starkits 1 1
    }
    
    ## \brief Overrides remove in Tmw::Browser1.
    # 
    # Closes files that are still open
    method removeProjects {nodes} {
        foreach {node} $nodes {
            if {[$node getParent] != ""} {
                continue
            }
            foreach {file} [$node getChildren yes] {
                set fName ""
                if {[$file isa ::Tmw::Fs::File]} {
                    set fName [$file cget -name]
                } elseif {[$file isa ::Parser::Script]} {
                    set fName [$file cget -filename]
                } else {
                    continue
                }
                set fCls [apply $options(-isopencmd) $fName]
                if {$fCls == ""} {
                    continue
                }
                
                uplevel #0 $options(-closefilecmd) $fCls
            }
        }
        
        $self remove $nodes yes
    }

    # @c Overrides createToolbar in Codebrowser. Adds other widgets and
    # @c aligns them different
    method createToolbar {} {
        global Icons
        $self toolbutton syncronize -toolbar tools -image $Icons(Syncronize) \
            -type checkbutton -variable [myvar Syncronize] -separate 0 \
            -command [mymethod onSyncronize]
        $self toolbutton collapse -toolbar tools -image $Icons(Collapse) \
            -type command -separate 0 -command [mymethod collapseAll]
    }
    
    method addStarkit {starKit} {
        lappend Starkits $starKit
    }
    
    method getStarkits {} {
        return $Starkits
    }
    
    # @c checks whether a file is open already. The method
    # @c invokes the -isopencmd code. If no -isopencmd is
    # @c given, the check can not be performed
    #
    # @a file: the file in the file system to check for
    method isOpen {{file ""}} {
        if {$options(-isopencmd) == ""} {
            return
        }
        if {$file == ""} {
            set file [$self selection]
        }
        
        set fname ""
        if {[$file isa ::Tmw::Fs::FSContent]} {
            set fname [$file cget -name]
        } elseif {[$file isa ::Parser::Script]} {
            set fname [$file cget -filename]
        }
        
        expr {$fname != "" && [apply $options(-isopencmd) $fname] != {}}
    }
    
    
}


### useful procs

proc ::Tloona::getNSQ {node} {
    # get fully qualified name
    set name [$node cget -name]
    set parent [$node getParent]
    while {$parent != "" && [$parent isa ::Parser::StructuredFile]} {
        if {[$parent cget -type] ne "script"} {
            set name [$parent cget -name]::[set name]
        }
        set parent [$parent getParent]
    }
    set name ::[string trim $name :]
}

## \brief Gets the node definition of a proc or class item.
#
# constructs a script to be send to other interpreters
#
# \param node
#    the node, a parser object
#
# \return the script to be sent
proc ::Tloona::getNodeDefinition {node {file {}}} {
    if {$node == {}} {
        return
    }
    set script ""
    set tokenType [$node cget -type]
    switch -glob -- $tokenType {
        
    *method - constructor - destructor {
        set clNode [$node getParent]
        
        set tktyp method
        set tknam [$node cget -name]
        set tkargs [list [$node cget -arglist]]
        append tkdef \{ [string trim [$node cget -definition] "{}"] \}
        
        switch -glob -- $tokenType {
        *method {
        }
        constructor {
            set tktyp constructor
            set tknam ""
        }
        destructor {
            set tktyp destructor
            set tknam ""
            set tkargs "{ }"
        }
        }
        
        switch -glob -- [$clNode info class] {
        *SnitTypeNode - *SnitWidgetNode {
            # obviously a snit type. handle appropriately. Need to redefine constructor/destructor
            switch -- $tokenType {
            constructor {
                set tktyp method
                set tknam $tokenType
            }
            destructor {
                set tktyp method
                set tknam $tokenType
                set tkargs "{ }"
            }
            }
            append script ::snit::[set tktyp] " [getNSQ $clNode] $tknam $tkargs $tkdef"  
        }
        *TclOOClassNode {
            set tktyp [$node cget -token]
            set scopedCmd [expr {
                ([$node cget -scope] eq "objdefine") ? "::oo::objdefine" : "::oo::define"
            }]
            append script $scopedCmd " [getNSQ $clNode] $tktyp $tknam $tkargs $tkdef"
        }
        *ItclClassNode {
            append script "::itcl::body "
            append script [getNSQ $node] " $tkargs $tkdef"
        }
        }
    }
    
    
    macro {
        append script "::sugar::macro [$node cget -name] [list [$node cget -arglist]] {"
        append script [string trim [$node cget -definition] "{}"]
        append script "}"
    }
    
    proc {
        append script [expr {[$node cget -sugarized] ? "::sugar::proc " : "proc "}]
        append script [getNSQ $node] " [list [$node cget -arglist]] {"
        append script [string trim [$node cget -definition] "{}"]
        append script "}"
    }
    
    *variable {
        set clNode [$node getParent]
        switch -glob -- [$clNode info class] {
        *SnitTypeNode - *SnitWidgetNode {
        }
        *TclOOClassNode {
            append script ::oo::define " [getNSQ $clNode] [$node cget -token] "
            append script [$node cget -name] " "
            append script [string trim [$node cget -definition] "{}"]
        }
        *ItclClassNode {
            # not possible
        }
        default {
            append script variable " [getNSQ $node] " 
            append script [string trim [$node cget -definition] "{}"]
        }
        
        }
    }
    
    namespace -
    webcmd -
    xo_* {
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
    
    class {
        # build up the node definition
        set name [$node cget -name]
        switch -glob -- [$node info class] {
        *SnitTypeNode - *SnitWidgetNode {
            append script ::snit:: [namespace tail [$node cget -token]] " "
            append script [getNSQ $node] " "
            append script \{ [string trim [$node cget -definition] "{}"] \}
        }
        *TclOOClassNode {
            append script ::oo::class " create [getNSQ $node] "
            append script \{ [string trim [$node cget -definition] "{}"] \}
        }
        *ItclClassNode {
            append script ::itcl::class " [getNSQ $node] "
            append script \{ [string trim [$node cget -definition] "{}"] \}
        }
        }
    }
    
    package {
        append script [$node cget -definition]
    }
    
    tcltest {
        append script [$node cget -testcmd]
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
    
    return $script
}


} ;# namespace Tmw

package provide tloona::codebrowser 2.0.0
