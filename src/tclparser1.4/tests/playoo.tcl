namespace import ::oo::*

namespace eval dummy {
    variable ttt
    variable xxx
    namespace eval ttt {
        variable uuu
    }
    
    proc tata {} {
    }
    
    variable ttt::zzzz
}

class ::dummy::ttt::Ufda {
    constructor {args} {}
}

proc ::dummy::ttt::uffdadda {} {
}

variable ::dummy::ttt::myVar

class create dog {
    variable tune
    constructor {name args} {
        set tune wau
        copy [self] $name
    }
    
    method barg {} {
        #my variable tune
        puts $tune
    }
    
    method _piss {} {
        puts piss
    }
}

class create snoopy {
    superclass dog
    method ppiss {} {
        my _piss
    }
}

class create cat
define cat method miau {args} {puts miau}


class Aitcl {
    public {
        variable x "" {
            puts yes
        } {
            puts no
        }
        constructor {args} {
        }
        method do {} {
        }
    }
    
    protected {
        variable y
        method prDo {args} {
        }
    }
    
    private {
        variable z
        method piDo {args} {
        }
    }
    
}

class Bitcl {
    inherit Aitcl
    constructor {args} {
    }
    
    public variable xx "" {
            puts yes
        } {
            puts no
        }
        
    protected variable yy
    private variable zz ""
    
    public method xDo {args} {
    }
    protected method yDo {args} {
    }
    private method zDo {args} {
    }
}