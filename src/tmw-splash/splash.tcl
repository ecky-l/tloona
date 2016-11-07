## \brief a splash screen

package require Tk

namespace eval Tmw {

namespace eval Splash {
    variable RootDir [file normalize [file dirname [info script]]]
    variable window
    
    variable MessageFont {Helvetica 12}
    variable Message "Welcome"
    
    variable AnimateDelay 500
    variable DoAnimate no
    variable AnimateImages {}
    variable AnimateItem {}
    
    variable Progress 0
}

}

proc Tmw::Splash::_Center {path} {
    update idletasks
    set w [winfo reqwidth  $path]
    set h [winfo reqheight $path]
    set sw [winfo screenwidth  $path]
    set sh [winfo screenheight $path]
    set vrx [expr {[winfo vrootx $path] < 0 ? 0 : [winfo vrootx $path]}]
    set vry [expr {[winfo vrooty $path] < 0 ? 0 : [winfo vrooty $path]}]
    set x0 [expr {($sw - $w)/2 - $vrx}]
    set y0 [expr {($sh - $h)/2 - $vry}]
    set x "+$x0"
    set y "+$y0"
    
    if {$::tcl_platform(platform) != "windows"} {
        if { ($x0 + $w) > $sw } {
            set x "-0"
            set x0 [expr {$sw - $w}]
        }
        if { $x0 < 0 } {
            set x "+0"
        }
        if { ($y0 + $h) > $sh } {
            set y "-0"
            set y0 [expr {$sh - $h}]
        }
        if { $y0 < 0 } {
            set y "+0"
        }
    }
    after idle wm geometry $path "${w}x${h}${x}${y}"
}

## \brief loads the default image
proc Tmw::Splash::_LoadDefaultImage {} {
    variable AnimateImages
    variable RootDir
    
    set nImg 0
    set imgFile [file join $RootDir tcllogo.gif]
    while {1} {
        set script "image create photo img[set nImg] "
        append script "-format \{gif -index $nImg \} "
        append script "-file $imgFile"
        if {[catch $script msg]} {
            break
        }
        lappend AnimateImages img[set nImg]
        incr nImg
    }
}

## \brief Animate the splash screen, if there is more than one image
proc Tmw::Splash::_Animate {nImg} {
    variable AnimateImages
    variable AnimateDelay
    variable AnimateItem
    variable DoAnimate
    
    #set DoAnimate $doit
    if {! $DoAnimate} {
        return
    }
    if {[llength $AnimateImages] <= 1} {
        return
    }
    
    set nImg [expr {$nImg % [llength $AnimateImages]}]
    set img [lindex $AnimateImages $nImg]
    incr nImg
    .s.c itemconfigure $AnimateItem -image $img
    after $AnimateDelay ::Tmw::Splash::Animate $nImg
    update
}


## \brief Creates a new splash window
#
# Initializes a background thread and creates a splash window in it.
# The window can then be manipulated by subsequent commands. It is threated
# as a singleton, effectively it should be the only splash window in an
# application
proc ::Tmw::Splash::Create {args} {
    variable AnimateImages
    variable AnimateItem
    variable DoAnimate
    variable MessageFont
    
    wm withdraw .
    toplevel .s
    if {[dict exists $args -title]} {
        wm title .s [dict get $args -title]
    }
    wm withdraw .s
    
    if {![dict exist $args -images]} {
        _LoadDefaultImage
    } else {
        set AnimateImages [dict get $args -images]
    }
    
    set img [lindex $AnimateImages 0]
    set height [image height $img]
    set width [image width $img]
    
    ttk::label .s.m -anchor center -justify center -textvariable ::Tmw::Splash::Message 
    canvas .s.c -width $width -height $height
    set AnimateItem [.s.c create image 0 0 -anchor nw -image $img]
    pack .s.m .s.c -side top -expand y -fill both
    if {[dict exist $args -showprogress] && [dict get $args -showprogress]} {
        ttk::progressbar .s.progress -variable ::Tmw::Splash::Progress \
            -orient horizontal
        pack .s.progress -side top -expand y -fill x
    }
    _Center .s
    #wm overrideredirect .s 0
    wm protocol .s WM_DELETE_WINDOW [list apply {{} exit}]
    
    wm attributes .s -topmost 1
    wm resizable .s 0 0
    wm deiconify .s
    
    update
    set DoAnimate on
    _Animate 0
}

proc ::Tmw::Splash::Destroy {} {
    variable AnimateImages
    variable DoAnimate
    variable DestroyMe
    
    set DestroyMe yes
    set DoAnimate off
    destroy .s
    image delete {*}$AnimateImages
}

proc ::Tmw::Splash::Progress {value} {
    variable Progress
    set Progress $value
    update
}

proc ::Tmw::Splash::Message {value} {
    variable Message
    set Message $value
    update
}

package provide tmw::splash 1.0

