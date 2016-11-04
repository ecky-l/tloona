## mainapp.tcl (created by Tloona here)
package require snit 2.3.2
package require tmw::platform 2.0.0
package require tmw::icons 1.0
package require tloona::kitbrowser 1.0
package require tloona::projectoutline 1.0
package require tmw::console 2.0
package require tloona::file 1.0
package require fileutil 1.7
package require parser::parse 1.0
package require tloona::debugger 1.0
package require comm 4.3

package provide tloona::mainapp 2.0.0

namespace eval ::Tloona {

## \brief This is Tloona's main application.
snit::widgetadaptor mainapp {
    inherit Tmw::Platform
    
    #### Options
    
    ## \brief font for the text in file objects
    option -filefont {fixed 14}
    ## \brief the tab size for files in chars
    option -filetabsize 4
    ## \brief whether to expand tab chars with spaces
    option -filetabexpand 1
    
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
        $self CreatePanes
        $self CreateNavigators
        onNewREPL slave
        onNewREPL comm
        
        # disable the debugger features for now... this does not work currently
        #$self CreateDebugTools
        #$Debugger configure -console [component output]
        
        menuentry Edit.Sep1 -type separator -toolbar maintoolbar
        menuentry Edit.Search -type checkbutton -toolbar maintoolbar \
            -image $Tmw::Icons(ActFileFind) -command [code $this onEditSearch %K] \
            -label "Search & Replace" -variable [scope _ShowSearchReplace] \
            -accelerator [set UserOptions(DefaultModifier)]-f
        menuentry Code.Comment -type command -toolbar maintoolbar \
            -image $Icons(ToggleCmt) -command [code $this onToggleComment] \
            -label "Comment/Uncomment section"
        menuentry Code.Indent -type command -toolbar maintoolbar \
            -image $Icons(Indent) -command [code $this onIndent 1] \
            -label "Indent section"
        menuentry Code.Unindent -type command -toolbar maintoolbar \
            -image $Icons(UnIndent) -command [code $this onIndent 0] \
            -label "Unindent section"
        menuentry REPL.Run -type command -toolbar maintoolbar -image $Tmw::Icons(ExeFile) \
            -command [code $this onExecFile] -label "Execute Script in current REPL"
        menuentry REPL.NewSlaveConsole -type command -toolbar maintoolbar -image $Tmw::Icons(ConsoleBlack) \
            -command [code $this onNewREPL slave] -label "New SlaveInterp REPL"
        menuentry REPL.NewCommConsole -type command -toolbar maintoolbar -image $Tmw::Icons(ConsoleRed) \
            -command [code $this onNewREPL comm] -label "New CommInterp REPL"
        menuentry REPL.CloseConsole -type command -toolbar maintoolbar -image $Tmw::Icons(ConsoleClose) \
            -command [code $this onCloseREPL comm] -label "Close current REPL"
        menuentry View.Browser -type checkbutton -label "Project/Code Browser" \
            -command [code $this onViewWindow browser] -toolbar maintoolbar \
            -variable [scope _ViewProjectBrowser] -image $Icons(ViewBrowser)
        menuentry View.Console -type checkbutton -label "Console" \
            -command [code $this onViewWindow console] -toolbar maintoolbar \
            -variable [scope _ViewConsole] -image $Icons(ViewConsole)
        menuentry View.Editor -type checkbutton -label "Text Editor" \
            -command [code $this onViewWindow editor] -toolbar maintoolbar \
            -variable [scope _ViewEditor] -image $Icons(ViewEditor)
        
        configure -title "Tloona - Tcl/Tk Development" \
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
        
        set T [component textnb]
        set cls [::Tloona::tclfile $T.file$_FileIdx -font $filefont \
            -sendcmd [mymethod SendToConsole] -threadpool [cget -threadpool] \
            -tabsize $filetabsize -expandtab $filetabexpand \
            -mainwindow [namespace tail $this] \
            -backupfile $UserOptions(File,Backup)]
                
        $cls createTree
        set ttl "unnamed $_FileIdx"
        component textnb add $cls -text $ttl
        component textnb select $cls
        $cls addToBrowser [component codebrowser]
        $cls modified 0
        $cls configure -modifiedcmd [code $this showModified $cls 1]
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
                -filetypes  $ft -parent [namespace tail $this]]
        if {$uri == ""} {
            return
        }
        openFile $uri 1
    }

    # @c callback handler for File.Open.Project menu entry.
    method onProjectOpen {{uri ""}} {
        if {$uri != ""} {
            openFile $uri 0
        }
        
        set uri [tk_chooseDirectory -mustexist 1 -initialdir $_InitDir \
            -parent [namespace tail $this]]
        if {$uri == ""} {
            return
        }
        openFile $uri 0
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
            showModified $file 0
            return
        }
        
        set filename [tk_getSaveFile -initialdir $_InitDir \
            -parent [namespace tail $this]]
        if {$filename == ""} {
            return
        }
        
        $file saveFile $filename
        lset _Files $i $filename
        lset _Files [expr {$i + 2}] 1
        
        set ttl [file tail $filename]
        component textnb tab $_CurrFile -text $ttl
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
                    onFileSave $file
                }
                "cancel" {
                    return
                }
            }
        }
        
        set idx [component textnb index $file]
        component textnb forget $idx
        if {[$file isa ::Tmw::BrowsableFile]} {
            $file removeFromBrowser [component codebrowser]
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
            "browser" {
                #showWidget view parentComp childComp
                #showWidget $view browsepw navigatepw
                if {$view == $_ViewProjectBrowser} {
                    return
                }
                if {$view == -1} {
                    set view $_ViewProjectBrowser
                }
                
                $self ShowWindowPart $view browsepw navigatepw browserSash 0
                set _ViewProjectBrowser $view
                if {$store} {
                    set UserOptions(View,browser) $view
                }
            }
            
            "console" {
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
            
            "editor" {
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
            
            "consoleOnly" {
                if {! $_ViewConsole} {
                    onViewWindow console 1 0
                }
                
                if {$view == $_ViewConsoleOnly} {
                    return
                }
                if {$view == -1} {
                    set view $_ViewConsoleOnly
                }
                
                if {! $view} {
                    if {$_ViewProjectBrowser} {
                        component browsepw insert 0 [component navigatepw] -weight 1
                    }
                    component txtconpw insert 0 [component textnb]
                    
                    # restore sash positions
                    update
                    component browsepw sashpos 0 $UserOptions(View,browserSash)
                    component txtconpw sashpos 0 $UserOptions(View,consoleSash)
                } else  {
                    # store sash positions
                    
                    set UserOptions(View,browserSash) [component browsepw sashpos 0]
                    set UserOptions(View,consoleSash) [component txtconpw sashpos 0]
                    
                    if {$_ViewProjectBrowser} {
                        component browsepw forget [component navigatepw]
                    }
                    component txtconpw forget [component textnb]
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
                    onFileSave $file
                }
                "cancel" {
                    return
                }
            }
            
            delete object $file
        }
        
        # get kit projects and store them
        set UserOptions(KitProjects) {}
        foreach {kit} [component kitbrowser getFileSystems] {
            lappend UserOptions(KitProjects) [$kit cget -name]
        }
        
        if {$_ViewProjectBrowser} {
            set UserOptions(View,browserSash) [component browsepw sashpos 0]
        } else {
            set UserOptions(View,browserSash) 0
        }
        
        if {$_ViewConsole} {
            set UserOptions(View,consoleSash) [component txtconpw sashpos 0]
        } else {
            set UserOptions(View,consoleSash) 0
        }
        
        ::Tloona::saveUserOptions
        ::Tloona::closeLog
        
        if {[cget -threadpool] != ""} {
            tpool::release [cget -threadpool]
        }
        
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
        set cons [component consolenb select]
        
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
        
        # disable this for now... just overhead
        set cnb [component consolenb]
        set last [lindex [split [lindex [lsort [component consolenb tabs]] end] .] end]
        set ni [string range $last 4 end]
        if {$ni == {}} {
            set ni 0
        }
        set repl repl[incr ni]
        Tmw::console $cnb.$repl -wrap $UserOptions(ConsoleWrap) \
            -font $UserOptions(ConsoleFont) \
            -colors $UserOptions(TclSyntax) -vimode y -mode $mode
            
        bind $cnb.$repl.textwin <Control-Tab> "[mymethod SwitchWidgets];break"
        $cnb add $cnb.$repl -text "REPL ($mode)"
    }
    
    ## \brief close a REPL
    method onCloseREPL {which} {
        set curr [component consolenb select]
        $curr eval exit -displayresult no
        component consolenb forget $curr
        destroy $curr
    }
    
    # @c callback that is triggered when the currently selected
    # @c file changes
    method onCurrFile {{file ""}} {
        if {$file != "" && [catch {component textnb select $file} msg]} {
            return -code error "no such file"
        }
        
        set fs [component textnb tabs]
        if {$fs == {}} {
            configure -title "Tloona - Tcl/Tk Development"
            return ""
        }
        
        set idx [component textnb index current]
        set _CurrFile [lindex $fs $idx]
        set fn [$_CurrFile cget -filename]
        configure -title "Tloona - $fn"
        focus -force [$_CurrFile component textwin].t
        
        # is the search toolbar showing in the new file?
        set _ShowSearchReplace [expr {[$_CurrFile showingSearch] ? 1 : 0}]
        onEditSearch
        
        set fObj [$_CurrFile cget -browserobj]
        if {$fObj != {} && [component kitbrowser exists $fObj]} {
            component kitbrowser selection set $fObj
            component kitbrowser see $fObj
        }
            
        # adjust code browser view
        if {[$_CurrFile isa ::Tmw::BrowsableFile]} {
            set fb [component codebrowser]
            $fb remove all
            if {[set tree [$_CurrFile getTree]] != ""} {
                $fb add $tree 1 0
                if {[$fb children ""] != {}} {
                    $fb see [lindex [$fb children ""] 0]
                }
            }
        }
        
        return $_CurrFile
    }
            
    # @c shows whether a file is modified or not
    method showModified {fileObj modified} {
        set ttl [component textnb tab $fileObj -text]
        set ttl [regsub {^\*} $ttl {}]
        
        set TN [component textnb]
        
        if {$modified} {
            set ttl "*$ttl"
            $TN tab $fileObj -text $ttl
        } else  {
            $TN tab $fileObj -text $ttl
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
        set toSelect [getFileFromItem $sel]
        if {$toSelect == {}} {
            return
        }
        component textnb select $toSelect
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
                    onViewWindow "browser" 0 0
                    onViewWindow "console" 0 0
                } else {
                    onViewWindow "browser" $::UserOptions(View,browser)
                    onViewWindow "console" $::UserOptions(View,console)
                }
                
            }
            "console" {
                set _ViewConsoleOnly [expr {! $_ViewConsoleOnly}]
                if {$_ViewConsoleOnly} {
                    onViewWindow "browser" 0 0
                    onViewWindow "editor" 0 0
                } else {
                    onViewWindow "browser" $UserOptions(View,browser)
                    onViewWindow "editor" $UserOptions(View,editor)
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
                foreach {kit} [component kitbrowser getFileSystems] {
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
                set ::UserOptions(CodeBrowser,SortSeq) \
                    [component codebrowser cget -sortsequence]
                set ::UserOptions(CodeBrowser,SortAlpha) \
                    [component codebrowser cget -sortalpha]
            }
            "KitBrowser,Sort" {
                set ::UserOptions(KitBrowser,SortSeq) \
                    [component kitbrowser cget -sortsequence]
                set ::UserOptions(KitBrowser,SortAlpha) \
                    [component kitbrowser cget -sortalpha]
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
            if {[isOpen $uri] != ""} {
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
                if {[set fileObj [isOpen $uri]] != ""} {
                    component textnb select $fileObj
                    return
                }
                set fCls [$self OpenTclFile $uri 1]
                set fileInPrj [$self IsProjectPart $uri browserObj]
                if {$fileInPrj && $browserObj != {}} {
                    $fCls configure -browserobj $browserObj
                }
                $fCls createTree -file $uri -displayformat {"%s (%s)" -name -dirname}
                
                $fCls updateHighlights
                $fCls addToBrowser [component codebrowser]
                if {$fileInPrj} {
                    $fCls addToFileBrowser [component kitbrowser]
                }
                update
            }
            ".tml" -
            ".html" -
            ".htm" -
            ".adp" {
                if {[set fileObj [isOpen $uri]] != ""} {
                    Tmw::message $TloonaApplication "File already open" ok \
                        "The file $uri exists already"
                    component textnb select $fileObj
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
                    if {[set fileObj [isOpen $uri]] != ""} {
                        component textnb select $fileObj
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
        component textnb select $fCls
        set _InitDir [file dirname $uri]
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
        append script "catch {comm::comm send [comm::comm self] \[list $this removeCommID $id \]}\n"
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
    
    method DefaultMenu {} {
        global Icons UserOptions
        
        menuentry File.New -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileNew) -command [code $this onFileNew] \
            -accelerator [set UserOptions(DefaultModifier)]-n
        menuentry File.Open -type cascade -image $Tmw::Icons(FileOpen)
        menuentry File.Open.File -type command  -toolbar maintoolbar \
            -command [code $this onFileOpen] -image $Icons(TclFileOpen) \
            -accelerator [set UserOptions(DefaultModifier)]-o -label "File..."
        menuentry File.Open.Project -type command -label "Project..." \
            -toolbar maintoolbar -command [code $this onProjectOpen] \
            -image $Icons(KitFileOpen) -accelerator [set UserOptions(DefaultModifier)]-p
        
        menuentry File.Save -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileSave) -command [code $this onFileSave] \
            -accelerator [set UserOptions(DefaultModifier)]-s
        menuentry File.Close -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileClose) -command [code $this onFileClose] \
            -accelerator [set UserOptions(DefaultModifier)]-w
        menuentry File.Sep0 -type separator -toolbar maintoolbar
        menuentry File.Quit -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActExit) -command [code $this onQuit] \
            -accelerator [set UserOptions(DefaultModifier)]-q
        
        menuentry Edit.Undo -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActUndo) -command [code $this onEditUndo] \
            -accelerator [set UserOptions(DefaultModifier)]-z
        menuentry Edit.Redo -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActRedo) -command [code $this onEditRedo] \
            -accelerator [set UserOptions(DefaultModifier)]-r
        menuentry Edit.Sep0 -type separator -toolbar maintoolbar
        menuentry Edit.Cut -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditCut) -command [code $this onEditCut] \
            -accelerator [set UserOptions(DefaultModifier)]-x
        menuentry Edit.Copy -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditCopy) -command [code $this onEditCopy] \
            -accelerator [set UserOptions(DefaultModifier)]-c
        menuentry Edit.Paste -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditPaste) -command [code $this onEditPaste] \
            -accelerator [set UserOptions(DefaultModifier)]-v
    }
        
    # @c shows a particular window part
    #
    # @a view: to view or not to view
    method ShowWindowPart {view parentComp childComp optionKey pos} {
        global UserOptions
        
        if {$view} {
            if {[string equal $pos end]} {
                component $parentComp add [component $childComp] -weight 1
            } else {
                component $parentComp insert $pos [component $childComp] -weight 1
            }
            update
            catch {component $parentComp sashpos 0 $UserOptions(View,$optionKey)}
        } else  {
            catch {
                set UserOptions(View,$optionKey) \
                    [component $parentComp sashpos 0]
            }
            
            component $parentComp forget [component $childComp]
        }
                
    }
    
    # @c switch between widgets inside the application
    method SwitchWidgets {} {
        set cfw [$_CurrFile component textwin].t
        set consw [component consolenb select].textwin.t
        if {[string match [focus] $cfw]} {
            focus -force $consw
        } elseif {[string match [focus] $consw]} {
            focus -force $cfw
        }
    }
    
    # @c creates the pane parts in the main window
    method CreatePanes {} {
        itk_component add browsepw {
            ::ttk::panedwindow [mainframe].browsepw \
                -orient horizontal
        }
        
        itk_component add navigatepw {
            ::ttk::panedwindow [component browsepw].navigatepw \
                -orient vertical
        }
        
        itk_component add browsenb {
            ::ttk::notebook [component navigatepw].browsenb \
                -width 150 -height 300
        }
        
        component navigatepw add [component browsenb] -weight 1
        
        itk_component add txtconpw {
            ::ttk::panedwindow [component browsepw].txtconpw \
                -orient vertical
        }
        
        itk_component add textnb {
            ::ttk::notebook [component txtconpw].textnb \
                -width 650 -height 400
        }
        
        itk_component add consolenb {
            ::ttk::notebook [component txtconpw].consolenb \
                -width 650 -height 100
        }
        
        component browsepw add [component navigatepw] -weight 1
        component browsepw add [component txtconpw] -weight 1
        
        # the text and console paned
        component txtconpw add [component textnb] -weight 1
        component txtconpw add [component consolenb] -weight 1 
        
        pack [component browsepw] -expand yes -fill both
        
        bind [component textnb] <Double-Button-1> [code $this showOnly textnb]
        bind [component textnb] <<NotebookTabChanged>> [code $this onCurrFile]
        bind [component consolenb] <Double-Button-1> [code $this showOnly console]
    }

    ## \brief creates the navigation controls: code browser, project browser...
    method CreateNavigators {} {
        global UserOptions Icons
        
        set bnb [component browsenb]
        
        # the project browser
        itk_component add kitbrowser {
            ::Tloona::kitbrowser $bnb.kitbrowser \
                -closefilecmd [code $this onFileClose] \
                -openfilecmd [code $this openFile] \
                -isopencmd [list {file} [concat [code $this isOpen] {$file}]] \
                -selectcodecmd [code $this selectCode] \
                -getfilefromitemcmd [code $this getFileFromItem] \
                -sortsequence $UserOptions(KitBrowser,SortSeq) \
                -sortalpha $UserOptions(KitBrowser,SortAlpha) \
                -mainwindow $itk_interior
        }
        set kb [component kitbrowser]
        # add a command to send code to the builtin console
        $kb addSendCmd [mymethod SendToConsole]
        $kb setNodeIcons [concat [$kb getNodeIcons] $Icons(ScriptIcons)]
        $bnb add $kb -text "Workspace"
        bind [component kitbrowser] <<SortSeqChanged>> \
            [code $this setOption %W "KitBrowser,Sort"]
        
        # The code outline
        itk_component add codebrowser {
            ::Tloona::codeoutline $bnb.codebrowser \
                -sortsequence $UserOptions(CodeBrowser,SortSeq) \
                -sortalpha $UserOptions(CodeBrowser,SortAlpha) \
                -mainwindow $itk_interior
        }
    
        component codebrowser setNodeIcons $Icons(ScriptIcons)
        component codebrowser addSendCmd [mymethod SendToConsole]
        $bnb add [component codebrowser] -text "Outline"
        set V [component codebrowser component treeview]
        bind $V <Button-1> [code $this selectCode %W %x %y 0]
        bind $V <Control-Button-1> [code $this selectCode %W %x %y 1]
        bind [component codebrowser] <<SortSeqChanged>> \
            [code $this setOption %W "CodeBrowser,Sort"]
    }

    # @c Creates debugging tools and inspection browsers
    method CreateDebugTools {} {
        global Icons
        set Debugger [Tloona::debugger -openfilecmd [code $this openFile] \
            -fileisopencmd [code $this isOpen] \
            -selectfilecmd [code $this component textnb select]]
        
        # the run button gets a menu assigned
        set mb [toolbutton runto -toolbar maintoolbar -image $Icons(DbgRunTo) \
            -stickto front -type menubutton -separate 0]
        menuentry Run.DebugConfigs -type command -label "Debug..." \
            -command [code $Debugger onManageConfigs] -image $Icons(DbgRunTo)
        menuentry Run.Step -type command -label "Step into" \
            -toolbar maintoolbar -command [code $Debugger onStep] \
            -image $Icons(DbgStep) -accelerator F5
        menuentry Run.Next -type command -label "Step over" \
            -toolbar maintoolbar -command [code $Debugger onNext] \
            -image $Icons(DbgNext) -accelerator F6
        menuentry Run.Continue -type command -label "Continue" \
            -toolbar maintoolbar -command [code $Debugger onStepOut] \
            -image $Icons(DbgStepOut) -accelerator F7
        menuentry Run.Stop -type command -label "Stop" \
            -toolbar maintoolbar -command [code $Debugger onStop] \
            -image $Icons(DbgStop) -accelerator F8
        
        $Debugger runMenu $mb
        set vi [$Debugger varInspector [component browsenb] -borderwidth 0 \
            -mainwindow $itk_interior]
        set si [$Debugger stackInspector [component consolenb] -borderwidth 0 \
            -mainwindow $itk_interior]
        component browsenb add $vi -text "Variables"
        component consolenb add $si -text "Call Frames"
    }
        
    # @c open a Tcl/Itcl file
    method OpenTclFile {uri createTree} {
        # @c opens an (I)tcl file
        global UserOptions
        
        set T [component textnb]
        set cls [::Tloona::tclfile $T.file$_FileIdx -filename $uri -font $filefont \
                -tabsize $filetabsize -expandtab $filetabexpand \
                -mainwindow [namespace tail $this] \
                -backupfile $UserOptions(File,Backup) \
                -sendcmd [mymethod SendToConsole] \
                -threadpool [cget -threadpool]]
        
        # set binding for shortcut to change windows
        bind [$cls component textwin].t <Control-Tab> "[mymethod SwitchWidgets];break"
        
        set ttl [file tail $uri]
        component textnb add $cls -text $ttl
        
        if {[catch {$cls openFile ""} msg]} {
            set messg "can not open file $uri :\n\n"
            append messg $msg
            tk_messageBox -title "can not open file" \
                -message $messg -type ok -icon error
            itcl::delete object $cls
            return
        }
        
        $cls modified 0
        $cls configure -modifiedcmd [code $this showModified $cls 1]
        
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
        set fs [component kitbrowser addFileSystem $uri]
        if {$fs == ""} {
            return
        }
        
        # associate eventual open visual files from the new project
        # with the parsed code trees
        foreach {file} [component kitbrowser getTclFiles $fs] {
            foreach {uri cls hn} $_Files {
                if {![string equal [$file cget -name] $uri]} {
                    continue
                }
                $cls setTree $file
                $cls addToFileBrowser [component kitbrowser]
                $cls updateHighlights
            }
        }
    }
        
    # @c open a plain file
    method OpenPlainFile {uri} {
        global UserOptions
        
        set T [component textnb]
        set cls [::Tmw::visualfile $T.file$_FileIdx \
                -filename $uri -font $filefont \
                -tabsize $filetabsize \
                -expandtab $filetabexpand \
                -mainwindow [namespace tail $this] \
                -backupfile $UserOptions(File,Backup)]
        
        set ttl [file tail $uri]
        component textnb add $cls -text $ttl
        
        $cls openFile ""        
        $cls modified 0
        $cls configure -modifiedcmd [code $this showModified $cls 1]
        
        lappend _Files $uri $cls 1
        incr _FileIdx
        
        # if the search is triggered, show search toolbar in the
        # new file immediately
        $cls showSearch $_ShowSearchReplace
        if {$_CurrFile != ""} {
            $cls configure \
                -searchstring [$_CurrFile cget -searchstring] \
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
        
        set T [component textnb]
        set cls [::Tloona::webfile $T.file$_FileIdx \
                -filename $uri -font $filefont \
                -tabsize $filetabsize \
                -expandtab $filetabexpand \
                -mainwindow [namespace tail $this] \
                -backupfile $UserOptions(File,Backup) \
                -threadpool [cget -threadpool]]
        
        set ttl [file tail $uri]
        component textnb add $cls -text $ttl
        
        if {[catch {$cls openFile ""} msg]} {
            set messg "can not open file $uri :\n\n"
            append messg $msg
            tk_messageBox -title "can not open file" \
                -message $messg -type ok -icon error
            itcl::delete object $cls
            return
        }
        
        $cls modified 0
        $cls configure -modifiedcmd [code $this showModified $cls 1]
        
        lappend _Files $uri $cls 1
        incr _FileIdx
        
        # if the search is triggered, show search toolbar in the
        # new file immediately
        $cls showSearch $_ShowSearchReplace
        if {$_CurrFile != ""} {
            $cls configure \
                -searchstring [$_CurrFile cget -searchstring] \
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
        foreach {prj} [component kitbrowser getStarkits] {
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
        set cons [component consolenb select]
        $cons eval $script -showlines 1
    }
    
}

} ;# namespace Tloona
