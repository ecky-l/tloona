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
    
    method do {args} {
        puts [coroutine nn apply {{obj} {
            set i 0
            set rr [yield blahblah,[incr i],[info coroutine]]
            puts $rr
            #yield $i ;#incri
            return gagga
        }} $this]
        puts hehyho,[nn x]
        #nn y
        #rename nn {}
    }
    
    method incri {} {
        incr I 3
    }
    
    method alln {} {
        yield
        set i 0
        return $i
        while 1 {
            yield $i
            incr i 2
        }
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