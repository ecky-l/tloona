
set auto_path [concat [file join [file dirname [info script]] .. ..] \
    $::auto_path]

package re tmw::mainapp

Tmw::mainapp .m -width 800 -height 500
pack [label [.m mainframe].l -text hya -background red] \
    -expand y -fill both
#after 2000 {.m toolbar maintoolbar -pos w}
#after 4000 {.m toolbar maintoolbar -pos e}
#after 6000 {.m toolbar maintoolbar -pos s}
#after 8000 {.m toolbar maintoolbar -pos n}
after 2000 {.m hideToolbar maintoolbar}
after 4000 {.m showToolbar maintoolbar}
.m toolbutton close -toolbar maintoolbar -type checkbutton \
    -image $Tmw::Icons(FileClose) -stickto back -separate 0
