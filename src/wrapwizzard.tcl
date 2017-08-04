## wrapwizzard.tcl (created by Tloona here)
package require snit 2.3.2
package require tmw::wizzard 2.0.0
package require tloona::starkit 1.0

namespace eval Tloona {

snit::widgetadaptor wrapwizzard {
    
    ### Options
    
    ### Components
    component appname
    component b_interp
    component b_runtime
    component c_interp
    component c_nocomp
    component c_runtime
    component c_writable
    component kitsel
    component l_interp
    component l_runtime
    component packsel
    component version
    component e_outputdir
    component l_sdx
    component t_sdx
    component b_sdx
    
    delegate method * to hull
    delegate option * to hull
    
    ### Variables
    
    ## \brief Determines whetherwe want a starkit or starpack
    variable _KitSel kit
    
    ## \brief The application name as which to deploy
    variable _AppName ""

    ## \brief The application version. Empty if no version
    variable _Version ""
    
    ## \brief The output directory underneath project dir
    variable _DeployDir target
    
    variable _Options
    array set _Options {
        c_interp 0
        v_interp ""
        c_runtime 0
        v_runtime ""
        c_writable 0
        c_nocomp 0
        v_sdx ""
    }
        
    constructor {args} {
        installhull using Tmw::wizzard
        
        array set _Options {
            c_interp 0
            v_interp ""
            c_runtime 0
            v_runtime ""
            c_writable 0
            c_nocomp 0
            v_sdx $::UserOptions(PathToSDX)
        }
        
        $self InitKitPackSel [$self addPage]
        $self InitOptions [$self addPage]
        
        $self configure -title "Create deployable runtime" -buttonpadx 20 \
            -nextcmd [mymethod _updateOptions]
        
        $self configurelist $args
        $self buttonconfigure OK -command [mymethod onOk] -state disabled
    }
    
    ## \brief Set the deployment details. 
    # 
    # Output directory is target/ inside the project. The extension depends
    # on the platform and type (.exe/.bin for starpacks, .kit for starkits)
    method setDeployDetails {file deployDir} {
        set _AppName [::Tloona::Fs::getStarkitApplicationName $file]
        set _Version [::Tloona::Fs::getStarkitVersion $file]
        set _DeployDir $deployDir
        
        set baseName "<Application Name>"
        append baseName - <version>
        set kitFile $baseName.kit
        set packFile $baseName.exe
        
        $kitsel configure -text "Create Starkit ($kitFile)"
        $packsel configure -text "Create Starpack ($packFile)"
    }

    method getOptions {} {
        set opts {}
        
        lappend opts -type $_KitSel -version $_Version -appname $_AppName \
            -deploydir $_DeployDir
        if {$_Options(c_interp)} {
            lappend opts -interp $_Options(v_interp)
        }
        if {$_Options(c_runtime)} {
            lappend opts -runtime $_Options(v_runtime)
        }
        if {$_Options(c_writable)} {
            lappend opts -writable
        }
        if {$_Options(c_nocomp)} {
            lappend opts -nocompress
        }
        
        return $opts
    }
    
    method onOk {} {
        if {$_KitSel eq "pack" && $_Options(c_runtime) == ""} {
            set m "Can not create a Starpack without a valid Tclkit runtime\n\n"
            append m "Please specify one"
            tk_messageBox -type ok -icon error -title "Runtime not provided" \
                -parent $win -message $m
            return
        }
        if {$::UserOptions(PathToSDX) == {} || ![file exists $::UserOptions(PathToSDX)]} {
            set m "Path to SDX is not valid. It must point to an executable sdx\n\n"
            append m "Please specify one"
            tk_messageBox -type ok -icon error -title "Path to SDX not valid" \
                -parent $win -message $m
            return
        }
        $self hide
        uplevel #0 [$self cget -okcmd]
    }
    
    ## Create the widgets in this dialog
    method InitKitPackSel {parent} {
        global Tmw::Icons UserOptions
        install kitsel using ttk::radiobutton $parent.kitsel -text "Create Starkit" \
            -variable [myvar _KitSel] -value kit
        install packsel using ttk::radiobutton $parent.packsel -text "Create Starpack" \
            -variable [myvar _KitSel] -value pack
        
        # the output directory
        set ff [ttk::frame $parent.foutput]
        ttk::label $ff.loutput -text "Output directory"
        install e_outputdir using ttk::entry $ff.e_outputdir \
            -textvariable [myvar _DeployDir] -text $_DeployDir 
        grid $ff.loutput -row 3 -column 0 -sticky w -padx 5 -pady 2
        grid $e_outputdir -row 3 -column 1 -sticky we -padx 5 -pady 2
        grid columnconfig $ff 1 -weight 1
        
        $e_outputdir configure -textvar [myvar _DeployDir]
        
        # the appname and version
        set f [ttk::frame $parent.fselsdx]
        ttk::label $f.lappname -text "Application Name (required): "
        install appname using ttk::entry $f.appname -width 15 -textvar [myvar _AppName]
        
        ttk::label $f.lversion -text "Version (empty for no version): "
        install version using ttk::entry $f.version -width 15 -textvar [myvar _Version]
        
        grid $f.lappname $appname -padx 5 -pady 2 -sticky we
        grid $f.lversion $version -padx 5 -pady 2 -sticky we
        
        pack $kitsel $packsel $ff $f -side top -expand y -fill both -padx 20 -pady 5
    }
    
    method InitOptions {parent} {
        global UserOptions
        # interp option
        install c_interp using ttk::checkbutton $parent.c_interp -text "-interp" \
            -variable [myvar _Options(c_interp)] \
                -command [mymethod _switchState c_interp l_interp b_interp]
        install l_interp using ttk::entry $parent.l_interp \
            -textvariable [myvar _Options(v_interp)] -state disabled
        install b_interp using ttk::button $parent.b_interp -style Toolbutton \
            -state disabled -command [mymethod _openFile interp] -image $Tmw::Icons(FileOpen)
        
        grid $c_interp -row 0 -column 0 -sticky w -padx 10 -pady 2
        grid $l_interp -row 0 -column 1 -sticky we -padx 10 -pady 2
        grid $b_interp -row 0 -column 2 -sticky e -padx 10 -pady 2
        
        # runtime options
        install c_runtime using ttk::checkbutton $parent.c_runtime -text "-runtime" \
            -variable [myvar _Options(c_runtime)] \
                -command [mymethod _switchState c_runtime l_runtime b_runtime]
        install l_runtime using ttk::entry $parent.l_runtime \
            -textvariable [myvar _Options(v_runtime)] -state disabled
        install b_runtime using ttk::button $parent.b_runtime -style Toolbutton \
            -state disabled -command [mymethod _openFile runtime] -image $Tmw::Icons(FileOpen)
        
        grid $c_runtime -row 1 -column 0 -sticky w -padx 10 -pady 2
        grid $l_runtime -row 1 -column 1 -sticky we -padx 10 -pady 2
        grid $b_runtime -row 1 -column 2 -sticky e -padx 10 -pady 2
        
        install c_writable using ttk::checkbutton $parent.c_writable -text "-writable" \
                -variable [myvar _Options(c_writable)]
        
        install c_nocomp using ttk::checkbutton $parent.c_nocomp -text "-nocompress" \
                -variable [myvar _Options(c_nocomp)]
        
        grid $c_writable -row 2 -column 0 -sticky w -padx 10 -pady 2
        grid $c_nocomp -row 2 -column 1 -sticky w -padx 10 -pady 2
        
        frame $parent.sdx_spacer -height 2
        grid $parent.sdx_spacer -row 3 -column 0 -columnspan 3 -sticky we -pady 4
        
        install l_sdx using ttk::label $parent.l_sdx -text "SDX executable"
        install t_sdx using ttk::entry $parent.t_sdx -textvar ::UserOptions(PathToSDX)
        install b_sdx using ttk::button $parent.b_sdx -style Toolbutton \
            -command [mymethod _openFile sdx] -image $Tmw::Icons(FileOpen)
        grid $l_sdx -row 4 -column 0 -sticky w -padx 10 -pady 2
        grid $t_sdx -row 4 -column 1 -sticky we -padx 10 -pady 2
        grid $b_sdx -row 4 -column 2 -sticky w -padx 10 -pady 2
    }
    
    method _switchState {bState args} {
        set state [expr {$_Options($bState) ? "normal" : "disabled"}]
        foreach {w} $args {
            [set $w] configure -state $state
        }
    }
    
    method _openFile {forWhat} {
        global tcl_platform
        set eFt {}
        switch -- $forWhat {
            "interp" {
                set _Options(v_interp) [tk_getOpenFile -filetypes $eFt]
            }
            "runtime" {
                set _Options(v_runtime) [tk_getOpenFile -filetypes $eFt]
            }
            sdx {
                set p [tk_getOpenFile]
                if {$p != {}} {
                    set ::UserOptions(PathToSDX) $p
                }
            }
        }
    }
    
    method _updateOptions {} {
        if {[$self page] == 1} {
            array unset _Options
            array set _Options {
                c_interp 0
                v_interp "tclkit"
                c_runtime 0
                v_runtime ""
                c_writable 0
                c_nocomp 0
            }
            
            switch -- $_KitSel {
            "kit" {
                $c_runtime configure -state disabled
                $l_runtime configure -state disabled
                $b_runtime configure -state disabled
                $c_interp configure -state normal
            }
            "pack" {
                $c_runtime invoke
                $c_runtime configure -state disabled
                $l_runtime configure -state normal
                $b_runtime configure -state normal
                $c_interp configure -state disabled
            }
            }
        }
    }
    
    method _finalCheck {} {
        if {$_KitSel == "pack" && ![file exists $_Options(v_runtime)]} {
            return 1
        }
        if {$::UserOptions(PathToSDX) == {} || ![file exists $::UserOptions(PathToSDX)]} {
            return 1
        }
        return 0
    }
    
} ;# wrapwizzard


} ;# namespace Tloona

package provide tloona::wrapwizzard 2.0.0
