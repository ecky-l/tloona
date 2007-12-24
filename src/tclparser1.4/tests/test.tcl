################################################################################
# test.tcl
#
# tests for parser/iparser
################################################################################
set path [file dirname [info script]]
set auto_path [concat [file join $path .. ..] $auto_path]

if {[lsearch [namespace children] ::tcltest] == -1} {
    package require tcltest
    namespace import ::tcltest::*
}

if {"[info commands parser]" == ""} {
    package require tclparser
}

test Proc "(test a single proc)" {
    set content {
        proc testProc {a1 a2} {
            puts dummy
        }
    }
    set root [::parser::Script ::#auto -name "Proc" \
            -definition $content -type "script"]
    $root parse 0
    return [$root print 4]
} {script: Proc (0)
    proc: testProc (1)
}

test NsProc "(a proc inside a namespace)" {
    set content {
        namespace eval ns {
            proc testProc {a1 a2} {
                puts dummy
            }
        }
    }
    set root [::parser::Script ::#auto -name "NsProc" \
            -definition $content -type "script"]
    $root parse 0
    return [$root print 4]
} {script: NsProc (0)
    namespace: ns (1)
        proc: testProc (2)
}

test NestedNsProc "(a proc inside a nested namespace)" {
    set content {
        namespace eval ns {
            namespace eval ns {
                proc testProc {a1 a2} {
                    puts dummy
                }
            }
            proc testProc {a3 a4} {
                return "dummy"
            }
        }
    }
    set root [::parser::Script ::#auto -name "NestedNsProc" \
            -definition $content -type "script"]
    $root parse 0
    return [$root print 4]
} {script: NestedNsProc (0)
    namespace: ns (1)
        namespace: ns (2)
            proc: testProc (3)
        proc: testProc (2)
}

test NsProcOutside "(a proc defined for a namespace outside)" {
    set content {
        namespace eval ns {
        }
        namespace eval ns::ns {
        }
        
        proc ns::testProc {a1 a2} {
            puts "dummy"
        }
        
        proc ns::ns::testProc {a3 a4} {
            return "dummy"
        }
    }
    set root [::parser::Script ::#auto -name "NsProcOutside" \
            -definition $content -type "script"]
    $root parse 0
    return [$root print 4]
} {script: NsProcOutside (0)
    namespace: ns (1)
        namespace: ns (2)
            proc: testProc (3)
        proc: testProc (2)
}

test MoreNsProc "(more / nested namespaces and proc)" {
    set content {
        namespace eval ns {
            proc testProc1 {} {
                return "dummy"
            }
        }
        namespace eval ns::ns {
        }
        proc ::ns::testProcNs {} {
            return "dummy"
        }
        proc ::ns::ns::testProcNsNs {a} {
            return "duummy"
        }
        
        namespace eval ns::ns {
            namespace eval ns3 {
            }
        }
        
        namespace eval ns2::ns2 {
            proc testProcNs2Ns_ {a1 a2} {
                puts dummy
            }
        }
        proc ::ns2::testProcNs2 {a2 a3} {
            return "dummy"
        }
        proc ns2::ns2::testProcNs2Ns {a b c} {
            return "dummy"
        }
    }
    set root [::parser::Script ::#auto -name "MoreNsProc" \
            -definition $content -type "script"]
    $root parse 0
    return [$root print 4]
} {script: MoreNsProc (0)
    namespace: ns (1)
        proc: testProc1 (2)
        namespace: ns (2)
            proc: testProcNsNs (3)
            namespace: ns3 (3)
        proc: testProcNs (2)
    namespace: ns2 (1)
        namespace: ns2 (2)
            proc: testProcNs2Ns_ (3)
            proc: testProcNs2Ns (3)
        proc: testProcNs2 (2)
}

test SimpleClass "(simple class construct)" {
    set content {
        class A {
        }
        itcl::class B {
        }
        ::itcl::class C {
        }
        
        class ::a::A {
        }
    }
    set root [::parser::Script ::#auto -name "SimpleClass" \
            -definition $content -type "script"]
    $root parse 0
    return [$root print 4]
} {script: SimpleClass (0)
    class: A (1)
    class: B (1)
    class: C (1)
    namespace: a (1)
        class: A (2)
}

