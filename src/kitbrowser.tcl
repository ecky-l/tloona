#
# kitbrowser.tcl
#
#package require tmw::filebrowser 1.0
package require tmw::dialog 1.0
package require tmw::icons 1.0
package require tmw::filesystem 1.0
package require tloona::wrapwizzard 1.0
package require tloona::codebrowser 1.0
package require parser::script 1.0
package require tloona::starkit 1.0
package provide tloona::kitbrowser 1.0

usual KitBrowser {}


# @c This class represents a browser for starkit projects (starkit and 
# @c starpacks). When the user opens a starkit, it is extracted resp.
# @c refreshed and the resulting .vfs directory is displayed in the
# @c browser. Files can be browsed and opened from there, it is also
# @c possible to insert new Tcl files directly
class ::Tloona::KitBrowser {
    inherit Tloona::ProjectBrowser
    
        
    constructor {args} {
        set tb [toolbar tools -pos n -compound none]
        
        set tw [component treeview]
        if {[tk windowingsystem] eq "aqua"} {
            # On Mac the right mouse button is Button-2
            bind $tw <Button-2> [code $this contextMenu %X %Y %x %y]
        } else {
            bind $tw <Button-3> [code $this contextMenu %X %Y %x %y]
        }
        bind $tw <Double-Button-1> [code $this onFileOpen %x %y]
        bind $tw <Control-Button-1> [code $this selectCode %x %y 1]
        configure -sortalpha 0 -nodeformat {"%s" -tail}
        eval itk_initialize $args        
    }
    
    # @v overrides addFileSystem in filebrowser. Kit files are
    # @v extracted immediately
    public method addFileSystem {root} {
        global TloonaApplication
        switch -- [file extension $root] {
            .kit {
                set kf [file rootname $root].vfs
                
                # check whether the vfs directory exists already
                # If so, ask to delete it
                if {[file isdirectory $kf]} {
                    Tmw::dialog .dlg -title "VFS exists" -master $TloonaApplication
                    .dlg add Ok -text "Delete directory"
                    .dlg add Cancel -text "Cancel"
                    set m "Directory $kf already exists\n"
                    append m "Do you want to delete it and replace it's"
                    append m " content with the content of the starkit?"
                    pack [ttk::label [.dlg childsite].l -text $m] \
                        -expand y -fill both -padx 10 -pady 10
                    if {[.dlg show] != "Ok"} {
                        destroy .dlg
                        return
                    }
                    destroy .dlg
                    file delete -force $kf
                }
            }
            .vfs {
            }
        }
        
        set fs [::Tloona::Fs::starkit -name $root -type "starkit" -expanded 0]
        if {![$fs extracted]} {
            set mw [cget -mainwindow]
            if {$mw != "" && [$mw isa ::Tloona::Mainapp]} {
                set defst [$mw cget -status]
                $mw configure -status "Extracting [file tail $root]"
                $mw showProgress 1
                $fs extract [cget -threadpool] var
                $mw showProgress 0
                $mw configure -status $defst
            }
            
            # if the vfs already exists, refresh its directory
            set dn [$fs cget -name]
            foreach {myFs} [getFileSystems] {
                if {[string match [$myFs cget -name] $dn]} {
                    global TloonaApplication
                    if {$mw != "" && [$mw isa ::Tloona::Mainapp]} {
                        set defst [$mw cget -status]
                        $mw configure -status "Refreshing $dn"
                        refresh $myFs
                        $mw configure -status $defst
                    }
                    return
                }
            }
        }
        
        # parse the tcl files
        Tmw::Fs::build $fs 1
        add $fs 1 0
        lappend Starkits $fs
        return $fs
    }
    
