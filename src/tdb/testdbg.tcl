lappend auto_path ..

package require tdb
package require parser
package re -exact Itcl 3.4
namespace import ::itcl::*



namespace eval xx {
    proc dummy {args} {
        #set x 0
        #lassign [info commands] cmd1 cmd2 cmd3
        for {set i 0 ; set j 1} {$i < 5} {incr i} {
            incr x $i
            for {set j 1} {$j < 10} {incr j} {
                incr x $j
            }
        }
        puts $j
        if {$x > 4} {
            puts huha
        } else {
            incr x 2
        }
        puts hi,$args,$x
    }
}

xx::dummy 1 2

::Tdb::SetProcDebug xx::dummy
xx::dummy 1 2 3
::Tdb::UnsetProcDebug xx::dummy

#TestDebug