test ClassMethods "(class with method definitions)" {
    set content {
        class A {
            method doPublic1 {a b c}
            method doPublicBody1 {z u o} {
                return "dummy"
            }
            public method doPublic2 {d e f}
            public method doPublicBody2 {a f z} {
                return "dummy"
            }
            protected method doProtected {d e f}
            protected method doProtectedBody {c g t} {
                return "dummy"
            }
            private method doPrivate {e r t}
            private method doPrivateBody {a b} {
                return "dummy"
            }
        }
    }
    set root [::parser::Script ::#auto -name "ClassMethods" \
            -definition $content -type "script"]
    $root parse 0
    return [$root print 4]
} {script: ClassMethods (0)
    class: A (1)
        public: (2)
            method: doPublic1 (3)
            method: doPublicBody1 (3)
            method: doPublic2 (3)
            method: doPublicBody2 (3)
        protected: (2)
            method: doProtected (3)
            method: doProtectedBody (3)
        private: (2)
            method: doPrivate (3)
            method: doPrivateBody (3)
}

test ClassVars "(class variable declarations)" {
    set content {
        class A {
            public variable var10
            public variable var11 ""
            public variable var12 "" {
                puts hello
            }
            public variable var13 "" {
                puts config
            } {
                puts cget
            }
            
            variable var20
            variable var21 ""
            variable var22 "" {
                puts hello
            }
            variable var23 "" {
                puts config
            } {
                puts cget
            }
            protected variable var24
            protected variable var25 ""
            protected variable var26 "" {
                puts hello
            }
            protected variable var27 "" {
                puts config
            } {
                puts cget
            }            
            
            private variable var30
            private variable var31 ""
        }
    }
    set root [::parser::Script ::#auto -name "ClassVars" \
            -definition $content -type "script"]
    $root parse 0
    return [$root print 4]
} {script: ClassVars (0)
    class: A (1)
        public: (2)
            variable: var10 (3)
            variable: var11 (3)
            variable: var12 (3)
                configcode
            variable: var13 (3)
                configcode
                cgetcode
        protected: (2)
            variable: var20 (3)
            variable: var21 (3)
            variable: var22 (3)
                configcode
            variable: var23 (3)
                configcode
                cgetcode
            variable: var24 (3)
            variable: var25 (3)
            variable: var26 (3)
                configcode
            variable: var27 (3)
                configcode
                cgetcode
        private: (2)
            variable: var30 (3)
            variable: var31 (3)
}

test ByteRange "(simple top level byte ranges)" {
    set content {
        class A {
            variable b "test"
            public variable c "test2"
            
            method getB {} {
                return $b
            }
            
            proc makeC {args} {
                set cc $args
            }
        }
        
        proc test2 {args} {
            return "test"
        }
    }
    set root [::parser::Script ::#auto -name "ClassVars" \
            -definition $content -type "script"]
    $root parse 0
    
    set br {}
    foreach {c} [$root getChildren] {
        lappend br [$c cget -byterange]
    }
    return $br
} {{9 257} {284 55}}

test NestedByteRange "(nested byte ranges)" {
    set content {
        class A {
            variable b "test"
            public variable c "test2"
            
            method getB {} {
                return $b
            }
            
            proc makeC {args} {
                set cc $args
            }
        }
        
        proc test2 {args} {
            return "test"
        }
    }
    set root [::parser::Script ::#auto -name "ClassVars" \
            -definition $content -type "script"]
    $root parse 0
    
    set br {}
    set cl [lindex [$root getChildren] 0]
    # check only public access - the second access node
    set pacc [lindex [$cl getChildren] 1]
    foreach {c} [$pacc getChildren] {
        lappend br [$c cget -byterange]
    }
    return $br
} {{61 25} {112 56} {194 62}}


