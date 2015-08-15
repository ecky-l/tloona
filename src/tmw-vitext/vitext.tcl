package re Tk
package require snit 2.3.2
package require ctext 3.3

namespace eval Tmw {
    namespace export vitext
}

## \brief a vi mode enabled text
# 
# This serves as base class for any other texts that can have vi mode
snit::widgetadaptor Tmw::ViText {
    delegate method * to hull
    delegate option * to hull
    
    option -vimode -default y -configuremethod SetupViMode
    
    option -commandmode y
    option -vismode n
    
    option {-cmdinsertbg cmdInsertBg CmdInsertBg} -default red -configuremethod ConfigCursor
    option {-insinsertbg insInsertBg InsInsertBg} -default red -configuremethod ConfigCursor
    option {-visinsertbg visInsertBg VisInsertBg} -default grey -configuremethod ConfigCursor
    
    option -linestart {insert linestart}
    option -lineend {insert lineend}
    option -textstart 1.0
    option -textend end
    
    option -upcmd -configuremethod ConfigArrowBinding
    option -downcmd -configuremethod ConfigArrowBinding
    option -leftcmd -configuremethod ConfigArrowBinding
    option -rightcmd -configuremethod ConfigArrowBinding
    option -homecmd -configuremethod ConfigHEBinding
    option -endcmd -configuremethod ConfigHEBinding
    option -backspacecmd -configuremethod ConfigBackspaceBinding
    option -wordcmd -configuremethod ConfigWBBinding
    option -backcmd -configuremethod ConfigWBBinding
    
    option -cutlinecmd -configuremethod ConfigCutYankPaste
    option -yanklinecmd -configuremethod ConfigCutYankPaste
    option -pastecmd -configuremethod ConfigCutYankPaste
    ## \brief backup default KeyPress bindings for command mode
    variable DefaultBindings -array {}
    ## \brief Command mode bindings
    variable CmdBindings -array {}
    
    ## \brief Matching parens array.
    #
    # Contains the matching paren, brace, or bracket for each of these chars
    typevariable MatchingParens -array {
        \{,v     \}
        \{,d     -forwards
        \[,v     \]
        \[,d     -forwards
        (,v      )
        (,d      -forwards
        \},v     \{
        \},d     -backwards
        \],v     \[
        \],d     -backwards
        ),v      (
        ),d      -backwards
    }
    
    ## \brief A number of repeatings for a following command
    variable RepeatBuf 1
    
    ## \brief A key command such as "d", "y" ...
    # 
    # Stores the Key command, which is followed by the real command. 
    # E.g. "d" refers to a delete operation, but the deletion is not done
    # until "w" or "l" or other motion commands are pressed afterwards.
    # Then a word ("w") or char ("l") is deleted. Key commands can be combined
    # with repeat modifiers
    variable KeyCommand {}
    
    ## \brief indicator for last yanked/cut tag type
    #
    # May be one of line or word. In VI mode this influnences how the last
    # copied tag type is inserted on paste. If this variable is empty (not a 
    # line or word), the whole clipboard is threated as the last selection and
    # inserted as normal. The variable is set on cut/copy/change word or line
    # and used in paste events. 
    variable LastCutYank {}
    
    constructor {args} {
        installhull using ctext
        $win configure -exportselection y
        set options(-upcmd) [list apply {{W} {
            ::tk::TextSetCursor $W [::tk::TextUpDownLine $W -1]
            $W see insert
        }} $win]
        set options(-downcmd) [list apply {{W} {
            ::tk::TextSetCursor $W [::tk::TextUpDownLine $W 1]
            $W see insert
        }} $win]
        set options(-leftcmd) [list apply {{W} {
            ::tk::TextSetCursor $W insert-1displayindices
            $W see insert
        }} $win]
        set options(-rightcmd) [list apply {{W} {
            ::tk::TextSetCursor $W insert+1displayindices
            $W see insert
        }} $win]
        set options(-homecmd) [list apply {{W} {
            ::tk::TextSetCursor $W {insert display linestart}
            $W see insert
        }} $win]
        set options(-endcmd) [list apply {{W} {
            ::tk::TextSetCursor $W [list insert display lineend]-1displayindices
            $W see insert
        }} $win]
        set options(-backspacecmd) [list apply {{W} {
            if {[::tk::TextCursorInSelection $W]} {
	            $W delete sel.first sel.last
            } elseif {[$W compare insert != 1.0]} {
	            $W delete insert-1c
            }
            $W see insert            
        }} $win]
        set options(-wordcmd) [list apply {{W} {
            ::tk::TextSetCursor $W [::tk::TextNextWord $W insert]+1displayindices
            $W see insert
        }} $win]
        set options(-backcmd) [list apply {{W} {
            ::tk::TextSetCursor $W [::tk::TextPrevPos $W insert tcl_startOfPreviousWord]
            $W see insert
        }} $win]
        set options(-cutlinecmd) [list apply {{W si} {
            $W tag add sel $si {insert lineend}
            tk_textCut $W
            $W see insert
        }} $win]
        set options(-yanklinecmd) [list apply {{W si} {
            $W tag add sel $si {insert lineend}
            tk_textCopy $W
            $W tag remove sel {insert linestart} {insert lineend}
            $W see insert
        }} $win]
        set options(-pastecmd) [list apply {{W si} {
            $W mark set insert $si
            tk_textPaste $W
        }} $win]
        
        # setup the command mode bindings
        set CmdBindings(i) [mymethod setInsertMode]
        set CmdBindings(a) [mymethod setAppendMode insert+1char]
        set CmdBindings(A) [mymethod setAppendMode {insert display lineend}]
        set CmdBindings(h) $options(-leftcmd)
        set CmdBindings(j) $options(-downcmd)
        set CmdBindings(k) $options(-upcmd)
        set CmdBindings(l) $options(-rightcmd)
        set CmdBindings(0) $options(-homecmd)
        set CmdBindings(dollar) $options(-endcmd)
        set CmdBindings(w) $options(-wordcmd)
        set CmdBindings(b) $options(-backcmd)
        
        set CmdBindings(d) $options(-cutlinecmd)
        set CmdBindings(y) $options(-yanklinecmd)
        set CmdBindings(D) $options(-cutlinecmd)
        set CmdBindings(Y) $options(-yanklinecmd)
        
        $self configurelist $args
    }
    
    destructor {
        puts "bye"
    }
    
    ## \brief Puts the text widget into command mode
    #
    # Sets up the key bindings that are handled for VI command mode.
    # Backs up the current key bindings so that they can be restored later
    method setCommandMode {} {
        set options(-commandmode) y
        set DefaultBindings(<KeyPress>) [bind $win <KeyPress>]
        set DefaultBindings(<KeyRelease>) [bind $win <KeyRelease>]
        bind $win <KeyPress> break
        bind $win <KeyRelease> break
        bind $win <KeyPress> "[mymethod HandleKey %K %A] ; break"
        bind $win <Escape> {}
        bind $win <BackSpace> "$options(-leftcmd) ; break"
        $self configure -blockcursor y -insertofftime 0 \
            -insertbackground $options(-cmdinsertbg)
        
        $self AdjustCursorPosEOL
    }
    
    ## \brief Puts the text widget in insert mode
    #
    # Restores the previous key bindings to the text widget and changes
    # the mode
    method setInsertMode {} {
        set options(-commandmode) n
        bind $win <KeyPress> $DefaultBindings(<KeyPress>)
        bind $win <KeyRelease> $DefaultBindings(<KeyRelease>)
        bind $win <Key-BackSpace> "$options(-backspacecmd) ; break"
        bind $win <Escape> "[mymethod setCommandMode] ; break"
        
        $self configure -blockcursor n -insertofftime 0 \
            -insertbackground $options(-insinsertbg)
    }
    
    method setAppendMode {where} {
        $win mark set insert $where
        $self setInsertMode
    }
    
    ##
    # Private methods
    ##
    
    ## \brief Adjust the cursor EOL position in command mode
    # 
    # For command mode the last char in a line is always the last 
    # char of the last word. This method takes care of that
    method AdjustCursorPosEOL {} {
        set ci [$win index insert]
        if {[$win compare $ci == $options(-lineend)] && \
                [$win compare $ci != $options(-linestart)]} {
            ::tk::TextSetCursor $win insert-1c
        }
    }
    
    ## \brief Handles the input key/char in command mode
    method HandleKey {key char} {
        switch -- $key {
        l - w - dollar {
            uplevel #0 $CmdBindings($key)
            after idle [mymethod AdjustCursorPosEOL]
        }
        i - a - A - h - j - k - b {
            if {$RepeatBuf != {}} {
                for {set i 0} {$i < $RepeatBuf} {incr i} {
                    uplevel #0 $CmdBindings($key)
                }
            } else {
                uplevel #0 $CmdBindings($key)
            }
            set RepeatBuf {}
        }
        0 {
            if {$RepeatBuf == {}} {
                uplevel #0 $CmdBindings($key)
                set RepeatBuf {}
            } else {
                append RepeatBuf 0
            }
        }
        d - y {
            if {$KeyCommand == $key} {
                uplevel #0 $CmdBindings($key) $options(-linestart)
                set LastCutYank line
                set KeyCommand {}
            } else {
                set KeyCommand $key
            }
        }
        D - Y {
            uplevel #0 $CmdBindings($key) insert
        }
        P - p {
            if {[string match $LastCutYank line]} {
                set ix [expr {
                    $key == "P" ? 
                        "$options(-linestart)-1l" : 
                        "$options(-linestart)+1l"
                }]
                uplevel #0 $options(-pastecmd) $ix
            } else {
                uplevel #0 $options(-pastecmd) insert
            }
        }
        percent {
            # matching braces
            set cb [$self get insert]
            if {![info exists MatchingParens($cb,v)]} {
                break
            }
            
            set pos [$self SearchMatchingParen $cb]
            $self mark set insert $pos
        }
        default {
            if {[string is digit $char]} {
                append RepeatBuf $char
            }
        }
        }
    }
    
    ## \brief Naive search for matching parens.
    #
    # Starting from the insertion index we go forward or backward 
    # char by char and compare the char at this index to the triggering
    # paren and the end paren. If the triggering paren is found, increment
    # a stack variable (means that there is a pair of the same class of
    # matching parens inside the one  we look for) and decrement the 
    # stack variable if a matching paren was found. There is a match only
    # if the stack variable is zero or below.
    method SearchMatchingParen {cb} {
        switch -- $MatchingParens($cb,d) {
        -forwards {
            set endIdx $options(-textend)
            set op +
        }
        -backwards {
            set endIdx $options(-textstart)
            set op -
        }
        default {
            return insert
        }
        }
        
        set i 1
        set pStack 0
        set idx insert[set op][set i]c
        set ce [$self get $idx]
        while {[$self compare $idx != $endIdx]} {
            if {$ce == $cb} {
                incr pStack
            } elseif {$ce == $MatchingParens($cb,v)} {
                if {$pStack <= 0} {
                    break
                }
                incr pStack -1
            }
            set idx insert[set op][incr i]c
            set ce [$self get $idx]
        }
        return $idx
    }
    
    ## \brief Setup the vi mode
    method SetupViMode {option value} {
        set options($option) $value
        if {$options(-vimode)} {
            $self setCommandMode
        } else {
            $self setInsertMode
        }
    }
    
    method ConfigArrowBinding {option value} {
        set options($option) $value
        set dk { -upcmd <Key-Up> -downcmd <Key-Down> -leftcmd <Key-Left> -rightcmd <Key-Right}
        set ck { -upcmd k -downcmd j -leftcmd h -rightcmd l}
        set CmdBindings([dict get $ck $option]) $value
        bind $win [dict get $dk $option] "$value ; break"
    }
    
    method ConfigHEBinding {option value} {
        set options($option) $value
        set dk { -homecmd <Home> -endcmd <End> }
        set ck { -homecmd 0 -endcmd dollar}
        set CmdBindings([dict get $ck $option]) $value
        bind $win [dict get $dk $option] "$value ; break"
    }
    
    method ConfigBackspaceBinding {option value} {
        set options($option) $value
        if {! $options(-commandmode)} {
            bind $win <Key-BackSpace> "$value ; break"
        }
    }
    
    method ConfigWBBinding {option value} {
        set options($option) $value
        set dk { -wordcmd <Control-Right> -backcmd <Control-Left>}
        set ck { -wordcmd w -backcmd b }
        set CmdBindings([dict get $ck $option]) $value
        bind $win [dict get $dk $option] "$value ; break"
    }
    
    method ConfigCursor {option value} {
        set options($option) $value
        if {$options(-commandmode)} {
            $self configure -blockcursor y -insertofftime 0 \
                -insertbackground $options(-cmdinsertbg)
            if {$options(-vismode)} {
                $self configure -blockcursor n -insertofftime 0 \
                    -insertbackground $options(-visinsertbg)
            }
        } else {
            $self configure -blockcursor n -insertofftime 0 \
                -insertbackground $options(-insinsertbg)
        }
    }
    
    method ConfigCutYankPaste {option value} {
        set options($option) $value
        switch -- $option {
        -cutlinecmd {
            set CmdBindings(d) $value
            set CmdBindings(D) $value
        }
        -yanklinecmd {
            set CmdBindings(y) $value
            set CmdBindings(Y) $value
        }
        }
    }
}

proc ::Tmw::vitext {path args} {
    uplevel ::Tmw::ViText $path $args
}

package provide tmw::vitext 1.0

