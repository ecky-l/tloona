################################################################################
# Tloona
#
# an integrated development environment for Tcl/Tk
################################################################################

set TloonaVersion {}

set ::TloonaRoot [file normalize [file dirname [info script]]]
set ::TloonaApplication .tloona
# adjust auto_path
set env(ITCL_LIBRARY) [file join $::TloonaRoot lib Itcl3.4]
set env(ITK_LIBRARY) [file join $::TloonaRoot lib Itk3.4]

set auto_path [linsert $auto_path 0 [file join $::TloonaRoot src] [file join $::TloonaRoot lib]]

package require tmw::splash 1.0


# create the splash screen
Tmw::Splash::Create -topdir $::TloonaRoot -showprogress 1 -title Tloona
Tmw::Splash::Message "Loading packages"

Tmw::Splash::Message "Loading comm"
Tmw::Splash::Progress 5
package require comm 4.3
Tmw::Splash::Message "Loading img::png"
Tmw::Splash::Progress 7
package require -exact img::png 1.4.2
Tmw::Splash::Message "Loading tmw::dialog"
Tmw::Splash::Progress 8
package require tmw::dialog 1.0
Tmw::Splash::Message "Loading tmw::icons"
Tmw::Splash::Progress 10
package require tmw::icons 1.0
Tmw::Splash::Message "Loading tmw::plugin"
Tmw::Splash::Progress 12
package require tmw::plugin 1.0
Tmw::Splash::Message "Loading log"
Tmw::Splash::Progress 15
package require log 1.2
Tmw::Splash::Message "Loading tloona::mainapp"
Tmw::Splash::Progress 16
package require tloona::mainapp 1.0
Tmw::Splash::Message "Loading tloona::starkit"
Tmw::Splash::Progress 20
package require tloona::starkit 1.0
Tmw::Splash::Message "Loading debug"
Tmw::Splash::Progress 22
package require debug 1.0
Tmw::Splash::Message "Loading starkit"
Tmw::Splash::Progress 25
package require starkit

Tmw::Splash::Message "Generating comm id"
Tmw::Splash::Progress 30

puts "Tloona comm ID: [set ::CommId [::comm::comm self]]"
source [file join $::TloonaRoot src toolbutton.tcl]

# Toolbar options
# See toolbutton.tcl.
option add *Toolbar.relief groove
option add *Toolbar.borderWidth 2
option add *Toolbar.Button.Pad 2
option add *Toolbar.Button.default disabled
option add *Toolbar*takeFocus 0

catch {tk_getOpenFile -with-invalid-argument}
namespace eval ::tk::dialog::file {
    variable showHiddenBtn 1
    variable showHiddenVar 0

}

namespace eval ::Tloona {
    variable RcFile [file join $::env(HOME) .tloonarc]
}


