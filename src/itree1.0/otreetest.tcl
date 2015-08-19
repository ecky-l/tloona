## otreetest.tcl (created by Tloona here)
package require tcltest
namespace import tcltest::*

configure -verbose {body pass}

source otree.tcl

##
test createnode "Create a simple tree node" -body {
    set n [::otree::node new]
    info obj class $n
} -result ::otree::node -cleanup {$n destroy}

##
test attributes-1 "Attributes set at construct time" -body {
    set n [::otree::node new -name gagga]
    $n cget -name
} -result gagga -cleanup {$n destroy}

##
test attributes-2 "Attributes set later" -body {
    set n [::otree::node new]
    $n configure -name gagga
    $n cget -name
} -result gagga -cleanup {$n destroy}

##
test attributes-3 "Default attribute (level = 0)" -body {
    set n [::otree::node new]
    $n cget -level
} -result 0 -cleanup {$n destroy}

##
test addnode "Add node to a node" -body {
    set m [::otree::node new]
    set n [::otree::node new]
    info obj class [$m addChild $n]
} -result ::otree::node -cleanup {$n destroy}


##
test addnodes "Add more nodes" -setup {
    lmap v {m n o} {
        set $v [otree::node new]
    }
} -body {
    set r [$m addChildren $n $o]
    lmap v [list $n $o] {
        expr {$v in $r}
    }
} -result {1 1} -cleanup {
    lmap v [list $m $n $o] {
        $v destroy
    }
}

##
test addnodes_repeat "Multiple adding of same node returns empty" -body {
    lmap v {m n o} {
        set $v [otree::node new]
    }
    $m addChildren $n $o
    $m addChildren $n $o
} -result {} -cleanup {
    lmap v [list $m $n $o] {
        $v destroy
    }
}

##
test getchildren-1 "Get only direct children" -setup {
    lmap v {m n o p q} {
        set $v [otree::node new -dynamic 1]
    }
} -body {
    $m addChildren $n $o
    $n addChildren $p $q
    concat [lmap v [$m getChildren] w [$n getChildren] {
        expr { $v in [list $n $o] && $w in [list $p $q] }
    } ] [llength [$m getChildren]] [llength [$n getChildren]]
} -result {1 1 2 2} -cleanup {$m destroy}

##
test removechildren-1 "Remove some children" -setup {
    set m [otree::node new -dynamic 1]
    lmap v {n o p q} {
        set $v [otree::node new -dynamic 1]
    }
    $m addChildren $n $o $p $q
} -body {
    $m removeChildren $o $p
    lmap v [$m getChildren] {expr {$v in [list $n $q]}}
} -result {1 1} -cleanup {$m destroy}

##
test removechildren-2 "Remove all children" -setup {
    set m [otree::node new -dynamic 1]
    lmap v {n o p q} {
        set $v [otree::node new -dynamic 1]
    }
    $m addChildren $n $o $p $q
} -body {
    $m removeChildren
    $m getChildren
} -result {} -cleanup {$m destroy}

##
test getchildren-2 "Get recursive children" -setup {
    lmap v {m n o p q} {
        set $v [otree::node new -dynamic 1]
    }
    $m addChildren $n $o
    $n addChildren $p $q
} -body {
    concat [lmap v [$m getChildren 1] {
        expr { $v in [list $n $o $p $q] }
    }] [llength [$m getChildren 1]]
} -result {1 1 1 1 4} -cleanup {$m destroy}

##
test siblings "Get next and previous sibling" -setup {
    set m [otree::node new -dynamic 1]
    lmap v {n o p q} {
        set $v [otree::node new -dynamic 1]
    }
    $m addChildren $n $o $p $q
} -body {
    list [expr { [$n nextSibling] eq $o }] \
        [expr {[$p prevSibling] eq $o}]
} -result {1 1} -cleanup {$m destroy}

##
test findchildren "Filter nodes by predicate functions" -setup {
    lmap v {m n o p q r} {
        set $v [otree::node new -dynamic 1 -name $v]
    }
    $m addChildren $n $o $p
    $n addChildren $q $r
} -body {
    set filter1 {apply { {n} {expr {[$n cget -name] in {o p} }} }}
    set filter2 {apply { {n} {expr {[$n cget -name] in {n r} }} }}
    concat [lmap x [$m findChildren $filter1] { expr {$x in [list $o $p]} }] \
        [lmap x [$m findChildren $filter2 1] { expr {$x in [list $n $r]} }]
} -result {1 1 1 1} -cleanup {$m destroy}

##
test findparents-1 "Get all parents by predicate" -setup {
    set m [otree::node new -dynamic 1 -name m]
    lmap v {m n o p q} w {n o p q r} {
        set $w [otree::node new -dynamic 1 -name $w]
        [set $v] addChild [set $w]
    }
} -body {
    set filter1 {apply { {n} {expr {[$n cget -name] in {n p} }} }}
    lmap x [$r findParents $filter1] { expr {$x in [list $n $p]} }
} -result {1 1} -cleanup { $m destroy }

##
test findparents-2 "Get only the first parent mathcing a predicate" -setup {
    set m [otree::node new -dynamic 1 -name m]
    lmap v {m n o p q} w {n o p q r} {
        set $w [otree::node new -dynamic 1 -name $w]
        [set $v] addChild [set $w]
    }
} -body {
    set filter1 {apply { {n} {expr {[$n cget -name] in {n p} }} }}
    expr {[$r findParents $filter1 0] eq $p}
} -result 1 -cleanup { $m destroy }

##
test gettopnode "Get the top node via findParents" -setup {
    set m [otree::node new -dynamic 1 -name m]
    lmap v {m n o p q} w {n o p q r} {
        set $w [otree::node new -dynamic 1 -name $w]
        [set $v] addChild [set $w]
    }
} -body {
    set f {apply { {n} {expr {[$n getParent] eq "" }} }}
    expr {[$r findParents $f 0] eq $m}
} -result 1 -cleanup {$m destroy}


