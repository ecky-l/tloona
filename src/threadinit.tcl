# per thread initialization

package require Thread 2.6.3
package require parser::parse 1.0
package require debug 1.0
package require tmw::filesystem 1.0

#trace set exception -uncaught [list breakpoint dummy]

source [file normalize [file join $::TloonaRoot sdx.tcl]]

namespace eval ::log {
    proc log {level text} {
        set mThread [tsv::get Threads Main]
        thread::send $mThread [list Tloona::log $level $text]
    }
}
