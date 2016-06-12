# tide::ui::WrapWizzard
package require tmw::icons 1.0
package require tmw::wizzard 1.0
package require tloona::starkit 1.0

package provide tloona::wrapwizzard 1.0


catch {
    namespace import ::itcl::*
    namespace import ::itk::*
}

itk::usual TRadiobutton {}
itk::usual TCheckbutton {}

class ::Tloona::WrapWizzard {
    inherit ::Tmw::Wizzard
    
    ## Determines whetherwe want a starkit or starpack
    private variable _KitSel kit
    
    ## The application name as which to deploy
    private variable _AppName ""

    ## The application version. Empty if no version
    private variable _Version ""
        
    private variable _Options
    array set _Options {
        c_interp 0
        v_interp ""
        c_runtime 0
        v_runtime ""
        c_writable 0
        c_nocomp 0
    }
        
    constructor {args} {
        eval itk_initialize $args
        
        _initKitPackSel [addPage]
        _initOptions [addPage]
        
        component OK configure -command [code $this onOk]
        
        buttonconfigure OK -state disabled
        configure -title "Create deployable runtime" \
            -buttonpadx 20 -nextcmd [code $this _updateOptions]
        
        array set _Options {
            c_interp 0
            v_interp ""
            c_runtime 0
            v_runtime ""
            c_writable 0
            c_nocomp 0
        }
    }
    
    ## Set the deployment details. 
    # 
    # Output directory is target/ inside the project. The extension depends
    # on the platform and type (.exe/.bin for starpacks, .kit for starkits)
    public method setDeployDetails {file} {
        set _AppName [::Tloona::Fs::getStarkitApplicationName $file]
        set _Version [::Tloona::Fs::getStarkitVersion $file]
        
        set baseName "<Application Name>"
        append baseName - <version>
        set kitFile $baseName.kit
        set packFile $baseName.exe
        
        component kitsel configure -text "Create Starkit ($kitFile)"
        component packsel configure -text "Create Starpack ($packFile)"
    }

    public method getOptions {} {
        set opts {}
        
        lappend opts -type $_KitSel -version $_Version -appname $_AppName
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
    
    protected method onOk {} {
        if {$_KitSel eq "pack" && $_Options(c_runtime) == ""} {
            set m "Can not create a Starpack without a valid Tclkit runtime\n\n"
            append m "Please specify one"
            tk_messageBox -type ok -icon error -title "Runtime not provided" \
                -parent [namespace tail $this] -message $m
            return
        }
        hide
        eval $itk_option(-okcmd)
    }
    
    ## Create the widgets in this dialog
    private method _initKitPackSel {parent} {
        global Tmw::Icons UserOptions
        
        itk_component add kitsel {
            ttk::radiobutton $parent.kitsel -text "Create Starkit" \
                -variable [scope _KitSel] -value kit
        }
        
        itk_component add packsel {
            ttk::radiobutton $parent.packsel -text "Create Starpack" \
                -variable [scope _KitSel] -value pack
        }
        
        
        # the appname and version
        set f [ttk::frame $parent.fselsdx]
        ttk::label $f.lappname -text "Application Name (required): "
        itk_component add appname {
            ttk::entry $f.appname -width 15 -textvar [scope _AppName]
        }
        
        ttk::label $f.lversion -text "Version (empty for no version): "
        itk_component add version {
            ttk::entry $f.version -width 15 -textvar [scope _Version]
        }
        
        grid $f.lappname [component appname] -padx 5 -pady 5 -sticky we
        grid $f.lversion [component version] -padx 5 -pady 5 -sticky we
        
        pack [component kitsel] [component packsel] $f -side top -expand y \
            -fill both -padx 20 -pady 10
    }
    
    private method _initOptions {parent} {
        # interp option
        itk_component add c_interp {
            ttk::checkbutton $parent.c_interp -text "-interp" \
                -variable [scope _Options(c_interp)] -command \
                [code $this _switchState c_interp l_interp b_interp]
        }
        itk_component add l_interp {
            ttk::entry $parent.l_interp -textvariable [scope _Options(v_interp)] \
                -state disabled
        }
        itk_component add b_interp {
            ttk::button $parent.b_interp -style Toolbutton -state disabled \
                -command [code $this _openFile interp] -image $Tmw::Icons(FileOpen)
        }
        
        grid [component c_interp] -row 0 -column 0 -sticky w -padx 10 -pady 2
        grid [component l_interp] -row 0 -column 1 -sticky we -padx 10 -pady 2
        grid [component b_interp] -row 0 -column 2 -sticky e -padx 10 -pady 2
        
        # runtime options
        itk_component add c_runtime {
            ttk::checkbutton $parent.c_runtime -text "-runtime" \
                -variable [scope _Options(c_runtime)] -command \
                [code $this _switchState c_runtime l_runtime b_runtime]
        }
        itk_component add l_runtime {
            ttk::entry $parent.l_runtime -textvariable [scope _Options(v_runtime)] \
                -state disabled
        }
        itk_component add b_runtime {
            ttk::button $parent.b_runtime -style Toolbutton -state disabled \
                -command [code $this _openFile runtime] \
                -image $Tmw::Icons(FileOpen)
        }
        
        grid [component c_runtime] -row 1 -column 0 -sticky w -padx 10 -pady 2
        grid [component l_runtime] -row 1 -column 1 -sticky we -padx 10 -pady 2
        grid [component b_runtime] -row 1 -column 2 -sticky e -padx 10 -pady 2
        
        itk_component add c_writable {
            ttk::checkbutton $parent.c_writable -text "-writable" \
                -variable [scope _Options(c_writable)]
        }
        
        itk_component add c_nocomp {
            ttk::checkbutton $parent.c_nocomp -text "-nocompress" \
                -variable [scope _Options(c_nocomp)]
        }
        
        grid [component c_writable] -row 2 -column 0 -sticky w -padx 10 -pady 2
        grid [component c_nocomp] -row 2 -column 1 -sticky w -padx 10 -pady 2
    }
    
    private method _switchState {bState args} {
        set state [expr {$_Options($bState) ? "normal" : "disabled"}]
        foreach {w} $args {
            component $w configure -state $state
        }
    }
    
    private method _openFile {forWhat} {
        global tcl_platform
        set eFt {}
        switch -- $forWhat {
            "interp" {
                set _Options(v_interp) [tk_getOpenFile -filetypes $eFt]
            }
            "runtime" {
                set _Options(v_runtime) [tk_getOpenFile -filetypes $eFt]
            }
        }
    }
    
    private method _updateOptions {} {
        if {[page] == 1} {
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
                    component c_runtime configure -state disabled
                    component l_runtime configure -state disabled
                    component b_runtime configure -state disabled
                    component c_interp configure -state normal
                }
                "pack" {
                    component c_runtime invoke
                    component c_runtime configure -state disabled
                    component l_runtime configure -state normal
                    component b_runtime configure -state normal
                    component c_interp configure -state disabled
                }
            }
        }
    }
    
    private method _finalCheck {} {
        if {$_KitSel == "pack" && ![file exists $_Options(v_runtime)]} {
            return 1
        }
        
        return 0
    }
    
}


proc ::Tloona::wrapwizzard {path args} {
    uplevel 0 WrapWizzard $path $args
}
