## browsablefile.tcl (created by Tloona here)

#lappend auto_path [pwd]/src [pwd]/lib

package require snit 2.3.2
package require tmw::visualfile 2.0.0
package require parser::script 1.0

namespace eval Tmw {

# @c This class implements a visual file which can be
# @c displayed and used in a browser
snit::widgetadaptor browsablefile {
    
    delegate method * to hull except openFile
    delegate option * to hull
    
    #### Variables
    
    ## \brief a tree to display in the browser
    variable BrowserTree ""
    
    ## \brief a list of displays, where the file content is displayed
    variable BrowserDisplays {}
    
    ## \brief The node we are currently in. Updated when the cursor 
    # position changes in the file
    variable CurrentNode ""
        
    constructor {args} {
        installhull using Tmw::visualfile
        $self configure -button1cmd [mymethod updateCurrentNode %x %y]
        
        #bind [component textwin] <Button-1> \
        #    [code $this updateCurrentNode %x %y]
        
        $self configurelist $args
    }
    
    # @c adds the file to the given code browser
    method addToBrowser {browser} {
        if {![$browser exists $BrowserTree]} {
            $browser add $BrowserTree 1 0
        }
        
        if {[lsearch $BrowserDisplays $browser] < 0} {
            lappend BrowserDisplays $browser
        }
    }
    
    # @c removes this file from the given file browser
    method removeFromBrowser {browser} {
        $browser remove $BrowserTree
        set idx [lsearch $BrowserDisplays $browser]
        set BrowserDisplays [lreplace $BrowserDisplays $idx $idx]
        #lvarpop BrowserDisplays $idx
    }
    
    # @c Creates a code tree that represents this file.
    method createTree {} {
        if {$BrowserTree != ""} {
            return
        }
        $self setTree [::Parser::StructuredFile ::#auto -type "file"]
    }
    
    # @c set the browsable tree
    method setTree {tree} {
        set BrowserTree $tree
    }
    
    # @r the browsable tree
    method getTree {} {
        return $BrowserTree
    }
    
    # @c Reparse the tree. This is meant to be overwritten by
    # @c deriving classes
    method reparseTree {} {
    }
    
    # @r the browsers where the file is visible
    method getBrowsers {} {
        return $BrowserDisplays
    }
    
    # @c overrides [openFile] in VisualFile. The default
    # @c implementation here configures the file name
    # @c for the BrowserTree
    method openFile {{file ""}} {
        $hull openFile $file
        $BrowserTree configure -file [$self cget -filename] \
            -displayformat {"%s (%s)" -name -dirname}
    }
    
    # @c update the highlighting. By default, does nothing.
    # @c Subclasses may override
    method updateKwHighlight {keyWords} {
    }
    
    # @c selects the code fragment at mouse position x, y or the 
    # @c insert cursor.
    method selectTreeDisplay {} {
        if {$BrowserTree == ""} {
            return
        }
        
        foreach browser [$self getBrowsers] {
            set bwin [$browser treeview]
            if {!([$browser exists $CurrentNode] && [winfo ismapped $bwin]
                    && [$browser cget -syncronize])} {
                continue
            }
            
            $browser selection set $CurrentNode
            $browser see $CurrentNode
        }
    }
    
    #
    # @a x: the x position of mouse cursor
    # @a y: the y position of mouse cursor
    method updateCurrentNode {{x -1} {y -1}} {
        event generate $win <<TextPositionChanged>>
        if {$BrowserTree == {}} {
            return
        }
        set tmp $CurrentNode
        set CurrentNode [$BrowserTree lookupRange [$self getTextPos $x $y]]
        if {$CurrentNode != "" && ![string equal $tmp $CurrentNode]} {
            $self selectTreeDisplay
        }
    }
    
} ;# browsablefile

} ;# namespace Tmw

package provide tmw::browsablefile 2.0.0

#package re Tk
#Tmw::browsablefile .v -vimode true
#pack .v

