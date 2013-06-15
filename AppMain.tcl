#
# This file opens Tloona from an double-clickable Tloona.app application on
# Mac OSX. See http://wiki.tcl.tk/12987 for instructions how to do that
# Basically these steps:
#   - copy Wish.app from /Applications/Utilities to somewhere else
#   - Display package contents (right click)
#   - Move the tloona-<ver> source directory to the Contents/Resources directory
#   - Copy tloona.icns file from tloona-<ver> to Contents/Resources/Wish.icns
#   - Rename the Tloona source directory to "Scripts"
#   - Close the Finder with that directory and rename it to "Tloona"
#   - Drag the new Tloona.app to /Applications 
#   - Log out and in again
# 
# Now you should be able to open Tloona by double click in the Applications
# folder and to open .vfs directories and .tcl files with Tloona (right click)
#
proc ::tk::mac::OpenDocument {args} {
    # args will be a list of all the documents dropped on your app, 
    # or double-clicked
    global TloonaApplication
    foreach {file} $args {
	$TloonaApplication openFile $file 1
    }
}

if {[string first "-psn" [lindex $argv 0]] == 0} {
    set argv [lrange $argv 1 end]
}
if [catch {source [file join [file dirname [info script]] main.tcl]}] {
    puts $errorInfo
}

