## toolbarframe.tcl (created by Tloona here)
package require snit 2.3.2
package require Tclx 8.4

namespace eval ::Tmw {

::snit::widgetadaptor toolbarframe2 {
    
    ### Options
    option {-tbrelief toolbarRelief ToolbarRelief} \
        -default groove -configuremethod ConfigTbRelief
    option {-tbborderwidth toolbarBorderwidth ToolbarBorderWidth} \
        -default 2 -configuremethod ConfigTbBorderwidth
    
    ## \brief The mainwindow where the browser lives.
    option -mainwindow ""
    
    ### components
    
    component topregion
    component bottomregion
    component leftregion
    component rightregion
    
    component childsite
    delegate option -relief to childsite
    delegate option -borderwidth to childsite
    delegate option -width to childsite
    delegate option -height to childsite
    
    ### variables
    
    ## \brief category separators for several toolbars.
    variable Separators
    array set Separators {}
    
    ## \brief the compound for several toolbars.
    variable Compounds
    array set Compounds {}
    
    ## \brief positions for several toolbars.
    variable Positions
    array set Positions {}
    
    ## \brief toolbutton widgets in several toolbars. Needed for reconfiguration
    variable Buttons
    array set Buttons {}
    
    ## \brief dropframes per toolbar
    variable Dropframes
    array set Dropframes {}
        
    
    constructor {args} {
        installhull using ttk::frame
        install topregion using ttk::frame $self.topregion
        install bottomregion using ttk::frame $self.bottomregion
        install leftregion using ttk::frame $self.leftregion
        install rightregion using ttk::frame $self.rightregion
        
        #showToolbarRegions
        pack $topregion -side top -expand n -fill x
        pack $bottomregion -side bottom -expand n -fill x
        pack $leftregion -side left -expand n -fill y
        pack $rightregion -side right -expand n -fill y
        
        install childsite using ttk::frame $self.childsite
        pack $childsite -expand yes -fill both
        
        $self configure -tbrelief groove -tbborderwidth 2
        $self configurelist $args
    }
    
    ## \brief Constructs a toolbar with a given tag (name). 
    #
    # If the toolbar exists already, it is configured. The args specify how the 
    # toolbar is generated or configured.
    #
    # \param name
    #    the tag for the toolbar. Needed later to refer to it
    # \param args
    #    -pos determines the position (n w e or s)
    #    -compound determines which compound the toolbar should have
    #    They are the same as the compounds for menus, default is none
    #
    # \return the path of the toolbar frame
    method toolbar {name args} {
        array set aargs $args
        
        set T ""
        if {![winfo exist $win.$name]} {
            ttk::frame $win.$name
            set Buttons($name) {}
        }
        
        set T $win.$name
        
        if {[info exists aargs(-pos)]} {
            if {[lsearch [pack slaves $win] $T] >= 0} {
                pack forget $T
            }
            
            set M $childsite
            switch -- $aargs(-pos) {
            n {
                pack $T -in $topregion -side top -fill x
            }
            s {
                pack $T -in $bottomregion -side bottom -fill x
            }
            w {
                pack $T -in $leftregion -side left -fill y
            }
            e {
                pack $T -in $rightregion -side right -fill y
            }
            }
            
            # reconfigure widgets
            switch -- $aargs(-pos) {
            n - s {
                foreach {ltype lpath stickto} $Buttons($name) {
                    if {[string match $stickto front]} {
                        set side left
                    } else {
                        set side right
                    }
                    switch -- $ltype {
                        separator {
                            $lpath configure -orient vertical
                            pack configure $lpath -side $side -fill y
                        }
                        innersep {
                            $lpath configure -orient vertical
                            pack configure $lpath -side $side -fill none
                        }
                        default {
                            pack configure $lpath -side $side
                        }
                    }
                    
                }
            }
            
            w - e {
                foreach {ltype lpath stickto} $Buttons($name) {
                    if {[string match $stickto front]} {
                        set side top
                    } else {
                        set side bottom
                    }
                    switch -- $ltype {
                        separator {
                            $lpath configure -orient horizontal
                            pack configure $lpath -side $side -fill x
                        }
                        innersep {
                            $lpath configure -orient horizontal
                            pack configure $lpath -side $side -fill none
                        }
                        default {
                            pack configure $lpath -side $side
                        }
                    }
                    
                }
            }
            }
            
            $self ShowRegions
            
            set Positions($name) $aargs(-pos)
        }
        
        if {[info exists aargs(-compound)]} {
            set Compounds($name) $aargs(-compound)
        } elseif {![info exists Compounds($name)]} {
            # the default compound
            set Compounds($name) none
        }
        
        return $T
    }
    
    ## \brief Hides a named toolbar, without deleting it.
    method tbhide {name} {
        pack forget $win.$name
        $self ShowRegions
    }
    
    ## \brief Shows a named toolbar
    method tbshow {name} {
        switch -- $Positions($name) {
        n {
            pack $win.$name -in $topregion -side top -fill x
        }
        s {
            pack $win.$name -in $bottomregion -side bottom -fill x
        }
        w {
            pack $win.$name -in $leftregion -side left -fill y
        }
        e {
            pack $win.$name -in $rightregion -side right -fill y
        }
        }
        
        $self ShowRegions
    }
    
    ## \brief Checks whether a toolbar or toolbuttons in it exist.
    #
    # With one argument the existence of the toolbar name is checked,
    # with two arguments the existence of the toolbutton or dropwidget
    # button is evaluated as well
    method tbexists {toolbar {toolbutton ""}} {
        if {![winfo exists $self.$toolbar]} {
            return 0
        }
        if {$toolbutton == ""} {
            return 1
        }
        
        foreach {ltype lpath stickto} $Buttons($toolbar) {
            if {[string match $lpath $toolbutton]} {
                return 1
            }
        }
        return 0
    }
    
    ## \brief Creates a toolbutton in a particular toolbar.
    #
    # The toolbar is given by the -toolbar option). If the name tag already exists 
    # and is associated with a toolbutton, this is configured. The args specify 
    # options for the toolbutton. It is possible to create all kinds of buttons 
    # for toolbars, e.g. checkbuttons, radiobuttons, normal buttons. The buttons 
    # are styled as appropriate for toolbars (@see toolbutton.tcl). Most arguments
    # apply to button configuration, some special ones apply to the configuration 
    # of the button within it's toolbar. The -compound argument for a toolbar 
    # determines how text and images are displayed. By default, only either images 
    # or text is displayed
    #
    # \param name
    #    name tag for the toolbutton
    # \param args
    #    configuration arguments
    #    -toolbar specifies the toolbar where to create the button
    #    -type specifies the button type (checkbutton, radiobutton, command = normal 
    #    button)
    #    -stickto specifies where to stick the button. May be either front ot back. 
    #    Front means left if the toolbar pos is n or s and top if the toolbar pos is 
    #    w or e. Back means the opposite all other arguments are equal to the button 
    #    args according to -type.
    #
    # \return path of the created button
    method toolbutton {name args} {
        set toolbar ""
        set type ""
        set stickto "front"
        set separate 1
        
        # check for special arguments
        if {[set i [lsearch $args -type]] >= 0} {
            lvarpop args $i
            set type [lvarpop args $i]
        }
        if {[set i [lsearch $args -toolbar]] >= 0} {
            lvarpop args $i
            set toolbar [lvarpop args $i]
        }
        if {[set i [lsearch $args -stickto]] >= 0} {
            lvarpop args $i
            set stickto [lvarpop args $i]
            switch -- $stickto {
                front - back {
                }
                default {
                    error "-stickto must be \"front\" or \"back\""
                }
            }
        }
        if {[set i [lsearch $args -separate]] >= 0} {
            lvarpop args $i
            set separate [lvarpop args $i]
        }
        
        # toolbar component name must be provided
        set path [regsub -all {\.} [string tolower $name] {_}]
        
        if {$toolbar == "" || ![winfo exists $win.$toolbar]} {
            error "-toolbar must be provided and valid! ($T)"
        }
        
        set T $win.$toolbar
        # if the widget path exists, configure or delete it
        if {[winfo exists $T.$path]} {
            if {[llength $args] == 1} {
                if {$args == "delete"} {
                    destroy $T.$path
                    set newl {}
                    foreach {ltype lpath} $Buttons($toolbar) {
                        if {[string match $lpath $T.$path]} {
                            continue
                        }
                        lappend newl $ltype $lpath
                    }
                    
                    set Buttons($toolbar) $newl
                    return
                }
                
                return [$T.$path cget $args]
            }
            
            eval $T.$path configure $args
            return
        }
        
        # At this stage, create the toolbutton. The first dot component
        # determines a category. Each category is separated by a 
        # ttk::separator - if the category (and hence the separator)
        # does not exist yet, create it
        set rName [string tolower [lindex [split $name .] 0]]
        set tbm $T.$rName
        
        switch -- $Positions($toolbar) {
            n - s {
                if {[string match $stickto front]} {
                    set side left
                } else {
                    set side right
                }
                set orient vertical
                set tsfill y
            }
            w - e {
                if {[string match $stickto front]} {
                    set side top
                } else {
                    set side bottom
                }
                set orient horizontal
                set tsfill x
            }
        }
                
        if {$separate && ![info exists Separators($tbm)]} {
            set sep [set rName]sep
            set Separators($tbm) [ttk::separator $T.$sep -orient $orient]
            pack $Separators($tbm) -expand n -fill $tsfill -side $side \
                -padx 2 -pady 2
            lappend Buttons($toolbar) separator $Separators($tbm) $stickto
        }
        
        # compound configuration
        if {[set i [lsearch $args -compound]] >= 0} {
            lset args [incr i] $Compounds($toolbar)
        } else {
            lappend args -compound $Compounds($toolbar)
        }
        
        # define widget and pack/widget arguments, depending on which 
        # type of toolbutton is to create
        set cmd ttk::button
        set packArgs [list -side $side -expand n -fill both]
        switch -- $type {
            command {
                set cmd ttk::button
                lappend args -style Toolbutton
            }
            checkbutton {
                set cmd ttk::checkbutton
                lappend args -style Toolbutton
            }
            radiobutton {
                set cmd ttk::radiobutton
                lappend args -style Toolbutton
            }
            menubutton -
            cascade {
                set cmd ttk::menubutton
                #lappend args -style Toolbutton
            }
            separator {
                set cmd ttk::separator
                set args [list -orient $orient]
                set packArgs [list -expand n -side $side -fill none -padx 1]
                set type innersep
            }
            default {
                error "type $type cannot be handeled"
            }
        }
        
        # create the widget
        set b [eval $cmd $T.$path $args]
        if {$separate} {
            eval pack $b -before $Separators($tbm) $packArgs
        } else {
            eval pack $b $packArgs
        }
        
        lappend Buttons($toolbar) $type $T.$path $stickto
        return $T.$path
    }
    
    ## \brief Creates a drop widget in the given toolbar.
    #
    # A drop widget is a toplevel frame that can contain arbitrary widgets. It is 
    # connected to a checkbutton style toolbutton. When toolbutton is checked, the 
    # widget is made visible and vice versa. The position of the dropframe depends 
    # on the position of the toolbar where the checkbutton is created. The frame is 
    # displayed next below the checkbutton if the toolbar position is n, next above 
    # the checkbutton if the toolbar pos is s, right next to the checkbutton if the 
    # toolbar pos is w and left next to the checkbutton if the tolbar pos is e.
    # Arguments are for the connected toolbutton and for the frame.
    #
    # \param name
    #    tag for the created toolbutton and drop frame
    # \param args
    #    all arguments as for [toolbutton] are accepted. In addition
    #    -anchor specifies the anchor for placing the frame. See the anchor option 
    #            to [place] how it works
    #    -relpos specifies the position of the dropframe relative to the free edge 
    #            of the toolbutton that triggers display (See above for dropframe display)
    #    -showcmd command is evaluated when the frame is displayed
    #    -hidecmd command is evaluated when the frame is hidden
    #
    # \return the frame where to place widgets
    method dropframe {name args} {
        if {[set idx [lsearch $args -toolbar]] < 0} {
            error "-toolbar must be provided"
        }
        set toolbar [lindex $args [incr idx]]
        
        set anchor nw
        if {[set idx [lsearch $args -anchor]] >= 0} {
            set args [lreplace $args $idx $idx]
            set anchor [lindex $args $idx]
            set args [lreplace $args $idx $idx]
        }
        
        set relpos .5
        if {[set idx [lsearch $args -relpos]] >= 0} {
            set args [lreplace $args $idx $idx]
            set relpos [lindex $args $idx]
            set args [lreplace $args $idx $idx]
        }
        
        set showcmd ""
        if {[set idx [lsearch $args -showcmd]] >= 0} {
            set args [lreplace $args $idx $idx]
            set showcmd [lindex $args $idx]
            set args [lreplace $args $idx $idx]
        }
        set hidecmd ""
        if {[set idx [lsearch $args -hidecmd]] >= 0} {
            set args [lreplace $args $idx $idx]
            set hidecmd [lindex $args $idx]
            set args [lreplace $args $idx $idx]
        }
        
        
        if {[info exists Dropframes($toolbar,$name)]} {
            # configure it
            return
        }
        
        if {[set idx [lsearch $args -type]] >= 0} {
            lset args [incr idx] checkbutton
        } else {
            lappend args -type checkbutton
        }
        
        # append command to show the frame to args
        set cmd [mymethod ShowDropframe $toolbar $name]
        if {[set idx [lsearch $args -command]] >= 0} {
            lset args [incr idx] $cmd
        } else {
            lappend args -command $cmd
        }
        
        set Dropframes($toolbar,$name,show) 0
        if {[set idx [lsearch $args -variable]] >= 0} {
            lset args [incr idx] [myvar Dropframes($toolbar,$name,show)]
        } else {
            lappend args -variable [myvar Dropframes($toolbar,$name,show)]
        }
        
        set Dropframes($toolbar,$name) \
            [list [ttk::frame $self.$toolbar,$name] \
                [$self toolbutton $name {*}$args] $anchor $relpos $showcmd $hidecmd]
        
        lindex $Dropframes($toolbar,$name) 0
    }
    
    # @r the childsite of the window
    method childsite {args} {
        if {$args == {}} {
            return $childsite
        }
        $childsite {*}$args
    }
    
    
    ### Private
    
    method ShowDropFrame {toolbar name} {
        set relx 0
        set rely 0
        switch -- $Positions($toolbar) {
        n {
            set relx [lindex $Dropframes($toolbar,$name) 3]
            set rely 1
        }
        w {
            set relx 1
            set rely [lindex $Dropframes($toolbar,$name) 3]
        }
        s {
            set relx [lindex $Dropframes($toolbar,$name) 3]
            set rely 0
        }
        e {
            set relx 0
            set rely [lindex $Dropframes($toolbar,$name) 3]
        }
        }
        
        set frm [lindex $Dropframes($toolbar,$name) 0]
        set cmd ""
        if {$Dropframes($toolbar,$name,show)} {
            set btn [lindex $Dropframes($toolbar,$name) 1]
            set cmd [lindex $Dropframes($toolbar,$name) 4]
            place $frm -in $btn -relx $relx -rely $rely -anchor \
                [lindex $Dropframes($toolbar,$name) 2]
        } else {
            set cmd [lindex $Dropframes($toolbar,$name) 5]
            place forget $frm
        }
        
        eval $cmd
    }
    
    method ShowRegions {} {
        set is [pack slaves $win]
        foreach {w} {topregion bottomregion leftregion rightregion childsite} {
            if {[lsearch $is [set $w]] >= 0} {
                pack forget [set $w]
            }
        }
        
        foreach {side fill} {top x bottom x left y right y} {
            set w [set [set side]region]
            set s [pack slaves $w]
            if {[pack slaves $w] != {}} {
                pack $w -side $side -expand n -fill $fill
            }
        }
        
        pack $childsite -expand yes -fill both
    }
    
    ## \brief configmethod for -tbrelief
    method ConfigTbRelief {option value} {
        set options($option) $value
        $topregion configure -relief $value
        $bottomregion configure -relief $value
        $leftregion configure -relief $value
        $rightregion configure -relief $value
    }
    
    ## \brief configmethod for -tbrelief
    method ConfigTbBorderwidth {option value} {
        set options($option) $value
        $topregion configure -borderwidth $value
        $bottomregion configure -borderwidth $value
        $leftregion configure -borderwidth $value
        $rightregion configure -borderwidth $value
    }
    
} ;# toolbarframe

} ;# namespace Tmw

package provide tmw::toolbarframe2 2.0.0

