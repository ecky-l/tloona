#
# mainapp.itk
#
package require tmw::platform 1.0
package require tmw::icons 1.0
package require tloona::kitbrowser 1.0
package require tloona::codebrowser 1.0
package require tloona::console 1.0
package require tloona::file 1.0
package require fileutil 1.7
package require parser::tcl 1.4
package require tloona::debugger 1.0
package require comm 4.3

package provide tloona::mainapp 1.0

namespace eval ::Tloona {}

usual TFrame {}
usual TPaned {}
usual TLabel {}
usual TProgressbar {}
usual TNotebook {}
usual Toolbar {}
usual TPanedwindow {}

# @c This is Tloona's main application. Only one instance of this class
# @c exists during runtime (per interpreter). It controls and displays
# @c everything of Tloona
class Tloona::Mainapp {
    inherit Tmw::Platform
    
    # @v filefont: the font for the text in file objects
    public variable filefont {fixed 14}
    # @v filetabsize: the tab size for files in chars
    public variable filetabsize 4
    # @v filetabexpand: whether to expand tab chars with
    # @v filetabexpand: space chars in file objects
    public variable filetabexpand 1
    # @v threadpool: A threadpool to run long running procedures
    public variable threadpool "" {
        component kitbrowser configure -threadpool [cget -threadpool]
    }
        
    # @v _FileIdx: the index of the actual file
    private variable _FileIdx 0
    # @v _Files: triple holding file objects
    private variable _Files {}
    # @v _CurrFile: the file that is currently active
    private variable _CurrFile ""
    # @v _Projects: holds the vfs projects
    private variable _Projects {}
    # @v _ViewProjectBrowser: indicates whether the project browser
    # @v _ViewProjectBrowser: is viewable
    private variable _ViewProjectBrowser 1
    # @v _ViewTextNbOnly: indicates that only the text notebook
    # @v _ViewTextNbOnly: should e shown
    private variable _ViewTextNbOnly 0
    # @v _ViewConsole: indicates whether to view the console
    private variable _ViewConsole 1
    # @v _ViewEditor: indicates whether to view the editor
    private variable _ViewEditor 1
    # @v _ViewConsoleOnly: indicates whether to view the console only
    private variable _ViewConsoleOnly 0
    # @v _ShowSearchReplace: indicates whether search/replace is showing
    private variable _ShowSearchReplace 0
    # @v _InitDir: initial dir for saving/opening
    private variable _InitDir $::env(HOME)
    # @v Debugger: The debugger object. This manages debug configurations,
    # @v Debugger: stack and variable inspector widgets and running of
    # @v Debugger: configurations
    private variable Debugger ""
    # @v CommIDs: A list of registered Comm ids for other interpreters
    private variable CommIDs {}
        
    constructor {args} {
        global Icons
        createPanes
        createNavigators
        createConsole
        createDebugTools
        $Debugger configure -console [component output]
        
        menuentry Edit.Sep1 -type separator -toolbar maintoolbar
        menuentry Edit.Search -type checkbutton -toolbar maintoolbar \
            -image $Tmw::Icons(ActFileFind) -command [code $this onEditSearch %K] \
            -label "Search & Replace" -variable [scope _ShowSearchReplace] \
            -accelerator Ctrl-f
        menuentry Code.Comment -type command -toolbar maintoolbar \
            -image $Icons(ToggleCmt) -command [code $this onToggleComment] \
            -label "Comment/Uncomment section"
        menuentry Code.Indent -type command -toolbar maintoolbar \
            -image $Icons(Indent) -command [code $this onIndent 1] \
            -label "Indent section"
        menuentry Code.Unindent -type command -toolbar maintoolbar \
            -image $Icons(UnIndent) -command [code $this onIndent 0] \
            -label "Unindent section"
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
            -status "ready [comm::comm self]"
        eval itk_initialize $args
    }
    
    # @r The initial directory for opening files
    public method getInitdir {} {
        return $_InitDir
    }
        