    # @c callback for open files from kit projects
    public method onFileOpen {x y {file ""}} {
        if {$itk_option(-openfilecmd) == ""} {
            return
        }
        
        if {$file == ""} {
            set file [selection]
        }
        
        if {[$file isa ::Tmw::Fs::FSContent]} {
            refreshFile $file
            set cls [eval $itk_option(-openfilecmd) [$file cget -name] 0]
            if {$cls == ""} {
                return
            }
            $cls updateHighlights
            if {[$cls isa ::Tmw::BrowsableFile]} {
                $cls setTree $file
                $cls reparseTree
            }
            return
        }
        
        # seems to be an inner node. Open the enclosing file
        set parent [$file getParent]
        while {$parent != "" && ![$parent isa ::Tmw::Fs::FSContent]} {
            set parent [$parent getParent]
        }
        if {![isOpen $parent]} {
        	    set cls [eval $itk_option(-openfilecmd) [$parent cget -name] 0]
             $cls updateHighlights
             if {[$cls isa ::Tmw::BrowsableFile]} {
                 $cls setTree $parent
                 $cls reparseTree
             }
        }
        
        selectCode $x $y 0
    }
        
    # @c callback for file delete
    public method onFileDelete {{file ""}} {
        global TloonaApplication
        if {$file == ""} {
            set file [selection]
        }
        
        set m "Are you sure that you want to delete the file\n\n"
        append m "[$file cget -name]?"
        set q [Tmw::message $TloonaApplication "Delete File?" yesno $m]
        if {$q != "yes"} {
            return
        }
        
        remove $file
        file delete -force [$file cget -name]
        if {[set parDir [$file getParent]] == {}} {
            delete object $file
            return
        }
        $parDir removeChild $file
        delete object $file
        
    }
        
    ## callback handler for wrapping a vfs project
    public method onWrapKit {{file ""}} {
        global TloonaApplication
        
        set mw [cget -mainwindow]
        if {$mw == ""} {
            return
        }
        
        Tloona::wrapwizzard .wrapwizz -master $TloonaApplication
        .wrapwizz setDeployDetails [$file cget -name]
        
        if {[.wrapwizz show] == "Cancel"} {
            delete object .wrapwizz
            return
        }
        
        set defst [$mw cget -status]
        $mw configure -status "creating standalone runtime..."
        $mw showProgress 1
        
        try {
            set a [.wrapwizz getOptions]
            if {[dict exists $a -runtime] && [dict get $a -runtime] == {}} {
                set m "Can not create a Starpack without a valid Tclkit runtime\n\n"
                append m "Please specify one"
                tk_messageBox -type ok -icon error -title "Runtime not provided" \
                    -parent [namespace tail $this] -message $m
                return
            }
            set n [eval $file wrap [.wrapwizz getOptions] -varptr var]
            $this refresh
            Tmw::message $TloonaApplication "Deployment finished" ok "Created $n"
        } finally {
            $mw showProgress 0
            $mw configure -status $defst
            delete object .wrapwizz
        }
    }
    
    ## \brief Change directory in the slave console that is configured
    public method onCdConsoleThere {item} {
        $mainwindow component console eval [list cd [$item cget -name]] 1
    }
    
    # @r All Tcl files in a particular starkit
    public method getTclFiles {starKit} {
        set tclFiles {}
        foreach {file} [$starKit getChildren yes] {
            if {![string equal [$file cget -type] tclfile]} {
                continue
            }
            lappend tclFiles $file
        }
        
        return $tclFiles
    }
        
    # @r All FileSystems in the browser
    public method getStarkits {} {
        return [children ""]
    }
        
    # @c Overrides the selection method in Tmw::Browser.
    # @c In a kit browser, the selection should always be set to
    # @c a file or directory, never to a containing code tree
    public method selection {args} {
        if {[llength $args] == 0} {
            eval chain $args
        }
        set selOp [lindex $args 0]
        set items {}
        foreach {item} [lindex $args 1] {
            lappend items [$item getTopnode ::Parser::StructuredFile]
        }
        
        eval chain $selOp $items
    }
        
    # @c Overrides see in Tmw::Browser. In Kit browsers, see does
    # @c never refer to inner code trees, it always refers to 
    # @c files or directories
    public method see {item} {
        chain [$item getTopnode ::Parser::StructuredFile]
    }
        
