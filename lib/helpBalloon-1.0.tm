#
# From DAS on Tcl Wiki
#
# Daniel Steffen - http://www.maths.mq.edu.au/~steffen/tcltk
# Modified and updated by Clif Flynt http://www.noucorp.com
#   Converted to use namespaces
#   Converted to tcl module.

package provide helpBalloon 1.0

proc balloon {w help} {
    bind $w <Any-Enter> "after 1000 [list balloon::show %W [list $help]]"
    bind $w <Any-Leave> "destroy %W.balloon"
}

namespace eval balloon {
################################################################
#  proc show {w text }--
#    display a help balloon if the cursor is within window w
# Arguments
#  w	The name of the window for the help
#  text	The text to display in the window
# Results
#  Destroys any existing window, and creates a new 
#   toplevel window containing a message widget with
#   the help text

 proc show {w text} {
    
    # Get the name of the window containing the cursor.

    set currentWin [eval winfo containing  [winfo pointerxy .]]
    
    # If the current window is not the one that requested the
    #   help, return.

    if {![string match $currentWin $w]} {
        return
    }

    # The  new toplevel window will be a child of the 
    #  window that requested help.

    set top $w.balloon

    # Destroy any previous help balloon

    catch {destroy $top}
    
    # Create a new toplevel window, and turn off decorations
    toplevel $top -borderwidth 1 
    wm overrideredirect $top 1

    # If Macintosh, do a little magic.

    if {$::tcl_platform(platform) == "macintosh"} {

    # Daniel A. Steffen added an 'unsupported1' command
    # to make this work on macs as well, otherwise
    # raising the balloon window would immediately
    # post a Leave event leading to the destruction
    # of the balloon... The 'unsupported1' command
    # makes the balloon window into a floating
    # window which does not put the underlying
    # window into the background and thus avoids
    # the problem. (For this to work, appearance 
    # manager needs to be present
    # 
    # In Tk 8.4, this command is renamed to:
    #  ::tk::unsupported::MacWindowStyle

     unsupported1 style $top floating sideTitlebar
    }

    # Create and pack the message object with the help text

    pack [message $top.txt -aspect 200 -background lightyellow \
            -font fixed -text $text]

    # Get the location of the window requesting help,
    #  use that to calculate the location for the new window.

    set wmx [winfo rootx $w]
    set wmy [expr [winfo rooty $w]+[winfo height $w]]
    wm geometry $top \
      [winfo reqwidth $top.txt]x[winfo reqheight $top.txt]+$wmx+$wmy
    
    # Raise the window, to be certain it's not hidden below
    #  other windows.
    raise $top
  }
}

if {[info exists argv] && ([string first -testBalloon $argv] >= 0)} {
 # Example:
  button  .b -text Exit -command exit
  balloon .b "Push me if you're done with this"
  pack    .b
}
