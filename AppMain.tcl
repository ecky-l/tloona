console show

proc ::tk::mac::OpenDocument {args} {
     # args will be a list of all the documents dropped on your app, or double-clicked
}

if {[string first "-psn" [lindex $argv 0]] == 0} {
    set argv [lrange $argv 1 end]
}
console show
if [catch {source [file join [file dirname [info script]] main.tcl]}] {
    puts $errorInfo
}

