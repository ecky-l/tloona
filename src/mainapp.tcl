## mainapp.tcl (created by Tloona here)
package require snit 2.3.2
package require tmw::platform 2.0.0
package require tmw::icons 1.0
package require tloona::kitbrowser 2.0.0
package require tloona::projectoutline 2.0.0
package require tmw::console 2.0
package require tloona::file1 1.0
package require fileutil 1.7
package require parser::parse 1.0
package require tloona::debugger 1.0
package require comm 4.3
package require tmw::dialog 2.0.0

namespace eval ::Tloona {

## \brief This is Tloona's main application.
snit::widgetadaptor mainapp {
    
    #### Options
    
    ## \brief font for the text in file objects
    option -filefont {fixed 14}
    ## \brief the tab size for files in chars
    option -filetabsize 4
    ## \brief whether to expand tab chars with spaces
    option -filetabexpand 1
    
    #### Components
    component browsenb
    
    component browsepw -public browsepw
    
    component codebrowser
    component kitbrowser
    #component navigatepw
    component textnb
    component txtconpw -public txtconpw
    component consolenb -public consolenb
    component outlinenb
    
    delegate method * to hull
    delegate option * to hull
    
    
    #### Variables
    
    ## \brief index of the actual file
    variable _FileIdx 0
    ## \brief triple holding file objects
    variable _Files {}
    ## \brief the file that is currently active
    variable _CurrFile ""
    ## \brief holds the vfs projects
    variable _Projects {}
    ## \brief indicates whether the project browser is viewable
    variable _ViewProjectBrowser 1
    ## \brief indicates whether the code outline should be viewed
    variable _ViewOutline 1
    ## \brief indicates that only the text notebook should e shown
    variable _ViewTextNbOnly 0
    ## \brief indicates whether to view the console
    variable _ViewConsole 1
    
    ## \brief indicates whether to view the editor
    variable _ViewEditor 1
    ## \brief indicates whether to view the console only
    variable _ViewConsoleOnly 0
    ## \brief indicates whether search/replace is showing
    variable _ShowSearchReplace 0
    ## \brief initial dir for saving/opening
    variable _InitDir $::env(HOME)
    
    ## \brief A list of registered Comm ids for other interpreters
    variable CommIDs {}
    
    constructor {args} {
        installhull using Tmw::platform
        
        global Icons UserOptions TloonaVersion
        $self CreateMenus
        $self CreatePanes
        $self CreateNavigators
        $self onNewREPL slave
        $self onNewREPL comm
        
        # disable the debugger features for now... this does not work currently
        #$self CreateDebugTools
        #$Debugger configure -console [component output]
        
        wm protocol $self WM_DELETE_WINDOW [mymethod onQuit]
        
        $self configure -title "Tloona - Tcl/Tk Development" \
            -status "Version $TloonaVersion"
        $self configurelist $args
    }
    
    # @r The initial directory for opening files
    method getInitdir {} {
        return $_InitDir
    }
        
    # @c Override callback handler for File.New menu entry.
    method onFileNew {} {
        # @c callback for new Tcl/Itcl scripts
        global UserOptions
        
        set cls [::Tloona::tclfile1 $textnb.file$_FileIdx -font $options(-filefont) \
            -sendcmd [mymethod SendToConsole] \
            -tabsize $options(-filetabsize) -expandtab $options(-filetabexpand) \
            -mainwindow $win -backupfile $UserOptions(File,Backup)]
                
        $cls createTree
        set ttl "unnamed $_FileIdx"
        $textnb add $cls -text $ttl
        $textnb select $cls
        $cls addToBrowser $codebrowser
        $cls modified 0
        $cls configure -modifiedcmd [mymethod showModified $cls 1]
        lappend _Files $ttl $cls 0
        incr _FileIdx
    }
    
    # @c callback handler for File.Open.File menu entry.
    method onFileOpen {} {
        global TloonaApplication
        set uri ""
        set ft {
            {"Tcl Files" {.tcl .tk .tm .itcl .itk .xotcl}}
            {Tests .test}
            {Web {.html .htm .tml .adp}}
        }
        set uri [tk_getOpenFile -initialdir $_InitDir \
                -filetypes  $ft -parent $win]
        if {$uri == ""} {
            return
        }
        openFile $uri 1
    }

    # @c callback handler for File.Open.Project menu entry.
    method onProjectOpen {{uri ""}} {
        if {$uri != ""} {
            $self openFile $uri 0
        }
        
        set uri [tk_chooseDirectory -mustexist 1 -initialdir $_InitDir \
            -parent $win]
        if {$uri == ""} {
            return
        }
        $self openFile $uri 0
    }

    
    # @c Override callback handler for File.Save menu entry.
    method onFileSave {{file ""}} {
        if {$file == ""} {
            set file $_CurrFile
        }
        if {$file == ""} {
            return
        }
        
        set filename ""
        set i 0
        set hasname 0
        foreach {fn fil hn} $_Files {
            if {$fil eq $file} {
                if {$hn} {
                    set filename $fn
                    set hasname 1
                }
                
                break
            }
            incr i 3
        }
        
        if {$hasname} {
            $file saveFile $filename
            $file modified 0
            $self showModified $file 0
            return
        }
        
        set filename [tk_getSaveFile -initialdir $_InitDir -parent $win]
        if {$filename == ""} {
            return
        }
        
        $file saveFile $filename
        lset _Files $i $filename
        lset _Files [expr {$i + 2}] 1
        
        set ttl [file tail $filename]
        $textnb tab $_CurrFile -text $ttl
        set _InitDir [file dirname $filename]
    }
    
    # @c Override callback handler for File.Close menu entry.
    method onFileClose {{file ""}} {
        if {$file == ""} {
            set file $_CurrFile
        }
        if {$file == ""} {
            return
        }
        
        if {[$file modified]} {
            set fn [file tail [$file cget -filename]]
            set ans [tk_messageBox -type yesnocancel -default yes \
                -message "File $fn is modified. Do you want to save?" \
                -icon question]
            switch -- $ans {
                "yes" {
                    $self onFileSave $file
                }
                "cancel" {
                    return
                }
            }
        }
        
        set idx [$textnb index $file]
        $textnb forget $idx
        if {[$file isa ::Tmw::BrowsableFile]} {
            $file removeFromBrowser $codebrowser
        }
        ::itcl::delete object $file
        
        
        # remove from _Files
        set newf {}
        foreach {ttl cls hn} $_Files {
            if {$cls == $file} {
                continue
            }
            lappend newf $ttl $cls $hn
        }
        set _Files $newf
        
        # notify kitbrowser that the file was closed,
        # if it is a kit file
        #component kitbrowser removeOpenFile $file
        
        set _CurrFile ""
    }
    
    # @c Override callback handler for Edit.Undo menu entry.
    method onEditUndo {} {
        if {$_CurrFile == ""} {
            return
        }
        $_CurrFile undo
        $_CurrFile updateHighlights
    }

    # @c Override callback handler for Edit.Redo menu entry.
    method onEditRedo {} {
        if {$_CurrFile == ""} {
            return
        }
        $_CurrFile redo
        $_CurrFile updateHighlights
    }

    # @c Override callback handler for Edit.Cut menu entry.
    method onEditCut {} {
        if {$_CurrFile == ""} {
            return
        }
        set T [$_CurrFile component textwin]
        if {[focus] != "$T.t"} {
            return
        }
        
        $T cut
    }

    # @c Override callback handler for Edit.Copy menu entry.
    method onEditCopy {} {
        if {$_CurrFile == ""} {
            return
        }
        set T [$_CurrFile component textwin]
        if {[focus] != "$T.t"} {
            return
        }
        $T copy
    }
    
    # @c Override callback handler for Edit.Paste menu entry.
    method onEditPaste {} {
        if {$_CurrFile == ""} {
            return
        }
        set T [$_CurrFile component textwin]
        if {[focus] != "$T.t"} {
            return
        }
        
        $T paste
    }

    # @c callback for Edit.Search
    method onEditSearch {{key ""}} {
        # when this callback was triggered from the key binding
        # the _ShowSearchReplace variable is not set. Therefore,
        # the key attribute is not empty but contains the key 
        # that triggered the event. Set _ShowSearchReplace manually
        if {$key == "f"} {
            set _ShowSearchReplace [expr {! $_ShowSearchReplace}]
        }
        
        foreach {fn cls hn} $_Files {
            $cls showSearch $_ShowSearchReplace
        }
        
        focus -force [$_CurrFile getSearchEntry]
    }
        
    # @c callback for view windows
    method onViewWindow {what {view -1} {store 1}} {
        # @c callback for viewing windows
        global UserOptions
        
        switch -- $what {
            browser {
                #showWidget view parentComp childComp
                #showWidget $view browsepw navigatepw
                if {$view == $_ViewProjectBrowser} {
                    return
                }
                if {$view == -1} {
                    set view $_ViewProjectBrowser
                }
                
                $self ShowWindowPart $view browsepw browsenb browserSash 0
                set _ViewProjectBrowser $view
                if {$store} {
                    set UserOptions(View,browser) $view
                }
            }
            outline {
                if {$view == $_ViewOutline} {
                    return
                }
                if {$view == -1} {
                    set view $_ViewOutline
                }
                $self ShowWindowPart $view browsepw outlinenb outlineSash end
                set _ViewOutline $view
                if {$store} {
                    set UserOptions(View,outline) $view
                }
            }
            console {
                if {$view == $_ViewConsole} {
                    return
                }
                if {$view == -1} {
                    set view $_ViewConsole
                }
                $self ShowWindowPart $view txtconpw consolenb consoleSash end
                set _ViewConsole $view
                if {$store} {
                    set UserOptions(View,console) $view
                }
            }
            
            editor {
                if {$view == $_ViewEditor} {
                    return
                }
                if {$view < 0} {
                    set view $_ViewEditor
                }
                $self ShowWindowPart $view txtconpw textnb consoleSash \
                    [expr {$_ViewConsole ? 0 : "end"}]
                set _ViewEditor $view
                if {$store} {
                    set UserOptions(View,editor) $view
                }
            }
            
            consoleOnly {
                if {! $_ViewConsole} {
                    $self onViewWindow console 1 0
                }
                
                if {$view == $_ViewConsoleOnly} {
                    return
                }
                if {$view == -1} {
                    set view $_ViewConsoleOnly
                }
                
                if {! $view} {
                    if {$_ViewProjectBrowser} {
                        $browsepw insert 0 $browsenb -weight 1
                    }
                    $txtconpw insert 0 $textnb
                    
                    # restore sash positions
                    update
                    $browsepw sashpos 0 $UserOptions(View,browserSash)
                    $txtconpw sashpos 0 $UserOptions(View,consoleSash)
                } else  {
                    # store sash positions
                    
                    set UserOptions(View,browserSash) [$browsepw sashpos 0]
                    set UserOptions(View,consoleSash) [$txtconpw sashpos 0]
                    
                    if {$_ViewProjectBrowser} {
                        $browsepw forget $browsenb
                    }
                    $txtconpw forget $textnb
                }
                set _ViewConsoleOnly $view
                set UserOptions(View,consoleOnly) $view
            }
            
            default {
                error "$what is not known here"
            }
        }
    }
        
    # @c Override: callback handler on quit
    method onQuit {} {
        # check on modified files and add all open files to
        # to the list of last open documents
        global UserOptions
        
        set UserOptions(LastOpenDocuments) {}
        foreach {fn file hn} $_Files {
            lappend UserOptions(LastOpenDocuments) \
                [$file cget -filename]
            
            if {![$file modified]} {
                delete object $file
                continue
            }
            
            set fn [file tail [$file cget -filename]]
            set ans [tk_messageBox -type yesnocancel -default yes \
                -message "File $fn is modified. Do you want to save?" \
                -icon question]
            switch -- $ans {
                "yes" {
                    $self onFileSave $file
                }
                "cancel" {
                    return
                }
            }
            
            delete object $file
        }
        
        # get kit projects and store them
        set UserOptions(KitProjects) {}
        foreach {kit} [$kitbrowser getStarkits] {
            lappend UserOptions(KitProjects) [$kit cget -name]
        }
        
        set olSashPos 1
        if {$_ViewProjectBrowser} {
            set UserOptions(View,browserSash) [$browsepw sashpos 0]
        } else {
            set UserOptions(View,browserSash) 0
            set olSashPos 0
        }
        
        set UserOptions(View,outlineSash) [expr {
            ($_ViewOutline) ? [$browsepw sashpos $olSashPos] : 0
        }]
        
        if {$_ViewConsole} {
            set UserOptions(View,consoleSash) [$txtconpw sashpos 0]
        } else {
            set UserOptions(View,consoleSash) 0
        }
        
        ::Tloona::saveUserOptions
        ::Tloona::closeLog
        
        ::exit
    }
        
    # @c callback for comment toogle
    method onToggleComment {} {
        if {$_CurrFile == ""} {
            return
        }
        set T [$_CurrFile component textwin]
        if {[$T tag ranges sel] == {}} {
            set start [$T index "insert linestart"]
            set end [$T index "insert lineend"]
        } else {
            set start [$T index sel.first]
            set end [$T index sel.last]
        }
        
        $T tag remove sel $start $end
        $_CurrFile toggleComment $start $end
    }
    
    # @c callback for indentation/unindentation
    method onIndent {indent} {
        if {$_CurrFile == ""} {
            return
        }
        
        set T [$_CurrFile component textwin]
        if {[$T tag ranges sel] == {}} {
            set start [$T index "insert linestart"]
            set end [$T index "insert lineend"]
        } else {
            set start [$T index sel.first]
            set end [$T index sel.last]
        }
        
        $T tag remove sel $start $end
        $_CurrFile indentBlock $indent $start $end
    }
    
    ## \brief Callback for execute script to console
    method onExecFile {} {
        if {$_CurrFile == {}} {
            return
        }
        set T [$_CurrFile component textwin]
        set script [$T get 1.0 end]
        set cons [$consolenb select]
        
        set errInfo {}
        set result [$cons eval $script -displayresult n -errinfovar errInfo]
        if {[string trim $result] != {}} {
            $cons displayResult run $result $errInfo
        } else {
            set fname "(current buffer)"
            foreach {fn fil hn} $_Files {
                if {$fil eq $_CurrFile} {
                    if {$hn} {
                        set fname $fn
                    }
                    break
                }
            }
            
            $cons displayResult run "Sourced Script $fname" $errInfo
        }
        #$cons eval [list puts "Sourced "]
    }
    
    ## \brief Create a new REPL
    method onNewREPL {mode} {
        global UserOptions
        
        set last [lindex [split [lindex [lsort [$consolenb tabs]] end] .] end]
        set ni [string range $last 4 end]
        if {$ni == {}} {
            set ni 0
        }
        set repl repl[incr ni]
        Tmw::console $consolenb.$repl -wrap $UserOptions(ConsoleWrap) \
            -font $UserOptions(ConsoleFont) \
            -colors $UserOptions(TclSyntax) -vimode y -mode $mode
            
        bind $consolenb.$repl.textwin <Control-Tab> "[mymethod SwitchWidgets];break"
        $consolenb add $consolenb.$repl -text "REPL ($mode)"
    }
    
    ## \brief close a REPL
    method onCloseREPL {which} {
        set curr [$consolenb select]
        $curr eval exit -displayresult no
        $consolenb forget $curr
        destroy $curr
    }
    
    # @c callback that is triggered when the currently selected
    # @c file changes
    method onCurrFile {{file ""}} {
        if {$file != "" && [catch {$textnb select $file} msg]} {
            return -code error "no such file"
        }
        
        set fs [$textnb tabs]
        if {$fs == {}} {
            $self configure -title "Tloona - Tcl/Tk Development"
            return ""
        }
        
        set idx [$textnb index current]
        set _CurrFile [lindex $fs $idx]
        set fn [$_CurrFile cget -filename]
        $self configure -title "Tloona - $fn"
        focus -force [$_CurrFile component textwin].t
        
        # is the search toolbar showing in the new file?
        set _ShowSearchReplace [expr {[$_CurrFile showingSearch] ? 1 : 0}]
        $self onEditSearch
        
        set fObj [$_CurrFile cget -browserobj]
        if {$fObj != {} && [$kitbrowser exists $fObj]} {
            $kitbrowser selection set $fObj
            $kitbrowser see $fObj
        }
            
        # adjust code browser view
        if {[$_CurrFile isa ::Tmw::BrowsableFile]} {
            $codebrowser remove all
            if {[set tree [$_CurrFile getTree]] != ""} {
                $codebrowser add $tree 1 0
                if {[$codebrowser children ""] != {}} {
                    $codebrowser see [lindex [$codebrowser children ""] 0]
                }
            }
        }
        
        return $_CurrFile
    }
            
    # @c shows whether a file is modified or not
    method showModified {fileObj modified} {
        set ttl [$textnb tab $fileObj -text]
        set ttl [regsub {^\*} $ttl {}]
        
        if {$modified} {
            set ttl "*$ttl"
            $textnb tab $fileObj -text $ttl
        } else  {
            $textnb tab $fileObj -text $ttl
        }
    }
    
    # @c returns the managed file object from the specified tree window at
    # @c position x/y
    method getFileFromItem {item} {
        set realSel $item
        set sel [$realSel getTopnode ::Parser::Script]
        
        set toSelect ""
        foreach {fn cls hasFn} $_Files {
            if {![$cls isa ::Tmw::BrowsableFile]} {
                continue
            }
            if {$sel == [$cls getTree]} {
                set toSelect $cls
                break
            }
        }
        return $toSelect
    }
    
    # @c selects a fragment of code in a file
    method selectCode {treewin x y definition} {
        set itm [$treewin identify $x $y]
        set sel ""
        switch -- [lindex $itm 0] {
            "item" {
                set sel [lindex $itm 1]
            }
            "nothing" -
            default {
                return
            }
        }
        
        set realSel $sel
        set toSelect [$self getFileFromItem $sel]
        if {$toSelect == {}} {
            return
        }
        $textnb select $toSelect
        if {[lindex [$realSel cget -byterange] 0] != -1} {
            $toSelect jumpTo $realSel $definition
            $toSelect flashCode $realSel $definition
        }
    }
        
    # @c shows only the component named
    method showOnly {widget} {
        global UserOptions
        
        switch -- $widget {
            "textnb" {
                set _ViewTextNbOnly [expr {! $_ViewTextNbOnly}]
                
                if {$_ViewTextNbOnly} {
                    $self onViewWindow browser 0 0
                    $self onViewWindow console 0 0
                    $self onViewWindow outline 0 0
                } else {
                    $self onViewWindow browser $::UserOptions(View,browser)
                    $self onViewWindow console $::UserOptions(View,console)
                    $self onViewWindow outline $::UserOptions(View,outline)
                }
                
            }
            "console" {
                set _ViewConsoleOnly [expr {! $_ViewConsoleOnly}]
                if {$_ViewConsoleOnly} {
                    $self onViewWindow browser 0 0
                    $self onViewWindow editor 0 0
                    $self onViewWindow outline 0 0
                } else {
                    $self onViewWindow "browser" $UserOptions(View,browser)
                    $self onViewWindow "editor" $UserOptions(View,editor)
                    $self onViewWindow outline $::UserOptions(View,outline)
                }
            }
            
            default {
                return -code error "$widget does not exist"
            }
        }
    }
        
    # @r the current active file object
    method getCurrFile {} {
        return $_CurrFile
    }
        
    # @c checks whether a file or project is open
    method isOpen {uri} {
        switch -- [file extension $uri] {
            .vfs {
                set urivfs [file rootname $uri].vfs
                foreach {kit} [$kitbrowser getFileSystems] {
                    if {[string match [$kit cget -name] $urivfs]} {
                        return $kit
                    }
                }
            }
            default {
                foreach {fn file hn} $_Files {
                    if {$uri != $fn} {
                        continue
                    }
                    return $file
                }
                
            }
        }
        
        return ""
    }
        
    # @r The open files as visual file objects
    method getOpenFiles {} {
        set result {}
        foreach {fn cls hn} $_Files {
            lappend result $cls
        }
        return $result
    }
        
    # @c sets the option key, indicated by widget
    method setOption {widget key} {
        switch -- $key {
        "CodeBrowser,Sort" {
            set ::UserOptions(CodeBrowser,SortSeq) [$codebrowser cget -sortsequence]
            set ::UserOptions(CodeBrowser,SortAlpha) [$codebrowser cget -sortalpha]
        }
        "KitBrowser,Sort" {
            set ::UserOptions(KitBrowser,SortSeq) [$kitbrowser cget -sortsequence]
            set ::UserOptions(KitBrowser,SortAlpha) [$kitbrowser cget -sortalpha]
        }
        }
    }
    
    # @c Opens a file, checks by extension which typeof file.
    # @c If createTree is true, a tree is created using the
    # @c fileObj createTree method.
    #
    # @a uri: file uri
    # @a createTree: create a tree?
    #
    # @r The file object. Type at least ::Parser::StructuredFile
    method openFile {uri createTree} {
        global TloonaApplication UserOptions
        
        if {[file isdirectory $uri]} {
            if {[$self isOpen $uri] != ""} {
                Tmw::message $TloonaApplication "Project exists" ok \
                    "The project $uri exists already"
                return
            }
            $self OpenKitFile $uri
            return
        }
        
        set ending [file extension $uri]
        set fCls ""
        switch -- $ending {
            .tcl - .tk - .tm - .itcl - .itk - .xotcl - .test - .ws3 {
                if {[set fileObj [$self isOpen $uri]] != ""} {
                    $textnb select $fileObj
                    return
                }
                set fCls [$self OpenTclFile $uri 1]
                set fileInPrj [$self IsProjectPart $uri browserObj]
                if {$fileInPrj && $browserObj != {}} {
                    $fCls configure -browserobj $browserObj
                }
                $fCls createTree -file $uri -displayformat {"%s (%s)" -name -dirname}
                
                $fCls updateHighlights
                $fCls addToBrowser $codebrowser
                if {$fileInPrj} {
                    $fCls addToFileBrowser $kitbrowser
                }
                update
            }
            ".tml" -
            ".html" -
            ".htm" -
            ".adp" {
                if {[set fileObj [$self isOpen $uri]] != ""} {
                    Tmw::message $TloonaApplication "File already open" ok \
                        "The file $uri exists already"
                    $textnb select $fileObj
                    return
                }
                set fCls [$self OpenWebFile $uri]
                set fileInPrj [$self IsProjectPart $uri browserObj]
                if {$fileInPrj && $browserObj != {}} {
                    $fCls configure -browserobj $browserObj
                }
            }
            ".kit" -
            ".vfs" -
            default {
                set fType [lindex [fileutil::fileType $uri] 0]
                if {[string equal $fType text]} {
                    if {[set fileObj [$self isOpen $uri]] != ""} {
                        $textnb select $fileObj
                        return
                    }
                    set fCls [$self OpenPlainFile $uri]
                    set fileInPrj [$self IsProjectPart $uri browserObj]
                    if {$fileInPrj && $browserObj != {}} {
                        $fCls configure -browserobj $browserObj
                    }
                    
                } else {
                    puts "cannot handle this"
                    return
                }
            }
        }
        
        $fCls configure -savelineendings $UserOptions(File,SaveLineEndings)
        $textnb select $fCls
        set _InitDir [file dirname $uri]
        $self showModified $fCls 0
        return $fCls
    }
    
    # @c Adds a comm id
    method addCommID {id} {
        if {[lsearch $CommIDs $id] >= 0} {
            return 1
        }
        
        # This makes sure that the comm id is removed when the
        # interpreter exits
        set script "catch {rename ::exit ::el_exit} m;\n"
        append script "proc ::exit {args} {\n"
        append script "catch {comm::comm send [comm::comm self] \[list $self removeCommID $id \]}\n"
        append script "eval ::el_exit \$args \n"
        append script "}\n"
        if {[catch {comm::comm send $id $script} res]} {
            return 0
        }
        lappend CommIDs $id
        return 1
    }
        
    # @c Removes a Comm id
    method removeCommID {id} {
        if {[set idx [lsearch $CommIDs $id]] < 0} {
            return
        }
        set CommIDs [lreplace $CommIDs $idx $idx]
    }
        
    # @r Comm IDs
    method getCommIDs {} {
        return $CommIDs
    }
    
    # @c shows a particular window part
    #
    # @a view: to view or not to view
    method ShowWindowPart {view parentComp childComp optionKey pos} {
        global UserOptions
        
        set pComp [set $parentComp]
        set cComp [set $childComp]
        if {$view} {
            if {[string equal $pos end]} {
                $pComp add $cComp -weight 1
            } else {
                $pComp insert $pos $cComp -weight 1
            }
            update
            try {
                set sashp [expr { ([string eq $pos end]) ? [llength [$pComp panes]] - 2 : $pos}]
                $pComp sashpos $sashp $UserOptions(View,$optionKey)
            } trap {TTK PANE SASH_INDEX} {err errOpts} {
                # ignore
            }
        } else  {
            try {
                set sashp [expr { ([string eq $pos end]) ? [llength [$pComp panes]] - 2 : $pos}]
                set UserOptions(View,$optionKey) [$pComp sashpos $sashp]
            } trap {TTK PANE SASH_INDEX} {err errOpts} {
                # ignore
            }
            $pComp forget $cComp
        }
                
    }
    
    # @c switch between widgets inside the application
    method SwitchWidgets {} {
        set cfw [$_CurrFile component textwin].t
        set consw [$consolenb select].textwin.t
        if {[string match [focus] $cfw]} {
            focus -force $consw
        } elseif {[string match [focus] $consw]} {
            focus -force $cfw
        }
    }
    
    ## \brief Create the menus
    method CreateMenus {} {
        global Icons UserOptions
        
        $self toolbar maintoolbar -pos n -compound none
        $self menuentry File.New -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileNew) -command [mymethod onFileNew] \
            -accelerator [set UserOptions(DefaultModifier)]-n
        $self menuentry File.Open -type cascade -image $Tmw::Icons(FileOpen)
        $self menuentry File.Open.File -type command  -toolbar maintoolbar \
            -command [mymethod onFileOpen] -image $Icons(TclFileOpen) \
            -accelerator [set UserOptions(DefaultModifier)]-o -label "File..."
        $self menuentry File.Open.Project -type command -label "Project..." \
            -toolbar maintoolbar -command [mymethod onProjectOpen] \
            -image $Icons(KitFileOpen) -accelerator [set UserOptions(DefaultModifier)]-p
        
        $self menuentry File.Save -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileSave) -command [mymethod onFileSave] \
            -accelerator [set UserOptions(DefaultModifier)]-s
        $self menuentry File.Close -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileClose) -command [mymethod onFileClose] \
            -accelerator [set UserOptions(DefaultModifier)]-w
        $self menuentry File.Sep0 -type separator -toolbar maintoolbar
        $self menuentry File.Quit -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActExit) -command [mymethod onQuit] \
            -accelerator [set UserOptions(DefaultModifier)]-q
        
        $self menuentry Edit.Undo -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActUndo) -command [mymethod onEditUndo] \
            -accelerator [set UserOptions(DefaultModifier)]-z
        $self menuentry Edit.Redo -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActRedo) -command [mymethod onEditRedo] \
            -accelerator [set UserOptions(DefaultModifier)]-r
        $self menuentry Edit.Sep0 -type separator -toolbar maintoolbar
        $self menuentry Edit.Cut -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditCut) -command [mymethod onEditCut] \
            -accelerator [set UserOptions(DefaultModifier)]-x
        $self menuentry Edit.Copy -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditCopy) -command [mymethod onEditCopy] \
            -accelerator [set UserOptions(DefaultModifier)]-c
        $self menuentry Edit.Paste -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditPaste) -command [mymethod onEditPaste] \
            -accelerator [set UserOptions(DefaultModifier)]-v
        $self menuentry Edit.Sep1 -type separator -toolbar maintoolbar
        $self menuentry Edit.Search -type checkbutton -toolbar maintoolbar \
            -image $Tmw::Icons(ActFileFind) -command [mymethod onEditSearch %K] \
            -label "Search & Replace" -variable [myvar _ShowSearchReplace] \
            -accelerator [set UserOptions(DefaultModifier)]-f
        
        $self menuentry Code.Comment -type command -toolbar maintoolbar \
            -image $Icons(ToggleCmt) -command [mymethod onToggleComment] \
            -label "Comment/Uncomment section"
        $self menuentry Code.Indent -type command -toolbar maintoolbar \
            -image $Icons(Indent) -command [mymethod onIndent 1] \
            -label "Indent section"
        $self menuentry Code.Unindent -type command -toolbar maintoolbar \
            -image $Icons(UnIndent) -command [mymethod onIndent 0] \
            -label "Unindent section"
        $self menuentry REPL.Run -type command -toolbar maintoolbar -image $Tmw::Icons(ExeFile) \
            -command [mymethod onExecFile] -label "Execute Script in current REPL"
        $self menuentry REPL.NewSlaveConsole -type command -toolbar maintoolbar -image $Tmw::Icons(ConsoleBlack) \
            -command [mymethod onNewREPL slave] -label "New SlaveInterp REPL"
        $self menuentry REPL.NewCommConsole -type command -toolbar maintoolbar -image $Tmw::Icons(ConsoleRed) \
            -command [mymethod onNewREPL comm] -label "New CommInterp REPL"
        $self menuentry REPL.CloseConsole -type command -toolbar maintoolbar -image $Tmw::Icons(ConsoleClose) \
            -command [mymethod onCloseREPL comm] -label "Close current REPL"
        
        $self menuentry View.Browser -type checkbutton -label "Project/Code Browser" \
            -command [mymethod onViewWindow browser] -toolbar maintoolbar \
            -variable [myvar _ViewProjectBrowser] -image $Icons(ViewBrowser)
        $self menuentry View.Outline -type checkbutton -label "Code Outline" \
            -command [mymethod onViewWindow outline] -toolbar maintoolbar \
            -variable [myvar _ViewOutline] -image $Icons(ViewBrowser)
        $self menuentry View.Console -type checkbutton -label "Console" \
            -command [mymethod onViewWindow console] -toolbar maintoolbar \
            -variable [myvar _ViewConsole] -image $Icons(ViewConsole)
        $self menuentry View.Editor -type checkbutton -label "Text Editor" \
            -command [mymethod onViewWindow editor] -toolbar maintoolbar \
            -variable [myvar _ViewEditor] -image $Icons(ViewEditor)
        
    }
    
    # @c creates the pane parts in the main window
    method CreatePanes {} {
        install browsepw using ttk::panedwindow [$self childsite].browsepw -orient horizontal
        #install navigatepw using ttk::panedwindow $browsepw.navigatepw -orient vertical
        #$browsepw add $navigatepw -weight 1
        #install browsenb using ttk::notebook $navigatepw.browsenb -width 150 -height 300
        install browsenb using ttk::notebook $browsepw.browsenb -width 150 -height 300
        $browsepw add $browsenb -weight 1
        #$navigatepw add $browsenb -weight 1
        install txtconpw using ttk::panedwindow $browsepw.txtconpw -orient vertical
        $browsepw add $txtconpw -weight 1
        install textnb using ttk::notebook $txtconpw.textnb -width 650 -height 400
        $txtconpw add $textnb -weight 1
        install consolenb using ttk::notebook $txtconpw.consolenb -width 650 -height 100
        $txtconpw add $consolenb -weight 1 
        install outlinenb using ttk::notebook $browsepw.outlooknb -width 100
        $browsepw add $outlinenb -weight 1
        
        pack $browsepw -expand yes -fill both
        
        bind $textnb <Double-Button-1> [mymethod showOnly textnb]
        bind $textnb <<NotebookTabChanged>> [mymethod onCurrFile]
        bind $consolenb <Double-Button-1> [mymethod showOnly console]
    }

    ## \brief creates the navigation controls: code browser, project browser...
    method CreateNavigators {} {
        global UserOptions Icons
        
        set bnb $browsenb
        install kitbrowser using Tloona::kitbrowser $browsenb.kitbrowser \
                -closefilecmd [list $self onFileClose] \
                -openfilecmd [list $self openFile] \
                -isopencmd [list {file} [concat [list $self isOpen] {$file}]] \
                -selectcodecmd [list $self selectCode] \
                -getfilefromitemcmd [list $self getFileFromItem] \
                -sortsequence $UserOptions(KitBrowser,SortSeq) \
                -sortalpha $UserOptions(KitBrowser,SortAlpha) \
                -mainwindow $win
        
        set kb $kitbrowser
        # add a command to send code to the builtin console
        $kitbrowser addSendCmd [mymethod SendToConsole]
        $kitbrowser setNodeIcons [concat [$kb getNodeIcons] $Icons(ScriptIcons)]
        $bnb add $kitbrowser -text "Workspace"
        bind $kitbrowser <<SortSeqChanged>> [mymethod setOption %W "KitBrowser,Sort"]
        
        # The code outline
        install codebrowser using ::Tloona::codeoutline $outlinenb.codebrowser \
                -sortsequence $UserOptions(CodeBrowser,SortSeq) \
                -sortalpha $UserOptions(CodeBrowser,SortAlpha) \
                -mainwindow $win
    
        $codebrowser setNodeIcons $Icons(ScriptIcons)
        $codebrowser addSendCmd [mymethod SendToConsole]
        #$bnb add $codebrowser -text "Outline"
        $outlinenb add $codebrowser -text Outline
        set V [$codebrowser treeview]
        bind $V <Button-1> [mymethod selectCode %W %x %y 0]
        bind $V <Control-Button-1> [mymethod selectCode %W %x %y 1]
        bind $codebrowser <<SortSeqChanged>> [mymethod setOption %W "CodeBrowser,Sort"]
    }

    # @c Creates debugging tools and inspection browsers
    method CreateDebugTools {} {
        global Icons
        set Debugger [Tloona::debugger -openfilecmd [mymethod openFile] \
            -fileisopencmd [mymethod isOpen] \
            -selectfilecmd [list $textnb select]]
        
        # the run button gets a menu assigned
        set mb [$self toolbutton runto -toolbar maintoolbar -image $Icons(DbgRunTo) \
            -stickto front -type menubutton -separate 0]
        $self menuentry Run.DebugConfigs -type command -label "Debug..." \
            -command [list $Debugger onManageConfigs] -image $Icons(DbgRunTo)
        $self menuentry Run.Step -type command -label "Step into" \
            -toolbar maintoolbar -command [list $Debugger onStep] \
            -image $Icons(DbgStep) -accelerator F5
        $self menuentry Run.Next -type command -label "Step over" \
            -toolbar maintoolbar -command [list $Debugger onNext] \
            -image $Icons(DbgNext) -accelerator F6
        $self menuentry Run.Continue -type command -label "Continue" \
            -toolbar maintoolbar -command [list $Debugger onStepOut] \
            -image $Icons(DbgStepOut) -accelerator F7
        $self menuentry Run.Stop -type command -label "Stop" \
            -toolbar maintoolbar -command [list $Debugger onStop] \
            -image $Icons(DbgStop) -accelerator F8
        
        $Debugger runMenu $mb
        set vi [$Debugger varInspector $browsenb -borderwidth 0 -mainwindow $win]
        set si [$Debugger stackInspector $consolenb -borderwidth 0 -mainwindow $win]
        $browsenb add $vi -text "Variables"
        $consolenb add $si -text "Call Frames"
    }
        
    # @c open a Tcl/Itcl file
    method OpenTclFile {uri createTree} {
        # @c opens an (I)tcl file
        global UserOptions
        
        set T $textnb
        set cls [::Tloona::tclfile1 $T.file$_FileIdx -filename $uri -font $options(-filefont) \
                -tabsize $options(-filetabsize) -expandtab $options(-filetabexpand) \
                -mainwindow $win -backupfile $UserOptions(File,Backup) \
                -sendcmd [mymethod SendToConsole]]
        
        # set binding for shortcut to change windows
        bind [$cls component textwin].t <Control-Tab> "[mymethod SwitchWidgets];break"
        
        set ttl [file tail $uri]
        $textnb add $cls -text $ttl
        
        if {[catch {$cls openFile ""} msg]} {
            set messg "can not open file $uri :\n\n"
            append messg $msg
            tk_messageBox -title "can not open file" \
                -message $messg -type ok -icon error
            itcl::delete object $cls
            return
        }
        
        $cls modified 0
        $cls configure -modifiedcmd [mymethod showModified $cls 1]
        
        lappend _Files $uri $cls 1
        incr _FileIdx
        
        # if the search is triggered, show search toolbar in the
        # new file immediately
        $cls showSearch $_ShowSearchReplace
        if {$_CurrFile != ""} {
            $cls configure -searchstring [$_CurrFile cget -searchstring] \
                -replacestring [$_CurrFile cget -replacestring] \
                -searchexact [$_CurrFile cget -searchexact] \
                -searchregex [$_CurrFile cget -searchregex] \
                -searchnocase [$_CurrFile cget -searchnocase]
        }
        
        return $cls
    }
        
    # @c open a starkit file
    method OpenKitFile {uri} {
        set fs [$kitbrowser addFileSystem $uri]
        if {$fs == ""} {
            return
        }
        
        # associate eventual open visual files from the new project
        # with the parsed code trees
        foreach {file} [$kitbrowser getTclFiles $fs] {
            foreach {uri cls hn} $_Files {
                if {![string equal [$file cget -name] $uri]} {
                    continue
                }
                $cls setTree $file
                $cls addToFileBrowser $kitbrowser
                $cls updateHighlights
            }
        }
    }
        
    # @c open a plain file
    method OpenPlainFile {uri} {
        global UserOptions
        
        set T $textnb
        set cls [::Tmw::visualfile1 $T.file$_FileIdx -filename $uri -font $options(-filefont) \
                -tabsize $options(-filetabsize) -expandtab $options(-filetabexpand) \
                -mainwindow $win -backupfile $UserOptions(File,Backup)]
        
        set ttl [file tail $uri]
        $textnb add $cls -text $ttl
        
        $cls openFile ""        
        $cls modified 0
        $cls configure -modifiedcmd [mymethod showModified $cls 1]
        
        lappend _Files $uri $cls 1
        incr _FileIdx
        
        # if the search is triggered, show search toolbar in the
        # new file immediately
        $cls showSearch $_ShowSearchReplace
        if {$_CurrFile != ""} {
            $cls configure -searchstring [$_CurrFile cget -searchstring] \
                -replacestring [$_CurrFile cget -replacestring] \
                -searchexact [$_CurrFile cget -searchexact] \
                -searchregex [$_CurrFile cget -searchregex] \
                -searchnocase [$_CurrFile cget -searchnocase]
        }
        
        return $cls
    }
        
    # @c open a web file
    method OpenWebFile {uri} {
        global UserOptions
        
        set T $textnb
        set cls [::Tloona::webfile1 $T.file$_FileIdx -filename $uri -font $options(-filefont) \
                -tabsize $options(-filetabsize) -expandtab $options(-filetabexpand) \
                -mainwindow $win -backupfile $UserOptions(File,Backup)]
        
        set ttl [file tail $uri]
        $textnb add $cls -text $ttl
        
        if {[catch {$cls openFile ""} msg]} {
            set messg "can not open file $uri :\n\n"
            append messg $msg
            tk_messageBox -title "can not open file" -message $messg -type ok -icon error
            itcl::delete object $cls
            return
        }
        
        $cls modified 0
        $cls configure -modifiedcmd [mymethod showModified $cls 1]
        
        lappend _Files $uri $cls 1
        incr _FileIdx
        
        # if the search is triggered, show search toolbar in the
        # new file immediately
        $cls showSearch $_ShowSearchReplace
        if {$_CurrFile != ""} {
            $cls configure -searchstring [$_CurrFile cget -searchstring] \
                -replacestring [$_CurrFile cget -replacestring] \
                -searchexact [$_CurrFile cget -searchexact] \
                -searchregex [$_CurrFile cget -searchregex] \
                -searchnocase [$_CurrFile cget -searchnocase]
        }
        
        return $cls
    }
        
    # @c adapts the search options of one file to the others
    method AdaptSearchOptions {fileObj} {
        set fileObj [namespace tail $fileObj]
        foreach {fn cls hn} $_Files {
            set cls [namespace tail $cls]
            if {[string match $cls $fileObj]} {
                continue
            }
            $cls configure -searchstring [$fileObj cget -searchstring] \
                -replacestring [$fileObj cget -replacestring] \
                -searchexact [$fileObj cget -searchexact] \
                -searchregex [$fileObj cget -searchregex] \
                -searchnocase [$fileObj cget -searchnocase]
        }
    }
        
    # @c Checks whether the give uri is part of an open project
    # @c If so, returns the code tree in treePtr and returns true
    # @c Otherwise, returns false
    #
    # @a uri: The uri to check
    # @a treePtr: (out) pointer to tree
    #
    # @r true if it is part, false otherwise
    method IsProjectPart {uri treePtr} {
        upvar $treePtr tree
        set tree {}
        foreach {prj} [$kitbrowser getStarkits] {
            set rn $uri
            if {[string match [$prj cget -name]* $uri]} {
                foreach {kid} [$prj getChildren yes] {
                    if {[$kid cget -name] == $uri} {
                        set tree $kid
                    }
                }
                return yes
            }
        }
        return no
    }
    
    # @c Send a script to the internal console
    method SendToConsole {script} {
        if {$script == {}} {
            return
        }
        set cons [$consolenb select]
        $cons eval $script -showlines 1
    }
    
}

} ;# namespace Tloona

package provide tloona::mainapp 2.0.0


