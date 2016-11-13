## file.tcl (created by Tloona here)
package require snit 2.3.2
package require tmw::browsablefile 2.0.0
package require tloona::codecompletion 2.0.0
package require tloona::htmlparser 1.0

namespace eval Tloona {

# @c a special Tcl/Tk file representation with 
# @c features & functionality for Tcl/Tk files
snit::widgetadaptor tclfile {
    
    #### Options
    
    ## \brief A command that is executed for sending code to interpreters
    option -sendcmd {}
    
    #### Components
    component completor -public completor
    
    delegate method * to hull except HandleInputChar
    delegate option * to hull
    
    #### Variables
    
    ## \brief the current indentation level
    variable IndentLevel 0
    ## \brief the last pressed key
    variable LastKey ""
    ## \brief The last pressed modifier
    variable LastModifier ""
    
    # @v _CmdThread: Thread where commands in the file are evaluated
    variable _CmdThread ""
    # @v _Namespaces: all namespaces in this file, according to packages
    variable _Namespaces {}
    # @v _Commands: list of all commands in this file
    variable _Commands {}
    
    constructor {args} {
        installhull using Tmw::browsablefile
        #install completor using ::Tloona::Completor $win.cmpl -textwin [$self textwin]
        install completor using ::Tloona::completor $win.cmpl -textwin [$self textwin]
        
        # TODO: review
        $self SetBindings
        $self updateHighlights
        $self configurelist $args
    }
    
    destructor {
        $self destruct
    }
    
    # @c overrides the openFile method
    method openFile {file} {
        $hull openFile $file
        try {
            $self reparseTree
        } trap {} {err errOpts} {
            puts $err,$errOpts
        }
    }

    # @c overloads the savefile from File
    method saveFile {{file ""}} {
        set ctn [$hull saveFile $file]
        $self modified 0
        update
        $self reparseTree
        $self updateHighlights
    }
    
    # @c Creates a code tree that represents this file.
    method createTree {args} {
        if {[$self getTree] != ""} {
            return
        }
        
        #setTree [::Parser::Script ::#auto -type "script"]
        $self setTree [::Parser::Script ::#auto -type "script" {*}$args]
        if {[$self cget -filename] != ""} {
            $self reparseTree
        }
    }
        
    # @c reparses the code tree
    method reparseTree {} {
        global TloonaApplication
        if {[$self getTree] == ""} {
            return
        }
        
        set ctn [$self get 1.0 end]
        set ctn [string range $ctn 0 end-1]
        
        set T [$self getTree]
        array set sel {}
        foreach {browser} [$self getBrowsers] {
            set sel($browser) [$browser selection]
            $browser remove $T
        }
        
        set newList {}
        set oldList {}
        ::Parser::reparse $T $ctn newList oldList
        foreach {elem} $oldList {
            itcl::delete object $elem
        }
        set cmds {}
        $T getCommands cmds
        $self updateKwHighlight $cmds
        foreach browser [$self getBrowsers] {
            $browser add $T 1 1
            if {$sel($browser) != {} && [$browser exists $sel($browser)]} {
                $browser selection set $sel($browser)
                $browser see $sel($browser)
            }
        }
    }
        
    ## \brief shows the completion box.
    # 
    # With possibilities for commands, ensembles, variables and object methods 
    # to call at the insert position
    method showCmdCompl {{ctrlsp 0}} {
        if {[$self getTree] == ""} {
            return
        }
        
        #set T [component textwin]
        
        set bbox [$self bbox insert]
        set rx [lindex $bbox 0]
        set ry [lindex $bbox 1]
        set cTree [$self getTree]
        set cdf [$cTree lookupRange [$self getTextPos $rx $ry]]
        
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
        set lcw [$self index "insert -1c"]
        set word [$self get "$lcw wordstart" "$lcw wordend"]
        
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
        $completor setItems $realCmds
        $completor configure -background white \
            -foreground [lindex $atmp(Keywords) 0] -forced $ctrlsp
        $completor show $rx $ry
        array unset atmp
    }
    
    # @c shows completion box with variables
    method showVarCompl {} {
        if {[$self getTree] == ""} {
            return
        }
        
        set bbox [$self bbox insert]
        set rx [lindex $bbox 0]
        set ry [lindex $bbox 1]
        set cTree [$self getTree]
        set cdf [$cTree lookupRange [$self getTextPos $rx $ry]]
        
        if {$cdf == ""} {
            set cdf $cTree
        }
        
        set vars {}
        set tp [$self getTextPos]
        foreach {k v} [$cdf getVariables] {
            if {$v > $tp} {
                continue
            }
            lappend vars $k
        }
        
        set vars [lsort -dictionary $vars]
        set ry [expr {$ry + [lindex $bbox 3]}]
        array set atmp $::UserOptions(TclSyntax)
        $completor setItems $vars
        $completor configure -background lightyellow \
            -foreground [lindex $atmp(Vars) 0] -forced 0
        $completor show $rx $ry
        array unset atmp
    }
    
    ## \brief handler for key press events
    #
    # \param key the key that was pressed
    # \param char the ASCII character that is inserted
    method onKeyPress {key char} {
        global tcl_platform
        switch -- $key {
            Return {
                set LastKey $key
                $self HandleInputChar [$self get [$self index "insert -1c"] \
                    [$self index "insert"]]
                after 1 [mymethod indent $IndentLevel]
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
                if {[$self HandleLastWord]} {
                    $self expandTab
                }
                return
            }
            
            colon {
                set LastKey $key
                set chars [$self get "insert linestart" "insert lineend"]
                if {[regexp {^[ \t]*:$} $chars]} {
                    $self showCmdCompl
                }
                return
            }
            
            dollar {
                $self showVarCompl
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
                after 1 [mymethod HandleInputChar $char]
            }
        }
        
    }
    
    # @c jumps to the code definition in the file that is defined
    # @c by codeItem
    method jumpTo {codeItem {def 0}} {
        set line [lindex [split [$self index insert] .] 0]
        set nline [expr {$line + 1}]
        
        $self tag configure inscolorize -background white
        $self tag remove inscolorize $line.0 $nline.0
        set brlist [$codeItem cget -byterange]
        if {[$codeItem isa ::Parser::OOProcNode]} {
            if {$def && [$codeItem cget -bodyextern]} {
                set brlist [$codeItem cget -defbrange]
            }
        }
        
        if {$brlist == {}} {
            return
        }
        set ch [lindex $brlist 0]
        set lc [$self index "1.0 +$ch c"]
        #focus -force [component textwin].t
        $self mark set insert $lc
        $self see insert
    }
        
    # @c flashes the given codeItem in the text. If line is
    # @c false, the whole definition is flashed, otherwise
    # @c only thefirst line
    method flashCode {codeItem {def 0}} {
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
        
        set brEnd [expr {[lindex $br 0] + [lindex $br 1]}]
        set lc0 [$self index "1.0 +[lindex $br 0] c"]
        set lc1 [$self index "1.0 +$brEnd c"]
        $self tag add flash $lc0 $lc1
        
        $self tag configure flash -background yellow
        after $::UserOptions(FlashTime) [list $self tag delete flash]
        #$self colorizeInsert
        $self get $lc0 $lc1
    }
        
    # @c updates the highlighting for hclass. The corresponding
    # @c commands are highlighted in color and the constructed
    # @c tag is configured with font
    #
    # @a hclass: highlight class and tag descriptor
    # @a color: color to use for hclass
    # @a font: font to use for hclass
    method updateHighlight {hclass color font} {
        set nothing 0
        set err 0
        set a b
        
        set T [$self childsite].textwin
        switch -- $hclass {
        "Keywords" {
            if {[set ctree [$self getTree]] != ""} {
                set cmds ""
                $ctree getCommands cmds
                ::ctext::addHighlightClass $T $hclass $color $cmds
            }
        }
        "Braces" {
            ::ctext::addHighlightClassForSpecialChars $T $hclass $color "\{\}"
        }
        "Brackets" {
            ::ctext::addHighlightClassForSpecialChars $T $hclass $color "\[\]"
        }
        "Parens" {
            ::ctext::addHighlightClassForSpecialChars $T $hclass $color "()"
        }
        "Options" {
            ::ctext::addHighlightClassForRegexp $T $hclass $color {[ \t]+-[a-zA-Z_]\w+}
        }
        "Digits" {
            ::ctext::addHighlightClassForRegexp $T $hclass $color {[0-9]*\.?[0-9]+}
        }
        "Comments" {
            ::ctext::addHighlightClassForRegexp $T $hclass $color {^[ \t]*#.*|;[ \t]*#.*}
        }
        "Strings" {
            ::ctext::addHighlightClassForRegexp $T $hclass $color {".*"}
        }
        "Vars" {
            ::ctext::addHighlightClassWithOnlyCharStart $T $hclass $color "\$"
        }
        default {
            return
        }
        }
        
        $self tag configure $hclass -font $font
        
    }
        
    
    # @c updates all highlight classes
    method updateHighlights {} {
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
            $self updateHighlight $k [lindex $v 0] $fnt
        }
        
        $self highlight 1.0 end
    }
        
    # @c update the keyword highlight
    method updateKwHighlight {keyWords} {
        global UserOptions
        
        set fnt $UserOptions(FileFont)
        if {[llength $fnt] < 3} {
            lappend fnt ""
        }
        set i [lsearch $UserOptions(TclSyntax) Keywords]
        set tl [lindex $UserOptions(TclSyntax) [incr i]]
        lset fnt 2 [lindex $tl 1]
        ::ctext::addHighlightClass $self Keywords [lindex $tl 0] $keyWords
        $self tag configure Keywords -font $fnt
    }
        
    # @c inserts a code template for a spezial word at insert
    # @c position. Places the insertion cursor smartly
    #
    # @a word:
    # @a indent:
    method insertTemplate {word {indent 0}} {
        set line [lindex [split [$self index insert] .] 0]
        set nline [expr {$line + 1}]
        $self tag configure inscolorize -background white
        $self tag remove inscolorize $line.0 $nline.0
        
        set ci [$self index insert]
        set iStr ""
        set insPos 2c
        switch -- $word {
            for {
                set iStr " \{\} \{\} \{\} \{\n"
                append iStr "[string repeat " " $indent]\}"
            }
            foreach {
                set iStr " \{\} \{\} \{\n"
                append iStr "[string repeat " " $indent]\}"
            }
            if -
            elseif {
                set iStr " \{\} \{\n"
                append iStr "[string repeat " " $indent]\}"
            }
            else {
                set innerInd [expr {$indent + $tabsize}]
                set iStr " \{\n"
                append iStr "[string repeat " " $innerInd]\n"
                set insPos [expr {[string length $iStr] - 1}]
                append iStr "[string repeat " " $indent]\}"
            }
            switch {
                set iStr " --  \{\n[string repeat " " $indent]\}"
                set insPos 4c
            }
            proc {
                set iStr "  \{\} \{\n[string repeat " " $indent]\}"
                set insPos 1c
            }
            method {
                set iStr "  \{\}"
                set insPos 1c
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
                set insPos 1c
            }
            test {
                set iStr "  \"\" -setup \{\n"
                append iStr "[string repeat " " $indent]\} -body \{\n"
                append iStr "[string repeat " " $indent]\} -cleanup \{\n"
                append iStr "[string repeat " " $indent]\} -result \{\}\n"
                set insPos 1c
            }
            default {
                return
            }
        }
        
        $self fastinsert insert $iStr
        after 1 [mymethod deleteCharBefore insert]
        after 2 [list $self mark set insert "$ci +$insPos"]
        $self highlight "$ci" "$ci +[string length $iStr]c"
        
    }
    
    # @c toggle comments
    #
    # @a start: start index for comment
    # @a end: end index for comment
    method toggleComment {start end} {
        set ls [lindex [split $start .] 0]
        set le [lindex [split $end .] 0]
        set minInd 1000000
        
        for {set i $ls} {$i <= $le} {incr i} {
            set line [$self get $i.0 "$i.0 lineend"]
            set v ""
            regexp -all {^([ \t]*)[^ ]+} $line m v
            if {[set nl [string length $v]] < $minInd} {
                set minInd $nl
            }
        }
        
        set minInd1 [expr {$minInd + 1}]
        for {set i $ls} {$i <= $le} {incr i} {
            set line [$self get $i.0 "$i.0 lineend"]
            if {[regexp "^\[ \\t\]\{$minInd\}#" $line]} {
                $self delete $i.$minInd $i.$minInd1
            } else {
                $self insert $i.$minInd "#"
            }
        }
        
        $self highlight $start $end
    }
    
    # @c indent the code after a new line
    method indent {level} {
        $self fastinsert insert [string repeat " " $level]
    }
    
    # @c indent a code block
    # 
    # @a indent: indent level
    # @a start: start index in text widget
    # @a end: end index in text widget
    method indentBlock {indent start end} {
        set ls [lindex [split $start .] 0]
        set le [lindex [split $end .] 0]
        
        # check if the indentation level is appropriate for
        # unindentation. If the block is not at least one times 
        # indented, do nothing
        set minInd 1000000
        for {set i $ls} {$i <= $le} {incr i} {
            set line [$self get $i.0 "$i.0 lineend"]
            set v ""
            set rr [regexp -all {^([ \t]*)[^ ]+} $line m v]
            if {$rr && ([set nl [string length $v]] < $minInd)} {
                set minInd $nl
            }
        }
        
        set iStr "\t"
        if {[$self cget -expandtab]} {
            set iStr [string repeat " " [$self cget -tabsize]]
        }
        set realInd [expr {$minInd - [string length $iStr]}]
        if {! $indent && $realInd < 0} {
            return
        }
        
        for {set i $ls} {$i <= $le} {incr i} {
            set line [$self get $i.0 "$i.0 lineend"]
            if {$indent} {
                $self insert $i.0 $iStr
            } else {
                $self delete $i.0 $i.[string length $iStr]
            }
        }
        
        $self tag add sel "$start linestart" "$end lineend"
    }
    
    # @c Sends code to via the sendcmd procedure
    method sendCode {} {
        if {$options(-sendcmd) == ""} {
            return
        }
        uplevel #0 $options(-sendcmd) [list [::Tloona::getNodeDefinition [$self getCurrentNode] $self]]
    }
    
    # @c set default bindings for the widget
    method SetBindings {} {
        global UserOptions
        set T [$self childsite].textwin
        
        # switch the bindtags sequence. The textwin (ctags textwin)
        # must come first in the list
        set ntags [lindex [bindtags $T] 1]
        lappend ntags [lindex [bindtags $T] 0]
        set ntags [concat $ntags [lrange [bindtags $T] 2 end]]
        bindtags $win $ntags
        
        # code completion bindings
        set accel $UserOptions(DefaultModifier)
        set accel [regsub {Ctrl} $accel Control]
        set accel [regsub {Meta} $accel M1]
        bind $T <[set accel]-space> [mymethod showCmdCompl 1]
        bind $T <[set accel]-Return> "[mymethod sendCode];break"

        #bind $T <Key-Up> [mymethod updateCurrentNode]
        #bind $T <Key-Down> [mymethod updateCurrentNode]
        bind $T <Key-Left> [mymethod updateCurrentNode]
        bind $T <Key-Right> [mymethod updateCurrentNode]
        bind $T <KeyPress> [mymethod onKeyPress %K %A]
        bind $T <KeyRelease> [mymethod HandleInputChar %A]
    }
    
    # @c handles the character that was typed last. Invoked 
    # @c from the onKeyPress handler
    # 
    # @a char: the input char
    # @a keyrelease: 1 if the callback was triggered from a
    # @a keyrelease: key release event
    method HandleInputChar {char} {
        global tcl_platform
        #set T $self
        if {$char == {}} {
            return
        }
        
        set tIdx [$self index insert]
        set line [$self get "$tIdx linestart" $tIdx]
        set tabsize [$self cget -tabsize]
        switch -- $char {
        \" {
            if {$::UserOptions(File,MatchQuotes) && $LastKey != "Return"} {
                $self fastinsert insert "\""
                $self mark set insert "insert -1c"
                $self highlight "insert" "insert +10c"
            }
        }
        ( {
            if {$::UserOptions(File,MatchParens)} {
                $self fastinsert insert ")"
                $self mark set insert "insert -1c"
                $self highlight "insert" "insert +1c"
            }
        }
        \{ {
            set c [$self get $tIdx "$tIdx lineend"]
            if {$LastKey == "Return" && $c != "\}"} {
                regexp -all {^([ \t]*)[^ ]+} $line m v1
                set IndentLevel [expr { [string len $v1] + $tabsize }]
            } elseif {$LastKey == "Return"} {
                $self highlight "insert" "insert +50c"
                # do nothing
            } elseif {$::UserOptions(File,MatchBraces)} {
                $self fastinsert insert "\}"
                $self mark set insert "insert -1c"
                $self highlight "insert" "insert +1c"
            }
        }
        \[ {
            set c [$self get $tIdx "$tIdx lineend"]
            if {$LastKey == "Return" && $c != "\}"} {
                regexp -all {^([ \t]*)[^ ]+} $line m v1
                set IndentLevel [expr { [string length $v1] + $tabsize }]
            } elseif {$LastKey == "Return"} {
                $self highlight "insert" "insert +50c"
                # do nothing
            } elseif {$::UserOptions(File,MatchBrackets)} {
                $self fastinsert insert "\]"
                $self mark set insert "insert -1c"
                $self highlight "insert" "insert +1c"
            }
        }
        \} {
            if {$LastKey == "Return"} {
                regexp -all {^([ \t]*).*$} $line m v1
                set IndentLevel [string length $v1]
            } else {
                set l [$self get "$tIdx linestart" "$tIdx lineend"]
                if {[regexp {^[ \t]*\}} $l]} {
                    set IndentLevel [expr { $IndentLevel - $tabsize }]
                    set l [lindex [split $tIdx .] 0]
                    set c [lindex [split $tIdx .] 1]
                    $self fastdelete $l.[expr {$c - $tabsize - 1}] "insert -1c"
                }
            }
        }
        \] {
            if {$LastKey == "Return"} {
                regexp -all {^([ \t]*).*$} $line m v1
                set IndentLevel [string length $v1]
            } else {
                set l [$self get "$tIdx linestart" "$tIdx lineend"]
                if {[regexp {^[ \t]*\}} $l]} {
                    set IndentLevel [expr { $IndentLevel - 2 * $tabsize }]
                    set l [lindex [split $tIdx .] 0]
                    set c [lindex [split $tIdx .] 1]
                    $self fastdelete $l.[expr {$c - 2 * $tabsize - 1}] "insert -1c"
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
    
    # @c handles the word just before the insertion cursor.
    # @c Invoked from onKeyPress handler if the key is space
    method HandleLastWord {} {
        set lcw [$self index "insert -1c"]
        set word [$self get "$lcw wordstart" "$lcw wordend"]
        
        set line [$self get "insert linestart" "insert"]
        
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
                $self insertTemplate $word [string length $v1]
                return 0
            }
            
            default {
                return 1
            }
    
        }
    }
    
} ;# tclfile

# @c Represents a web file. This are files that contain HTML and/or
# @c Tcl code wrapped in any special tags (for AOLserver, Tclhttpd 
# @c or whatever).
# @c In addition to provide syntax highlighting and code completion,
# @c for Tcl, web files have these features for HTML.
snit::widgetadaptor webfile {
    
    constructor {args} {
        installhull using tclfile
        #setTree [::Parser::Webscript -ts ::#auto -type "webscript"]
        $self configurelist $args
    }
    
    method updateHighlights {} {
        global UserOptions
        
        Tloona::TclFile::updateHighlights
        
        # update highlighting. First, check whether font
        # has three elements (last being a style) or two
        # (normal style anyway)
        set fnt $UserOptions(FileFont)
        if {[llength $fnt] < 3} {
            lappend fnt ""
        }
        set T [$self childsite].t
        foreach {k v} $UserOptions(HtmlSyntax) {
            lset fnt 2 [lindex $v 1]
            set color [lindex $v 0]
            switch -- $k {
            Tags {
                ::ctext::addHighlightClassForRegexp $T Tags \
                    $color {(?:</?\w+[ \t>])|(/>)}
                $self tag configure $k -font $fnt
            }
            TagOptions {
                ::ctext::addHighlightClassForRegexp $T TagName $color {\w+="}
            }
            HtmlComment {
                ::ctext::addHighlightClassForRegexp $T $k $color {<!--.*-->}
                $self tag configure $k -font $fnt
            }
            }
        }
        
        $self highlight 1.0 end
    }
    
    method showTagCompl {} {
        set bbox [$self bbox insert]
        set rx [lindex $bbox 0]
        set ry [lindex $bbox 1]
        #set cmds $::Tloona::HtmlTags
        set cmds [array names ::Tloona::Html::Tags]
        
        # see TclFile::showCmdCompl
        set lcw [$self index "insert -1c"]
        set word [$self get "$lcw wordstart" "$lcw wordend"]
        
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
        $self completor setItems $realCmds
        $self completor configure -background white \
            -foreground [lindex $atmp(Tags) 0] -forced 1
        $self completor show $rx $ry
        array unset atmp
    }
        
    method showAttrCompl {} {
        set ci [$self index insert]
        # search the start sign for this tag
        if {[set tagName [$self getTag $ci]] == ""} {
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
        
        set bbox [$self bbox insert]
        set rx [lindex $bbox 0]
        set ry [lindex $bbox 1]
        
        set ry [expr {$ry + [lindex $bbox 3]}]
        array set atmp $::UserOptions(HtmlSyntax)
        $self completor setItems $attrList ;#$realCmds
        $self completor configure -background white \
            -foreground [lindex $atmp(Tags) 0] -forced 1
        $self completor show $rx $ry 1
        array unset atmp
        
        # this appends '=""' to the attribute and places the cursor 
        # between the quotes. The script releases the binding by itself
        # after it is done
        bind [$self childsite].t <<InsCompletion>> [list apply {{W} {
            $W fastinsert insert =\"\"
            set ci [$W index insert]
            $W mark set insert "[$W index insert] -1c"
            bind $W <<InsCompletion>> {}
        }} [$self childsite].t]
        
        #set script "$T fastinsert insert =\"\"\n"
        #append script "set ci \[$T index insert\]\n"
        #append script "$T mark set insert \"\$ci -1c\"\n"
        #append script "bind $T <<InsCompletion>> {}\n"
        #bind [component textwin] <<InsCompletion>> $script
    }
    
    method matchTag {} {
        set ci [$self index insert]
        
        if {[$self get "insert -1c"] == "/"} {
            # no closing tag needed
            return
        }
        
        switch -- [set tagName [$self getTag $ci]] {
            "" -
            "%" -
            "%=" -
            "\$" -
            br/ {
                return
            }
            br {
                $self insert insert /
                return
            }
        }
        
        # if it is a closing tag or no starttag was found, 
        # do nothing. We might decrease the insert later on, 
        # maybe...
        
        after 1 [list $self insert "insert" "</$tagName>"]
        after 2 [list $self mark set insert "$ci +1c"]
    }
    
    # @c Overwritten for the moment because there is no real and 
    # @c useful tree in web files currently
    method reparseTree {} {
    }
    
    # @c Overwritten for the moment because there is no real and 
    # @c useful tree in web files currently
    method updateCurrentNode {{x -1} {y -1}} {
    }
    
    method setBindings {} {
        $hull setBindings
        
        set T [$self childsite].t
        bind $T <Key-less> [mymethod showTagCompl]
        bind $T <Key-greater> [mymethod matchTag]
        bind $T <Key-space> [mymethod showAttrCompl]
    }
    
    method getTag {index} {
        # search the start sign for this tag
        set row [lindex [split $index .] 0]
        set col [lindex [split $index .] 1]
        set tagName ""
        while {$col >= 0} {
            set char [$self get $row.$col]
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
    
} ;# webfile


} ;# namespace Tloona

package provide tloona::file 2.0.0
