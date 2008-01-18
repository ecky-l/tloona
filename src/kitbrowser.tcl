#
# kitbrowser.tcl
#
#package require tmw::filebrowser 1.0
package require tmw::dialog 1.0
package require tmw::icons 1.0
package require tmw::filesystem 1.0
package require tloona::wrapwizzard 1.0
package require tloona::codebrowser 1.0
package require parser::structuredfile 1.4

package provide tloona::kitbrowser 1.0

usual KitBrowser {}

# @c This class is used to represent starkits. They can be extracted 
# @c and wrapped. Besides that, configuration of the -name attribute 
# @c is special.
# @c Starkits are file systems and can be displayed in the kit browser.
class ::Tloona::Fs::Starkit {
    inherit ::Tmw::Fs::FileSystem
    
    constructor {args} {
        eval configure $args
    }
    
    public {
        # @v name: overrides name attribute. Checks for extrated
        variable name "" {
            switch -- [file extension $name] {
                .kit {
                    extracted 0
                }
                default {
                    extracted 1
                }
            }
            configure -tail [file tail $name] -dirname [file dirname $name]
        }
        
        variable vfsid ""
        
        # @c Extracts a starkit. If wThread is not "", the extraction is
        # @c done in this thread
        method extract {tPool varPtr}
        
        # @c Wraps a starkit. If wThread is not "", this is done in this
        # @c thread
        method wrap {tPool args}
        
        method extracted {{e -1}}
    }
    
    private {
        variable _Extracted 0
    }
}

body ::Tloona::Fs::Starkit::extract {tPool varPtr} {
    if {[extracted]} {
        return
    }
    
    upvar $varPtr var
    
    set script "eval sdx::unwrap::unwrap [cget -name] \n"
    #thread::send -async $wThread $script var
    if {$tPool != ""} {
        set job [tpool::post -nowait $tPool $script]
        tpool::wait $tPool $job
    } else {
        eval $script
    }
    configure -name [file rootname [cget -name]].vfs
    
    return ""
}

body ::Tloona::Fs::Starkit::extracted {{e -1}} {
    if {$e < 0} {
        return $_Extracted
    }
    
    if {![string is boolean -strict $e]} {
        error "argument e must be boolean"
    }
    set _Extracted $e
}

body ::Tloona::Fs::Starkit::wrap {args} {
    global auto_path TloonaRoot UserOptions
    if {![extracted]} {
        return
    }
    
    if {$UserOptions(PathToSDX) == ""} {
        error "Need SDX. Get it from http://www.equi4.com/starkit/sdx.html"
    }
    
    set nargs {}
    set ktype "kit"
    set tPool ""
    while {$args != {}} {
        switch -- [lindex $args 0] {
            -type {
                set args [lrange $args 1 end]
                set ktype [lindex $args 0]
            }
            -varptr {
                set args [lrange $args 1 end]
                upvar [lindex $args 0] var
            }
            -tpool {
                set args [lrange $args 1 end]
                set tPool [lindex $args 0]
            }
            default {
                lappend nargs [lindex $args 0]
            }
        }
        
        set args [lrange $args 1 end]
    }
    
    switch -- $ktype {
        "pack" {
            switch -- $::tcl_platform(platform) {
                "windows" {
                    set k [file join [file dirname [cget -name]] \
                        [file root [file tail [cget -name]]].exe]
                }
                "unix" -
                default {
                    set k [file join [file dirname [cget -name]] \
                        [file root [file tail [cget -name]]].bin]
                }
            }
            
        }
        "kit" -
        default {
            set k [file join [file dirname [cget -name]] \
                [file root [file tail [cget -name]]].kit]
            
        }
    }
    
    set script "source $::UserOptions(PathToSDX)\n"
    append script "package require sdx\n"
    append script "set tmpDir [pwd]\n"
    append script "cd [eval file join [lrange [file split $k] 0 end-1]]\n"
    append script "sdx::sdx wrap $k $nargs \n"
    append script "cd \$tmpDir \n"
    eval $script
    
    return $k
}

proc ::Tloona::Fs::starkit {args} {
    uplevel Tloona::Fs::Starkit ::#auto $args
}

# @c This class represents a browser for starkit projects (starkit and 
# @c starpacks). When the user opens a starkit, it is extracted resp.
# @c refreshed and the resulting .vfs directory is displayed in the
# @c browser. Files can be browsed and opened from there, it is also
# @c possible to insert new Tcl files directly
class ::Tloona::KitBrowser {
    inherit Tloona::CodeBrowser
    
