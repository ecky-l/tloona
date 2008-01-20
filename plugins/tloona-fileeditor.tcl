
package require tloona::file 1.0

plugin provide tloona-fileeditor 1.0 {
    extends tmw-platform editor Tloona::getEditorWindow
}

namespace eval ::Tloona {
}

proc ::Tloona::getEditorWindow {} {
    
}