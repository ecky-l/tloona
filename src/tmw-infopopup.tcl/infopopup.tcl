#
# infopopup.tcl
#
# procedure(s) that display a toplevel infopopup box
# that contains some text.
# To use it, just bind the event to the procedure

package require tile 0.7.5

package provide tmw::infopopup 1.0

namespace eval ::Tmw {}

proc ::Tmw::infopopup {args} {
    # @c displays an infopopup for a particular widget
    # @c usually, the <Enter> event is bind to this
    # @c procedure.
    # @c The given text is displayed in a label in the
    # @c popup, together with the image, if appropriate
    #
    # @a args: the arguments -widget w -coords {x y} 
    # @a args: -delay ms -text "" -image "" -imagepos [nswe]
    set widget ""
    set xc -1
    set yc -1
    set delay 0
    set text ""
    set image ""
    set imagepos w
    set data {}
    set hideEvent <Leave>
    set padx 5
    set pady 2
    
    # parse arguments
    while {$args != {}} {
        set aa [lindex $args 0]
        set args [lrange $args 1 end]
        switch -- $aa {
            -widget {
                set widget [lindex $args 0]
            }
            -leaveevent {
                set hideEvent [lindex $args 0]
            }
            -coords {
                set cc [lindex $args 0]
                if {[llength $cc] != 2} {
                    error "wrong coords, must be \{x y\}"
                }
                set xc [lindex $cc 0]
                set yc [lindex $cc 1]
            }
            -delay {
                set delay [lindex $args 0]
            }
            -text {
                set text [lindex $args 0]
            }
            -image {
                set image [lindex $args 0]
            }
            -data {
                set data [lindex $args 0]
            }
            -padding {
                set cc [lindex $args 0]
                set padx [lindex $cc 0]
                set pady [lindex $cc 1]
            }
            default {
                set e "wrong argument $aa should be -widget -coords "
                append e "-delay -text or -image"
                error $e
            }
        }
        set args [lrange $args 1 end]
    }
    
    if {$widget == ""} {
        error "must have a parent widget"
    }
    if {$xc < 0 || $yc < 0} {
        # popup is displayed below widget per default
        set xc [winfo rootx $widget]
        set yc [winfo rooty $widget]
        incr yc [winfo height $widget]
    }
    
    if {[winfo exists .tmw_infopopup]} {
        destroy .tmw_infopopup
    }
    
    set p [toplevel .tmw_infopopup -relief solid -borderwidth 1 \
        -background lightyellow]
    wm overrideredirect $p 1
    wm geometry $p +$xc+$yc
    wm withdraw $p
    
    
    if {$data == {}} {
        pack [label $p.l -text $text -background lightyellow] \
            -padx 5 -pady 2
    } else {
        if {[llength $data] % 2} {
            error "data must be even length"
        }
        
        set i 0
        foreach {k v} $data {
            set la [label $p.l[set i]1 -text $k -background lightyellow]
            set lb [label $p.l[set i]2 -text $v -background lightyellow]
            grid $la -row $i -column 0 -sticky e -padx $padx -pady $pady
            grid $lb -row $i -column 1 -sticky w -padx $padx -pady $pady
            incr i
        }
    }
    bind $widget $hideEvent {destroy .tmw_infopopup}
    after $delay [list wm deiconify $p]
    
}

