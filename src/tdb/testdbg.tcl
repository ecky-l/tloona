lappend auto_path ..

package require tloonadebug
package require parser
package re -exact Itcl 3.4
namespace import ::itcl::*



namespace eval xx {
    proc dummy {args} {
        set x 0
        lassign [info commands] cmd1 cmd2 cmd3
        for {set i 0} {$i < 5} {incr i} {
            incr x $i
        }
        puts hi,$args
    }
}

xx::dummy 1 1 2

::Debugger::SetProcDebug xx::dummy
xx::dummy 1 2 3

::Debugger::UnsetProcDebug xx::dummy
xx::dummy 1 2 3

#TestDebug
