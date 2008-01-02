#
# console.itk
#

package require Itcl 3.3
package require Itk 3.3

package provide tmw::console 1.0

usual Ctext {
	keep -width -height -background -borderwidth \
     -exportselection -foreground \
     -highlightbackground -highlightcolor \
     -highlightthickness \
     -insertbackground -insertborderwidth \
     -insertontime -insertofftime \
     -insertwidth -relief \
     -selectbackground -selectborderwidth \
     -selectforeground -setgrid \
     -takefocus -tabs -wrap
}

usual TScrollbar {}
usual Console {}
usual SlaveConsole {}
usual BackendConsole {}

namespace eval ::Tmw {}

# @c This is a basic console widget. It contains a ctext widget
# @c as input and output channel and the possibility to colorize
# @c the input and output. It serves as base class for specific
# @c consoles, which are e.g. attached to a slave interpreter or
# @c to to any backend (IO pipe based or socket based). Commands
# @c are saved in a history for later retrieval.
class ::Tmw::Console {
    inherit ::itk::Widget
    
    # @v -font: The console font
    itk_option define -font font Font {fixed 14} {
        component textwin configure -font $itk_option(-font)
    }
    
    # @v -exitcmd: a chunk of code to run when exit is typed
    itk_option define -exitcmd exitCmd Command ""
    
    # @v -prompt: the prompt to display
    itk_option define -prompt prompt Prompt "([file tail [pwd]]) % "
    
    # @v slave: a slave to talk to. The virtual methods define
    # @v slave: how the slave is handled.
    public variable slave "" {
        if {[cget -slave] == ""} {
            return
        }
        if {![info exists History($slave)]} {
            set History($slave) {}
        }
        configure -colors $colors
    }
        
    # @v colors: The text colors
    public variable colors {} {
        # colorize
        array set Colors $colors
        
        if {[cget -slave] == "" || $itk_option(-font) == ""} {
            return
        }
        
        if {[llength $itk_option(-font)] < 3} {
            lappend itk_option(-font) ""
        }
        foreach {k v} $colors {
            lset itk_option(-font) 2 [lindex $v 1]
            colorize $k [lindex $v 0] $itk_option(-font)
        }
    }
        
    # @v Colors: An array of colors for different character classes
    protected variable Colors
    array set Colors {}
    
    # @v History: Array containing a command history for each slave.
    # @v History: For each slave this is a list of commands
    protected variable History
    array set History {}
    
    # @v HistLevel: This is the current history level when the history
    # @v HistLevel: is retrieved
    protected variable HistLevel 0
        
    constructor {args} {
        #itk_initialize -prompt "([file tail [pwd]]) % "
        initialize
        configure -relief flat -background white
        ::eval itk_initialize $args
        insertPrompt
    
        # do this tag configurations later so that
        # the corresp. colors overwrite the syntax
        # colors
        set T [component textwin]
        $T tag configure prompt -foreground brown
        $T tag configure result -foreground purple
        $T tag configure error -foreground red
        $T tag configure output -foreground blue
    }
    
    # @v prompt: The console prompt
    #variable prompt "([file tail [pwd]]) % "
        
    # @c This method evaluates a code fragment that was typed in.
    # @c Clients need to provide an implementation, dependent on
    # @c how and where the code should be evaluated. The default 
    # @c implementation checks whether the scrollbars are to be 
    # @c displayed.
    public method eval {cmd} {
        component textwin fastinsert insert [cget -prompt] prompt
        component textwin see insert
        component textwin mark set limit insert
        
        insertHScroll
        set yv [component textwin yview]
        if {[lindex $yv 0] != 0 || [lindex $yv 1] != 1} {
            grid [component vscroll] -row 0 -column 1 -padx 0 -pady 0 -sticky nes
        } else {
            grid forget [component vscroll]
        }
        
        set row [lindex [split [component textwin index insert] .] 0]
        component textwin see $row.0
    }
        
    # @r Commands in a slave. Clients need to override.
    public method getCommands {gSlave}
        
    # @c Evaluates an external command
    public method evalExtern {cmd} {
        set T [component textwin]
        $T insert insert "\n"
        if {[info complete $cmd]} {
            $T mark set limit insert
            eval $cmd
        }
        
        set HistLevel -1
        if {$cmd == "\n"} {
            return
        }
        set History($slave) [concat \
            [list [string trimright $cmd "\n"]] $History($slave)]
        
        set fnt $itk_option(-font)
        if {[llength $fnt] < 3} {
            lappend fnt ""
        }
        colorize Keywords [lindex $Colors(Keywords) 0] \
            [lset fnt 2 [lindex $Colors(Keywords) 1]]
    }
    
    # @c creates the widgets and initializes the console
    protected method initialize {} {
        itk_component add textwin {
            ctext $itk_interior.textwin -wrap word
        }
        set T [component textwin]
        
        itk_component add -private vscroll {
            ttk::scrollbar $itk_interior.vscroll -command "$T yview" \
                -class TScrollbar
        }
        itk_component add -private hscroll {
            ttk::scrollbar $itk_interior.hscroll -orient horizontal \
                -command "$T xview" -class TScrollbar
        }
        
        set vs [component vscroll]
        set hs [component hscroll]
        $T configure -yscrollcommand "$vs set" -xscrollcommand "$hs set"
        
        grid $T -column 0 -row 0 -sticky news
        #grid $vs -column 1 -row 0 -sticky nsw
        
        grid rowconfigure $itk_interior 0 -weight 1
        grid columnconfigure $itk_interior 0 -weight 1
        
        
        bind $T <KeyPress> [code $this insertHScroll]
        bind $T <Return> "[code $this evalTypeIn]; break"
        bind $T <Key-Up> "[code $this getHistory %K]; break"
        bind $T <Key-Down> "[code $this getHistory %K]; break"
        bind $T <Key-BackSpace> "[code $this onBackspace]; break"
        bind $T <Control-x> [list $T cut]
        bind $T <Control-c> [list $T copy]
        bind $T <Control-v> [list $T paste]
        
    }
        
