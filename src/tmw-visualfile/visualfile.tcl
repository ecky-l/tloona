## visualfile.tcl (created by Tloona here)

#lappend auto_path [pwd]/src [pwd]/lib

package require snit 2.3.2
package require tmw::toolbarframe 2.0.0
package require tmw::vitext

namespace eval Tmw {

## \brief general class for a visual file. 
snit::widgetadaptor visualfile {
    
    #### Options
    option {-modifiedcmd modifiedCmd Command} -default {} -configuremethod ConfigModifiedCmd
    option {-button1cmd button1Cmd Command} -default {} -configuremethod ConfigButton1Cmd
    
    ## \brief line ending for save. lf (unix), crlf (windows) or auto
    option -savelineendings auto
    ## \brief the browser object for the file. Used for display in file browsers (not code browsers)
    option -browserobj {}
    ## \brief the main window where the file lives
    option -mainwindow ""
    ## \brief the filename
    option -filename ""
    ## \brief whether to create a backup file
    option -backupfile 1
    ## \brief tab size in spaces
    option -tabsize 4
    ## \brief expand tab characters with spaces
    option -expandtab 1
    ## \brief String to search for in the file
    option -searchstring -default "" -configuremethod ConfigSearchString 
    ## \brief String that replaces occurence of SearchFor
    option -replacestring -default "" -configuremethod ConfigReplaceString
    ## \brief Search parameter for -exact flag
    option -searchexact 1
    ## \brief Search parameter for -regexp flag
    option -searchregex 0
    ## \brief Search parameter for -nocase flag
    option -searchnocase 0
        
    #### Components
    delegate method childsite to hull
    delegate method dropframe to hull
    delegate method tbexists to hull
    delegate method tbhide to hull
    delegate method tbshow to hull
    delegate method toolbar to hull
    delegate method toolbutton to hull
    
    delegate option -relief to hull
    delegate option -borderwidth to hull
    delegate option -height to hull
    delegate option -width to hull
    
    component vscroll
    component hscroll
    
    component textwin
    delegate method * to textwin
    delegate option -textrelief to textwin as -relief
    delegate option -textbd to textwin as -borderwidth
    delegate option * to textwin
    
    #### Variables
    
    ## \brief the current indentation level
    variable IndentLevel 0
    ## \brief the last pressed key
    variable LastKey ""
    ## \brief The last pressed modifier
    variable LastModifier ""
    ## \brief indicates whether search bar is showing
    variable ShowingSearch 0
    ## \brief The actual search Index
    variable SearchIndex 1.0
    ## \brief the search entry widget
    variable WSearch ""
    ## \brief the replace entry widget
    variable WReplace ""

    ## \brief List of file only browsers where this object appears
    variable FileBrowsers {}
    
    variable _OldLinePos 1
        
    constructor {args} {
        installhull using Tmw::toolbarframe
        set cs [$self childsite]
        install textwin using vitext $cs.textwin
        #install textwin using ctext $cs.textwin
        install vscroll using ttk::scrollbar $cs.vscroll \
            -command "$textwin yview" -orient vertical
        install hscroll using ttk::scrollbar $cs.hscroll \
            -command "$textwin xview" -orient horizontal
        
        $textwin configure -xscrollcommand "$hscroll set" \
            -yscrollcommand "$vscroll set"
        
        grid $textwin -column 0 -row 0 -sticky news
        grid $vscroll -column 1 -row 0 -sticky nsw
        grid $hscroll -column 0 -row 1 -sticky wen
        
        grid rowconfigure $cs 0 -weight 1
        grid columnconfigure $cs 0 -weight 1
        
        $self configure -wrap none -textrelief flat -textbd 0
        
        # colorize the line where the insert cursor is
        bind $textwin.t <KeyPress> +[mymethod colorizeInsLine]
        bind $textwin.t <Button-1> +[mymethod colorizeInsLine %x %y]
        bind $textwin <Button-1> +[mymethod adjustSearchIndex]
        bind $textwin.t <FocusIn> [list $self tag delete sflash]
        $self configurelist $args
    }
    
    
    destructor {
        if {$options(-backupfile) && $options(-filename) != ""} {
            set fn $options(-backupfile).bak
            file delete $fn
        }
        
    }
    
    method textwin {args} {
        if {$args == {}} {
            return $textwin
        }
        $textwin {*}$args
    }
    
    ## \brief add to a file browser
    method addToFileBrowser {browser} {
        if {![$browser exists $options(-browserobj)]} {
            $browser add $options(-browserobj) 1 0
        }
        
        if {[lsearch $FileBrowsers $browser] < 0} {
            lappend FileBrowsers $browser
        }
    }
    
    ## \brief remove from a file browser
    method removeFromFileBrowser {browser} {
        $browser remove $browserobj
        set idx [lsearch $FileBrowsers $browser]
        lvarpop BrowserDisplays $idx
    }
    
    # @c saves the file. If file is given as argument,
    # @c it is set as the new filename. Otherwise, the
    # @c filename of this object is used. If no filename
    # @c was set, an error is generated
    method saveFile {{file ""}} {
        if {$file != ""} {
            $self configure -filename $file
        }
        if {$options(-filename) == ""} {
            return -code error "no filename was given"
        }
        
        if {$options(-backupfile) && [file exists $options(-filename)]} {
            set bkf $options(-filename)
            append bkf ".bak"
            file copy -force -- $options(-filename) $bkf
        }
        
        set ctn [$self get 1.0 end]
        set ctn [string range $ctn 0 end-1]
        set fh [open $options(-filename) w]
        fconfigure $fh -translation $options(-savelineendings)
        puts -nonewline $fh $ctn
        close $fh
        
        return $ctn
    }
    
    ## \brief open a file, set the file name if it is not ""
    method openFile {{file ""}} {
        if {$file != ""} {
            $self configure -filename $file
        }
        if {$options(-filename) == ""} {
            return -code error "no filename was given"
        }
        $self delete 1.0 end
        
        if {[catch {open $options(-filename) r} fh]} {
            puts $::errorInfo
            return -code error $fh
        }
        
        set ctn [read $fh]
        close $fh
        $self insert 1.0 $ctn
        $self mark set insert 1.0
        $self edit reset
    }
    
    # @r whether the text is modified
    method modified {{setit ""}} {
        if {$setit != ""} {
            $self edit modified $setit
        }
        
        $self edit modified
    }
    
    ## \brief translates the cursor position at x/y to a byte in the text.
    #
    # \param x,y: x and y position. If both are -1, the insert cursor position
    # \return the cursors byte position
    method getTextPos {{x -1} {y -1}} {
        set curPos @$x,$y
        if {$x == -1 && $y == -1} {
            set curPos insert
        }
        string length [$self get 1.0 [$self index $curPos]]
    }
    
    # @c undo a step of operation. Delegates to [edit undo]
    #
    # @a steps: number of steps to undo
    method undo {{steps 1}} {
        for {set i 0} {$i < $steps} {incr i} {
            $self edit undo
        }
    }
    
    # @c redo a previously undone operation. Delegates to [edit redo]
    #
    # @a steps: number of steps to redo
    method redo {{steps 1}} {
        for {set i 0} {$i < $steps} {incr i} {
            $self edit redo
        }
    }
    
    # @c Shows the search toolbar at the top of the file content. This
    # @c enables for searching (and replacing) text inside the file
    #
    # @a show: 1 for showing, 0 for hiding the toolbar
    method showSearch {show} {
        if {! $show} {
            set ShowingSearch 0
            if {[$self tbexists searchtool]} {
                $self tbhide searchtool
            }
            return
        }
        
        set ShowingSearch 1
        set SearchIndex 1.0
        if {[$self tbexists searchtool]} {
            $self tbshow searchtool
            return
        }
        
        set S [$self toolbar searchtool -pos n -compound none]
        
        # the search widgets: an entry for the search string, a
        # drop widget for search options and up/down buttons
        ttk::label $S.sfl -text "Search:"
        ttk::entry $S.sentry -textvariable [myvar options(-searchstring)]
        pack $S.sfl $S.sentry -expand n -fill none -side left -padx 3 -pady 1
        
        set f [$self dropframe preferences -toolbar searchtool -separate 1 \
            -image $Tmw::Icons(AppTools) -relpos 0]
        ttk::checkbutton $f.exact -text Exact -variable [myvar options(-searchexact)] \
            -command [mymethod searchOptsChanged searchexact]
        ttk::checkbutton $f.regex -text Regex -variable [myvar options(-searchregex)] \
            -command [mymethod searchOptsChanged searchregex]
        ttk::checkbutton $f.nocase -text Nocase -variable [myvar options(-searchnocase)] \
            -command [mymethod searchOptsChanged searchnocase]
        pack $f.exact $f.regex $f.nocase -side top -anchor w -expand y -fill both
        
        set upb [$self toolbutton up -toolbar searchtool -type command \
            -image $Tmw::Icons(NavUp) -separate 0 -state disabled \
            -command [mymethod doSearch -backwards]]
        set downb [$self toolbutton down -toolbar searchtool -type command \
            -image $Tmw::Icons(NavDown) -separate 1 -state disabled \
            -command [mymethod doSearch -forwards]]
        
        # the replace widgets: an entry for the replace string, a
        # button for replacing the current selection
        ttk::label $S.rpb -text "Replace:"
        ttk::entry $S.rentry -textvariable [myvar options(-replacestring)]
        pack $S.rpb $S.rentry -expand n -fill none -side left \
            -padx 3 -pady 1
        
        set replb [$self toolbutton replace -toolbar searchtool -separate 0 \
            -image $Tmw::Icons(ActCheck) -state disabled \
            -command [mymethod doReplace] -type command]
        
        # bindings for validation and such
        bind $S.sentry <KeyRelease> [mymethod enableSearchButtons -searchstring $upb $downb]
        bind $S.rentry <KeyRelease> [mymethod enableSearchButtons -replacestring $replb]
        bind $S.sentry <Return> [mymethod doSearch -forwards]
        bind $S.rentry <Return> [mymethod doSearch -backwards]
        bind $S.sentry <Alt-r> [mymethod doReplace]
        bind $S.rentry <Alt-r> [mymethod doReplace]
        
        lappend WSearch $S.sentry $upb $downb
        lappend WReplace $S.rentry $replb
    }
    
    ## \brief callback for colorizing insert line
    method colorizeInsLine {{x -1} {y -1}} {
        set currPos insert
        if {$x >= 0 || $y >= 0} {
            set currPos @$x,$y
        }
        if {"inscolorize" in [$self tag names] \
                && [$self tag ranges inscolorize] != {}} {
            $self tag configure inscolorize -background white
            $self tag remove inscolorize inscolorize.first inscolorize.last
        }
        
        #after 2 [list apply {{}}]
        after 2 [list apply {{W currPos} {
            $W tag add inscolorize [list $currPos linestart] \
                [list $currPos lineend]+1displayindices
            $W tag configure inscolorize -background #e0f1ff
            $W tag raise sel
            $W see $currPos
        }} $self $currPos]
    }
    
    # @r whether the search toolbar is showing
    method showingSearch {} {
        return $ShowingSearch
    }
    
    # @c Triggers a search in the text window. The String in the
    # @c protected variable SearchFor is used for search, if it is
    # @c not empty
    #
    # @a direction: the direction in which to search
    method doSearch {direction} {
        global tcl_platform
        
        $self tag delete sflash
        
        if { $options(-searchstring) == "" } {
            return
        }
        switch -- $direction {
            -forwards -
            -backwards {
            }
            default {
                error "direction can only be -forwards or -backwards"
            }
        }
        
        if {"sel" in [$self tag names] && [$self tag ranges sel] != {}} {
            $self tag remove sel sel.first sel.last
        }
        
        set tmpsi $SearchIndex
        set SearchIndex [eval $self search $direction \
            [expr { $options(-searchexact) ? "-exact" : "" } ] \
            [expr { $options(-searchregex) ? "-regexp" : "" } ] \
            [expr { $options(-searchnocase) ? "-nocase" : "" } ] \
            [list $options(-searchstring)] $SearchIndex]
        
        if {$SearchIndex == ""} {
            # not found
            set SearchIndex $tmpsi
            return
        }
        
        set len [string length $options(-searchstring)]
        $self tag add sel $SearchIndex "$SearchIndex + $len chars"
        $self see "$SearchIndex wordend"
        
        # on windows, the text is only highlighted if the textwin has focus
        # this is a fake selection in adddition to the normal one
        if {[string match $tcl_platform(platform) windows] \
                && ![string match [focus] $textwin.t]} {
            $self tag add sflash $SearchIndex "$SearchIndex + $len chars"
            $self tag configure sflash -background blue -foreground white
        }
        
        set SearchIndex [$self index "$SearchIndex + $len chars"]
    }
    
    # @c Triggers a replace action in the text window. The highlighted
    # @c region in the text is replaced by the content of ReplaceBy, if
    # @c it is equal to the SearchFor string.
    method doReplace {} {
        if { $options(-replacestring) == "" \
                || $options(-searchstring) == ""} {
            return
        }
        
        if {[catch {
                set s0 [$self index sel.first]
                set s1 [$self index sel.last]
            } msg]} {
            return
        }
        
        $self delete $s0 $s1
        $self fastinsert $s0 $options(-replacestring)
        set len [string length $options(-replacestring)]
        set SearchIndex [$self index "$s0 + $len chars"]
    }
    
    # @r the search entry widget
    method getSearchEntry {} {
        return [lindex $WSearch 0]
    }
    
    # @r the replace entry widget
    method getReplaceEntry {} {
        return [lindex $WReplace 0]
    }
    
    # @c update highlights dummy method. Meant to be overwritten by
    # @c client classes
    method updateHighlights {} {
    }
    
    ## \brief Displays a byte range in the file. 
    #
    # If offset is < 0, every display from before is cleared.
    
    # \param offset byte offset for display start
    # \param length byte length
    # \param color background color for the text
    method displayByteRange {offset length color} {
        $self tag configure inscolorize -background white
        eval $self tag remove inscolorize [$self tag ranges inscolorize]
        
        set ni [$self index "1.0 + $offset chars"]
        set li [$self index "1.0 + [expr {$offset + $length}] chars"]
        $self tag add inscolorize $ni $li
        $self tag configure inscolorize -background $color
        $self see $ni
    }
    
    method deleteCharBefore {index} {
        $self delete "$index -1c" "$index"
    }
    
    method expandTab {} {
        # @c sets up the bindings
        set LastKey Tab
        if {! $options(-expandtab)} {
            return
        }
        
        $self fastinsert insert [string repeat " " $options(-tabsize)]
        incr IndentLevel $options(-tabsize)
        after 1 [mymethod deleteCharBefore insert]
    }
    
    ## \brief validation command for search entries. 
    # Enables the buttons according on whether the entries are empty
    #
    # \param var either SearchFor or ReplaceBy
    # \param args list of buttons to enable/disable
    method enableSearchButtons {varPtr args} {
        # for some reason the value can not be obtained via [cget]
        # before this is done:
        #$self configure -$varPtr [set $varPtr]
        
        set state [expr {($options($varPtr) == "") ? "disabled" : "normal"}]
        foreach {widget} $args {
            $widget configure -state $state
        }
        event generate $win <<SearchOptionsChanged>>
        return 1
    }
        
    # @c helper method to generate event on changing search
    # @c options
    #
    # @a varPtr: variable to configure
    method searchOptsChanged {varPtr} {
        configure -$varPtr [set $varPtr]
        event generate $itk_interior <<SearchOptionsChanged>>
    }
    
    # @c adjusts the search index, when the user clicks
    # @c in the file
    method adjustSearchIndex {} {
        set SearchIndex [$self index insert]
    }
    
    ## \brief configuremethod for -modifiedcmd
    method ConfigModifiedCmd {option value} {
        set options($option) $value
        bind $textwin <<Modified>> $value
    }
    
    ## \brief configuremethod for -button1cmd
    method ConfigButton1Cmd {option value} {
        set options($option) $value
        bind $textwin.t <Button-1> $value
    }
    
    ## \brief configuremethod for -searchstring
    method ConfigSearchString {option value} {
        set options($option) $value
        set state disabled
        if {$value != ""} {
            set state normal
        }
        foreach {w} [lrange $WSearch 1 end] {
            $w configure -state $state
        }
    }
    
    ## \brief configuremethod for -replacestring
    method ConfigReplaceString {option value} {
        set options($option) $value
        set state disabled
        if {$value != ""} {
            set state normal
        }
        foreach {w} [lrange $WReplace 1 end] {
            $w configure -state $state
        }
    }
        
} ;# visualfile

} ;# namespace Tmw

package provide tmw::visualfile 2.0.0

### Test Code
#package re Tk
#Tmw::visualfile .v -vimode true
#pack .v
