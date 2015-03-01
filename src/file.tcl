#
# file.itk
#
package require tmw::browsablefile 1.0
package require Itree 1.0
package require parser::parse 1.0
package require tloona::codecompletion 1.0
package require tloona::htmlparser 1.0

package provide tloona::file 1.0
# @c a special Tcl/Tk file representation with 
# @c features & functionality for Tcl/Tk files
class ::Tloona::TclFile {
    inherit ::Tmw::BrowsableFile
    
    # @v sendcmd: A command that is executed for sending code to foreign
    # @v sendcmd: interpreters
    public variable sendcmd ""
    
    # @v _CmdThread: Thread where commands in the file are evaluated
    private variable _CmdThread ""
    # @v _Namespaces: all namespaces in this file, according to packages
    private variable _Namespaces {}
    # @v _Commands: list of all commands in this file
    private variable _Commands {}
        
    constructor {args} {
        
        itk_component add completor {
            ::Tloona::Completor $itk_interior.cmpl \
                -textwin [component textwin]
        }
        
        setBindings
        updateHighlights
        eval itk_initialize $args
    }
    
    destructor {
        bind [component textwin] <KeyPress> {}
    }
    
    # @c overrides the openFile method
    public method openFile {file} {
        ::Tmw::VisualFile::openFile $file
        if {[catch {reparseTree} msg]} {
            puts $msg
        }
    }

    # @c overloads the savefile from File
    public method saveFile {{file ""}} {
        set ctn [::Tmw::VisualFile::saveFile $file]
        modified 0
        update
        reparseTree
        updateHighlights
    }
    
