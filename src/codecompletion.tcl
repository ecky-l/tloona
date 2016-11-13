## codecompletion.tcl (created by Tloona here)
package require snit 2.3.2

namespace eval Tloona {

# @c Represents a completion box with commands or variables
# @c that can be inserted at the position where the box is
# @c popped up
snit::widget completor {
    hulltype toplevel
    
    #### Options
    
    ## \brief the root text window where the completor applies
    option -textwin ""
    option -forced 0
    option -autohidetime 5000
    
    #### Components
    component list
    delegate method * to list
    delegate option -background to list
    delegate option -relief to list
    delegate option -borderwidth to list
    delegate option -foreground to list
    
    #### Variables
    variable _Bindings
    array set _Bindings {}
    
    variable _Word ""
    
    ## \brief indicates whether the completor is showing
    variable Showing 0
        
    constructor {args} {
        wm overrideredirect $win 1
        wm withdraw $win
        
        install list using listbox $win.lb -height 10 -width 20
        $self configure -background white -relief flat -borderwidth 0
        
        set vs [ttk::scrollbar $win.vscroll -command [list $list yview]]
        $list configure -yscrollcommand [list $vs set]
        
        grid $list -row 0 -column 0 -sticky news
        grid $vs -row 0 -column 1 -sticky nse
        
        $self configurelist $args
    }
    
    ## \brief getter for the list
    method list {} {
        return $list
    }
    
    ## \brief set the items in the completor box list of the items
    method setItems {items} {
        set _Word ""
        $self delete 0 end
        $self insert end {*}$items
    }
        
    # @r the items in the completor box or an empty list
    method getItems {} {
        $self get 0 end
    }
        
    ## \brief Shows the completor box at the given x and y position.
    #
    # The coordinates are relative to the textwin window, which is the root 
    # of the completor box
    #
    # \param x 
    #    rel x coordinate
    # \param y 
    #    rel y coordinate
    # \param noSpace 
    #    if set to true, spaces are not allowed and the completion list entries 
    #    are always treated as new words
    method show {x y {noSpace 0}} {
        if {$Showing} {
            $self hide
        }
        # if the completion list is empty (no suggestions to make), do nothing.
        if {[$self getItems] == {}} {
            return
        }
        
        set xc [expr {[winfo rootx $options(-textwin)] + $x}]
        set yc [expr {[winfo rooty $options(-textwin)] + $y}]
        
        # backup orginal bindings. We're going to bind
        # other scripts
        set _Bindings(Up) [bind $options(-textwin) <Key-Up>]
        set _Bindings(Down) [bind $options(-textwin) <Key-Down>]
        set _Bindings(Return) [bind $options(-textwin) <Key-Return>]
        set _Bindings(KeyRelease) [bind $options(-textwin) <KeyRelease>]
        set _Bindings(FocusOut) [bind $options(-textwin) <FocusOut>]
        set _Bindings(Key-Escape) [bind $options(-textwin) <Key-Esc>]
        
        bind $options(-textwin) <Key-Up> "[mymethod Select up] ; break"
        bind $options(-textwin) <Key-Down> "[mymethod Select down] ; break"
        bind $options(-textwin) <Key-Return> "[mymethod Insert] ; break"
        bind $options(-textwin) <KeyRelease> "[mymethod Update %K] ; break"
        bind $options(-textwin) <Key-Escape> "[mymethod hide] ; break"
        
        bind $options(-textwin) <FocusOut> [list apply {{W t} {
            after $t
            if {[focus] != [$W list]} {
                $W hide
            }
        }} $self $options(-autohidetime)]
        
        bind $list <Key-Return> [mymethod Insert]
        bind $list <Double-Button-1> [mymethod Insert]
        bind $list <KeyPress> [list $options(-textwin) fastinsert insert %A]
        bind $list <KeyRelease> [mymethod Update %K]
        bind $list <Key-Escape> [mymethod hide]
        
        # save the characters just before insert
        set ci [$options(-textwin) index "insert -1c"]
        set c [$options(-textwin) get "$ci wordstart" "$ci wordend"]
        if {[regexp {[\w:]+} $c]} {
            set _Word $c
        }
        if {$noSpace} {
            set _Word ""
        }
        
        # show the list with entries to select
        wm geometry $win +$xc+$yc
        wm deiconify $win
        raise $win
        focus -force $options(-textwin).t
        set Showing 1
    }
        
    ## \brief Hides the completion box and restores bindings on the text window
    method hide {args} {
        if {! $Showing} {
            return
        }
        
        wm withdraw $win
        #wm attributes [namespace tail $this] -topmost no
        bind $options(-textwin) <Key-Up> $_Bindings(Up)
        bind $options(-textwin) <Key-Down> $_Bindings(Down)
        bind $options(-textwin) <Key-Return> $_Bindings(Return)
        bind $options(-textwin) <KeyRelease> $_Bindings(KeyRelease)
        bind $options(-textwin) <FocusOut> $_Bindings(FocusOut)
        bind $options(-textwin) <Key-Escape> $_Bindings(Key-Escape)
        focus -force $options(-textwin).t
        set Showing 0
    }
    
    method Select {updown} {
        set act [$self index active]
        $self selection clear $act
        switch -- $updown {
        Up -
        up {
            incr act -1
            if {$act < 0} {
                set act [$self index end]
            }
        }
        
        Down -
        down {
            incr act
            if {$act >= [$self index end]} {
                set act 0
            }
        }
        }
        
        $self activate $act
        $self selection set $act
        $self see $act
        
        #focus -force $L
    }
    
    method Update {key} {
        set lchar [$options(-textwin) get "insert -1c" "insert"]
        switch -- $key {
            Shift_L -
            Shift_R -
            Alt_L  {
                # do nothing
            }
            
            Up -
            Down - 
            up -
            down {
                return
            }
            
            Control_L -
            Control_R -
            Control {
                return
            }
            space -
            less - ?? {
                if {$options(-forced)} {
                    return
                }
            }
            
            default {
                append _Word $lchar
            }
        }
        
        set poss [$self get 0 end]
        
        set gvar [regexp {^\$::} $_Word]
        set wd [string trimleft $_Word \$]
        set wd [string trimleft $wd :]
        
        set newPoss {}
        set idcs {}
        if {$gvar} {
            set idcs [lsearch -all -regexp $poss "^::$wd"]
        } else {
            set idcs [lsearch -all -regexp $poss "^$wd"]
        }
        
        foreach {i} $idcs {
            lappend newPoss [lindex $poss $i]
        }
        
        if {$newPoss == {} && ! $options(-forced)} {
            set _Word ""
            $self hide
            focus -force $options(-textwin).t
            return
        }
        
        $self delete 0 end
        eval $self insert end $newPoss
        $self activate 0
        $self selection set 0
        
        set options(-forced) 0
    }
    
    method Insert {} {
        $self hide
        focus -force $options(-textwin).t
        
        set sel [$self get active]
        set nre ""
        if {[regexp {^\$} $_Word]} {
            regexp {([\w:]+)} $_Word m nre
        } else {
            regsub {^::} $sel {} sel
            regexp {(\w+)} $_Word m nre
        }
        
        set ln [string length $nre]
        set toIns [string range $sel $ln end]
        
        $options(-textwin) fastinsert insert $toIns
        $options(-textwin) highlight "insert linestart" "insert lineend"
        
        event generate $options(-textwin) <<InsCompletion>>
    }
} ;# completor


} ;# namespace Tloona

package provide tloona::codecompletion 2.0.0
