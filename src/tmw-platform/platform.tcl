## platform.tcl (created by Tloona here)
package require snit 2.3.2

namespace eval ::Tmw {

::snit::widget platform {
    hulltype toplevel
    delegate option * to hull
    
    component progress
    component mainframe
    component mainmenu
    component statusline
    
    variable Menus
    array set Menus {}
    
    constructor {args} {
        set mainmenu [menu $win.mainmenu -tearoff no -relief raised]
        
        $win configure -menu $mainmenu
        $self configurelist $args
    }
    
    method menuentry {name args} {
        set M $mainmenu
        
        # get type and toolbar
        set type ""
        set toolbar ""
        set cmd ""
        set accel ""
        set nargs {}
        for {set i 0} {$i < [llength $args]} {incr i} {
            set arg [lindex $args $i]
            switch -- $arg {
                -type {
                    set j [expr {$i + 1}]
                    set type [lindex $args [incr i]]
                }
                -toolbar {
                    set j [expr {$i + 1}]
                    set toolbar [lindex $args [incr i]]
                }
                -command {
                    set cmd [lindex $args [incr i]]
                    lappend nargs $arg $cmd
                }
                -accelerator {
                    set accel [lindex $args [incr i]]
                    lappend nargs $arg $accel
                }
                delete {
                    return
                }
                default {
                    lappend nargs $arg
                }
            }
        }
        
        # Configure the entry (or delete it) when it exists
        set sName $M.[string tolower $name]
        if {[info exists Menus($sName)]} {
            set parent [join [lrange [split $sName .] 0 end-1] .]
            set i [lindex $Menus($sName) 2]
            
            if {[llength $args] == 0} {
                return [array get Menus]
            }
            
            if {[llength $args] == 1} {
                # do an entrycget operation
                switch -- $args {
                    -type {
                        return [lindex $Menus($sName) 1]
                    }
                    -toolbar {
                        return [lindex $Menus($sName) 3]
                    }
                }
                
                return [$parent entrycget $i $args]
            }
            
            eval $parent entryconfigure $i $nargs
            
            # eval toolbar configuration as well
            if {[set tb [lindex $Menus($sName) 3]] != ""} {
                if {[set i [lsearch $nargs -label]] != -1} {
                    lset nargs $i -text
                }
                if {[set i [lsearch $nargs -accelerator]] >= 0} {
                    set nargs [lreplace $nargs $i [incr i]]
                }
                
                eval $tb configure $nargs
            }
            
            if {$cmd != "" && $accel != ""} {
                set accel [regsub {Ctrl} $accel Control]
                set accel [regsub {Meta} $accel M1]
                bind [namespace tail $this] <[set accel]> $cmd
            }
            
            return
        }
        
        # type must be given at this point
        if {$type == ""} {
            error "type must be given"
        }
        
        set parentMenu $M
        set pToolMenu ""
        set nm [lindex [split $name .] 0]
        if {[llength [split $name .]] > 1} {
            # toplevel is a cascade. Check whether it exists.
            # If it does not exist, create it
            set casc $M.[string tolower $nm]
            if {![info exists Menus($casc)]} {
                set Menus($casc) $nm
                lappend Menus($casc) cascade
                $parentMenu add cascade -label $nm -menu [menu $casc -tearoff no]
                lappend Menus($casc) [$parentMenu index last]
                lappend Menus($casc) ""
            }
            set parentMenu $casc
        }
        
        if {[llength [split $name .]] > 2} {
            # At least one sublevel is a cascade as well. Same procedure
            # as above
            set nnm $nm
            set parentMenu $casc
            foreach {cc} [lrange [split $name .] 1 end-1] {
                append casc .[string tolower $cc]
                append nnm .$cc
                if {[info exists Menus($casc)]} {
                    set lclm [$parentMenu entrycget [lindex $Menus($casc) 2] -menu]
                    
                    # If this was an explicitely created cascade and it has a
                    # toolbar entry (menubutton in a toolbar), then the corresp.
                    # menu goes here
                    set pToolMenu [lindex $Menus($casc) 4]
                    if {$lclm == ""} {
                        $parentMenu entryconfigure [lindex $Menus($casc) 2] \
                            -menu [menu $casc -tearoff no]
                        set parentMenu $casc
                    } else {
                        set parentMenu $casc
                    }
                    continue
                }
                
                set Menus($casc) $nnm
                lappend Menus($casc) cascade
                $parentMenu add cascade -label $cc -menu [menu $casc -tearoff no]
                lappend Menus($casc) [$parentMenu index last]
                lappend Menus($casc) ""
                
                set parentMenu $casc
            }
        }
        
        set sName $M.[string tolower $name]
        set Menus($sName) [list $name $type]
        #lappend Menus($sName) $type
        
        if {$type != "separator"} {
            # set some arguments if not present
            if {[lcontain $nargs -image] && ![lcontain $args -compound]} {
                lappend nargs -compound left
            }
            if {![lcontain $nargs -label]} {
                lappend nargs -label [lindex [split $name .] end]
            }
        }
        
        eval $parentMenu add $type $nargs
        lappend Menus($sName) [$parentMenu index last]
        if {$pToolMenu != ""} {
            eval $pToolMenu add $type $nargs
        }
        
        # Create a toolbar entry if requested
        set toolButton ""
        set toolMenu ""
        if {$toolbar != ""} {
            if {[set i [lsearch $nargs -label]] != -1} {
                lset nargs $i -text
            }
            if {[set i [lsearch $nargs -accelerator]] >= 0} {
                set nargs [lreplace $nargs $i [incr i]]
            }
            set toolButton [eval component mainframe toolbutton $name \
                -type $type -toolbar $toolbar $nargs]
            
            # if it is a cascade, create a menu for it. This is filled
            # with subsequent entries
            if {[string equal $type cascade]} {
                set toolMenu [menu $toolButton.m -tearoff no]
                $toolButton configure -menu $toolMenu
            }
            lappend Menus($sName) $toolButton $toolMenu
        } else {
            lappend Menus($sName) "" ""
        }
        
        if {$cmd != "" && $accel != ""} {
            set accel [regsub {Ctrl} $accel Control]
            set accel [regsub {Meta} $accel M1]
            bind [namespace tail $this] <[set accel]> $cmd
        }
        
        list $parentMenu [$parentMenu index last] $toolButton $toolMenu
    }
    
    ## private 
    method DefaultMenu {} {
        menuentry File.New -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileNew) -command [code $this onFileNew] \
            -accelerator Ctrl-n
        menuentry File.Open -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileOpen) -command [code $this onFileOpen] \
            -accelerator Ctrl-o
        menuentry File.Save -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileSave) -command [code $this onFileSave] \
            -accelerator Ctrl-s
        menuentry File.Close -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileClose) -command [code $this onFileClose] \
            -accelerator Ctrl-w
        menuentry File.Sep0 -type separator -toolbar maintoolbar
        menuentry File.Quit -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActExit) -command [code $this onQuit] \
            -accelerator Ctrl-q
        
        menuentry Edit.Undo -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActUndo) -command [code $this onEditUndo] \
            -accelerator Ctrl-z
        menuentry Edit.Redo -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActRedo) -command [code $this onEditRedo] \
            -accelerator Ctrl-r
        menuentry Edit.Sep0 -type separator -toolbar maintoolbar
        menuentry Edit.Cut -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditCut) -command [code $this onEditCut] \
            -accelerator Ctrl-x
        menuentry Edit.Copy -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditCopy) -command [code $this onEditCopy] \
            -accelerator Ctrl-c
        menuentry Edit.Paste -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditPaste) -command [code $this onEditPaste] \
            -accelerator Ctrl-v
    }
}

} ;# namespace Tmw

package provide tmw::platform 2.0.0

# testcode
Tmw::platform .p