    # @c Override callback handler for File.New menu entry.
    public method onFileNew {} {
        # @c callback for new Tcl/Itcl scripts
        global UserOptions
        
        set T [component textnb]
        set cls [::Tloona::tclfile $T.file$_FileIdx \
                -font $filefont \
                -tabsize $filetabsize \
                -expandtab $filetabexpand \
                -mainwindow [namespace tail $this] \
                -backupfile $UserOptions(File,Backup)]
        
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
    public method onFileOpen {} {
        global TloonaApplication
        set uri ""
        set ft {
            {"Tcl Files" {.tcl .tk .itcl .itk}}
            {Starkits {.kit .exe}} 
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
    public method onProjectOpen {{uri ""}} {
        if {$uri != ""} {
            openFile $uri 0
        }
        
        while {1} {
            set uri [tk_chooseDirectory -mustexist 1 \
                -initialdir $_InitDir -parent [namespace tail $this]]
            if {$uri == ""} {
                return
            }
            if {[file extension $uri] == ".vfs" } {
                break
            }
                
            tk_messageBox -type ok -icon info -title \
                "Not a vfs directory" \
                -message "Directory must have the ending .vfs"
        }
        
        openFile $uri 0
    }

    
    # @c Override callback handler for File.Save menu entry.
    public method onFileSave {{file ""}} {
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
    public method onFileClose {{file ""}} {
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
        $file removeFromBrowser [component codebrowser]
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
    public method onEditUndo {} {
        if {$_CurrFile == ""} {
            return
        }
        $_CurrFile undo
        $_CurrFile updateHighlights
    }

    # @c Override callback handler for Edit.Redo menu entry.
    public method onEditRedo {} {
        if {$_CurrFile == ""} {
            return
        }
        $_CurrFile redo
        $_CurrFile updateHighlights
    }

    # @c Override callback handler for Edit.Cut menu entry.
    public method onEditCut {} {
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
    public method onEditCopy {} {
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
    public method onEditPaste {} {
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
    public method onEditSearch {{key ""}} {
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
    public method onViewWindow {what {view -1} {store 1}} {
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
                
                showWindowPart $view browsepw navigatepw browserSash 0
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
                showWindowPart $view txtconpw consolenb consoleSash end
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
                showWindowPart $view txtconpw textnb consoleSash \
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
    public method onQuit {} {
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
    public method onToggleComment {} {
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
    public method onIndent {indent} {
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
        
    # @c callback that is triggered when the currently selected
    # @c file changes
    public method onCurrFile {{file ""}} {
        if {$file != "" && \
                    [catch {component textnb select $file} msg]} {
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
    
        # adjust code browser view
        set fb [component codebrowser]
        $fb remove all
        if {[set tree [$_CurrFile getTree]] != ""} {
            $fb add $tree 1 0
            if {[$fb children ""] != {}} {
                $fb see [lindex [$fb children ""] 0]
            }
        }
        
        set fb [component kitbrowser]
        set cTree [$_CurrFile getTree]
        if {$cTree != "" && [$fb exists $cTree] 
                && [$fb cget -syncronize]} {
            $fb selection set $cTree
            $fb see $cTree
        }
        
        return $_CurrFile
    }
            
    # @c shows whether a file is modified or not
    public method showModified {fileObj modified} {
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
        
    # @c selects a fragment of code in a file
    public method selectCode {treewin x y definition} {
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
        set sel [$realSel getTopnode ::parser::Script]
        
        set toSelect ""
        foreach {fn cls hasFn} $_Files {
            if {$sel == [$cls getTree]} {
                set toSelect $cls
                break
            }
        }
        
        if {$toSelect == ""} {
            return
        }
        
        component textnb select $toSelect
        if {[lindex [$realSel cget -byterange] 0] != -1} {
            $toSelect jumpTo $realSel $definition
            $toSelect flashCode $realSel $definition
        }
    }
        
    # @c shows only the component named
    public method showOnly {widget} {
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
    public method getCurrFile {} {
        return $_CurrFile
    }
        
    # @c checks whether a file or project is open
    public method isOpen {uri} {
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
    public method getOpenFiles {} {
        set result {}
        foreach {fn cls hn} $_Files {
            lappend result $cls
        }
        return $result
    }
        
    # @c sets the option key, indicated by widget
    public method setOption {widget key} {
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
    # @r The file object. Type at least ::parser::StructuredFile
    public method openFile {uri createTree} {
        global TloonaApplication
        
        set ending [file extension $uri]
        set fCls ""
        switch -- $ending {
            ".tcl" -
            ".tk" -
            ".itcl" -
            ".itk" -
            ".test" -
            ".ws3" {
                if {[set fileObj [isOpen $uri]] != ""} {
                    Tmw::message $TloonaApplication "File exists" ok \
                        "The File $uri exists already"
                    component textnb select $fileObj
                    return
                }
                set fCls [openTclFile $uri 1]
                if {$createTree} {
                    # the code tree does not exist yet. Create it, but
                    # only if this is a file that was not opened from
                    # an existing vfs project
                    if {[isProjectPart $uri cTree]} {
                        component kitbrowser refreshFile $cTree
                        $fCls setTree $cTree
                    } else {
                        $fCls createTree
                    }
                } elseif {[isProjectPart $uri cTree]} {
                    component kitbrowser refreshFile $cTree
                    $fCls setTree $cTree
                }
                $fCls updateHighlights
                $fCls addToBrowser [component codebrowser]
                update
            }
            ".kit" {
                openKitFile $uri
                return
            }
            ".vfs" {
                if {[isOpen $uri] != ""} {
                    Tmw::message $TloonaApplication "Project exists" ok \
                        "The project $uri exists already"
                    return
                }
                openKitFile $uri
                return
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
                set fCls [openWebFile $uri]
            }
            
            default {
                set fType [lindex [fileutil::fileType $uri] 0]
                if {[string equal $fType text]} {
                    if {[set fileObj [isOpen $uri]] != ""} {
                        Tmw::message $TloonaApplication \
                            "File already open" ok \
                            "The file $uri exists already"
                        component textnb select $fileObj
                        return
                    }
                    set fCls [openPlainFile $uri]
                    
                } else {
                    puts "cannot handle this"
                    return
                }
            }
        }
        
        component textnb select $fCls
        set _InitDir [file dirname $uri]
        return $fCls
    }

        
    # @c Adds a comm id
    public method addCommID {id} {
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
    public method removeCommID {id} {
        puts geee,$CommIDs,$id
        if {[set idx [lsearch $CommIDs $id]] < 0} {
            return
        }
        puts here,$CommIDs
        set CommIDs [lreplace $CommIDs $idx $idx]
        puts after,$CommIDs
    }
        
    # @r Comm IDs
    public method getCommIDs {} {
        return $CommIDs
    }
    
    protected method defaultMenu {} {
        global Icons
        
        menuentry File.New -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileNew) -command [code $this onFileNew] \
            -accelerator Ctrl-n
        menuentry File.Open -type cascade -image $Tmw::Icons(FileOpen)
        menuentry File.Open.File -type command  -toolbar maintoolbar \
            -command [code $this onFileOpen] -image $Icons(TclFileOpen) \
            -accelerator Ctrl-o -label "File..."
        menuentry File.Open.Project -type command -label "Project..." \
            -toolbar maintoolbar -command [code $this onProjectOpen] \
            -image $Icons(KitFileOpen) -accelerator Ctrl-p
        
        menuentry File.Save -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileSave) -command [code $this onFileSave] \
            -accelerator Ctrl-s
        menuentry File.Close -type command -toolbar maintoolbar \
            -image $Tmw::Icons(FileClose) -command [code $this onFileClose] \
            -accelerator Ctrl-w
        menuentry File.Sep0 -type separator -toolbar maintoolbar
        menuentry File.Quit -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActExit) -command [code $this onQuit] \
            -accelerator Ctrl-q
        
        menuentry Edit.Undo -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActUndo) -command [code $this onEditUndo] \
            -accelerator Ctrl-z
        menuentry Edit.Redo -type command -toolbar maintoolbar \
            -image $Tmw::Icons(ActRedo) -command [code $this onEditRedo] \
            -accelerator Ctrl-r
        menuentry Edit.Sep0 -type separator -toolbar maintoolbar
        menuentry Edit.Cut -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditCut) -command [code $this onEditCut] \
            -accelerator Ctrl-x
        menuentry Edit.Copy -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditCopy) -command [code $this onEditCopy] \
            -accelerator Ctrl-c
        menuentry Edit.Paste -type command -toolbar maintoolbar \
            -image $Tmw::Icons(EditPaste) -command [code $this onEditPaste] \
            -accelerator Ctrl-v
    }
        
    # @c shows a particular window part
    #
    # @a view: to view or not to view
    protected method showWindowPart {view parentComp childComp optionKey pos} {
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
    
    # @c creates the pane parts in the main window
    private method createPanes {} {
        itk_component add browsepw {
            ::ttk::paned [mainframe].browsepw \
                -orient horizontal
        }
        
        itk_component add navigatepw {
            ::ttk::paned [component browsepw].navigatepw \
                -orient vertical
        }
        
        itk_component add browsenb {
            ::ttk::notebook [component navigatepw].browsenb \
                -width 150 -height 300
        }
        
        component navigatepw add [component browsenb] -weight 1
        
        itk_component add txtconpw {
            ::ttk::paned [component browsepw].txtconpw \
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

    # @c creates the navigation controls: code browser, project
    # @c browser...
    private method createNavigators {} {
        global UserOptions Icons
        
        set bnb [component browsenb]
        
        # the project browser
        itk_component add kitbrowser {
            ::Tloona::kitbrowser $bnb.kitbrowser \
                -closefilecmd [code $this onFileClose] \
                -openfilecmd [code $this openFile] \
                -isopencmd [code $this isOpen] \
                -selectcodecmd [code $this selectCode] \
                -sortsequence $UserOptions(KitBrowser,SortSeq) \
                -sortalpha $UserOptions(KitBrowser,SortAlpha) \
                -mainwindow $itk_interior
        }
        set kb [component kitbrowser]
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
        $bnb add [component codebrowser] -text "Outline"
        set V [component codebrowser component treeview]
        bind $V <Button-1> [code $this selectCode %W %x %y 0]
        bind $V <Control-Button-1> [code $this selectCode %W %x %y 1]
        bind [component codebrowser] <<SortSeqChanged>> \
            [code $this setOption %W "CodeBrowser,Sort"]
    }

    # @c Creates debugging tools and inspection browsers
    private method createDebugTools {} {
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
        
    # @c creates the console
    private method createConsole {} {
        global UserOptions
            
        set cnb [component consolenb]
        itk_component add output {
            Tloona::backendconsole $cnb.output \
                -colors $UserOptions(TclSyntax) \
                -font $UserOptions(ConsoleFont)
        }
        component output createBackend [info nameofexecutable] yes
        $cnb add [component output] -text "Debug Console"
        
        itk_component add console {
            Tloona::slaveconsole $cnb.console -colors $UserOptions(TclSyntax) \
                -font $UserOptions(ConsoleFont)
        }
            
        #breakpoint
        #puts [info level [info level]]
        #puts [info frame [info frame]]
        set C [component console]
        set _DefaultInterp [$C createInterp 1]
        $cnb add $C -text "Slave Console"
    }
        
    # @c open a Tcl/Itcl file
    private method openTclFile {uri createTree} {
        # @c opens an (I)tcl file
        global UserOptions
        
        set T [component textnb]
        set cls [::Tloona::tclfile $T.file$_FileIdx \
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
            $cls configure -searchstring [$_CurrFile cget -searchstring] \
                -replacestring [$_CurrFile cget -replacestring] \
                -searchexact [$_CurrFile cget -searchexact] \
                -searchregex [$_CurrFile cget -searchregex] \
                -searchnocase [$_CurrFile cget -searchnocase]
        }
        
        return $cls
    }
        
    # @c open a starkit file
    private method openKitFile {uri} {
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
                $cls addToBrowser [component kitbrowser]
                $cls updateHighlights
            }
        }
    }
        
    # @c open a plain file
    private method openPlainFile {uri} {
        global UserOptions
        
        set T [component textnb]
        set cls [::Tmw::browsablefile $T.file$_FileIdx \
                -filename $uri -font $filefont \
                -tabsize $filetabsize \
                -expandtab $filetabexpand \
                -mainwindow [namespace tail $this] \
                -backupfile $UserOptions(File,Backup)]
        
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
        
    # @c open a web file
    private method openWebFile {uri} {
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
    private method adaptSearchOptions {fileObj} {
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
    private method isProjectPart {uri treePtr} {
        upvar $treePtr tree
        
        set vfsDirs {}
        set dirList [file split $uri]
        for {set i 0} {$i < [llength $dirList]} {incr i} {
            set dir [lindex $dirList $i]
            if {![string equal [file extension $dir] .vfs]} {
                continue
            }
            
            lappend vfsDirs [eval file join [lrange $dirList 0 $i]]
        }
        
        if {$vfsDirs == {}} {
            return no
        }
        
        foreach {vfs} [component kitbrowser getStarkits] {
            if {[lsearch $vfsDirs [$vfs cget -name]] < 0} {
                continue
            }
            
            foreach {kid} [$vfs getChildren yes] {
                if {[$kid cget -name] == $uri} {
                    set tree $kid
                    return yes
                }
            }
        }
        
        return no
    }
    
}

