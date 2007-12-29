#set ::TloonaRoot [file dirname [info script]]
#set auto_path [concat [file join $::TloonaRoot lib] $::TloonaRoot $auto_path]

#error "this shouldnt happen"

package require Itree 1.0
package require tmw::dialog 1.0
package require tmw::toolbarframe 1.0
package require tmw::browser 1.0
package require tmw::icons 1.0
package require tdom 0.8.1

package provide tloona::debugger 1.0

namespace eval ::Tloona {}

usual VarInspector {}
usual StackInspector {}
usual Debugger {}
usual Menu {}
usual TEntry {}
usual TCombobox {}
usual Listbox {}
usual Text {}

# @c This is a callframe node that can be displayed in the stack browser
# @c It is also capable of searching the appropriate file and offset in
# @c a given base directory
class ::Tloona::Callframe {
    inherit ::itree::Node
    
    # @v offset: The offset in the called procedure
    public variable offset ""
    # @v length: The byte length in the called procedure
    public variable length ""
    # @v deffile: The file where the callframe is defined
    public variable deffile ""
    # @v defnode: The node where the callframe is defined
    public variable defnode ""
        
    constructor {args} {
        eval configure $args
    }
    
    # @c Searches the definition of this callframe and stores
    # @c the result in deffile/defnode
    #
    # @a baseFss: list of base directories as Tmw::Fs::Filesystem 
    # @a baseFss: objects
    public method lookupDefinition {baseFss} {
        set tkList [split [string trim \
            [regsub -all {::} [cget -name] { }]] " "]
        set mNode ""
        foreach {base} $baseFss {
            foreach {ch} [$base getChildren 1] {
                if {[$ch cget -type] != "tclfile"} {
                    continue
                }
                
                set mNode [$ch lookup [lindex $tkList end] \
                    [lrange $tkList 0 end-1]]
                if {$mNode != ""} {
                    configure -deffile $ch -defnode $mNode
                    break
                }
            }
            if {$mNode != ""} {
                break
            }
        }
    }
    
}

# @c This is a browser for locally visible variables
class ::Tloona::VarInspector {
    inherit Tmw::ToolbarFrame
    
    # @v FrameVars: An array of variables for call frames. The callframes
    # @v FrameVars: are treenode objects
    private variable FrameVars
    array set FrameVars {}
        
    # @v LocalVars: Root Itree node for local variables
    private variable LocalVars ""
    # @v GlobalVars: Root Itree node for global variables
    private variable GlobalVars ""
        
