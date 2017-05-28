set Root [file dirname [info script]]
set auto_path [concat [file join $Root .. ..] $auto_path]

package re web::parser 1.0
package re struct::queue

proc parseCommand {args} {
     foreach {tag slash param text} $args {break}
     puts "=> tag='$tag' slash='$slash' param='$param' text='$text'"

} 

set fh [open [file join $Root test.html] r]
set content [read $fh]
close $fh

htmlparse::parse -cmd parseCommand $content
