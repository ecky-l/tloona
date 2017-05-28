## platform.tcl (created by Tloona here)
package require snit 2.3.2

package require tmw::toolbarframe 2.0.0
package require tmw::icons 1.0

namespace eval ::Tmw {

## \brief Main application Megawidget. 
# 
# It contains methods to create menus, toolbars and a status line. The toolbar functionality 
# is delegated to a Toolbarframe megawidget inside. Menu entries can be displayed in the main 
# menu and in a main toolbar simultaneously, via the [menuentry] method. The builtin statusline 
# contains a status message label (can be configured via the -status variable) and a progress 
# indicator that can be displayed on demand. By default it is hidden.
::snit::widget platform {
    hulltype toplevel
    delegate option -mainmenu to hull as -menu
    
    ## \brief The toolbar frame that serves as main frame. Everything is in this frame.
    component mainframe
    delegate method toolbar to mainframe
    delegate method toolbutton to mainframe
    delegate method tbshow to mainframe
    delegate method tbhide to mainframe
    delegate method childsite to mainframe
    delegate option -mainrelief to mainframe as -relief
    delegate option -mainbd to mainframe as -borderwidth
    delegate option -width to mainframe
    delegate option -height to mainframe
    
    component mainmenu
    
    component action
    
    ## \brief The status line. Contains a status message and a progress indicator.
    component statusline
    delegate option -statusrelief to statusline as -relief
    delegate option -statusbd to statusline as -borderwidth
    delegate option -statusheight to statusline as -height
    
    component progress
    delegate option -progressmode to progress as -mode
    delegate option -progresslength to progress as -length
    
    ### Options
    option -title -default tmw-platform -configuremethod ConfigSetTitle
    option -status hello
    option -createdefaultmenu false
    option -progressincr 10
    
    #### variables
    variable Menus
    array set Menus {}
    
    constructor {args} {
        install mainmenu as menu $self.mainmenu -tearoff no -relief raised
        install mainframe as Tmw::toolbarframe $self.mainframe
        #$mainframe configure -background red
        pack $mainframe -expand yes -fill both
        $self configure -mainrelief flat -mainbd 1
        
        $self AddStatusLine
        if {[lsearch $args -createdefaultmenu] >= 0} {
            $self AddDefaultMenu
        }
        
        wm protocol $self WM_DELETE_WINDOW [mymethod onQuit]
        
        $self configure -mainmenu $mainmenu
        $self configurelist $args
    }
    
    #### Public 
    
    ## \brief Create a menu entry
    #
    # The menuentry is at the same time added to the main toolbar
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
        set sName $mainmenu.[string tolower $name]
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
                bind $win <[set accel]> $cmd
            }
            