# @c initializes the platform icons
proc ::Tloona::initIcons {} {
    global Icons TloonaRoot
    array set Icons {}
    set IconPath [file join $TloonaRoot icons]
    
    set Icons(TclTestfile) [image create photo -file [file join $IconPath tcltestfile.png]]
    
    set Icons(TclPublic) [image create photo -file [file join $IconPath public_method.png]]
    set Icons(TclProtected) [image create photo -file [file join $IconPath protected_method.png]]
    set Icons(TclPrivate) [image create photo -file [file join $IconPath private_method.png]]

    set Icons(TclNs) [image create photo -file [file join $IconPath namespace.png]]
    set Icons(TclClass) [image create photo -file [file join $IconPath appboxes18.png]]
    set Icons(TclProc) [image create photo -file [file join $IconPath proc.png]]
    set Icons(TclSugarProc) [image create photo -file [file join $IconPath sugar_proc.png]]
    set Icons(TclConstructor) [image create photo -file [file join $IconPath constructor.png]]
    set Icons(TclDestructor) [image create photo -file [file join $IconPath destructor.png]]
    set Icons(TclMethod) [image create photo -file [file join $IconPath method.png]]
    set Icons(TclPublicMethod) [image create photo -file [file join $IconPath public_method.png]]
    set Icons(TclProtectedMethod) [image create photo -file [file join $IconPath protected_method.png]]
    set Icons(TclPrivateMethod) [image create photo -file [file join $IconPath private_method.png]]
    set Icons(TclVar) [image create photo -file [file join $IconPath variable.png]]
    set Icons(TclPublicVar) [image create photo -file [file join $IconPath public_variable.png]]
    set Icons(TclProtectedVar) [image create photo -file [file join $IconPath protected_variable.png]]
    set Icons(TclPrivateVar) [image create photo -file [file join $IconPath private_variable.png]]
    set Icons(TclPublicCommon) [image create photo -file [file join $IconPath public_common.png]]
    set Icons(TclProtectedCommon) [image create photo -file [file join $IconPath protected_common.png]]
    set Icons(TclPrivateCommon) [image create photo -file [file join $IconPath private_common.png]]
    set Icons(TclPkg) [image create photo -file [file join $IconPath package.png]]
    set Icons(TclTest) [image create photo -file [file join $IconPath tcltest.png]]
    set Icons(ItkComponents) [image create photo -file [file join $IconPath itk_components.png]]
    set Icons(PublicComponent) [image create photo -file [file join $IconPath public_component.png]]
    set Icons(PrivateComponent) [image create photo -file [file join $IconPath private_component.png]]
    set Icons(SnitDeletages) [image create photo -file [file join $IconPath delegates.png]]
    set Icons(SnitDeletage) [image create photo -file [file join $IconPath delegate.png]]
    set Icons(SnitDeletageOption) [image create photo -file [file join $IconPath delegate_option.png]]
    set Icons(SnitOptions) [image create photo -file [file join $IconPath options.png]]
    set Icons(SnitOption) [image create photo -file [file join $IconPath option.png]]

    # @v Icons: This is an array which contains the icons that are displayed
    # @v Icons: in the code and project browsers for different types of files
    set Icons(ScriptIcons) [list script $::Tmw::Icons(TclFile) \
                testfile $Icons(TclTestfile) \
                file $::Tmw::Icons(DocumentFile) \
                webscript $::Tmw::Icons(WebFile) \
                webcmd $::Tmw::Icons(WebScript) \
                namespace $Icons(TclNs) \
                class $Icons(TclClass) \
                proc $Icons(TclProc) \
                sugar_proc $Icons(TclSugarProc) \
                method $Icons(TclMethod) \
                public_method $Icons(TclPublicMethod) \
                protected_method $Icons(TclProtectedMethod) \
                private_method $Icons(TclPrivateMethod) \
                xo_proc $Icons(TclProc) \
                xo_instproc $Icons(TclPublicMethod) \
                variable $Icons(TclVar) \
                public_variable $Icons(TclPublicVar) \
                protected_variable $Icons(TclProtectedVar) \
                private_variable $Icons(TclPrivateVar) \
                public_common $Icons(TclPublicCommon) \
                protected_common $Icons(TclProtectedCommon) \
                private_common $Icons(TclPrivateCommon) \
                package $Icons(TclPkg) \
                constructor $Icons(TclConstructor) \
                macro $Icons(TclConstructor) \
                destructor $Icons(TclDestructor) \
                itk_components $Icons(ItkComponents) \
                public_component $Icons(PublicComponent) \
                private_component $Icons(PrivateComponent) \
                tcltest $Icons(TclTest) \
                snit_delegates $Icons(SnitDeletages) \
                snit_delegate $Icons(SnitDeletage) \
                snit_delegate_option $Icons(SnitDeletageOption) \
                snit_options $Icons(SnitOptions) \
                snit_option $Icons(SnitOption)]

    set Icons(TclFileOpen) [image create photo -file [file join $IconPath tclfileopen.png]]
    set Icons(KitFileOpen) [image create photo -file [file join $IconPath kitfileopen.png]]
    set Icons(ViewBrowser) [image create photo -file \
        [file join $IconPath viewtree18.png]]
    set Icons(ViewConsole) [image create photo -file [file join $IconPath viewconsole18.png]]
    set Icons(ViewEditor) [image create photo -file \
        [file join $IconPath vieweditor16.png]]

    set Icons(ToggleCmt) [image create photo -file [file join $IconPath togglecmt.png]]
    set Icons(Indent) [image create photo -file [file join $IconPath indent.png]]
    set Icons(UnIndent) [image create photo -file [file join $IconPath unindent.png]]
    
    
    set Icons(SortSeq) [image create photo -file [file join $IconPath sortseq.png]]
    set Icons(SortSeqCfg) [image create photo -file [file join $IconPath sortcfg.png]]
    set Icons(Collapse) [image create photo -file [file join $IconPath collapse.png]]
    set Icons(Syncronize) [image create photo -file [file join $IconPath syncronize.png]]
    
    set Icons(DbgRunTo) [image create photo -file [file join $IconPath dbgrunto.png]]
    set Icons(DbgStep) [image create photo -file [file join $IconPath dbgstep.png]]
    set Icons(DbgNext) [image create photo -file [file join $IconPath dbgnext.png]]
    set Icons(DbgStepOut) [image create photo -file [file join $IconPath dbgstepout.png]]
    set Icons(DbgStop) [image create photo -file [file join $IconPath dbgstop.png]]
    unset IconPath
}


# @c loads the user options file or initializes default options
proc ::Tloona::loadUserOptions {} {
    global UserOptions TloonaRoot
    variable RcFile
    array set UserOptions {}
    if {![file exists $RcFile]} {
        uplevel 1 source [file join $TloonaRoot useroptions.tcl]
    } else {
        source $RcFile
    }

    #error tttaaaagag
}
    