    constructor {args} {
        createComponents
        
        set GlobalVars [::itree::Node ::#auto -type debug_vars -name "Globals" -expanded 0]
        set LocalVars [::itree::Node ::#auto -type debug_vars -name "Locals" -expanded 1]
        
        component browser configure -selectcmd [code $this displayValue]
        #component treeview configure -columns {value}
        eval itk_initialize $args
    }
    
    # @c Reset and destroy all variable nodes
    public method deleteFrameVars {} {
        set tmp {}
        foreach {k node} [array get FrameVars] {
            lappend tmp $node
        }
        component browser remove $tmp yes
        array unset FrameVars
        array set FrameVars {}
    }
        
    # @c Add a variable to a call frame node
    public method addFrameVar {callFrame scope args} {
        if {![info exists FrameVars($callFrame,$scope)]} {
            set FrameVars($callFrame,$scope) {}
        }
        
        if {[lsearch $args -type] < 0} {
            lappend args -type variable
        }
        
        set node [eval ::itree::Node ::#auto $args]
        lappend FrameVars($callFrame,$scope) $node
        return $node
    }
        
    # @c Display the variables for a given callframe
    public method displayFrameVars {callFrame {reset yes}} {
        if {$reset} {
            component browser remove all
        }
        
        if {[info exists FrameVars($callFrame,global)]} {
            $GlobalVars removeChildren
            $GlobalVars addChildren $FrameVars($callFrame,global)
        }
        if {[info exists FrameVars($callFrame,local)]} {
            $LocalVars removeChildren
            $LocalVars addChildren $FrameVars($callFrame,local)
        }
        component browser add [list $GlobalVars $LocalVars] 1 0
    }
        
    # @c Displays the value of a selected variable in the text window
    #
    # @a varNode: an itree node representing the varnode. Displayed is
    # @a varNode: the -data value
    public method displayValue {{varNode ""}} {
        if {$varNode == ""} {
            set varNode [component browser selection]
        }
        if {$varNode == ""} {
            return
        }
        
        foreach {win} {vscroll hscroll} {
            if {[grid info [component $win]] != {}} {
                grid forget [component $win]
            }
        }
        
        component valuedisplay configure -state normal
        component valuedisplay delete 1.0 end
        component valuedisplay insert end [$varNode cget -data]
        component valuedisplay configure -state disabled
        set xv [component valuedisplay xview]
        set yv [component valuedisplay yview]
        if {[lindex $xv 0] != 0 || [lindex $xv 1] != 1} {
            grid [component hscroll] -row 1 -column 0 -padx 0 -pady 0 -sticky wes
        }
        if {[lindex $yv 0] != 0 || [lindex $yv 1] != 1} {
            grid [component vscroll] -row 0 -column 1 -padx 0 -pady 0 -sticky nes
        }
    }
        
    # @c Clears the browser and the value display. If delete is true,
    # @c the varnode objects are deleted
    public method clear {{delete no}} {
        component browser remove all $delete
        component browser remove all $delete
        set GlobalVars [::itree::Node ::#auto -type debug_vars -name "Globals" -expanded 0]
        set LocalVars [::itree::Node ::#auto -type debug_vars -name "Locals" -expanded 1]
        #component browser remove $GlobalVars no
        #component browser remove $LocalVars no
        
        array unset FrameVars
        array set FrameVars {}
        
        foreach {win} {vscroll hscroll} {
            if {[grid info [component $win]] != {}} {
                grid forget [component $win]
            }
        }
        
        component valuedisplay configure -state normal
        component valuedisplay delete 1.0 end
        component valuedisplay configure -state disabled
        
    }
    
    # @c Creates the inner components. This are a browser for the
    # @c variables and a text window for displaying the content
    private method createComponents {} {
        # The browser
        set par [ttk::paned [childsite].paned -orient vertical]
        itk_component add browser {
            Tmw::browser $par.browser
        }
        
        set f [ttk::frame $par.textframe -border 0 -relief flat]
        itk_component add valuedisplay {
            text $f.valuedisplay -borderwidth 1 -relief flat -background white \
                -wrap none -height 3
        }
        set T [component valuedisplay]
        itk_component add -private vscroll {
            ttk::scrollbar $f.vscroll -command "$T yview" -class TScrollbar
        }
        itk_component add -private hscroll {
            ttk::scrollbar $f.hscroll -orient horizontal -command "$T xview" \
                -class TScrollbar
        }
        $T configure -xscrollcommand [list $f.hscroll set] \
            -yscrollcommand [list $f.vscroll set]
        
        grid $T -row 0 -column 0 -sticky news -padx 1 -pady 1
        grid rowconfigure $f 0 -weight 1
        grid columnconfigure $f 0 -weight 1
        
        $par add [component browser] -weight 1
        $par add $f -weight 1
        pack $par -expand yes -fill both
    }
    
}

        





proc ::Tloona::VarInspector::parseFrameVars {obj xmlNode callFrame scope} {
    foreach {node} $xmlNode {
        set name [$node getAttribute name]
        set type [$node getAttribute type]
        set value ""
        if {[$node hasChildNodes]} {
            set vn [$node firstChild]
            set value [$vn nodeValue]
        }
        $obj addFrameVar $callFrame $scope -name $name -type $type \
            -displayformat {"%s (%s)" -name -type} -data $value
    }
}

# @c This is a browser for the stack trace at a certain
# @c code position
class ::Tloona::StackInspector {
    inherit Tmw::Browser
    
    # @v -openfilecmd: a piece of code that is executed to open files
    #itk_option define -selectcmd selectCmd Command ""

    constructor {args} {
        configure -sortalpha 0 -selectcmd [code $this onSelectFrame]
        eval itk_initialize $args
    }
    
    # @c Callback for selecting a stack frame
    public method onSelectFrame {} {
        foreach {handler} $SelectHandlers {
            eval $handler [selection]
        }
    }
        
    
}


# @c This is a dialog for managing debug configurations. Each debug
# @c configuration has a name, a main script and possibly a working
# @c directory, where the script is executed. Possibly it also has
# @c arguments for script execution. The debug configurations appear
# @c in the run menu later in the debugger.
class ::Tloona::DebugConfigDlg {
    inherit Tmw::Dialog
    
    # @v projects: A list of projects that are displayed in a combobox
    # @v projects: for selection of an entry
    public variable projects {} {
        set pres {}
        foreach {prj} $projects {
            lappend pres [$prj cget -tail]
        }
        component projectcombo configure -values $pres
    }
    
    # @v Configs: an array of configurations
    private variable Configs
    array set Configs {}
    # @v Current: current name entry content
    private variable Current ""
        
    # @v CurrName: current name
    private variable CurrName ""
    # @v CurrScript: current script
    private variable CurrScript ""
    # @v CurrBasedir: current base directory
    private variable CurrBasedir ""
    # @v CurrArgs: current arguments
    private variable CurrArgs ""
    # @v CurrProject: Current workspace project
    private variable CurrProject ""
        
    constructor {args} {
        createComponents
        
        add close -text "Close"
        add debug -text "Debug"
        eval itk_initialize $args
    }
    
    # @c Invoked on configuration add
    public method onAddConfig {} {
        set name "New Configuration"
        component configlist insert end $name
        component configlist selection clear 0 end
        component configlist selection set end
    
        set Current [component configlist curselection]
        set Configs($Current,Name) $name
        set Configs($Current,Project) ""
        set Configs($Current,Script) ""
        set Configs($Current,Basedir) ""
        set Configs($Current,Args) {}
        
        
        setCurrentConfig
    }
        
    # @c Invoked on configuration delete
    public method onDeleteConfig {} {
        set ci [component configlist curselection]
        
        # Adjust the configs array. Configurations from the next but
        # choosen entry's index are put at the current index
        set n [expr {[llength [array names Configs]] / 5}]
        for {set i [expr {$ci + 1}]} {$i < $n} {incr i} {
            set j [expr {$i - 1}]
            set Configs($j,Project) $Configs($i,Project)
            set Configs($j,Name) $Configs($i,Name)
            set Configs($j,Script) $Configs($i,Script)
            set Configs($j,Basedir) $Configs($i,Basedir)
            set Configs($j,Args) $Configs($i,Args)
        }
        
        incr n -1
        unset Configs($n,Project)
        unset Configs($n,Name)
        unset Configs($n,Script)
        unset Configs($n,Basedir)
        unset Configs($n,Args)
        
        component configlist selection clear 0 end
        component configlist delete $ci
        if {$ci == [component configlist index end]} {
            set ci 0
        }
        
        # If there are no more configurations, initialize default values
        # for the entries and return
        if {$n == 0} {
            set CurrName ""
            set CurrScript ""
            set CurrBasedir ""
            set CurrArgs {}
            return
        }
        
        component configlist selection set $ci
        setCurrentConfig $ci
    }
        
    # @c Open a script for debug execution
    public method onOpenScript {{uri ""}} {
        global TloonaApplication
        
        if {$uri == ""} {
            set ft {
                {"Tcl Files" {.tcl .tk .itcl .itk}}
                {Starkits {.kit .exe}} 
                {Tests .test}
            }
            set uri [tk_getOpenFile -initialdir \
                [$TloonaApplication getInitdir] \
                -filetypes  $ft -parent $itk_interior]
        }
        
        if {$uri == ""} {
            return
        }
        
        set CurrScript $uri
        set Configs($Current,Script) $uri
    }
        
    # @c Open the base directory for a configuration
    public method onOpenBasedir {{uri ""}} {
        global TloonaApplication
        
        if {$uri == ""} {
            set uri [tk_chooseDirectory -mustexist 1 \
                -parent $itk_interior \
                -initialdir [$TloonaApplication getInitdir]]
        }
        
        if {$uri == ""} {
            return
        }
        
        set CurrBasedir $uri
        set Configs($Current,Basedir) $uri
    }
        
    # @r All configurations as a list of lists:
    # @r {{name script basedir args} {name script ...}}
    public method getConfigs {} {
        set n [expr {[llength [array names Configs]] / 5}]
        set res {}
        for {set i 0} {$i < $n} {incr i} {
            lappend res [list $Configs($i,Name) $Configs($i,Project) \
                $Configs($i,Script) $Configs($i,Basedir) $Configs($i,Args)]
        }
        
        return $res
    }
        
    # @c Sets the configurations from a list of the form
    # @c that getConfigs returns
    public method setConfigs {cfgs} {
        if {$cfgs == {}} {
            return
        }
        
        array unset Configs
        array set Configs {}
        for {set i 0} {$i < [llength $cfgs]} {incr i} {
            set cfg [lindex $cfgs $i]
            set Configs($i,Name) [lindex $cfg 0]
            set Configs($i,Project) [lindex $cfg 1]
            set Configs($i,Script) [lindex $cfg 2]
            set Configs($i,Basedir) [lindex $cfg 3]
            set Configs($i,Args) [lindex $cfg 4]
            
            component configlist insert end $Configs($i,Name)
        }
        
        component configlist selection set end
        setCurrentConfig
    }
    
    # @c Creates the inner components
    private method createComponents {} {
        set inner [childsite]
        
        set f1 [::ttk::frame $inner.lf -relief groove -borderwidth 1]
        itk_component add configlist {
            listbox $f1.configlist -background white -height 10 -width 25 \
                -borderwidth 0
        }
        set L [component configlist]
        set vscroll [ttk::scrollbar $f1.vscroll -orient vertical \
            -command [list $L yview] -class TScrollbar]
        $L configure -yscrollcommand [list $vscroll set]
        
        set f2 [ttk::frame $f1.buttons -relief flat -borderwidth 0]
        ttk::button $f2.add -text "Add" -command [code $this onAddConfig]
        ttk::button $f2.delete -text "Delete" -command [code $this onDeleteConfig]
        pack $f2.add $f2.delete -side left -padx 2
        
        grid $L -row 0 -column 0 -sticky news
        grid $vscroll -row 0 -column 1 -sticky nse
        grid $f2 -row 1 -column 0 -columnspan 2 -sticky wes -pady 5
        
        set f2 [ttk::frame $inner.cfgframe -relief groove -borderwidth 1]
        ttk::label $f2.namelab -text "Name: "
        ttk::entry $f2.namee -width 30 -textvariable [scope CurrName]
        bind $f2.namee <FocusOut> [code $this setConfigVar Name]
        
        ttk::label $f2.projlab -text "Workspace Project: "
        itk_component add projectcombo {
            ttk::combobox $f2.projcombo -justify left -state readonly -values {} \
                -textvariable [scope CurrProject]
        }
        bind [component projectcombo] <<ComboboxSelected>> \
            [code $this setConfigVar Project]
        
        ttk::label $f2.scriptlab -text "Script: "
        ttk::entry $f2.scriptentry -width 30 \
            -textvariable [scope CurrScript]
        ttk::button $f2.scriptbutton -image $Tmw::Icons(FileOpen) \
            -compound image -command [code $this onOpenScript]
        bind $f2.scriptentry <FocusOut> \
            [code $this setConfigVar Script]
        
        ttk::label $f2.basedirlab -text "Base Directory: "
        ttk::entry $f2.basedire -width 30 \
            -textvariable [scope CurrBasedir]
        ttk::button $f2.basedirbutton -image $Tmw::Icons(FileOpen) \
            -compound image -command [code $this onOpenBasedir]
        bind $f2.basedire <FocusOut> [code $this setConfigVar Basedir]
        
        ttk::label $f2.argslab -text "Script Arguments: "
        ttk::entry $f2.argse -width 30 -textvariable [scope CurrArgs]
        bind $f2.argse <FocusOut> [code $this setConfigVar Args]
        
        grid $f2.namelab -row 0 -column 0 -sticky e -padx 4 -pady 3
        grid $f2.namee -row 0 -column 1 -sticky we -padx 4 -pady 3
        grid $f2.projlab -row 1 -column 0 -sticky e -padx 4 -pady 3
        grid [component projectcombo] -row 1 -column 1 \
            -sticky we -padx 4 -pady 3
        grid $f2.scriptlab -row 2 -column 0 -sticky e -padx 4 -pady 3
        grid $f2.scriptentry -row 2 -column 1 -sticky we -padx 4 -pady 3
        grid $f2.scriptbutton -row 2 -column 2 -sticky w -padx 4 -pady 3
        grid $f2.basedirlab -row 3 -column 0 -sticky e -padx 4 -pady 3
        grid $f2.basedire -row 3 -column 1 -sticky we -padx 4 -pady 3
        grid $f2.basedirbutton -row 3 -column 2 -sticky w \
            -padx 4 -pady 3
        grid $f2.argslab -row 4 -column 0 -sticky e -padx 4 -pady 3
        grid $f2.argse -row 4 -column 1 -sticky we -padx 4 -pady 3
        
        pack $f1 $f2 -side left -padx 2 -pady 2 -ipady 2 \
            -ipadx 4 -expand yes -fill both
        
        bind $L <<ListboxSelect>> [code $this setCurrentConfig]
    }
        
    # @c Sets the actual config name in the list
    private method setConfigVar {arg} {
        switch -- $arg {
            Project {
                set Configs($Current,Project) $CurrProject
            }
            Name {
                set Configs($Current,Name) $CurrName
            }
            Script {
                set Configs($Current,Script) $CurrScript
            }
            Basedir {
                set Configs($Current,Basedir) $CurrBasedir
            }
            Args {
                set Configs($Current,Args) $CurrArgs
            }
        }
    }
        
    # @c Set the currently selected Configuration
    private method setCurrentConfig {{index -1}} {
        if {$index < 0} {
            set index [component configlist curselection]
        }
        set Current $index
        set CurrProject $Configs($Current,Project)
        set CurrName $Configs($Current,Name)
        set CurrScript $Configs($Current,Script)
        set CurrBasedir $Configs($Current,Basedir)
        set CurrArgs $Configs($Current,Args)
    }
        
    
}


# @c This is the graphical debugger. It contains inspection views,
# @c a configuration dialog and run toolbar
class ::Tloona::Debugger {
    
    # @v console: the console for debugger output. This is where
    # @v console: the backend comes from and output is sent to
    public variable console ""
    # @v opencmd: A code fragment executed to open a file
    public variable openfilecmd ""
    # @v fileisopencmd: A code fragment executed to see if a file is open
    public variable fileisopencmd ""
    # @v selectfilecmd: A command to bring a file to the top
    public variable selectfilecmd ""
        
    # @v RunMenu: The path to a run menu. The debugger can create
    # @v RunMenu: the menu for a given menu button
    private variable RunMenu ""
    # @v VarInspector: A variable inspector. 
    private variable VarInspector ""
    # @v StackInspector: A stack trace inspector
    private variable StackInspector ""
    # @v DebugXML: A string of DebugInfo XML. This comes from backend
    # @v DebugXML: processes running the program to debug
    private variable DebugXML ""
        
    # @v FetchingDBG: Indicates whether the readBackend method is
    # @v FetchingDBG: currently fetching debug info
    private variable FetchingDbg no
        
    # @v Configs: The available debug configurations
    private variable Configs
    array set Configs {}
        
    # @v CurrentRun: The index of Debug configuration currently running
    private variable CurrentRun -1
    
    constructor {args} {
        #createComponents
        eval configure $args
    }
    
    # @c Creates the run menu (with run config entries)
    #
    # @a mButton: the menu button to which the menu is attached
    public method runMenu {{mButton ""}} {
        if {$RunMenu == ""} {
            if {$mButton == ""} {
                error "Menubutton must be provided for creating run menu"
            }
            set RunMenu [menu $mButton.runconfig -tearoff 0]
            $mButton configure -menu $RunMenu
        }
        restoreConfigs
        
        return $RunMenu
    }
        
    # @c Creates the Variable inspector in a given parent
    #
    # @a parent: the parent frame
    # @a args: configuration args for the var inspector
    public method varInspector {{parent ""} args} {
        if {$VarInspector == ""} {
            if {$parent == ""} {
                error "Parent must be provided for creating var inspector"
            }
            set VarInspector [eval ::Tloona::VarInspector $parent.varinspector $args]
            if {$StackInspector != ""} {
                $StackInspector addSelectHandler \
                    [code $VarInspector displayFrameVars]
            }
        }
        
        return $VarInspector
    }
        
    # @c Creates the stack inspector in a given parent and returns it
    #
    # @a parent: the parent frame where to create the stack inspector
    # @a args: config arguments for the stack inspector
    public method stackInspector {{parent ""} args} {
        if {$StackInspector == ""} {
            if {$parent == ""} {
                error "Parent must be provided for creating stack inspector"
            }
            set StackInspector [eval ::Tloona::stackinspector $parent.stackinspector $args]
            if {$VarInspector != ""} {
                $StackInspector addSelectHandler \
                    [code $VarInspector displayFrameVars]
            }
        }
        
        return $StackInspector
    }
        
    # @c Runs the debugger
    #
    # @a index: The configuration index to run
    public method onRun {index} {
        global TloonaRoot TloonaApplication
        
        if {$CurrentRun == $index} {
            return
        }
        
        if {$Configs($index,Script) == {}} {
            return
        }
        
        # If the project is open, set the correspoding file system
        set Configs($index,ProjectFs) [$TloonaApplication \
            component kitbrowser getFilesys *$Configs($index,Project)]
        
        $console addOutFilter [code $this filterDebugInfo]
        
        if {$Configs($index,Basedir) != ""} {
            puts [$console cget -slave] [list cd $Configs($index,Basedir)]
        }
        
        puts [$console cget -slave] \
            "set ::auto_path [list $::auto_path]; set ::TloonaDbg_topdir $::TloonaRoot;"
        puts [$console cget -slave] {
            catch {
                package require vfs
                vfs::mk4::Mount $TloonaDbg_topdir $TloonaDbg_topdir -readonly
            } msg
            #package require tmw::debugger
        }
        $console eval [list source $Configs($index,Script)]
        
        set CurrentRun $index
        
        bind $console <<BackendExit_[$console cget -slave]>> \
            [code $this clearInspectors yes]
    }
        
    # @c Steps into the next command
    public method onStep {} {
        if {$CurrentRun < 0} {
            return
        }
        puts [$console cget -slave] step
    }
        
    # @c Steps over the next command
    public method onNext {} {
        if {$CurrentRun < 0} {
            return
        }
        puts [$console cget -slave] next
    }
        
    # @c Steps out of the current command
    public method onStepOut {} {
        if {$CurrentRun < 0} {
            return
        }
        puts [$console cget -slave] continue
    }
        
    # @c Stops the running application
    public method onStop {} {
        if {$CurrentRun < 0} {
            return
        }
        $console eval ::exit
    }
        
    # @c called when the user wants to manage debug
    # @c configurations
    public method onManageConfigs {} {
        global TloonaApplication UserOptions
        
        Tloona::debugconfigdlg .dbgc -master $TloonaApplication \
            -title "Debug Configurations" \
            -projects [$TloonaApplication component kitbrowser getStarkits]
        if {[info exists UserOptions(DebugConfigs)]} {
            .dbgc setConfigs $UserOptions(DebugConfigs)
        }
        
        set res [.dbgc show]
        
        set aCfg [.dbgc getConfigs]
        restoreConfigs $aCfg
        set UserOptions(DebugConfigs) $aCfg
        
        set curSel [.dbgc component configlist curselection]
        destroy .dbgc
        
        if {[string equal $res debug]} {
            if {$curSel == ""} {
                set m "Please create and/or select a configuration to run.\n"
                Tmw::message $TloonaApplication \
                    "No configuration selected" ok $m
                return
            }
            onRun $curSel
        }
    }
        
    # @c Parses the debug info XML string and makes the values
    # @c visible in the inspection boxes
    #
    # @a xml: A tdom xml node
    public method parseDebugInfo {xml} {
        if {$VarInspector == "" || $StackInspector == ""} {
            return
        }
        
        set doc [dom parse $xml]
        set root [$doc documentElement]
        
        # Get stack trace and insert it into the stackinspector
        set stNode [$root getElementsByTagName stacktrace]
        set cfNodes [$stNode getElementsByTagName callframe]
        set mThread [::itree::Node ::#auto -type debug_thread \
            -name "Main Thread" -expanded 1]
        $VarInspector deleteFrameVars
        for {set i 0} {$i < [llength $cfNodes]} {incr i} {
            set cfNode [lindex $cfNodes end-$i]
            set cfName "Global Level"
            if {[set cfn [$cfNode getElementsByTagName command]] != ""} {
                set ctn [$cfn firstChild]
                set cfName [$ctn nodeValue]
            }
            set tNode [$mThread addChild [::Tloona::Callframe ::#auto \
                -type callframe -name $cfName \
                -length [$cfNode getAttribute length] \
                -offset [$cfNode getAttribute offset]]]
            $tNode lookupDefinition $Configs($CurrentRun,ProjectFs)
            
            # Local and global variables in the current call frame
            set lvXml [$cfNode selectNodes variable\[@scope='local'\]]
            Tloona::VarInspector::parseFrameVars $VarInspector \
                $lvXml $tNode local
            set gvXml [$cfNode selectNodes variable\[@scope='global'\]]
            Tloona::VarInspector::parseFrameVars $VarInspector \
                $gvXml $tNode global
        }
        
        # insert the variables of first call frame in the varinspector
        set tNode [lindex [$mThread getChildren] 0]
        $StackInspector remove all yes
        $StackInspector add $mThread 1 0
        $StackInspector selection set $tNode
        $VarInspector displayFrameVars $tNode
        displayCallframe $tNode
    }
        
    # @c Clears variable and stack frame inspector
    public method clearInspectors {{delete no}} {
        $VarInspector clear $delete
        $StackInspector remove all $delete
        set CurrentRun -1
    }
        
    
    # @c Displays the command at a given callframe. Opens the file
    # @c for the frame using the openfilecmd and highlights the
    # @c range in the file during dispatching to the [selectRange]
    # @c method of the file (which must be a Tmw::VisualFile)
    public method displayCallframe {cFrame} {
        if {[set fsFile [$cFrame cget -deffile]] == ""} {
            return
        }
        
        set fname [$fsFile cget -name]
        if {[cget -fileisopencmd] == "" || [cget -openfilecmd] == "" ||
                [cget -selectfilecmd] == ""} {
            error "set -fileisopencmd, -openfilecmd and -selectfilecmd "
        }
        if {[set fCls [eval [cget -fileisopencmd] $fname]] == ""} {
            set fCls [eval [cget -openfilecmd] $fname 1]
        }
        eval [cget -selectfilecmd] $fCls
        
        if {[set dnode [$cFrame cget -defnode]] == ""} {
            return
        }
        #puts ---[$dnode cget -name]---[$cFrame cget -offset]---
        #puts "doffs: [$dnode cget -defoffset], [lindex [$dnode cget -byterange] 0]"
        set os [expr {
            [lindex [$dnode cget -byterange] 0] + [$dnode cget -defoffset]
        }]
        incr os [$cFrame cget -offset]
        $fCls displayByteRange $os [$cFrame cget -length] lightblue
    }
    
    # @c restores the configurations
    private method restoreConfigs {{aCfg {}}} {
        global UserOptions
        if {$aCfg == {} && [info exists UserOptions(DebugConfigs)]} {
            set aCfg $UserOptions(DebugConfigs)
        }
        
        $RunMenu delete 0 end
        array unset Configs
        array set Configs {}
        for {set i 0} {$i < [llength $aCfg]} {incr i} {
            set cfg [lindex $aCfg $i]
            set Configs($i,Name) [lindex $cfg 0]
            set Configs($i,Project) [lindex $cfg 1]
            set Configs($i,Script) [lindex $cfg 2]
            set Configs($i,Basedir) [lindex $cfg 3]
            set Configs($i,Args) [lindex $cfg 4]
            set Configs($i,ProjectFs) {}
            
            $RunMenu add command -label $Configs($i,Name) \
                -command [code $this onRun $i]
            
        }
        
        $RunMenu add separator
        $RunMenu add command -label "Manage Configurations ..." \
            -command [code $this onManageConfigs]
    }
        
    # @c Filter for debugging output
    #
    # @a line: the line to filter
    private method filterDebugInfo {line} {
        if {[string match <debuginfo* $line]} {
            set FetchingDbg yes
            append DebugXML $line
            return true
        } elseif {[string match </debuginfo* $line]} {
            set FetchingDbg no
            append DebugXML $line
            parseDebugInfo $DebugXML
            set DebugXML ""
            return true
        } elseif {$FetchingDbg} {
            append DebugXML $line
            return true
        }
        
        return false
    }
    
}


proc ::Tloona::varinspector {path args} {
    uplevel Tloona::VarInspector $path $args
}

proc ::Tloona::stackinspector {path args} {
    uplevel Tloona::StackInspector $path $args
}

proc ::Tloona::debugger {args} {
    uplevel Tloona::Debugger ::#auto $args
}

proc ::Tloona::debugconfigdlg {path args} {
    uplevel Tloona::DebugConfigDlg $path $args
}

