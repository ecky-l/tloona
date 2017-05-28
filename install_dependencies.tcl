#
# dependencies:
# ?      src/img_png-1.3
# ?      src/Itk-3.4
# ?      src/htmlparse
# ?      src/thread2.6.5
# ?      src/zlibtcl-1.2.3
# ?      src/tdom-0.8.2
# ?      src/pngtcl-1.2.12
# ?      src/fileutil
# ?      src/log
# ?      src/struct
# ?      src/ctext
# ?      src/comm
# ?      src/tclx8.4
# ?      src/img_base-1.3
# ?      src/cmdline
# ?      src/snit
#
# If you want to create a starpack or starkit, include these directories
#
# Unfortunately the excellent sugar macro package is not available via
# teacup. Please download it from http://wiki.tcl.tk/11155 and install it
# manually. Alternatively you can copy the directory src/sugar0.1 somewhere
# to your tcl_pkgPath (execute "set tcl_pkgPath" in a tclsh to find out
# where your tclsh setup resolves packages)

foreach pkg {comm Img Itcl Itk log htmlparse ctext fileutil tdom starkit vfs::mk4 mk4vfs Tclx} {
    puts "Installing $pkg ..."
    puts [exec teacup install $pkg]
}


if {[catch package require sugar]} {
    puts {


# Unfortunately the excellent sugar macro package is not available via
# teacup. Please download it from http://wiki.tcl.tk/11155 and install it
# manually. Alternatively you can copy the directory src/sugar0.1 somewhere
# to your tcl_pkgPath (execute "set tcl_pkgPath" in a tclsh to find out
# where your tclsh setup resolves packages)

    }
}
