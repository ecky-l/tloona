
package provide tmw::backendconsole 1.0
package require tmw::console 1.0

# @c This console dispatches commands to a backend Tclsh/wish process
# @c through an IO pipe and gathers the output from there.
class ::Tmw::BackendConsole {
    inherit ::Tmw::Console
    
    constructor {args} {
        addOutFilter [code $this filterCmdHighl]
        addOutFilter [code $this filterError]
        configure -prompt "% "
        ::eval itk_initialize $args
    }
    
    destructor {
        foreach {be} [array names Backends] {
            deleteBackend $be
        }
    }
    
    # @see Tmw::Console::getCommands
    public method eval {cmd} {
        set cmd [string trimright $cmd \n]
        set rcmd "puts <cons_res>;"
        append rcmd "if \{\[catch \{$cmd\} res\]\} \{"
        append rcmd "puts <cons_error>\[set ::errorInfo\]</cons_error>"
        append rcmd "\} elseif \{\$res != \"\"\} "
        append rcmd "\{puts \[set res\]\};"
        append rcmd "puts </cons_res>;"
        puts $slave $rcmd
    }
        
    # @r Commands in the backend. 
    # @see Tmw::Console::getCommands
    public method getCommands {gSlave} {
        set script "set nsCmdList \{\};"
        append script "getNsCmd :: nsCmdList;"
        append script "puts \"<cons_commands> \$nsCmdList </cons_commands>\";"
        puts $gSlave $script
        
        # wait until the backend has processed the request and thus the
        # Commands variable has been set through the fileevent handler
        #::vwait [list [scope Commands]]
        #::vwait [scope Commands]
        set rRes {}
        foreach cmd $Commands {
            lappend rRes [string trimleft $cmd :]
        }
        set Commands $rRes
        return $Commands
    }
        
    # @c Adds a filter script (procedure) to the list of output
    # @c filters. See the OutFilters attribute for a description
    public method addOutFilter {filterProc} {
        if {[lsearch $OutFilters $filterProc] < 0} {
            lappend OutFilters $filterProc
        }
    }
        
    # @c Removes an output filter
    public method removeOutFilter {filterProc} {
        set newf {}
        foreach {filter} $OutFilters {
            if {[string equal $filter $filterProc]} {
                continue
            }
            lappend newf $filter
        }
        set OutFilters $newf
    }
        
    # @c Creates a backend with the given executable. If select is
    # @c true, the console is configured to use the new backend
    public method createBackend {exe select} {
        set backend [open "|$exe" r+]
    
        set Backends($backend) $exe
        fconfigure $backend -buffering line
        fileevent $backend readable [code $this readBackend $backend]
        
        set script "proc getNsCmd \{parent nsCmdListPtr\} \{;"
        append script "  upvar \$nsCmdListPtr nsCmdList;"
        append script "  set nsCmdList \[concat \$nsCmdList "
        append script "\[info commands \$\{parent\}::*\]\];"
        append script "  foreach ns \[namespace children \$parent\] \{;"
        append script "    getNsCmd \$ns nsCmdList;"
        append script "  \};"
        append script "  return;"
        append script "\};"
        puts $backend $script
        puts $backend "catch \{wm withdraw .\};"
        
        if {$select} {
            configure -slave $backend
        }
        
        return $backend
    }
        
    # @c Deletes a backend and closes the pipe to it
    public method deleteBackend {backend} {
        if {![info exists Backends($backend)]} {
            return
        }
        
        catch {
            fileevent $backend readable {}
            puts $backend ::exit
            close $backend
        }
        
        unset Backends($backend)
    }
    
    # @c Read the output from backend. This method is used if
    # @c the backend is selected with cfgEvent true
    protected method readBackend {backend} {
        # If the backend was closed, flush all output and reset the 
        # console
        if {[eof $backend]} {
            set exe $Backends($backend)
            deleteBackend $backend
            createBackend $exe yes
            component textwin delete 1.0 end
            Tmw::Console::eval dummy
            event generate $itk_interior <<BackendExit_[set backend]>>
            focus -force [component textwin].t
            return
        }
        
        set line [gets $backend]
        foreach {func} $OutFilters {
            if {[::eval $func [list $line]]} {
                return
            }
        }
        
        # Insert the output. Everything between the <cons_res> tags is output
        # and is inserted at once. If the matching </cons_res> tag is
        # encountered, we display the prompt and adjust the scrollbars by 
        # calling the base class' eval command
        if {[string match <cons_res> $line]} {
            set GetsResult 1
        } elseif {[string match </cons_res> $line]} {
            set GetsResult 0
            Tmw::Console::eval $line
        } elseif {$GetsResult} {
            component textwin fastinsert insert [set line]\n result
        }
        
    }
        
    # @c Inserts a prompt
    protected method insertPrompt {} {
        component textwin fastinsert insert "% " prompt
        component textwin mark set limit insert
        component textwin mark gravity limit left
    }
    
    # @v Backends: Array of backends and the corresponding executables
    private variable Backends
    array set Backends {}
        
    # @v GetsError: Indicates whether we get an error currently
    private variable GetsError 0
        
    # @v GetsResult: Variable for vwaiting on while the command is
    # @v GetsResult: executed
    private variable GetsResult 0
        
    # @v Commands: list of the commands in the backend
    private variable Commands {}
    
    # @v OutFilters: A list of procedures that are executed when output
    # @v OutFilters: from the backend arrives. The output line is appended
    # @v OutFilters: to each filter procedure, so the arg list for the
    # @v OutFilters: procedure must have at least one argument.
    # @v OutFilters: If one of the procedures returns true, the execution
    # @v OutFilters: is stopped and no more filters are applied. Also, the
    # @v OutFilters: line is not inserted if one of the filters returns.
    # @v OutFilters: The filters are executed before insertion, that means
    # @v OutFilters: if the line should be inserted in the console, every
    # @v OutFilters: filter must return false.
    private variable OutFilters {}
        
    # @c filter for commands highlighting
    private method filterCmdHighl {line} {
        if {[string match <cons_commands* $line]} {
            set Commands [lrange $line 1 end-1]
            return true
        }
        return false
    }
        
    # @c Filter for errors. Inserts the error in red color into the
    # @c Text window
    private method filterError {line} {
        if {[string match <cons_error>* $line]} {
            set GetsError 1
            regsub -all {<cons_error>} $line {} line
            component textwin fastinsert insert [set line]\n error
            return true
        } elseif {[string match *</cons_error> $line]} {
            set GetsError 0
            regsub -all {</cons_error>} $line {} line
            component textwin fastinsert insert [set line]\n error
            return true
        } elseif {$GetsError} {
            component textwin fastinsert insert [set line]\n error
            return true
        }
        
        return false
    }
    
}

proc ::Tmw::backendconsole {path args} {
    uplevel 0 BackendConsole $path $args
}