    # @c Creates a code tree that represents this file.
    public method createTree {} {
        if {[getTree] != ""} {
            return
        }
        setTree [::Parser::Script ::#auto -type "script"]
        if {[cget -filename] != ""} {
            reparseTree
        }
    }
        
    # @c reparses the code tree
    public method reparseTree {} {
        global TloonaApplication
        
        if {[getTree] == ""} {
            return
        }
        
        set ctn [component textwin get 1.0 end]
        set ctn [string range $ctn 0 end-1]
        
        array set sel {}
        foreach {browser} [getBrowsers] {
            set sel($browser) [$browser selection]
            $browser remove [getTree]
        }
        
        set newList {}
        set oldList {}
        ::Parser::reparse [getTree] $ctn newList oldList
        foreach {elem} $oldList {
            itcl::delete object $elem
        }
        set cmds {}
        [getTree] getCommands cmds
        updateKwHighlight $cmds
        foreach browser [getBrowsers] {
            $browser add [getTree] 1 1
            if {$sel($browser) != {} && [$browser exists $sel($browser)]} {
                $browser selection set $sel($browser)
                $browser see $sel($browser)
            }
        }
    }
        
    # @c shows a completion box with possibilities for commands,
    # @c ensembles, variables and object methods to call at
    # @c the insert position
    public method showCmdCompl {{ctrlsp 0}} {
        if {[getTree] == ""} {
            return
        }
        
        set T [component textwin]
        
        set bbox [$T bbox insert]
        set rx [lindex $bbox 0]
        set ry [lindex $bbox 1]
        set cTree [getTree]
        set cdf [$cTree lookupRange [getTextPos $rx $ry]]
        
        if {$cdf == ""} {
            set cdf $cTree
        }
        
        set cmds ""
        $cdf getCommands cmds
        set cmds [lsort -dictionary $cmds]
        
        # get the characters directly before insert. If they
        # match the beginning of a command, we assume that
        # they are the first chars of that command. Cut the
        # command list to contain only the matching commands
        set lcw [$T index "insert -1c"]
        set word [$T get "$lcw wordstart" "$lcw wordend"]
        
        set idc {}
        if {$word != "\["} {
            set idc [lsearch -all -regexp $cmds "^$word"]
        }
        
        if {$idc == {}} {
            set realCmds $cmds
            set delBef 0
        } else {
            set realCmds {}
            set delBef 1
            foreach {i} $idc {
                lappend realCmds [lindex $cmds $i]
            }
        }
        
        set ry [expr {$ry + [lindex $bbox 3]}]
        array set atmp $::UserOptions(TclSyntax)
        component completor setItems $realCmds
        component completor configure -background white \
            -foreground [lindex $atmp(Keywords) 0] -forced $ctrlsp
        component completor show $rx $ry
        array unset atmp
    }
    
    # @c shows completion box with variables
    public method showVarCompl {} {
        if {[getTree] == ""} {
            return
        }
        set T [component textwin]
        
        set bbox [$T bbox insert]
        set rx [lindex $bbox 0]
        set ry [lindex $bbox 1]
        set cTree [getTree]
        set cdf [$cTree lookupRange [getTextPos $rx $ry]]
        
        if {$cdf == ""} {
            set cdf $cTree
        }
        
        set vars {}
        set tp [getTextPos]
        foreach {k v} [$cdf getVariables] {
            if {$v > $tp} {
                continue
            }
            lappend vars $k
        }
        
        set vars [lsort -dictionary $vars]
        set ry [expr {$ry + [lindex $bbox 3]}]
        array set atmp $::UserOptions(TclSyntax)
        component completor setItems $vars
        component completor configure -background lightyellow \
            -foreground [lindex $atmp(Vars) 0] -forced 0
        component completor show $rx $ry
        array unset atmp
    }
    
    # @c handler for key press events
    #
    # @a key: the key that was pressed
    # @a char: the ASCII character that is inserted
    public method onKeyPress {key char} {
        global tcl_platform
        switch -- $key {
            Return {
                set LastKey $key
                set tw [component textwin]
                handleInputChar [$tw get [$tw index "insert -1c"] \
                    [$tw index "insert"]]
                after 1 [code $this indent $IndentLevel]
                return
            }
            
            w {
                if {[regexp {Control} $LastKey]} {
                    # this is the close shortcut
                    return
                }
            }
            
            Tab {
                set LastKey $key
                if {[handleLastWord]} {
                    expandTab
                }
                return
            }
            
            colon {
                set LastKey $key
                set chars [component textwin get "insert linestart" \
                    "insert lineend"]
                if {[regexp {^[ \t]*:$} $chars]} {
                    showCmdCompl
                }
                return
            }
            
            dollar {
                showVarCompl
            }
            
            Delete -
            BackSpace -
            Home -
            End -
            space -
            Caps_Lock -
            Shift_L -
            Shift_R -
            Alt_L -
            Alt_R -
            ISO_Level3_Shift -
            Menu -
            Control_L -
            Control_R {
                set LastKey $key
                return
            }
            default {
            }
        }
        
        if {$tcl_platform(platform) != "windows"} {
            return
        }
        
        # On windows, the %A field is empty for key release events,
        # if the released key was \{ or \[. That causes failure of the
        # registered KeyRelease binding in these cases.
        # That's why we handle the appropriate event here with an
        # [after]
        switch -- $char {
            \{ - \} - \[ - \] {
                # these chars are not handled in the KeyRelease binding
                after 1 [code $this handleInputChar $char]
            }
        }
        
    }
    
    # @c jumps to the code definition in the file that is defined
    # @c by codeItem
    public method jumpTo {codeItem {def 0}} {
        set T [component textwin]
        set line [lindex [split [$T index insert] .] 0]
        set nline [expr {$line + 1}]
        
        $T tag configure inscolorize -background white
        $T tag remove inscolorize $line.0 $nline.0
        set brlist [$codeItem cget -byterange]
        if {[$codeItem isa ::Parser::OOProcNode]} {
            if {$def && [$codeItem cget -bodyextern]} {
                set brlist [$codeItem cget -defbrange]
            }
        }
#        switch -- [$codeItem cget -type] {
#            public_method -
#            protected_method -
#            private_method -
#            proc {
#                if {$def && [$codeItem cget -bodyextern]} {
#                    set brlist [$codeItem cget -defbrange]
#                }
#                
#            }
#            default {}
#        }
        
        if {$brlist == {}} {
            return
        }
        set ch [lindex $brlist 0]
        set lc [component textwin index "1.0 +$ch c"]
        #focus -force [component textwin].t
        component textwin mark set insert $lc
        component textwin see insert
    }
        
    # @c flashes the given codeItem in the text. If line is
    # @c false, the whole definition is flashed, otherwise
    # @c only thefirst line
    public method flashCode {codeItem {def 0}} {
        set br [$codeItem cget -byterange]
        switch -- [$codeItem cget -type] {
            "method" -
            "proc" {
                if {$def && [$codeItem cget -bodyextern]} {
                    set br [$codeItem cget -defbrange]
                }
            }
            default {}
        }
        if {$br == {}} {
            return
        }
        
        set T [component textwin]
        set brEnd [expr {[lindex $br 0] + [lindex $br 1]}]
        set lc0 [$T index "1.0 +[lindex $br 0] c"]
        set lc1 [$T index "1.0 +$brEnd c"]
        $T tag add flash $lc0 $lc1
        
        $T tag configure flash -background yellow
        set script "$T tag delete flash\n"
        #append script "focus -force $T.t"
        after $::UserOptions(FlashTime) $script
        colorizeInsert
        $T get $lc0 $lc1
    }
        
    # @c updates the highlighting for hclass. The corresponding
    # @c commands are highlighted in color and the constructed
    # @c tag is configured with font
    #
    # @a hclass: highlight class and tag descriptor
    # @a color: color to use for hclass
    # @a font: font to use for hclass
    public method updateHighlight {hclass color font} {
        set T [component textwin]
        set nothing 0
        set err 0
        set a b
        
        switch -- $hclass {
            "Keywords" {
                if {[set ctree [getTree]] != ""} {
                    set cmds ""
                    $ctree getCommands cmds
                    ::ctext::addHighlightClass $T $hclass $color $cmds
                }
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
        
    
    # @c updates all highlight classes
    public method updateHighlights {} {
        global UserOptions
        
        # update highlighting. First, check whether font
        # has three elements (last being a style) or two
        # (normal style anyway)
        set fnt $UserOptions(FileFont)
        if {[llength $fnt] < 3} {
            lappend fnt ""
        }
        foreach {k v} $UserOptions(TclSyntax) {
            lset fnt 2 [lindex $v 1]
            updateHighlight $k [lindex $v 0] $fnt
        }
        
        component textwin highlight 1.0 end
    }
        
    # @c update the keyword highlight
    public method updateKwHighlight {keyWords} {
        global UserOptions
        
        set fnt $UserOptions(FileFont)
        if {[llength $fnt] < 3} {
            lappend fnt ""
        }
        set i [lsearch $UserOptions(TclSyntax) Keywords]
        set tl [lindex $UserOptions(TclSyntax) [incr i]]
        lset fnt 2 [lindex $tl 1]
        ::ctext::addHighlightClass [component textwin] Keywords \
            [lindex $tl 0] $keyWords
        component textwin tag configure Keywords -font $fnt
    }
        
    # @c inserts a code template for a spezial word at insert
    # @c position. Places the insertion cursor smartly
    #
    # @a word:
    # @a indent:
    public method insertTemplate {word {indent 0}} {
        set T [component textwin]
        set line [lindex [split [$T index insert] .] 0]
        set nline [expr {$line + 1}]
        $T tag configure inscolorize -background white
        $T tag remove inscolorize $line.0 $nline.0
        
        set ci [$T index insert]
        switch -- $word {
            for {
                set iStr " \{\} \{\} \{\} \{\n"
                append iStr "[string repeat " " $indent]\}"
                $T fastinsert "insert" $iStr
                after 1 [code $this deleteCharBefore insert]
                after 2 [list $T mark set insert "$ci +2c"]
                $T highlight "$ci" "$ci +[string length $iStr]c"
            }
            foreach {
                set iStr " \{\} \{\} \{\n"
                append iStr "[string repeat " " $indent]\}"
                $T fastinsert "insert" $iStr
                after 1 [code $this deleteCharBefore insert]
                after 2 [list $T mark set insert "$ci +2c"]
                $T highlight "$ci" "$ci +[string length $iStr]c"
            }
            if -
            elseif {
                set iStr " \{\} \{\n"
                append iStr "[string repeat " " $indent]\}"
                $T fastinsert "insert" $iStr
                after 1 [code $this deleteCharBefore insert]
                after 2 [list $T mark set insert "$ci +2c"]
                $T highlight "$ci" "$ci +[string length $iStr]c"
            }
            else {
                set innerInd [expr {$indent + $tabsize}]
                set iStr " \{\n"
                append iStr "[string repeat " " $innerInd]\n"
                set insPos [expr {[string length $iStr] - 1}]
                append iStr "[string repeat " " $indent]\}"
                $T fastinsert "insert" $iStr
                after 1 [code $this deleteCharBefore insert]
                after 2 [list $T mark set insert "$ci +$insPos c"]
                $T highlight "$ci" "$ci +[string length $iStr]c"
            }
            switch {
                set iStr " --  \{\n[string repeat " " $indent]\}"
                $T fastinsert "insert" $iStr
                after 1 [code $this deleteCharBefore insert]
                after 2 [list $T mark set insert "$ci +4c"]
                $T highlight "$ci" "$ci +[string length $iStr]c"
            }
            proc {
                set iStr "  \{\} \{\n[string repeat " " $indent]\}"
                $T fastinsert "insert" $iStr
                after 1 [code $this deleteCharBefore insert]
                after 2 [list $T mark set insert "$ci +1c"]
                $T highlight "$ci" "$ci +[string length $iStr]c"
            }
            method {
                set iStr "  \{\}"
                $T fastinsert insert $iStr
                after 1 [code $this deleteCharBefore insert]
                after 2 [list $T mark set insert "$ci +1c"]
                $T highlight "$ci" "$ci +[string length $iStr]c"
            }
            class {
                set inner [expr {$indent + $tabsize}]
                set ins [string repeat " " $inner]
                set iStr "  \{\n"
                append iStr "${ins}\n"
                append iStr "${ins}constructor \{args\} \{\n"
                append iStr "${ins}\}\n${ins}\n"
                append iStr ""
                append iStr "${ins}destructor \{\n"
                append iStr "${ins}\}\n${ins}\n"
                append iStr "${ins}public \{\n"
                append iStr "${ins}\}\n${ins}\n"
                append iStr "${ins}protected \{\n"
                append iStr "${ins}\}\n${ins}\n"
                append iStr "${ins}private \{\n"
                append iStr "${ins}\}\n${ins}\n"
                append iStr "[string repeat " " $indent]\}"
                $T fastinsert insert $iStr
                after 1 [code $this deleteCharBefore insert]
                after 2 [list $T mark set insert "$ci +1c"]
                $T highlight "$ci" "$ci +[string length $iStr]c"
            }
            test {
                set iStr "  \"\" -setup \{\n"
                append iStr "[string repeat " " $indent]\} -body \{\n"
                append iStr "[string repeat " " $indent]\} -cleanup \{\n"
                append iStr "[string repeat " " $indent]\} -result \{\}\n"
                $T fastinsert insert $iStr
                after 1 [code $this deleteCharBefore insert]
                after 2 [list $T mark set insert "$ci +1c"]
                $T highlight "$ci" "$ci +[string length $iStr]c"
            }
        }
    }
    
    # @c toggle comments
    #
    # @a start: start index for comment
    # @a end: end index for comment
    public method toggleComment {start end} {
        set T [component textwin]
        set ls [lindex [split $start .] 0]
        set le [lindex [split $end .] 0]
        set minInd 1000000
        
        for {set i $ls} {$i <= $le} {incr i} {
            set line [$T get $i.0 "$i.0 lineend"]
            set v ""
            regexp -all {^([ \t]*)[^ ]+} $line m v
            if {[set nl [string length $v]] < $minInd} {
                set minInd $nl
            }
        }
        
        set minInd1 [expr {$minInd + 1}]
        for {set i $ls} {$i <= $le} {incr i} {
            set line [$T get $i.0 "$i.0 lineend"]
            if {[regexp "^\[ \\t\]\{$minInd\}#" $line]} {
                $T delete $i.$minInd $i.$minInd1
            } else {
                $T insert $i.$minInd "#"
            }
        }
        
        $T highlight $start $end
    }
    
    # @c indent a code block
    # 
    # @a indent: indent level
    # @a start: start index in text widget
    # @a end: end index in text widget
    public method indentBlock {indent start end} {
        set T [component textwin]
        set ls [lindex [split $start .] 0]
        set le [lindex [split $end .] 0]
        
        # check if the indentation level is appropriate for
        # unindentation. If the block is not at least one times 
        # indented, do nothing
        set minInd 1000000
        for {set i $ls} {$i <= $le} {incr i} {
            set line [$T get $i.0 "$i.0 lineend"]
            set v ""
            set rr [regexp -all {^([ \t]*)[^ ]+} $line m v]
            if {$rr && ([set nl [string length $v]] < $minInd)} {
                set minInd $nl
            }
        }
        
        set iStr "\t"
        if {$expandtab} {
            set iStr [string repeat " " $tabsize]
        }
        set realInd [expr {$minInd - [string length $iStr]}]
        if {! $indent && $realInd < 0} {
            return
        }
        
        for {set i $ls} {$i <= $le} {incr i} {
            set line [$T get $i.0 "$i.0 lineend"]
            if {$indent} {
                $T insert $i.0 $iStr
            } else {
                $T delete $i.0 $i.[string length $iStr]
            }
        }
        
        $T tag add sel "$start linestart" "$end lineend"
    }
    
    # @c set default bindings for the widget
    protected method setBindings {} {
        global UserOptions
        set T [component textwin]
        
        # switch the bindtags sequence. The textwin (ctags textwin)
        # must come first in the list
        set ntags [lindex [bindtags $T.t] 1]
        lappend ntags [lindex [bindtags $T.t] 0]
        set ntags [concat $ntags [lrange [bindtags $T.t] 2 end]]
        bindtags $T.t $ntags

        # code completion bindings
        set accel $UserOptions(DefaultModifier)
        set accel [regsub {Ctrl} $accel Control]
        set accel [regsub {Meta} $accel M1]
        bind $T <[set accel]-space> [code $this showCmdCompl 1]
        bind $T <[set accel]-Return> "[code $this sendCode];break"

        bind $T <Key-Up> [code $this updateCurrentNode]
        bind $T <Key-Down> [code $this updateCurrentNode]
        bind $T <Key-Left> [code $this updateCurrentNode]
        bind $T <Key-Right> [code $this updateCurrentNode]
        bind $T <KeyPress> [code $this onKeyPress %K %A]
        bind $T <KeyRelease> [code $this handleInputChar %A]
    }
    
    # @c Sends code to via the sendcmd procedure
    protected method sendCode {} {
        if {$sendcmd == ""} {
            return
        }
        $sendcmd [::Tloona::getNodeDefinition $CurrentNode $this]
    }
    
    # @c handles the character that was typed last. Invoked 
    # @c from the onKeyPress handler
    # 
    # @a char: the input char
    # @a keyrelease: 1 if the callback was triggered from a
    # @a keyrelease: key release event
    private method handleInputChar {char} {
        global tcl_platform
        set T [component textwin]
        if {$char == {}} {
            return
        }
        
        set tIdx [$T index insert]
        set line [$T get "$tIdx linestart" $tIdx]
        switch -- $char {
            \" {
                if {$::UserOptions(File,MatchQuotes) && \
                        $LastKey != "Return"} {
                    $T fastinsert insert "\""
                    $T mark set insert "insert -1c"
                    $T highlight "insert" "insert +10c"
                }
            }
            ( {
                if {$::UserOptions(File,MatchParens)} {
                    $T fastinsert insert ")"
                    $T mark set insert "insert -1c"
                    $T highlight "insert" "insert +1c"
                }
            }
            \{ {
                set c [$T get $tIdx "$tIdx lineend"]
                if {$LastKey == "Return" && $c != "\}"} {
                    regexp -all {^([ \t]*)[^ ]+} $line m v1
                    set IndentLevel [expr \
                        {[string length $v1] + $tabsize}]
                } elseif {$LastKey == "Return"} {
                    $T highlight "insert" "insert +50c"
                    # do nothing
                } elseif {$::UserOptions(File,MatchBraces)} {
                    $T fastinsert insert "\}"
                    $T mark set insert "insert -1c"
                    $T highlight "insert" "insert +1c"
                }
            }
            \[ {
                set c [$T get $tIdx "$tIdx lineend"]
                if {$LastKey == "Return" && $c != "\}"} {
                    regexp -all {^([ \t]*)[^ ]+} $line m v1
                    set IndentLevel [expr \
                        {[string length $v1] + $tabsize}]
                } elseif {$LastKey == "Return"} {
                    $T highlight "insert" "insert +50c"
                    # do nothing
                } elseif {$::UserOptions(File,MatchBrackets)} {
                    $T fastinsert insert "\]"
                    $T mark set insert "insert -1c"
                    $T highlight "insert" "insert +1c"
                }
            }
            \} {
                if {$LastKey == "Return"} {
                    regexp -all {^([ \t]*).*$} $line m v1
                    set IndentLevel [string length $v1]
                } else {
                    set l [$T get "$tIdx linestart" "$tIdx lineend"]
                    if {[regexp {^[ \t]*\}} $l]} {
                        set IndentLevel [expr {$IndentLevel - $tabsize}]
                        set l [lindex [split $tIdx .] 0]
                        set c [lindex [split $tIdx .] 1]
                        $T fastdelete $l.[expr {$c - $tabsize - 1}] \
                            "insert -1c"
                    }
                }
            }
            \] {
                if {$LastKey == "Return"} {
                    regexp -all {^([ \t]*).*$} $line m v1
                    set IndentLevel [string length $v1]
                } else {
                    set l [$T get "$tIdx linestart" "$tIdx lineend"]
                    if {[regexp {^[ \t]*\}} $l]} {
                        set IndentLevel [expr {
                            $IndentLevel - 2*$tabsize
                        }]
                        set l [lindex [split $tIdx .] 0]
                        set c [lindex [split $tIdx .] 1]
                        $T fastdelete $l.[expr {$c - 2 * $tabsize - 1}] \
                                "insert -1c"
                    }
                }
            }
            \\ {
                if {$LastKey == "Return"} {
                    regexp -all {^([ \t]*)[^ ]+} $line m v1
                    set IndentLevel [expr {[string length $v1] + $tabsize}]
                }
            }
            
            default {
                if {$LastKey == "Return"} {
                    # an ordinary statement or empty line
                    if {[regexp -all {^([ \t]*).*$} $line m v1]} {
                        set IndentLevel [string length $v1]
                    }
                }
            }
        }
    }
    
    private method closeBraces {} {
        
    }
        
    # @c handles the word just before the insertion cursor.
    # @c Invoked from onKeyPress handler if the key is space
    private method handleLastWord {} {
        set T [component textwin]
        set lcw [$T index "insert -1c"]
        set word [$T get "$lcw wordstart" "$lcw wordend"]
        
        set line [$T get "insert linestart" "insert"]
        
        switch -- $word {
            for -
            foreach -
            if -
            elseif -
            else -
            switch -
            proc -
            method -
            class -
            test {
                if {! $::UserOptions(File,InsertCodeTemplates)} {
                    return
                }
                regexp -all {^([ \t]*)[^ ]+} $line m v1
                insertTemplate $word [string length $v1]
                return 0
            }
            
            default {
                return 1
            }
    
        }
    }
        
    # @c indent the code after a new line
    private method indent {level} {
        component textwin fastinsert insert [string repeat " " $level]
    }
    
}



proc ::Tloona::tclfile {path args} {
    # @c convenience command for constructing files
    uplevel ::Tloona::TclFile $path $args
}

# @c Represents a web file. This are files that contain HTML and/or
# @c Tcl code wrapped in any special tags (for AOLserver, Tclhttpd 
# @c or whatever).
# @c In addition to provide syntax highlighting and code completion,
# @c for Tcl, web files have these features for HTML.
class ::Tloona::WebFile {
    inherit Tloona::TclFile
    
    constructor {args} {
        #setTree [::Parser::Webscript -ts ::#auto -type "webscript"]
        eval itk_initialize $args
    }
    
    public method updateHighlights {} {
        global UserOptions
        
        Tloona::TclFile::updateHighlights
        
        # update highlighting. First, check whether font
        # has three elements (last being a style) or two
        # (normal style anyway)
        set fnt $UserOptions(FileFont)
        if {[llength $fnt] < 3} {
            lappend fnt ""
        }
        set T [component textwin]
        foreach {k v} $UserOptions(HtmlSyntax) {
            lset fnt 2 [lindex $v 1]
            set color [lindex $v 0]
            switch -- $k {
                Tags {
                    ::ctext::addHighlightClassForRegexp $T Tags \
                        $color {(?:</?\w+[ \t>])|(/>)}
                    component textwin tag configure $k -font $fnt
                }
                TagOptions {
                    ::ctext::addHighlightClassForRegexp $T TagName \
                        $color {\w+="}
                }
                HtmlComment {
                    ::ctext::addHighlightClassForRegexp $T $k \
                        $color {<!--.*-->}
                    component textwin tag configure $k -font $fnt
                }
            }
        }
        
        component textwin highlight 1.0 end
    }
    
    public method showTagCompl {} {
        set T [component textwin]
        set bbox [$T bbox insert]
        set rx [lindex $bbox 0]
        set ry [lindex $bbox 1]
        #set cmds $::Tloona::HtmlTags
        set cmds [array names ::Tloona::Html::Tags]
        
        # see TclFile::showCmdCompl
        set lcw [$T index "insert -1c"]
        set word [$T get "$lcw wordstart" "$lcw wordend"]
        
        set idc {}
        if {$word != "<"} {
            set idc [lsearch -all -regexp $cmds "^$word"]
        }
        
        if {$idc == {}} {
            set realCmds $cmds
            set delBef 0
        } else {
            set realCmds {}
            set delBef 1
            foreach {i} $idc {
                lappend realCmds [lindex $cmds $i]
            }
        }
        
        set ry [expr {$ry + [lindex $bbox 3]}]
        array set atmp $::UserOptions(HtmlSyntax)
        component completor setItems $realCmds
        component completor configure -background white \
            -foreground [lindex $atmp(Tags) 0] -forced 1
        component completor show $rx $ry
        array unset atmp
    }
        
    public method showAttrCompl {} {
        set T [component textwin]
        set ci [$T index insert]
        # search the start sign for this tag
        if {[set tagName [getTag $ci]] == ""} {
            return
        }
        if {![info exists ::Tloona::Html::Tags($tagName)]} {
            return
        }
        
        set attrList [concat style class id title $::Tloona::Html::Tags($tagName)]
        if {[lsearch $::Tloona::Html::NoEventHandlers $tagName] < 0} {
            set attrList [concat $::Tloona::Html::EventHandlerAttr $attrList]
        }
        set attrList [lsort -dictionary $attrList]
        
        set bbox [$T bbox insert]
        set rx [lindex $bbox 0]
        set ry [lindex $bbox 1]
        
        set ry [expr {$ry + [lindex $bbox 3]}]
        array set atmp $::UserOptions(HtmlSyntax)
        component completor setItems $attrList ;#$realCmds
        component completor configure -background white \
            -foreground [lindex $atmp(Tags) 0] -forced 1
        component completor show $rx $ry 1
        array unset atmp
        
        # this appends '=""' to the attribute and places the cursor 
        # between the quotes. The script releases the binding by itself
        # after it is done
        set script "$T fastinsert insert =\"\"\n"
        append script "set ci \[$T index insert\]\n"
        append script "$T mark set insert \"\$ci -1c\"\n"
        append script "bind $T <<InsCompletion>> {}\n"
        bind [component textwin] <<InsCompletion>> $script
    }
    
    public method matchTag {} {
        set T [component textwin]
        set ci [$T index insert]
        
        if {[$T get "insert -1c"] == "/"} {
            # no closing tag needed
            return
        }
        
        switch -- [set tagName [getTag $ci]] {
            "" -
            "%" -
            "%=" -
            "\$" -
            br/ {
                return
            }
            br {
                $T insert insert /
                return
            }
        }
        
        # if it is a closing tag or no starttag was found, 
        # do nothing. We might decrease the insert later on, 
        # maybe...
        
        after 1 [list $T insert "insert" "</$tagName>"]
        after 2 [list $T mark set insert "$ci +1c"]
    }
    
    # @c Overwritten for the moment because there is no real and 
    # @c useful tree in web files currently
    public method reparseTree {} {
    }
    
    # @c Overwritten for the moment because there is no real and 
    # @c useful tree in web files currently
    public method updateCurrentNode {{x -1} {y -1}} {
    }
    
    protected method setBindings {} {
        Tloona::TclFile::setBindings
        
        set T [component textwin]
        bind $T <Key-less> [code $this showTagCompl]
        bind $T <Key-greater> [code $this matchTag]
        bind $T <Key-space> [code $this showAttrCompl]
    }
    
    private method getTag {index} {
        set T [component textwin]
        
        # search the start sign for this tag
        set row [lindex [split $index .] 0]
        set col [lindex [split $index .] 1]
        set tagName ""
        while {$col >= 0} {
            set char [$T get $row.$col]
            if {$char == "<"} {
                break
            }
            if {$char == " "} {
                set tagName ""
            }
            set tagName [set char][set tagName]
            incr col -1
        }
        
        set tagName [string trim $tagName]
        if {[string index $tagName 0] == "/" || $col < 0} {
            return ""
        }
        return $tagName
    }
    
}


proc ::Tloona::webfile {path args} {
    uplevel ::Tloona::WebFile $path $args
}


