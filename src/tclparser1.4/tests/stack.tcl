package require nx

nx::Class create Stack {

   #
   # Stack of Things
   #
   :variable things ""
   
   :public method push {thing} {
       set :things [linsert ${:things} 0 $thing]
       return $thing
   }
  
   :public method pop {} {
       set top [lindex ${:things} 0]
       set :things [lrange ${:things} 1 end]
       return $top
   }
   
   :public object method instances {} {
       # return the currently defined stack instances
       return [:info instances]
   }
}

nx::Class create IntStack -superclass Stack {
    #
    # Stack of Integers
    #
    :public method push {thing:integer} {next}
}

#
# test some methodtypes
#
nx::Class create Foo {
    :property {x:integer 100}
    :property y:double
    :variable -accessor public text "hello world"
    :public method foo {} {return ${:x}}
    :public alias set -frame object ::set
    :public forward fwd %self set
}

Foo create f1
f1 set x 101
puts [f1 set x]
puts [f1 fwd x]

Foo public method bar1 {} {
    return bar1
}
Foo private method bar2 {} {
    return bar2
}
Foo protected method bar3 {} {
    return bar3
}
Foo method bar4 {} {
    return bar4
}
Foo variable z:integer,1..n {1 2 3}

