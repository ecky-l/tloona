# need to be commented

lappend auto_path src lib

package require snit 2.3.2
package require tmw::vitext 1.0


namespace eval ::Tmw {
    namespace export console
    
}

## \brief A basic console widget. 
# 
# It contains a ctext widget as input and output channel and the possibility to 
# colorize the input and output. It can be used for evaluating commands within 
# the same interpreter (by configuring the -slave option to {}) or to evaluate
# commands in a slave interpreter (configure the -slave to the slave interp).
# More advanced child widgets of this might evaluate commands to other interps
# via a socket or comm ID. 
# Commands are saved in a history for later retrieval. The command history can be
# [cget] and stored for later [configure].
snit::widget ::Tmw::Console {
    
    option {-prompt prompt Prompt} -default "([file tail [pwd]]) % "
 #       -configuremethod ConfigPrompt
    
    ## \brief Colors for the text window that resembles the console
    #
    # A dictionary with Keyword tag as key and a list of {color textface} as
    # value, e.g. {Comments {blue bold} ...}
    option {-colors colors Colors} -default {} -configuremethod ConfigSpecial
    
    ## \brief A list of previously typed commands
    option {-history history History} -default {}
    option -historyfile ~/.tmwsh.history
    option -maxhistory 1000
    
    option {-mode mode Mode} -default n -configuremethod ConfigMode
    variable SlaveInterp {}
    
    ## \brief The communications ID if mode is comm
    variable CommInterp {}
    
    ## \brief The text window to type in
    component textwin -inherit yes
    ##\brief The vertical scrollbar
    component vscroll
    ## \brief The horizontal scrollbar
    component hscroll
    
    variable History {}
    
    ## \brief Regexp and char classes for syntax colorizer
    typevariable Colorizers {
        Braces        "\{\}"
        Brackets      "\[\]"
        Parens        "()"
        Options       {[ \t]+-[a-zA-Z_]\w+}
        Digits        {[0-9]*\.?[0-9]+}
        Comments      {^[ \t]*#.*|;[ \t]*#.*}
        Strings       {".*"}
        Vars          "\$"
    }
    
    ## \brief Current history level 
    variable HistLevel -1
    
    delegate option -vimode to textwin
    delegate option -cmdinsertbg to textwin
    delegate option -insinsertbg to textwin
    
    delegate method setCommandMode to textwin
    delegate method setInsertMode to textwin
    
    ## \brief Create a list of commands in namespaces and their children
    proc getNamespaceCmds {parent nsCmdListPtr} {
        upvar $nsCmdListPtr nsCmdList
        set nsCmdList [concat $nsCmdList [info commands ${parent}::*]]
        foreach ns [namespace children $parent] {
            getNamespaceCmds $ns nsCmdList
        }
        
    }
    
    constructor {args} {
        set options(-historyfile) [file join $::env(HOME) .tmwhistory]
        set textwin [vitext $win.textwin -wrap word -linemap 0]
        set vscroll [ttk::scrollbar $win.vscroll -command [list $textwin yview]]
        set hscroll [ttk::scrollbar $win.hscroll -orient horizontal \
                -command [list $textwin xview]]
        $textwin configure -yscrollcommand [list $vscroll set] \
            -xscrollcommand [list $hscroll set]
        
        grid $textwin -column 0 -row 0 -sticky news
        grid $vscroll -column 1 -row 0 -sticky ns
        
        grid rowconfigure $win 0 -weight 1
        grid columnconfigure $win 0 -weight 1
        
        bind $textwin <KeyPress> [list apply {{thisWin key char} {
            switch -- $char {
                \{ - \[ - ( {
                    # these chars are not handled in the KeyRelease binding
                    after 1 [list $thisWin handleInputChar $key $char]
                }
            }
        }} $self %K %A]
        #bind $textwin <KeyRelease> [mymethod handleInputChar %K %A]
        bind $textwin <Return> "[mymethod evalTypeIn]; break"
        
        $textwin configure -linestart limit -lineend end-1c \
            -textstart limit -textend end \
            -upcmd [mymethod getHistory Up] \
            -downcmd [mymethod getHistory Down] \
            -leftcmd [mymethod HandleCursorLeftKey] \
            -backspacecmd [mymethod OnBackspace] \
            -homecmd [mymethod HandleHomeKey] \
            -endcmd [mymethod HandleEndKey] \
            -backcmd [mymethod HandleWordBack] \
            -cutlinecmd [mymethod CutLine] \
            -yanklinecmd [mymethod YankLine]
        
        bind $textwin <Control-x> [list $textwin cut]
        bind $textwin <Control-c> [list $textwin copy]
        bind $textwin <Control-v> [list $textwin paste]
        
        grid $hscroll -row 1 -column 0 -padx 0 -pady 0 -sticky wes
        grid $vscroll -row 0 -column 1 -padx 0 -pady 0 -sticky nes
        
        set promptFcn InsertPrompt
        if {[dict exists $args -mode]} {
            set m [dict get $args -mode]
            if {[lindex $m 0] eq "comm"} {
                package require comm
                if {[llength $m] == 1} {
                    set promptFcn AskForCommInterp
                }
            }
        } else {
            lappend args -mode default
        }
        $self $promptFcn
        
        #if {![dict exist $args -mode]} {
        #    lappend args -mode default
        #    $self InsertPrompt
        #} elseif {[lindex [dict get $args -mode] 0] eq "comm" 
        #    && [llength [dict get $args -mode]] == 1} {
        #    $self AskForCommInterp
        #} else {
        #    $self InsertPrompt
        #}
        
        $self configurelist $args
        
        # do this tag configurations later so that
        # the corresp. colors overwrite the syntax
        # colors
        $textwin tag configure prompt -foreground brown
        $textwin tag configure result -foreground purple
        $textwin tag configure error -foreground red
        $textwin tag configure output -foreground blue
        
        set clr [dict get $options(-colors) Keywords]
        $self colorize Keywords [lindex $clr 0]
        
        $self highlight 1.0 end
        $self LoadHistory
        
    }
    
    ## \brief Does some additional processing on special input chars
    #
    # Inserts matching braces, parens and brackets, inserts a horizontal scrollbar
    method handleInputChar {key char} {
        set matchings { \{ \} \[ \] ( ) }
        $textwin fastinsert insert [dict get $matchings $char]
        $textwin mark set insert "insert -1c"
        $textwin highlight "insert" "insert +10c"
    }
    
    ## \brief Apply the configured colors to the textwin component
    method colorize {hclass color} {
        switch -- $hclass {
        Keywords {
            ::ctext::addHighlightClass $textwin $hclass $color [$self getCommands]
        }
        Braces - Brackets - Parens {
            ::ctext::addHighlightClassForSpecialChars $textwin \
                    $hclass $color [dict get $Colorizers $hclass]
        }
        Options - Digits - Comments - Strings {
            ::ctext::addHighlightClassForRegexp $textwin $hclass \
                    $color [dict get $Colorizers $hclass]
        }
        Vars {
            ::ctext::addHighlightClassWithOnlyCharStart $textwin \
                    $hclass $color "\$"
        }
        }
        
    }
    
    ## \brief Evaluates a code fragment that was typed in.
    #
    # Clients can provide an overridden implementation, dependent on how 
    # and where the code should be evaluated. The default implementation
    # runs [eval] in the current interp. The cmd is assumed to be complete
    method eval {cmd {extern 0}} {
        $textwin mark set insert end
        $textwin see insert
        
        set err 0
        set errInfo ""
        set result ""
        switch -glob -- $options(-mode) {
        slave {
            set err [catch {$SlaveInterp eval $cmd} result]
            if {$err} {
                set errInfo [$SlaveInterp eval {set errorInfo}] 
            }
        }
        comm {
            set err [catch {comm::comm send $CommInterp $cmd} result]
            if {$err} {
                global __ConsCommResult__
                set errInfo [dict get $__ConsCommResult__ -errorinfo] 
            }
        }
        default {
            set err [catch {uplevel #0 $cmd} result]
            if {$err} {
                set errInfo [uplevel #0 set errorInfo] 
            }
        }
        }
        
        if {$err} {
            append errInfo \n
            $textwin fastinsert insert $errInfo error
        } else {
            if {$result != ""} {
                append result \n
            } elseif {$extern} {
                append result [lindex [split $cmd \n] 0] " ..." \n
            }
            $textwin fastinsert insert $result result
        }
        if {[lindex $cmd 0] == "cd"} {
            # update prompt
            $self configure -prompt "([file tail [pwd]]) % "
        }
        
        $self InsertPrompt
        $textwin see insert
        $textwin mark set limit insert
        
        set clr [dict get $options(-colors) Keywords]
        $self colorize Keywords [lindex $clr 0]
    }
    
    # @r Commands in a slave. Clients need to override.
    method getCommands {} {
        append script "set nsCmdList \{\}\n"
        append script "getNsCmd :: nsCmdList\n"
        append script "return \$nsCmdList\n"
        
        set err 0
        if {$SlaveInterp != {}} {
            set err [catch {$SlaveInterp eval $script} res]
        } else {
            set err [catch {uplevel #0 $script} res]
        }
        set rRes {}
        foreach cmd $res {
            lappend rRes [string trimleft $cmd :]
        }
        
        return $rRes
    }
    
    ## \brief Evaluates an external command
    method evalExtern {cmd} {
        $textwin insert insert "\n"
        if {[info complete $cmd]} {
            $T mark set limit insert
            $self eval $cmd
        }
        
        set HistLevel -1
        if {$cmd == "\n"} {
            $self InsertPrompt
            return
        }
        set options(-history) [linsert $options(-history) 0 [string trimright $cmd "\n"]]
        
        set fnt $options(-font)
        if {[llength $fnt] < 3} {
            lappend fnt ""
        }
        set clr [dict get $Colors Keywords]
        $self colorize Keywords [lindex $clr 0] [lset fnt 2 [lindex $clr 1]]
    }
    
    ## \brief callback for keys to retrieve the history
    method getHistory {key} {
        set currLine [lindex [split [$textwin index insert] .] 0]
        switch -- $key {
            Up - up {
                incr HistLevel
            }
            Down - down {
                incr HistLevel -1
            }
        }
        
        $textwin fastdelete limit end
        $textwin mark set insert limit
        if {$HistLevel < 0} {
            set HistLevel -1
            return
        }
        
        if {$HistLevel == [llength $options(-history)]} {
            set HistLevel [expr {[llength $options(-history)] - 1}]
        }
        
        $textwin fastinsert limit [lindex $options(-history) end-$HistLevel]
        set mark [expr {
            [$self cget -commandmode] ? "limit" : "end"
        }]
        
        $textwin mark set insert $mark
    }
        
    ## \brief Triggers the evaluation of a line of code. 
    #
    # It captures the input, evaluates it using the virtual eval method and 
    # inserts the input into the history and the output into the text window
    method evalTypeIn {} {
        $textwin mark set insert end
        set command [$textwin get limit end]
        
        $textwin fastinsert insert "\n"
        if {$command == "\n" && [$self cget -vimode]} {
            $self setInsertMode
        }
        
        if {$options(-mode) eq "comm" && $CommInterp == {}} {
            set command [string trim $command]
            if {$command != {} && [string is int $command]} {
                $self SetCommInterp $command
                $textwin mark set limit insert
                puts "Connected to Comm ID $command"
                $self InsertPrompt
                return
            }
            $self AskForCommInterp
            return
        }
        
        if {[info complete $command]} {
            $textwin mark set limit insert
            $self eval $command
        }
        
        set HistLevel -1
        set command [string trimright $command \n]
        set i [lsearch $options(-history) $command]
        if {[set i [lsearch $options(-history) $command]] >= 0} {
            set options(-history) [lreplace $options(-history) $i $i]
        }
        lappend options(-history) $command
        
        # cut history when it gets too large
        if {[llength $options(-history)] > $options(-maxhistory)} {
            set options(-history) \
                [lrange $options(-history) 0 $options(-maxhistory)]
        }
    }
    
    ## \brief set the comm interp for remote interaction
    method SetCommInterp {id} {
        ::comm::comm connect $id
        ::comm::comm send $id list
        set CommInterp $id
        
        ::comm::comm hook reply {
            global __ConsCommResult__
            set __ConsCommResult__ [array get return]
            dict set __ConsCommResult__ -ret $ret
        }
        
        set script {
        ::comm::comm hook eval {
            set cmdl [string trimright [lindex $buffer 0] \n]
            set cmdArgs [lrange $cmdl 1 end]
            switch -- [lindex $cmdl 0] {
            puts {
                set xchan stdout
                if {[llength $cmdArgs] > 1} {
                    switch -- [lindex $cmdArgs 0] {
                    -nonewline {
                        if {[llength [lrange $cmdArgs 1 end]] > 1} {
                            set xchan [lindex $cmdArgs 1]
                        }
                    }
                    default {
                        set xchan [lindex $cmdArgs 0]
                    }
                    }
                }
                
                if {[regexp (stdout|stderr) $xchan]} {
                    ::comm::comm send $id [uplevel subst $buffer]
                }
            }
            }
        }
        }
        
        ::comm::comm send $id $script
        ::comm::comm send $id {proc bgerror {args} {}}
    }
    
    ## \brief Setup the interp aliases for console mode
    # 
    # Some regular commands need to be specialized for handling in the 
    # attached console, namely puts, gets and exit (maybe more that I
    # cannot think of right now). We setup aliases for those commands 
    # to perform the specialized operations.
    method SetupAliases {} {
        set renameScript {
            rename ::puts ::__puts__
            rename ::exit ::__exit__
            rename ::gets ::__gets__
        }
        set aliasFcn {{self interp} {
            interp alias $interp puts {} $self putsAlias
            interp alias $interp exit {} $self exitAlias
            interp alias $interp gets {} $self getsAlias
        }}
        
        switch -glob -- $options(-mode) {
        slave {
            $SlaveInterp eval $renameScript
            apply $aliasFcn $self $SlaveInterp
        }
        default {
            uplevel #0 $renameScript
            apply $aliasFcn $self {}
        }
        }
    }
    
    ## \brief Handles the puts command. 
    #
    # If the channel is stdout (or not specified), we want to direct the
    # output to the console window. Therefore the real puts command has been
    # renamed to __puts__ in the attached interpreter and is only called
    # if the channel is something else than stdout.
    method putsAlias {args} {
        if {[llength $args] > 3} {
            error "invalid arguments"
        }
        # for real __puts__ below
        set realArgs $args
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
            foreach {line} [lrange [split $string \n] 0 end-1] {
                append line \n
                $textwin mark gravity limit right
                $textwin fastinsert limit $line output
                $textwin see limit
                update
                $textwin mark gravity limit left
            }
            return
        }
        
        switch -glob -- $options(-mode) {
        slave {
            $SlaveInterp eval __puts__ $realArgs
        }
        default {
            __puts__ {*}$realArgs
        }
        }
    }
    
    ## \brief Handles the gets command.
    #
    # As with puts, we want to capture stdin from the console's text window
    # and evaluated (set variable in gets <var>) in the attached interp.
    method getsAlias {args} {
        if {[llength $args] < 1 || [llength $args] > 2} {
            error "wrong # of args, should be gets channel ?var?"
        }
        if {[string match [lindex $args 0] stdin]} {
            set origRet [bind $textwin <Return>]
            bind $textwin <Return> "[mymethod GetsStdin]; break"
            vwait ::getsVar
            set result [string range $::getsVar 0 end-1] ;# remove trailing \n
            unset ::getsVar
            $textwin see limit
            bind $textwin <Return> $origRet
            
            # if a variable name was specified, set the variable
            if {[llength $args] == 2} {
                $self eval [list set [lindex $args 1] $result]
                set result [string length $result]
            }
            return $result
        }
        
        # if we reached here, there is another channel to read
        switch -glob -- $options(-mode) {
        slave {
            $SlaveInterp eval __gets__ $args
        }
        comm {
            comm::comm send $CommInterp [list eval gets $args]
        }
        default {
            __gets__ {*}$args
        }
        }
    }
    
    ## \brief Handles the exit command.
    # 
    # Real exit should only be performed when the console is attached to
    # the main interpreter.
    method exitAlias {args} {
        $self SaveHistory
        switch -glob -- $options(-mode) {
        slave - comm {
            interp delete $SlaveInterp
            interp create $SlaveInterp
            $self SetupAliases
            $self delete 1.0 end
        }
        default {
            __exit__
        }
        }
        return
    }
    
    
    ##
    # private methods
    ##
    
    ## \brief Save the history, usually called on exit
    method SaveHistory {} {
        set fh [open $options(-historyfile) w]
        puts $fh $options(-history)
        close $fh
    }
    
    ## \brief Load history file
    method LoadHistory {} {
        if {![file exist $options(-historyfile)]} {
            set options(-history) {}
            return
        }
        set fh [open $options(-historyfile) r]
        set options(-history) [read $fh]
        close $fh
    }
    
    # @c Small helper procedure to gets stdin in slave interpreter
    method GetsStdin {args} {
        global getsVar
        $textwin mark set insert end
        set ::getsVar [$textwin get limit end]
        $textwin insert insert "\n"
        $textwin mark set limit insert
    }
    
    ## \brief Inserts the prompt
    method InsertPrompt {} {
        $textwin fastinsert insert $options(-prompt) prompt
        $textwin mark set limit insert
        $textwin mark gravity limit left
    }
    
    ## \brief If the -mode is comm and no comm id is given, ask for one
    method AskForCommInterp {} {
        $textwin fastinsert insert "Connect to Comm ID: " prompt
        $textwin mark set limit insert
        $textwin mark gravity limit left
    }
    
    ## \brief configure whether this console operates a slave interpreter
    method ConfigMode {opt val} {
        set options($opt) [lindex $val 0]
        
        # a proc for retrieval of all commands in namespaces
        # used for colorize
        set script "proc getNsCmd \{parent nsCmdListPtr\} \{\n"
        append script "  upvar \$nsCmdListPtr nsCmdList\n"
        append script "  set nsCmdList \[concat \$nsCmdList "
        append script "\[info commands \$\{parent\}::*\]\]\n"
        append script "  foreach ns \[namespace children \$parent\] \{\n"
        append script "    getNsCmd \$ns nsCmdList\n"
        append script "  \}\n"
        append script "\}\n"
        
        switch -- $val {
        slave {
            set SlaveInterp [interp create]
            $SlaveInterp eval $script
        }
        comm {
            package require comm
            set CommInterp [lindex $val 1]
        }
        default {
            if {$SlaveInterp != {}} {
                interp delete $SlaveInterp
                set SlaveInterp {}
            }
        }
        }
        
        uplevel #0 $script
        $self SetupAliases
    }
    
    ## \brief Callback binding for backspace. 
    # 
    # Makes sure that the prompt is not deleted.
    method OnBackspace {} {
        set ci [$textwin index current]
        set row [lindex [split [$textwin index insert] .] 0]
        set col [lindex [split [$textwin index insert] .] 1]
        if {$col <= [string length $options(-prompt)]} {
            return
        }
        
        incr col -1
        $textwin fastdelete $row.$col
    }
    
    ## \brief Handles the Home key 
    #
    # Sets the insert cursor to the first char after the prompt
    method HandleHomeKey {} {
        $textwin mark set insert limit
        $textwin see insert
    }
    
    ## \brief Handles the End key
    #
    # Sets the insert cursor to the end of the text widget
    method HandleEndKey {} {
        $textwin mark set insert end
        $textwin see insert
    }
    
    ## \brief Handles word back binding
    #
    # Makes sure that the cursor does not go beyond the prompt
    method HandleWordBack {} {
        if {[$textwin compare insert <= limit]} {
            $textwin mark set insert limit
            return
        }
        ::tk::TextSetCursor $textwin \
            [::tk::TextPrevPos $textwin insert tcl_startOfPreviousWord]
        $textwin see insert
    }
    
    ## \brief Binding for cursor left key (or appropriate VI binding)
    # 
    # Makes sure that the cursor does not go beyond the prompt
    method HandleCursorLeftKey {} {
        set ci [$textwin index insert]
        if {[$textwin compare insert <= limit]} {
            $textwin mark set insert limit
            return
        }
        ::tk::TextSetCursor $textwin insert-1displayindices
        $textwin see insert
    }
    
    ## \brief The cutline command.
    # 
    # For console widgets the line starts at the end of the prompt
    method CutLine {startIdx} {
        $textwin tag add sel $startIdx end-1c
        tk_textCut $textwin
    }
    
    ## \brief The yank line command
    # 
    # For console widgets the line starts at the end of the prompt
    method YankLine {startIdx} {
        $textwin tag add sel $startIdx end-1c
        tk_textCopy $textwin
        $textwin tag remove sel $startIdx end-1c
    }
    
    ## \brief configmethod for colors
    method ConfigSpecial {option value} {
        set options($option) $value
        
        foreach {k v} $options(-colors) {
            $self colorize $k [lindex $v 0]
        }
        
    }
    
}


## \brief console command to the outside world
proc Tmw::console {path args} {
    uplevel ::Tmw::Console $path $args
}

## \brief slaveconsole command to the outside world
proc Tmw::slaveconsole {path args} {
    uplevel ::Tmw::SlaveConsole $path $args
}

package provide tmw::console 2.0

#
Tmw::console .c -wrap none -font {"Lucida Sans Typewriter" 13} \
    -colors {
            Keywords {darkred normal}
            Braces {darkorange2 normal}
            Brackets {red normal}
            Parens {maroon4 normal}
            Options {darkorange3 normal}
            Digits {darkviolet normal}
            Strings {magenta normal}
            Vars {green4 normal}
            Comments {blue normal}
    } -vimode y -mode comm
pack .c -expand y -fill both
#