    # @c updates the highlighting for hclass. The corresponding
    # @c commands are highlighted in color and the constructed
    # @c tag is configured with font
    #
    # @a hclass: highlight class and tag descriptor
    # @a color: color to use for hclass
    # @a font: font to use for hclass
    protected method colorize {hclass color font} {
        set T [component textwin]
        set nothing 0
        set err 0
        set a b
        
        switch -- $hclass {
            "Keywords" {
                set cmds [getCommands $slave]
                ::ctext::addHighlightClass $T $hclass $color $cmds
            }
            "Braces" {
                ::ctext::addHighlightClassForSpecialChars $T \
                        $hclass $color "\{\}"
            }
            "Brackets" {
                ::ctext::addHighlightClassForSpecialChars $T \
                        $hclass $color "\[\]"
            }
            "Parens" {
                ::ctext::addHighlightClassForSpecialChars $T \
                        $hclass $color "()"
            }
            "Options" {
                ::ctext::addHighlightClassForRegexp $T $hclass \
                        $color {[ \t]+-[a-zA-Z_]\w+}
            }
            "Digits" {
                ::ctext::addHighlightClassForRegexp $T $hclass \
                        $color {[0-9]*\.?[0-9]+}
            }
            "Comments" {
                ::ctext::addHighlightClassForRegexp $T $hclass \
                        $color {^[ \t]*#.*|;[ \t]*#.*}
            }
            "Strings" {
                ::ctext::addHighlightClassForRegexp $T $hclass \
                        $color {".*"}
            }
            "Vars" {
                # TODO: add support for really defined variables
                ::ctext::addHighlightClassWithOnlyCharStart $T \
                        $hclass $color "\$"
            }
            default {
                return
            }
        }
        
        component textwin tag configure $hclass -font $font
        
    }
        
    # @c This method is a callback for keys to retrieve the history
    #
    # @a key: the pressed key
    # @r The history, depending on the pressed key
    protected method getHistory {key} {
        set T [component textwin]
        switch -- $key {
            Up {
                incr HistLevel
            }
            Down {
                incr HistLevel -1
            }
        }
        
        $T fastdelete limit end
        $T mark set insert limit
        
        if {$HistLevel < 0} {
            set HistLevel -1
            return
        }
        
        if {$HistLevel == [llength $History($slave)]} {
            set HistLevel [expr {[llength $History($slave)] - 1}]
        }
        
        $T fastinsert limit [lindex $History($slave) $HistLevel]
    }
        
    # @c This method triggers the evaluation of a line of code. 
    # @c Essentially, it captures the input, evaluates it using the
    # @c virtual eval method and inserts the input into the history.
    protected method evalTypeIn {} {
        set T [component textwin]
        $T mark set insert end
        set command [$T get limit end]
        
        $T insert insert "\n"
        if {[info complete $command]} {
            $T mark set limit insert
            eval $command
        }
        
        set HistLevel -1
        if {$command == "\n"} {
            return
        }
        set History($slave) [concat \
            [list [string trimright $command "\n"]] $History($slave)]
        
        set fnt $itk_option(-font)
        if {[llength $fnt] < 3} {
            lappend fnt ""
        }
        colorize Keywords [lindex $Colors(Keywords) 0] \
            [lset fnt 2 [lindex $Colors(Keywords) 1]]
        #$T tag raise prompt
    }
        
    # @c Inserts a prompt
    protected method insertPrompt {} {
        component textwin fastinsert insert [cget -prompt] prompt
        component textwin mark set limit insert
        component textwin mark gravity limit left
    }
    
    # @c Callback binding for backspace. Makes sure that the prompt
    # @c can not be deleted
    private method onBackspace {} {
        set T [component textwin]
        set row [lindex [split [$T index insert] .] 0]
        set col [lindex [split [$T index insert] .] 1]
        if {$col <= [string length [cget -prompt]]} {
            return
        }
        
        incr col -1
        $T fastdelete $row.$col
    }
        
    # @c Inserts the horizontal scrollbar if necessary
    private method insertHScroll {} {
        set xv [component textwin xview]
        
        if {[lindex $xv 0] != 0 || [lindex $xv 1] != 1} {
            grid [component hscroll] -row 1 -column 0 -padx 0 -pady 0 -sticky wes
        } else {
            grid forget [component hscroll]
        }
    }
    
}


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
            puts -nonewline $chan $string
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
            vwait ::vVar
            $T mark gravity limit right
            $T fastinsert limit $::vVar output
            $T see limit
            $T mark gravity limit left
            bind $T <Return> $origRet
            
            # if a variable name was specified, set the variable
            if {[llength $args] == 2} {
                $interp eval [list set [lindex $args 1] $::vVar]
            }
            unset ::vVar
            return
        }
        
        # if we reached here, there is another channel to read
        $interp eval __gets__ $args
    }
    
    # @c Small helper procedure to gets stdin in slave interpreter
    private method getsStdin {args} {
        global vVar
        set T [component textwin]
        $T mark set insert end
        set ::vVar [$T get limit end]
        $T insert insert "\n"
        $T mark set limit insert
    }
    
}


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



proc ::Tmw::slaveconsole {path args} {
    uplevel 0 SlaveConsole $path $args
}

proc ::Tmw::backendconsole {path args} {
    uplevel 0 BackendConsole $path $args
}
