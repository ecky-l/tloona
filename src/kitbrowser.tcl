## kitbrowser.tcl (created by Tloona here)
package require snit 2.3.2
package require tmw::dialog 2.0.0
package require tloona::codebrowser 2.0.0
package require tloona::wrapwizzard 2.0.0

namespace eval Tloona {

## \brief The browser widget for starkit projects 
snit::widgetadaptor kitbrowser {
    
    #### Options
    
    #### Components
    delegate method * to hull except {addFileSystem expand}
    delegate option * to hull
    
    #### Variables
    
    constructor {args} {
        installhull using Tloona::projectbrowser
        
        set tb [$self toolbar tools -pos n -compound none]
        $self configure -sortalpha 0 -nodeformat {"%s" -tail}
        $self configurelist $args
        
        set T [$self treeview]
        
        if {[tk windowingsystem] eq "aqua"} {
            # On Mac the right mouse button is Button-2
            bind $T <Button-2> [mymethod contextMenu %X %Y %x %y]
        } else {
            bind $T <Button-3> [mymethod contextMenu %X %Y %x %y]
        }
        bind $T <Double-Button-1> [mymethod onFileOpen %x %y]
        bind $T <Control-Button-1> [mymethod selectCode %x %y 1]
    }
    
    # @v overrides addFileSystem in filebrowser. Kit files are
    # @v extracted immediately
    method addFileSystem {root} {
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
            set mw [$self cget -mainwindow]
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
            foreach {myFs} [$self getFileSystems] {
                if {[string match [$myFs cget -name] $dn]} {
                    global TloonaApplication
                    if {$mw != ""} {
                        set defst [$mw cget -status]
                        $mw configure -status "Refreshing $dn"
                        $self refresh $myFs
                        $mw configure -status $defst
                    }
                    return
                }
            }
        }
        
        # parse the tcl files
        Tmw::Fs::build $fs 1
        $self add $fs 1 0
        $self sort
        $self addStarkit $fs
        return $fs
    }
    
    # @c callback for open files from kit projects
    method onFileOpen {x y {file ""}} {
        set ofCmd [$self cget -openfilecmd]
        if {$ofCmd == ""} {
            return
        }
        
        if {$file == ""} {
            set file [$self selection]
        }
        uplevel #0 $ofCmd [$file cget -name] 1
    }
        
    # @c callback for file delete
    method onFileDelete {{file ""}} {
        global TloonaApplication
        if {$file == ""} {
            set file [$self selection]
        }
        
        set m "Are you sure that you want to delete the file\n\n"
        append m "[$file cget -name]?"
        set q [Tmw::message $TloonaApplication "Delete File?" yesno $m]
        if {$q != "yes"} {
            return
        }
        
        $self remove $file
        file delete -force [$file cget -name]
        if {[set parDir [$file getParent]] == {}} {
            destroy $file
            return
        }
        $parDir removeChild $file
        destroy $file
    }
        
    ## callback handler for wrapping a vfs project
    method onWrapKit {{file ""}} {
        global TloonaApplication tcl_version
        
        # wrapping only works in Tcl >= 8.6
        if {$tcl_version < 8.6} {
            tk_messageBox -type ok -icon error -title "Tcl Version not supported" \
                -parent $TloonaApplication -message "Deployment works only in Tcl >= 8.6"
            return
        }
        
        if {[catch {package require starkit}]} {
            tk_messageBox -type ok -icon error -title "starkit not available" \
                -parent $TloonaApplication \
                    -message "starkit package is not present, but needed for deployment"
            return
        }
        
        set mw $TloonaApplication
        if {$mw == ""} {
            return
        }
        
        set defst [$mw cget -status]
        try {
            Tloona::wrapwizzard .wrapwizz -master $TloonaApplication
            .wrapwizz setDeployDetails [$file cget -name] [$file cget -deploydir]
            
            if {[.wrapwizz show] == "Cancel"} {
                destroy .wrapwizz
                return
            }
            
            $mw configure -status "creating standalone runtime..."
            $mw showProgress 1
        
            set a [.wrapwizz getOptions]
            if {[dict exists $a -runtime] && [dict get $a -runtime] == {}} {
                set m "Can not create a Starpack without a valid Tclkit runtime\n\n"
                append m "Please specify one"
                tk_messageBox -type ok -icon error -title "Runtime not provided" \
                    -parent $TloonaApplication -message $m
                return
            }
            $file configure -deploydir [dict get $a -deploydir]
            set n [eval $file wrap [dict remove $a -deploydir] -varptr var]
            $self refresh
            tk_messageBox -type ok -icon info -title "Deployment finished" \
                -parent $TloonaApplication -message "Created $n"
        } trap README_NOT_EXIST {err errOpts} {
            tk_messageBox -type ok -icon error -title "Deployment Error" \
                -parent $TloonaApplication -message $err
        } trap {} {err errOpts} {
            tk_messageBox -type ok -icon error -title "Error, Code: [dict get $errOpts -errorcode]" \
                -parent $TloonaApplication -message $err
            puts $err,$errOpts
        } finally {
            $mw showProgress 0
            $mw configure -status $defst
            destroy .wrapwizz
        }
    }
    
