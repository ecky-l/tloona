# need to be commented

package provide tmw::console 1.0
package require -exact Itcl 3.4
package require -exact Itk 3.4

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
            ctext $itk_interior.textwin -wrap word -linemap 0
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

