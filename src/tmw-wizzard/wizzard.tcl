## wizzard.tcl (created by Tloona here)
package require snit 2.3.2
package require tmw::dialog 2.0.0

namespace eval Tmw {

snit::widgetadaptor wizzard {
    
    ### Options
    option {-okcmd okCmd Command ""}
    option {-prevcmd prevCmd Command ""}
    option {-nextcmd nextCmd Command ""}
    option {-cancelcmd cancelCmd Command ""}
    
    ### Components
    delegate method * to hull
    delegate option * to hull
    
    ### Variables
    
    ## \brief list of the path names of all wizzard pages
    variable WizzPages {}
    ## \brief wizzard page that is actually shown
    variable Page 0
    variable Canceled 0
    
    constructor {args} {
        installhull using Tmw::dialog
        $self addButtons
        $self configurelist $args
    }
    
    ## \brief Add default buttons
    method addButtons {} {
        $self add Cancel -text "Cancel" -command [mymethod onCancel]
        $self add Previous -text "Previous" -state disabled -command [mymethod onPrevious] -nowait
        $self add Next -text "Next" -state normal -nowait -command [mymethod onNext]
        $self add OK -text OK -command [mymethod onOk]
        $self configure -buttonpos e
    }
    
    # @c adds a frame to the childsite and returns its path
    #
    # @r path to a frame to put widgets inside
    method addPage {args} {
        set f [ttk::frame [$self childsite].page[llength $WizzPages] {*}$args]
        lappend WizzPages $f
        return $f
    }
    
    # @c shows the page with pageidx
    method showPage {pageidx} {
        pack [lindex $WizzPages $pageidx] -expand yes -fill both
    }
    
    method page {} {
        return $Page
    }
    
    method canceled {} {
        return $Canceled
    }
    
    # @c hides the page with pageidx
    method hidePage {pageidx} {
        pack forget [lindex $WizzPages $pageidx]
    }
    
    method removePage {pageidx} {
    }
    
    method show {} {
        $self showPage 0
        set Canceled 0
        $hull show
    }
    
    # @c Cancel callback
    method onCancel {} {
        $self hide
        set Canceled 1 
        uplevel #0 $options(-cancelcmd)
    }
    
    # @c Next callback
    method onNext {} {
        if {[llength $WizzPages] <= 1} {
            return
        }
        $self hidePage $Page
        incr Page
        $self showPage $Page
        
        if {$Page == [expr {[llength $WizzPages] - 1}]} {
            # we're on the last page now
            $self buttonconfigure Next -state disabled
            $self buttonconfigure OK -state normal
        }
        
        $self buttonconfigure Previous -state normal
        uplevel #0 $options(-nextcmd)
    }
    
    # @c Ok callback
    method onOk {} {
        $self hide
        uplevel #0 $options(-okcmd)
    }
    
    # @c Previous callback
    method onPrevious {} {
        if {$Page == 0} {
            return
        }
        
        $self hidePage $Page
        incr Page -1
        $self showPage $Page
        
        if {$Page == 0} {
            # we're on the first page
            $self buttonconfigure Previous -state disabled
        }
        
        $self buttonconfigure Next -state normal
        uplevel #0 $options(-prevcmd)
    }
    
}


} ;# namespace Tmw

package provide tmw::wizzard 2.0.0
