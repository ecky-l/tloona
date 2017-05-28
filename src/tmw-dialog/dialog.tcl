## dialog.tcl (created by Tloona here)
package require snit 2.3.2

namespace eval ::Tmw {

## \brief A generic dialog widget
#
# Pops up a modal dialog with a childsite where other widgets
# can be placed. If the -block option is set, the application
# is blocked until the dialog is closed with one of the buttons
::snit::widget dialog {
    hulltype toplevel
    
    option -title -default tmw-dialog -configuremethod ConfigSetTitle
    option -buttonpos -default center -configuremethod ConfigButtonPos
    option -master -default . -configuremethod ConfigMaster
    option -block -default yes -configuremethod ConfigBlock
    option {-buttonpadx buttonPadx Padx} -default 1 -configuremethod ConfigButtonPadx
    option {-buttonpady buttonPady Pady} -default 1 -configuremethod ConfigButtonPady
    
    component buttonbox
    component childsite
    
    ### variables
    variable Wait {}
    
    constructor {args} {
        install childsite as ttk::frame $self.childsite
        ttk::separator $self.sep -orient horiz
        install buttonbox as ttk::frame $self.buttonbox
        
        pack $childsite -expand yes -fill both -padx 1 -pady 1
        pack $self.sep -expand n -fill x -pady 5 -padx 1
        pack $buttonbox -expand no -fill none -padx 1 -pady 1
        
        wm resizable $win 0 0
        $self configurelist $args
        $self hide
    }
    
    destructor {
        grab release $win
    }
    
    ### public
    
    ## \brief Center the dialog relative to a master window
    method center {{masterwin ""}} {
        if {$masterwin == ""} {
            set masterwin [namespace tail $options(-master)]
        }
        
        update
        set yx0 [winfo rootx $masterwin]
        set yy0 [winfo rooty $masterwin]
        set yw [winfo width $masterwin]
        set yh [winfo height $masterwin]
        
        # if the window is not mapped yet, take the
        # requested width/height instead of the real
        # width/height
        set mw [winfo reqwidth $win]
        set mh [winfo reqheight $win]
        if {[winfo ismapped $win]} {
            set mw [winfo width $win]
            set mh [winfo height $win]
        }
        
        set mx0 [expr {round(($yx0 + .5 * $yw) - .5 * $mw)}]
        set my0 [expr {round(($yy0 + .5 * $yh) - .5 * $mh)}]
        
        wm geometry $win "+$mx0+$my0"
    }
    
    ## \brief Add a button to the dialog. 
    #
    # \param tag
    #    A tag for the button. The button itself is constructed as sub
    #    window below the buttonbox component named <tag> in lower case
    #    The text on the button is equal to <tag> unless a -text option
    #    is specified in the args
    # \param args
    #    Additional args as accepted by ttk::button
    #
    # \return The button window path
    method add {tag args} {
        set t [string tol $tag]
        if {[winfo exists $buttonbox.$t]} {
            return -code error "$tag already exists"
        }
        
        set nowait 0
        if {[set i [lsearch $args -nowait]] >= 0} {
            set nowait 1
            lvarpop args $i
        }
        
        ttk::button $buttonbox.$t -text $tag {*}$args
        pack $buttonbox.$t -side left -padx 3 -pady 3
        
        if {! $nowait} {
            bind $buttonbox.$t <Button-1> +[list $self pressed $tag]
        }
        return $buttonbox.$t
    }
        
    ## \brief Shows the dialog on the screen and sets a local grab to it.
    method show {} {
        wm transient $win $options(-master)
        $self center
        wm deiconify $win
        grab set $win
        if {$options(-block)} {
            tkwait variable [myvar Wait]
            return $Wait
        }
    }
    
    method hide {} {
        grab release $win
        wm withdraw $win
    }
    
    method childsite {args} {
        if {$args == {}} {
            return $childsite
        }
        $childsite {*}$args
    }
    
    method buttonconfigure {tag args} {
        set t [string tol $tag]
        if {![winfo exists $buttonbox.$t]} {
            return -code error "$tag does not exist"
        }
        $buttonbox.$t configure {*}$args
    }
    
    method pressed {{tag ""}} {
        if {$tag == ""} {
            return $Wait
        }
        set Wait $tag
    }
    
    ### private
    
    ## \brief configuremethod for -buttonpos
    method ConfigButtonPos {option value} {
        set options($option) $value
        switch -glob -- $value {
        c* {
            pack configure $buttonbox -side top
        }
        w* {
            pack configure $buttonbox -side left
        }
        e* {
            pack configure $buttonbox -side right
        }
        default {
            error "wrong button pos, must be w, e or c"
        }
        }
    }
    
    ## \brief configuremethod for -master
    method ConfigMaster {option value} {
        set options($option) $value
        if {![winfo exists $value] || ![winfo ismapped $value]} {
            return
        }
        wm transient $win $value
        update
        $self center
    }
    
    ## \brief configuremethod for block
    method ConfigBlock {option value} {
        set options($option) $value
        if {$value} {
            wm protocol $win WM_DELETE_WINDOW [list $self pressed Close]
        } else {
            wm protocol $win WM_DELETE_WINDOW [list $self hide]
        }
    }
    
    ## \brief configuremethod for -title
    method ConfigSetTitle {option value} {
        set options($option) $value
        wm title $win $value
    }
    
    method ConfigButtonPadx {option value}  {
        set options($option) $value
        pack configure $buttonbox -padx $value
    }
    
    method ConfigButtonPady {option value} {
        set options($option) $value
        pack configure $buttonbox -pady $value
    }    
}

# \brief Displays a message dialog
#
# \param master 
#    master of the message box
# \param title
#    title of the message box
# \param type
#    type of the message box - one of ok, cancel, okcancel, yes,
#    yesno yesnocancel
# \param msg
#    Message to display
# \param icon
#    an image icon
proc ::Tmw::message {master title type msg {icon ""}} {
    Tmw::dialog .dlg -title $title -master $master
    switch -- $type {
        ok {
            .dlg add ok -text "Ok"
        }
        okcancel {
            .dlg add ok -text "Ok"
            .dlg add cancel -text "Cancel"
        }
        yes {
            .dlg add yes -text "Yes"
        }
        yesno {
            .dlg add yes -text "Yes"
            .dlg add no -text "No"
        }
        yesnocancel {
            .dlg add yes -text "Yes"
            .dlg add no -text "No"
            .dlg add cancel -text "Cancel"
        }
            
    }
        
    if {$icon != ""} {
        # create icon
    }
    
    pack [ttk::label [.dlg childsite].l -text $msg] -expand y \
        -fill both -padx 10 -pady 10
    set res [.dlg show]
    destroy .dlg
    return $res
}

## \brief Displays an input dialog and returns the input
proc ::Tmw::input {master title type} {
    Tmw::dialog .dlg -title $title -master $master
    switch -- $type {
        ok {
            .dlg add ok -text "Ok"
        }
        okcancel {
            .dlg add ok -text "Ok"
            .dlg add cancel -text "Cancel"
        }
        default {
            error "Wrong type, must be ok or okcancel"
        }
    }
    
    set ::Tmw::Inputvar ""
    pack [ttk::entry [.dlg childsite].e -textvariable ::Tmw::Inputvar] \
        -expand y -fill x
    bind [.dlg childsite].e <Return> [list .dlg pressed ok]
    
    set res [.dlg show]
    set tmp $::Tmw::Inputvar
    unset ::Tmw::Inputvar
    destroy .dlg
    if {$res == "cancel"} {
        return ""
    }
    return $tmp
}


} ;# namespace Tmw

package provide tmw::dialog 2.0.0
