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

foreach pkg {comm Img Itcl Itk log htmlparse ctext fileutil tdom starkit vfs::mk4 mk4vfs Tclx} {
    puts "Installing $pkg ..."
    puts [exec teacup install $pkg]
}

