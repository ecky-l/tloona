
package provide tmw::slaveconsole 1.0
package require tmw::console 1.0

# @c This is a console that evaluates commands in an associated
# @c slave interpreter
class ::Tmw::SlaveConsole {
    inherit ::Tmw::Console
    
    public variable slave "" {
        if {$slave == ""} {
            return
        }
        if {![lcontain $ValidInterps $slave]} {
            error "interpreter is not valid here"
        }
        chain $slave
    }
        
    private variable ValidInterps {}
        
    constructor {args} {
        ::eval itk_initialize $args
    }
    
    # @c @see Tmw::Console::eval
    public method eval {cmd} {
        set T [component textwin]
        $T mark set insert end
        
        if {$slave == ""} {
            $T fastinsert insert "no interpreter set\n" error
        } elseif {[catch {$slave eval $cmd} result]} {
            $T fastinsert insert [$slave eval set errorInfo]\n error
        } else {
            if {$result != ""} {
                append result \n
            }
            $T fastinsert insert $result result
        }
        
        if {[lindex $cmd 0] == "cd"} {
            # update prompt
            configure -prompt "([file tail [pwd]]) % "
        }
        
        chain $cmd
    }
        
    # @c creates a slave interpreter and sets some
    # @c aliases in it. Returns the handle and marks
    # @c the interpreter as "usable" inside the object
    # 
    # @a set: set the interpreter as the actual one
    public method createInterp {{set 0}} {
        set nSlave [interp create]
        setAliases $nSlave
        
        lappend ValidInterps $nSlave
        if {$set} {
            configure -slave $nSlave -colors $colors
            set History($slave) {}
        }
        
        return $nSlave
    }
        
    # @r commands in a child interpreter
    public method getCommands {gSlave} {
        set script "proc getNsCmd \{parent nsCmdListPtr\} \{\n"
        append script "  upvar \$nsCmdListPtr nsCmdList\n"
        append script "  set nsCmdList \[concat \$nsCmdList "
        append script "\[info commands \$\{parent\}::*\]\]\n"
        append script "  foreach ns \[namespace children \$parent\] \{\n"
        append script "    getNsCmd \$ns nsCmdList\n"
        append script "  \}\n"
        append script "\}\n"
        append script "set nsCmdList \{\}\n"
        append script "getNsCmd :: nsCmdList\n"
        append script "return \$nsCmdList\n"
        
        set err 0
        if {[catch {$gSlave eval $script} res]} {
            set err 1
        }
    
        set rRes {}
        foreach cmd $res {
            lappend rRes [string trimleft $cmd :]
        }
        
        return $rRes
    }
    
    # @c Set the alias commands for an interpreter
    protected method setAliases {interp} {
        $interp eval "set auto_path \{$::auto_path\}\n"
        $interp eval {
            rename puts __puts__
            rename exit __exit__
            rename gets __gets__
        }
        interp alias $interp puts {} [code $this putsAlias $interp]
        interp alias $interp exit {} [code $this exitAlias $interp]
        interp alias $interp gets {} [code $this getsAlias $interp]
    }
    
    # @c The puts alias for slave interpreters
    private method putsAlias {interp args} {
        if {[llength $args] > 3} {
            error "invalid arguments"
        }
        
        set newline "\n"
        if {[string match "-nonewline" [lindex $args 0]]} {
            set newline ""
            set args [lreplace $args 0 0]
        }
        
        if {[llength $args] == 1} {
            set chan stdout
            set string [lindex $args 0]$newline
        } else {
            set chan [lindex $args 0]
            set string [lindex $args 1]$newline
        }
        
        if [regexp (stdout|stderr) $chan] {
            set T [component textwin]
            $T mark gravity limit right
            $T fastinsert limit $string output
            $T see limit
            $T mark gravity limit left
        } else {
            $interp eval __puts__ $args
        }
        
    }
        
    # @c The exit alias for slave interpreters
    private method exitAlias {interp args} {
        interp delete $slave
        interp create $slave
        setAliases $slave
        
        set History($slave) {}
        set HistLevel 0
        
        component textwin delete 1.0 end
        return
    }
    
    # @c Gets alias for slave interpreter
    private method getsAlias {interp args} {
        if {[llength $args] < 1 || [llength $args] > 2} {
            error "wrong # of args, should be gets channel ?var?"
        }
        if {[string match [lindex $args 0] stdin]} {
            set T [component textwin]
            set origRet [bind $T <Return>]
            bind $T <Return> "[code $this getsStdin]; break"
            vwait ::getsVar
            set result [string range $::getsVar 0 end-1] ;# remove trailing \n
            unset ::getsVar
            $T see limit
            bind $T <Return> $origRet
            
            # if a variable name was specified, set the variable
            if {[llength $args] == 2} {
                $interp eval [list set [lindex $args 1] $result]
                set result [string length $result]
            }
            return $result
        }
        
        # if we reached here, there is another channel to read
        $interp eval __gets__ $args
    }
    
    # @c Small helper procedure to gets stdin in slave interpreter
    private method getsStdin {args} {
        global getsVar
        set T [component textwin]
        $T mark set insert end
        set ::getsVar [$T get limit end]
        $T insert insert "\n"
        $T mark set limit insert
    }
    
}

proc ::Tmw::slaveconsole {path args} {
    uplevel 0 SlaveConsole $path $args
}
