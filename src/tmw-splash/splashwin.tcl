
package require Tk
package require Img

namespace eval Tmw {

namespace eval SplashWin {
    variable RootDir [file normalize [file dirname [info script]]]
    variable window
    
    variable MessageFont {Helvetica 12}
    variable Message "Welcome"
    
    variable AnimateDelay 500
    variable DoAnimate no
    variable AnimateImages {}
    variable AnimateItem {}
    
    variable Progress 0
    
    variable DestroyMe no
}
    
}

proc Tmw::SplashWin::Center {path} {
    update idletasks
    set w [winfo reqwidth  $path]
    set h [winfo reqheight $path]
    set sw [winfo screenwidth  $path]
    set sh [winfo screenheight $path]
    set x0 [expr {([winfo screenwidth  $path] - $w)/2 - [winfo vrootx $path]}]
    set y0 [expr {([winfo screenheight $path] - $h)/2 - [winfo vrooty $path]}]
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
proc Tmw::SplashWin::LoadDefaultImages {} {
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

## \brief Creates the splash window
# 
# This is the window all other commands are referring to later
proc Tmw::SplashWin::Create {args} {
    variable AnimateImages
    variable AnimateItem
    variable DoAnimate
    variable MessageFont
    
    wm withdraw .
    toplevel .s
    wm withdraw .s
    
    if {![dict exist $args -images]} {
        LoadDefaultImages
    } else {
        set AnimateImages [dict get $args -images]
    }
    
    set img [lindex $AnimateImages 0]
    set height [image height $img]
    set width [image width $img]
    
    ttk::label .s.m -anchor center -justify center -textvariable ::Tmw::SplashWin::Message 
    canvas .s.c -width $width -height $height
    set AnimateItem [.s.c create image 0 0 -anchor nw -image $img]
    pack .s.m .s.c -side top -expand y -fill both
    if {[dict exist $args -showprogress] && [dict get $args -showprogress]} {
        ttk::progressbar .s.progress -variable ::Tmw::SplashWin::Progress \
            -orient horizontal
        pack .s.progress -side top -expand y -fill x
    }
    Center .s
    wm overrideredirect .s 0
    wm attributes .s -topmost 1
    wm resizable .s 0 0
    wm deiconify .s
    
    update
    set DoAnimate on
    Animate 0
}

proc Tmw::SplashWin::SetProgress {value} {
    variable Progress
    set Progress $value
    update
}

## \brief Send a message to the splash window
proc Tmw::SplashWin::SetMessage {value} {
    variable Message
    set Message $value
    update
}

proc Tmw::SplashWin::Animate {nImg} {
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
    after $AnimateDelay ::Tmw::SplashWin::Animate $nImg
    update
}

proc Tmw::SplashWin::Destroy {args} {
    variable AnimateImages
    variable DoAnimate
    variable DestroyMe
    
    set DestroyMe yes
    set DoAnimate off
    destroy .s
    image delete {*}$AnimateImages
    
}


package provide tmw::splashwin 1.0

