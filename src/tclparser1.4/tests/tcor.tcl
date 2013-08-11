#package re itcl 4
#namespace import ::itcl::*

#namespace import ::oo::*

oo::class create xxx {
    constructor {args} {
        puts hh
    }
    method aaa {} {
        puts aaa
    }
}


class A {
    variable I 0
    constructor {args} {
        puts ttt,$this
    }
    
    destructor {
        puts bye
    }
    
    private method do {args} {
        puts pub
    }
    
    method incri {} {
        incr I 3
    }
    
    method alln {} {
    }
}

snit::type snitty {
    variable x
    constructor {args} {
        puts yyay
    }
    method x {} {
        puts y
    }
}

#A a
#set a [A new]
#a do
#set c [a alln]
#proc allNumbers {} {
#    yield
#    set i 0
#    for {set j 0} {$j < 5} {incr j} {
#        yield $i
#        incr i 2
#    }
#    return $i
#    #while 1 {
#    #    yield $i
#    #    incr i 2
#    #}
#}
#coroutine nextNumber allNumbers
#for {set i 0} {$i < 10} {incr i} {
#    puts "received [nextNumber]"
#}
#rename nextNumber {}