proc ::Tloona::saveUserOptions {} {
    # @c saves the preferences
    global UserOptions TloonaApplication
    variable RcFile
    
    set UserOptions(MainGeometry) [wm geometry $TloonaApplication]
    set fh [open $RcFile w]
    foreach {k v} [array get UserOptions] {
        set v "\{$v\}"
        puts $fh "set ::UserOptions($k) $v"
    }
    
    close $fh
}
    
proc ::Tloona::openLog {} {
    global AppLogChannel TloonaVersion
    set AppLogChannel [open [file join $::env(HOME) .tloonalog] w]
    puts $AppLogChannel "Tloona Version $TloonaVersion"
    puts $AppLogChannel ""
    flush $AppLogChannel
    log::lvChannelForall $::AppLogChannel
    log::lvSuppress debug 0
    log::lvSuppress error 0
}


proc ::Tloona::closeLog {} {
    global AppLogChannel
    catch {close $AppLogChannel}
}
    
# @c logs a message. In addition to writing to the log channel,
# @c this procedure flushes the channel so that the output is
# @c visible immediately
proc ::Tloona::log {level text} {
    global AppLogChannel
    ::log::log $level $text
    flush $AppLogChannel
}


namespace eval ::Tloona::Ui {
    
    proc inputdlg {master title} {
        set ::vVar ""
        if {![winfo exists .inputdlg]} {
            Tmw::dialog .inputdlg -master $master -title $title
            .inputdlg add Cancel -text "Cancel" -command \
                {.inputdlg hide}
            .inputdlg add Ok -text "OK" -command {.inputdlg hide}
            
            set cs [.inputdlg childsite]
            pack [ttk::entry $cs.e -textvariable ::vVar] -expand y -fill x
        }
        
        .inputdlg show
        
        set tmp $::vVar
        unset ::vVar
        
        return $tmp
    }
    
}


proc ::main {args} {
    # load configuration file
    global UserOptions tcl_platform TloonaRoot TloonaApplication TloonaVersion
    set TloonaVersion [Tloona::Fs::getStarkitVersion $TloonaRoot]
    
    ::Tmw::Splash::Message "Opening Logfile"
    ::Tmw::Splash::Progress 35
    Tloona::openLog
    
    ::Tmw::Splash::Message "Initializing Icons"
    ::Tmw::Splash::Progress 40
    Tloona::initIcons
    
    ::Tmw::Splash::Message "Loading User Options"
    ::Tmw::Splash::Progress 45
    Tloona::loadUserOptions
    catch {ttk::style theme use $UserOptions(Theme)}

    wm withdraw .
    if {$tcl_platform(platform) == "windows"} {
        # set a nice icon
        #catch {console show}
        catch {
            wm iconbitmap . -default [file join $TloonaRoot icons tide.ico]
        }
    }
    
    ::Tmw::Splash::Message "Creating Main Application"
    ::Tmw::Splash::Progress 50
    # create the tooltip and completion box
    ::Tloona::Mainapp $TloonaApplication -filefont $UserOptions(FileFont) \
            -filetabsize $UserOptions(FileNTabs) -progressincr 5 \
            -filetabexpand $UserOptions(FileExpandTabs) -threadpool "" ;#$tPool
    wm geometry $TloonaApplication $UserOptions(MainGeometry)
    update
    
    # restore saved userr options
    
    # sash positions
    if {[set sp $UserOptions(View,browserSash)] > 0} {
        $TloonaApplication component browsepw sashpos 0 $sp
    }
    
    if {[set sp $UserOptions(View,consoleSash)] > 0} {
        $TloonaApplication component txtconpw sashpos 0 $sp
    }
    
    ::Tmw::Splash::Message "Applying Window Settings"
    ::Tmw::Splash::Progress 60
    # window settings
    foreach {thing} {browser console editor} {
        $TloonaApplication onViewWindow $thing $UserOptions(View,$thing)
    }
    

    ::Tmw::Splash::Message "Opening previous session Files"
    ::Tmw::Splash::Progress 70
    # open projects
    foreach {prj} $UserOptions(KitProjects) {
        if {![file exists $prj]} {
            continue
        }
        $TloonaApplication openFile $prj 0
    }
    
    ::Tmw::Splash::Message "Restoring previous Session"
    set nf [llength $UserOptions(LastOpenDocuments)]
    set ic [expr {int(30/$nf)}]
    set pInc 70
    foreach {file} $UserOptions(LastOpenDocuments) {
        if {![file exists $file]} {
            continue
        }
        ::Tmw::Splash::Message "Opening File [file tail $file]"
        ::Tmw::Splash::Progress [incr pInc $ic]
        set fob [$TloonaApplication openFile $file 1]
    }
    
    ::Tmw::Splash::Message "Opening given Files"
    ::Tmw::Splash::Progress 98
    # open droped files from argv
    foreach {file} $args {
	set fob [$TloonaApplication openFile $file 1]
    }
    #update
    
    ::Tmw::Splash::Message "Setting Current File"
    ::Tmw::Splash::Progress 100
    $TloonaApplication onCurrFile
    ::Tmw::Splash::Destroy
}

eval ::main $argv


