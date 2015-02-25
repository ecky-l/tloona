## \brief a splash screen

package require Thread 2.6.7
#package require snit 2.3.2

namespace eval Tmw {

namespace eval Splash {
    variable WorkerThread {}
}

}

#snit::widget ::Tmw::Splash::Splash {
#}

## \brief Creates a new splash window
#
# Initializes a background thread and creates a splash window in it.
# The window can then be manipulated by subsequent commands. It is threated
# as a singleton, effectively it should be the only splash window in an
# application
proc ::Tmw::Splash::create {args} {
    variable WorkerThread
    if {$WorkerThread != {}} {
        thread::release $WorkerThread
        thread::join $WorkerThread
    }
    
    set WorkerThread [thread::create -joinable]
    set T $WorkerThread
    thread::send $T [list set ::auto_path $::auto_path]
    thread::send $T [list package require tmw::splashwin]
    thread::send -async $T [list Tmw::SplashWin::Create {*}$args]
}

proc ::Tmw::Splash::destroy {} {
    variable WorkerThread
    if {$WorkerThread != {}} {
        thread::send -async $WorkerThread [list Tmw::SplashWin::Destroy]
        thread::release $WorkerThread
        thread::join $WorkerThread
    }
    
}

proc ::Tmw::Splash::progress {value} {
    variable WorkerThread
    if {$WorkerThread != {}} {
        thread::send -async $WorkerThread [list Tmw::SplashWin::SetProgress $value]
    }
}

proc ::Tmw::Splash::message {value} {
    variable WorkerThread
    if {$WorkerThread != {}} {
        thread::send -async $WorkerThread [list Tmw::SplashWin::SetMessage $value]
    }
}

package provide tmw::splash 1.0

lappend auto_path ../.. ./
Tmw::Splash::create -showprogress 1
