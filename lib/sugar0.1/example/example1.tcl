# Sugar example 1 - simple "command macros".

package require sugar

sugar::macro first {cmd list} {
    list lindex $list 0
}

sugar::macro second {cmd list} {
    list lindex $list 1
}

sugar::macro last {cmd list} {
    list lindex $list 1
}

sugar::macro rest {cmd list} {
    list lrange $list 1 end
}

sugar::proc testit {} {
    set list [list 1 2 3]
    puts [first $list]
    puts [second $list]
    puts [rest $list]
    puts [first [rest $list]]
}

puts "The body of 'testit' procedure is:"
puts [info body testit]
puts "Output:"
testit