    # @c Overrides the expand method
    public method expand {open {item ""}} {
        if {$item == ""} {
            set item [component treeview selection]
        }
        refreshFile $item
        chain $open $item
    }
    
    # @c Reparses and updates a Tcl file. This is triggered by a click
    # @c on the open cross before the file or when files are opened initially
    public method refreshFile {item} {
        switch -- [$item cget -type] {
        tclfile -
        testfile {
            set chds [[$item getTree] getChildren yes]
            if {[llength $chds] == 1 && [string equal [$chds cget -name] dummy]} {
                $item removeChild $chds
                $item parseFile [$item cget -name]
                add $item 1 1
                itcl::delete object $chds
            }
        }
        }
    }
    
    # @c pops up a context menu
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
        if {[winfo exists .kitcmenu]} {
            destroy .kitcmenu
        }
        menu .kitcmenu -tearoff no
        
        if {[$realItem getParent] == ""} {
            # it's a topnode (extracted) starkit
            
            if {[$realItem extracted]} {
                .kitcmenu add command -label "CD Console There" -image $Tmw::Icons(FileOpen) \
                    -command [code $this onCdConsoleThere $realItem] -compound left
                .kitcmenu add command -label "Refresh" -image $Tmw::Icons(ActReload) \
                    -command [code $this refresh] -compound left
                .kitcmenu add command -label "Deploy..." -image $Tmw::Icons(KitFile) \
                    -command [code $this onWrapKit $realItem] -compound left
                set d [file join [file dirname [$realItem cget -name]] \
                    [file root [file tail [$realItem cget -name]]].kit]
            }
            
            .kitcmenu add separator
            .kitcmenu add command -label "Remove from Browser" -compound left \
                -command [code $this removeProjects $realItem] -image $Tmw::Icons(ActCross)
        } elseif {[$realItem isa ::Tmw::Fs::FSContent]} {
            set tno [$realItem getTopnode]
            switch -- [$realItem cget -type] {
                tclfile {
                    .kitcmenu add command -label "Open File" \
                        -state [expr {[isOpen $realItem] ? "disabled" : "normal"}] \
                        -command [code $this onFileOpen $x $y $realItem]
                    .kitcmenu add separator
                }
                file {
                }
                directory {
                    if {[$tno extracted]} {
                        .kitcmenu add command \
                            -label "New Tcl/Itcl script" \
                            -command [code $this onNewTclScript $realItem]
                    } else {
                        .kitcmenu add command \
                            -label "Add file/directory from Filesystem..." \
                            -command [code $this onCopyFromFs $realItem]
                    }
                    .kitcmenu add separator
                }
            }
            
            .kitcmenu add command -label "Delete" \
                -command [code $this onFileDelete $realItem]
            
        } else {
            menu .kitcmenu.commm -tearoff no
            .kitcmenu add cascade -label "Send to Comm" -menu .kitcmenu.commm
            if {[set mw [cget -mainwindow]] != "" &&
                    [$mw isa ::Tloona::Mainapp] && 
                    [$mw getCommIDs] != {}} {
                
                foreach {cid} [$mw getCommIDs] {
                    .kitcmenu.commm add command -label "Comm $cid" \
                        -command [code $this sendDefinition $realItem comm $cid]
                }
                .kitcmenu.commm add separator
            }
            .kitcmenu.commm add command -label "New Comm ID" \
                -command [code $this sendDefinition $realItem comm ""]
            
            # to the console
            .kitcmenu add command -label "Send to Console" -command \
                [code $this sendDefinition $realItem console ""]
        }
        
        tk_popup .kitcmenu $xr $yr
    }
    
}


proc ::Tloona::kitbrowser {path args} {
    uplevel ::Tloona::KitBrowser $path $args
}

proc ::Tloona::KitBrowser::globFilter {pattern node} {
    string match $pattern [$node cget -tail]
}