    ## \brief callback handler for new Tclscript menu entry
    method onFileNew {parentItem} {
        global TloonaApplication
        set fileName [Tmw::input $TloonaApplication "File Name:" okcancel]
        if {$fileName == ""} {
            return
        }
        set uri [file join [$parentItem cget -name] $fileName]
        if {[file exists $uri]} {
            Tmw::message $TloonaApplication "File exists" ok "File $fileName already exists here!"
            return
        }
        
        set fh [open $uri w]
        puts $fh "## $fileName (created by Tloona here)"
        close $fh
        
        ::Tmw::Fs::rebuild $parentItem 1 nf of
        $self add [$parentItem lookup $uri] 1 1
   	    set cls [uplevel #0 [$self cget -openfilecmd] $uri 0]
    }
    
    ## \brief Change directory in the slave console that is configured
    method onCdConsoleThere {item} {
        global TloonaApplication
        set cons [$TloonaApplication consolenb select]
        $cons eval [list cd [$item cget -name]] -showlines 1
    }
    
    # @r All Tcl files in a particular starkit
    method getTclFiles {starKit} {
        set tclFiles {}
        foreach {file} [$starKit getChildren yes] {
            if {![string equal [$file cget -type] tclfile]} {
                continue
            }
            lappend tclFiles $file
        }
        
        return $tclFiles
    }
    
    # @c Overrides the expand method
    method expand {open {item ""}} {
        if {$item == ""} {
            set item [$self selection]
        }
        $self refreshFile $item
        $hull expand $open $item
    }
    
    # @c Reparses and updates a Tcl file. This is triggered by a click
    # @c on the open cross before the file or when files are opened initially
    method refreshFile {item} {
        switch -- [$item cget -type] {
        tclfile -
        testfile {
            set chds [[$item getTree] getChildren yes]
            if {[llength $chds] == 1 && [string equal [$chds cget -name] dummy]} {
                $item removeChild $chds
                #$item parseFile [$item cget -name]
                $self add $item 1 1
                itcl::delete object $chds
            }
        }
        }
    }
    
    # @c pops up a context menu
    method contextMenu {xr yr x y} {
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
        #Tmw::Browser::selection set $realItem
        # create context menu
        if {[winfo exists .kitcmenu]} {
            destroy .kitcmenu
        }
        menu .kitcmenu -tearoff no
        
        if {[$realItem getParent] == ""} {
            # it's a topnode (extracted) starkit
            
            if {[$realItem extracted]} {
                .kitcmenu add command -label "CD Console There" -image $Tmw::Icons(FileOpen) \
                    -command [mymethod onCdConsoleThere $realItem] -compound left
                .kitcmenu add command -label "New File..." -image $Tmw::Icons(FileNew) \
                    -command [mymethod onFileNew $realItem] -compound left
                .kitcmenu add command -label "Refresh" -image $Tmw::Icons(ActReload) \
                    -command [mymethod refresh] -compound left
                .kitcmenu add command -label "Deploy..." -image $Tmw::Icons(KitFile) \
                    -command [mymethod onWrapKit $realItem] -compound left
                set d [file join [file dirname [$realItem cget -name]] \
                    [file root [file tail [$realItem cget -name]]].kit]
            }
            
            .kitcmenu add separator
            .kitcmenu add command -label "Remove from Browser" -compound left \
                -command [mymethod removeProjects $realItem] -image $Tmw::Icons(ActCross)
        } elseif {[$realItem isa ::Tmw::Fs::FSContent]} {
            set tno [$realItem getTopnode]
            switch -- [$realItem cget -type] {
            tclfile {
                .kitcmenu add command -label "Open File" \
                    -state [expr {[$self isOpen $realItem] ? "disabled" : "normal"}] \
                    -command [mymethod onFileOpen $x $y $realItem]
                .kitcmenu add separator
            }
            file {
            }
            directory {
                if {[$tno extracted]} {
                    .kitcmenu add command -label "CD Console There" -image $Tmw::Icons(FileOpen) \
                        -command [mymethod onCdConsoleThere $realItem] -compound left
                    .kitcmenu add command -label "New File..." -image $Tmw::Icons(FileNew) \
                        -command [mymethod onFileNew $realItem] -compound left
                } else {
                    .kitcmenu add command \
                        -label "Add file/directory from Filesystem..." \
                        -command [mymethod onCopyFromFs $realItem]
                }
                .kitcmenu add separator
            }
            }
            
            .kitcmenu add command -label "Delete" -command [mymethod onFileDelete $realItem]
            
        } else {
            menu .kitcmenu.commm -tearoff no
            .kitcmenu add cascade -label "Send to Comm" -menu .kitcmenu.commm
            if {[set mw $TloonaApplication] != "" &&
                    [$mw isa ::Tloona::Mainapp] && 
                    [$mw getCommIDs] != {}} {
                
                foreach {cid} [$mw getCommIDs] {
                    .kitcmenu.commm add command -label "Comm $cid" \
                        -command [mymethod sendDefinition $realItem comm $cid]
                }
                .kitcmenu.commm add separator
            }
            .kitcmenu.commm add command -label "New Comm ID" \
                -command [mymethod sendDefinition $realItem comm ""]
            
            # to the console
            .kitcmenu add command -label "Send to Console" -command \
                [mymethod sendDefinition $realItem console ""]
        }
        
        tk_popup .kitcmenu $xr $yr
    }
    
}

namespace eval KitBrowser {
proc globFilter {pattern node} {
    string match $pattern [$node cget -tail]
}
} ;# namespace KitBrowser


} ;# namespace Tloona

package provide tloona::kitbrowser 2.0.0