    # @v -openfilecmd: a piece of code that is executed to open files
    itk_option define -openfilecmd openFileCmd Command ""
    # @v -closefilecmd: a piece of code that is executed to close files
    itk_option define -closefilecmd closeFileCmd Command ""
    # @v -isopencmd: a piece of code to determine whether a file is open
    itk_option define -isopencmd isOpenCmd Command ""
    # @v -selectcodecmd: a command that is executed when a code fragment is selected
    itk_option define -selectcodecmd selectCodeCmd Command ""
    
    # @v Starkits: A list of File systems
    protected variable Starkits {}
        
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
            $cls setTree $file
            $cls updateHighlights
            $cls reparseTree
            return
        }
        
        # seems to be an inner node. Open the enclosing file
        set parent [$file getParent]
        while {$parent != "" && ![$parent isa ::Tmw::Fs::FSContent]} {
            set parent [$parent getParent]
        }
        if {![isOpen $parent]} {
        	    set cls [eval $itk_option(-openfilecmd) [$parent cget -name] 0]
             $cls setTree $parent
             $cls updateHighlights
             $cls reparseTree
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
        
    # @c callback handler for wrapping a vfs project
    public method onWrapKit {{file ""}} {
        global TloonaApplication
        
        Tloona::wrapwizzard .wrapwizz -master $TloonaApplication
        .wrapwizz setRuntimeNames [$file cget -name]
        
        if {[.wrapwizz show] == "Cancel"} {
            delete object .wrapwizz
            return
        }
        
        if {[set mw [cget -mainwindow]] != "" && [$mw isa ::Tloona::Mainapp]} {
            set defst [$mw cget -status]
            $mw configure -status "creating standalone runtime..."
            $mw showProgress 1
            if {[cget -threadpool] == ""} {
                set n [eval $file wrap [.wrapwizz getOptions] -varptr var]
            } else {
                set n [eval $file wrap -tpool [cget -threadpool] [.wrapwizz getOptions] \
                    -varptr var]
            }
            #set n [eval $file wrap "" [.wrapwizz getOptions] -varptr var]
            
            $mw showProgress 0
            $mw configure -status $defst
        }
        
        delete object .wrapwizz
    }
        
    # @c Callback for collapse the tree view
    public method onSyncronize {} {
        configure -syncronize $syncronize
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
            lappend items [$item getTopnode ::parser::StructuredFile]
        }
        
        eval chain $selOp $items
    }
        
    # @c Overrides see in Tmw::Browser. In Kit browsers, see does
    # @c never refer to inner code trees, it always refers to 
    # @c files or directories
    public method see {item} {
        chain [$item getTopnode ::parser::StructuredFile]
    }
        
    # @c selects the code definition of Itcl methods. Essentially,
    # @c dispatches to the -selectcodecmd option.
    public method selectCode {x y def} {
        if {$itk_option(-selectcodecmd) == ""} {
            return
        }
        eval $itk_option(-selectcodecmd) [component treeview] $x $y $def
    }
        
    # @c Overrides remove in Tmw::Browser. Closes files that are still
    # @c open
    public method removeProjects {nodes} {
        foreach {node} $nodes {
            if {[$node getParent] != ""} {
                continue
            }
            foreach {file} [$node getChildren yes] {
                if {![$file isa ::Tmw::Fs::File]} {
                    continue
                }
                set fCls [eval $itk_option(-isopencmd) [$file cget -name]]
                if {$fCls == ""} {
                    continue
                }
                
                eval $itk_option(-closefilecmd) $fCls
            }
        }
        
        remove $nodes yes
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
        }
        
        tk_popup .kitcmenu $xr $yr
    }
        
    # @c Overrides createToolbar in Codebrowser. Adds other widgets and
    # @c aligns them different
    protected method createToolbar {} {
        global Icons
        
        chain
        toolbutton syncronize -toolbar tools -image $Icons(Syncronize) \
            -type checkbutton -variable [scope syncronize] -separate 0 \
            -command [code $this onSyncronize]
        toolbutton collapse -toolbar tools -image $Icons(Collapse) \
            -type command -separate 0 -command [code $this collapseAll]
    }
    
    # @c checks whether a file is open already. The method
    # @c invokes the -isopencmd code. If no -isopencmd is
    # @c given, the check can not be performed
    #
    # @a file: the file in the file system to check for
    private method isOpen {{file ""}} {
        if {$itk_option(-isopencmd) == ""} {
            return
        }
        if {$file == ""} {
            set file [selection]
        }
        set fname [$file cget -name]
        return [expr {[eval $itk_option(-isopencmd) $fname] != ""}]
    }
    
}


proc ::Tloona::kitbrowser {path args} {
    uplevel ::Tloona::KitBrowser $path $args
}

proc ::Tloona::KitBrowser::globFilter {pattern node} {
    string match $pattern [$node cget -tail]
}