            return
        }
        
        # type must be given here
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
        
        if {$type != "separator"} {
            # set some arguments if not present
            if {[lsearch $nargs -image] >= 0 && [lsearch $args -compound] < 0} {
                lappend nargs -compound left
            }
            if {[lsearch $nargs -label] < 0} {
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
            set toolButton [$self toolbutton $name -type $type -toolbar $toolbar {*}$nargs]
            
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
            bind $win <[set accel]> $cmd
        }
        
        list $parentMenu [$parentMenu index last] $toolButton $toolMenu
    }
    
    ## \brief Shows the progress bar in the status line. 
    #
    # This is a ttk::progress widget right next to the status information in determinate mode 
    # (by default). The mode can be configured via the -progressmode option
    #
    # \param show 
    #    0 for hide, 1 for show the progress bar. If left empty (the default), this method 
    #    returns whether the progress bar is showing right now
    method showProgress {{show -1}} {
        set prgShow [expr { [lsearch [pack slaves $statusline] $progress] >= 0 } ]
        if {$show < 0} {
            return $prgShow
        }
        
        if {$show} {
            if {$prgShow} {
                # progress already showing
                return $prgShow
            }
            
            pack $progress -before $action -fill x -expand n -side right -padx 3
            $progress start $options(-progressincr)
        } else {
            if {! $prgShow} {
                # progress already hidden
                return $prgShow
            }
            $progress stop
            pack forget $progress
        }
        
        return $show
    }
    
    ## \brief callback handler for exiting the application. 
    #
    # This method is connected to the File.Quit menuentry in the default application menu 
    # and to the close button. Clients may override.
    method onQuit {} {
        ::exit
    }
    
    ## \brief Callback handler for default File.New menu entry. 
    #
    # Needs to be overridden
    method onFileNew {} {}
    
    ## \brief Callback handler for default File.Open menu entry. 
    method onFileOpen {} {}
    
    ## \brief Callback handler for default File.Save menu entry. 
    method onFileSave {} {}
    
    ## \brief Callback handler for default File.Close menu entry. 
    method onFileClose {} {}
    
    ## \brief Callback handler for default Edit.Undo menu entry.
    method onEditUndo {} {}
    
    ## \brief Callback handler for default Edit.Redo menu entry.
    method onEditRedo {} {}
    
    ## \brief Callback handler for default Edit.Cut menu entry.
    method onEditCut {} {}
    
    ## \brief Callback handler for default Edit.Copy menu entry.
    method onEditCopy {} {}
    
    ## \brief Callback handler for default Edit.Paste menu entry.
    method onEditPaste {} {}
        
    #### Private 
    
    ## \brief configure method for title
    method ConfigSetTitle {option value} {
        set options($option) $value
        wm title $win $value
    }
    
    ## \brief Creates and adds the status line at the bottom of the window
    method AddStatusLine {} {
        install statusline using ttk::frame $self.statusline
        install action using ttk::label $statusline.action -textvar [myvar options(-status)]
        install progress using ttk::progressbar $self.progress
        #ttk::label $statusline.action -textvar [myvar Status]
        set sep1 [ttk::separator $statusline.s1 -orient vertical]
        pack $statusline.action -fill x -expand n -side right -padx 3
        pack $sep1 -fill y -expand n -side right -padx 5 -pady 2
        pack $statusline -side bottom -expand no -fill x
        $self configure -statusrelief flat -statusbd 0 -statusheight 20 \
            -progressmode determinate -progresslength 40
    }
    
    ## \brief create a default menu
    method AddDefaultMenu {} {
        $self toolbar maintoolbar -pos n -compound none
        $self menuentry File.New -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileNew) -command [list $self onFileNew] \
            -accelerator Ctrl-n
        $self menuentry File.Open -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileOpen) -command [list $self onFileOpen] \
            -accelerator Ctrl-o
        $self menuentry File.Save -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileSave) -command [list $self onFileSave] \
            -accelerator Ctrl-s
        $self menuentry File.Close -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileClose) -command [list $self onFileClose] \
            -accelerator Ctrl-w
        $self menuentry File.Sep0 -type separator -toolbar maintoolbar
        $self menuentry File.Quit -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActExit) -command [list $self onQuit] \
            -accelerator Ctrl-q
        
        $self menuentry Edit.Undo -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActUndo) -command [list $self onEditUndo] \
            -accelerator Ctrl-z
        $self menuentry Edit.Redo -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActRedo) -command [list $self onEditRedo] \
            -accelerator Ctrl-r
        $self menuentry Edit.Sep0 -type separator -toolbar maintoolbar
        $self menuentry Edit.Cut -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditCut) -command [list $self onEditCut] \
            -accelerator Ctrl-x
        $self menuentry Edit.Copy -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditCopy) -command [list $self onEditCopy] \
            -accelerator Ctrl-c
        $self menuentry Edit.Paste -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditPaste) -command [list $self onEditPaste] \
            -accelerator Ctrl-v
    }
}

} ;# namespace Tmw

package provide tmw::platform 2.0.0

# testcode
#package re Tk
#wm withdraw .
#Tmw::platform .p -createdefaultmenu y -width 800 -height 600 -status ready
