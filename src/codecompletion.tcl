#
# codecompletion.itk
#

package require Itcl 3.3
package require Itk 3.3
package require tile 0.7.2

package provide tloona::codecompletion 1.0


catch {
    namespace import ::itcl::*
    namespace import ::itk::*
}

itk::usual Completor {
    keep -background -relief -borderwidth
    keep -foreground
}

# @c Represents a completion box with commands or variables
# @c that can be inserted at the position where the box is
# @c popped up
class ::Tloona::Completor {
    inherit ::itk::Toplevel
    
    # @v textwin: the root text window where the completor applies
    public variable textwin ""
    
    public variable forced 0
    
    private variable _Bindings
    array set _Bindings {}
    
    private variable _Word ""
    
    # @v Showing: indicates whether the completor is showing
    private variable Showing 0
        
    constructor {args} {
        wm overrideredirect $itk_interior 1
        wm withdraw [namespace tail $this]
        
        itk_component add list {
            listbox $itk_interior.lb -height 10 -width 20
        } {
            keep -background -relief -borderwidth
            keep -foreground
        }
        
        itk_initialize -background white -relief flat \
            -borderwidth 0
        
        set L [component list]
        set vs [ttk::scrollbar $itk_interior.vscroll -class TScrollbar \
            -command [list $L yview]]
        component list configure -yscrollcommand [list $vs set]
        
        grid [component list] -row 0 -column 0 -sticky news
        grid $vs -row 0 -column 1 -sticky nse
        
        eval itk_initialize $args
    }
    
        
    # @c set the items in the completor box
    # @a items: list of the items
    public method setItems {items} {
        set _Word ""
        set L [component list]
        $L delete 0 end
        eval $L insert end $items
    }
        
    # @r the items in the completor box or an empty list
    public method getItems {} {
        component list get 0 end
    }
        
    # @c Shows the completor box at the given x and y position.
    # @c The coordinates are given as relative coordinates to the
    # @c textwin window, which is the root of the completor box
    #
    # @a x: rel x coordinate
    # @a y: rel y coordinate
    # @a noSpace: if set to true, spaces are not allowed and the
    # @a noSpace: completion list entries are always treated as new words
    public method show {x y {noSpace 0}} {
        if {$Showing} {
            hide
        }
        # if the completion list is empty (that is, no suggestions 
        # to make), do nothing.
        if {[getItems] == {}} {
            return
        }
        
        set xc [expr {[winfo rootx $textwin] + $x}]
        set yc [expr {[winfo rooty $textwin] + $y}]
        
        # backup orginal bindings. We're going to bind
        # other scripts
        set _Bindings(Up) [bind $textwin <Key-Up>]
        set _Bindings(Down) [bind $textwin <Key-Down>]
        set _Bindings(Return) [bind $textwin <Key-Return>]
        set _Bindings(KeyRelease) [bind $textwin <KeyRelease>]
        set _Bindings(FocusOut) [bind $textwin <FocusOut>]
        set _Bindings(Key-Escape) [bind $textwin <Key-Esc>]
        
        bind $textwin <Key-Up> "[code $this _select up]; break"
        bind $textwin <Key-Down> "[code $this _select down]; break"
        bind $textwin <Key-Return> "[code $this _insert]; break"
        bind $textwin <KeyRelease> [code $this _update %K]
        bind $textwin <Key-Escape> [code $this hide]
        
        set script "if \{\[focus\] != \"[component list]\"\} \{$this hide\}\n"
        bind $textwin <FocusOut> [list after 5000 $script]
        
        set L [component list]
        bind $L <Key-Return> [code $this _insert]
        bind $L <Double-Button-1> [code $this _insert]
        bind $L <KeyPress> [list $textwin fastinsert insert %A]
        bind $L <KeyRelease> [code $this _update %K]
        bind $L <Key-Escape> [code $this hide]
        
        # save the characters just before insert
        set ci [$textwin index "insert -1c"]
        set c [$textwin get "$ci wordstart" "$ci wordend"]
        if {[regexp {[\w:]+} $c]} {
            set _Word $c
        }
        if {$noSpace} {
            set _Word ""
        }
        
        # show the list with entries to select
        set mywin [component hull]
        wm geometry $mywin +$xc+$yc
        wm deiconify $mywin
        raise $mywin
        focus -force $textwin.t
        set Showing 1
    }
        
    # @c Hides the completion box and restores bindings on the text window
    public method hide {args} {
        if {! $Showing} {
            return
        }
        
        wm withdraw [namespace tail $this]
        #wm attributes [namespace tail $this] -topmost no
        bind $textwin <Key-Up> $_Bindings(Up)
        bind $textwin <Key-Down> $_Bindings(Down)
        bind $textwin <Key-Return> $_Bindings(Return)
        bind $textwin <KeyRelease> $_Bindings(KeyRelease)
        bind $textwin <FocusOut> $_Bindings(FocusOut)
        bind $textwin <Key-Escape> $_Bindings(Key-Escape)
        focus -force $textwin.t
        set Showing 0
    }
    
    private method _select {updown} {
        set L [component list]
        set act [$L index active]
        $L selection clear $act
        switch -- $updown {
            "Up" -
            "up" {
                incr act -1
                if {$act < 0} {
                    set act [$L index end]
                }
            }
            
            "Down" -
            "down" {
                incr act
                if {$act >= [$L index end]} {
                    set act 0
                }
            }
        }
        
        $L activate $act
        $L selection set $act
        
        focus -force $L
    }
    
    private method _update {key} {
        set lchar [$textwin get "insert -1c" "insert"]
        
        switch -- $key {
            Shift_L -
            Shift_R -
            Alt_L {
                # do nothing
            }
            
            Up -
            Down -
            Control_L -
            Control_R {
                return
            }
            space -
            less {
                if {$forced} {
                    return
                }
            }
            
            default {
                append _Word $lchar
            }
        }
        
        set lb [component list]
        set poss [$lb get 0 end]
        
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
        
        if {$newPoss == {} && ! $forced} {
            set _Word ""
            hide
            focus -force $textwin.t
            return
        }
        
        $lb delete 0 end
        eval $lb insert end $newPoss
        $lb activate 0
        $lb selection set 0
        
        set forced 0
    }
    
    private method _insert {} {
        hide
        focus -force $textwin.t
        
        set sel [component list get active]
        set nre ""
        if {[regexp {^\$} $_Word]} {
            regexp {([\w:]+)} $_Word m nre
        } else {
            regsub {^::} $sel {} sel
            regexp {(\w+)} $_Word m nre
        }
        
        set ln [string length $nre]
        set toIns [string range $sel $ln end]
        
        $textwin fastinsert insert $toIns
        $textwin highlight "insert linestart" "insert lineend"
        
        event generate $textwin <<InsCompletion>>
    }
}





