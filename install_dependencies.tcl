foreach pkg {comm Img Itcl Itk log htmlparse ctext fileutil tdom starkit vfs::mk4 mk4vfs Tclx} {
    puts "Installing $pkg ..."
    puts [exec teacup install $pkg]
}
