## filebrowser.tcl (created by Tloona here)
package require snit 2.3.2
package require tmw::browser 2.0.0
package require tmw::filesystem 1.0

namespace eval Tmw {
    
snit::widgetadaptor filebrowser {
    
    #### Options
    
    ## \brief indicates whether to ignore backup files
    option -ignorebackup 1
    
    #### Components
    
    delegate method * to hull except refresh
    delegate option * to hull
    
    #### Variables
    
    ## \brief filter pattern and widgets
    variable Filter
    array set Filter {}
    
    ## \brief list of all file trees. Used for filtering
    variable FileSystems {}
    
    constructor {args} {
        installhull using Tmw::browser
        
        set Filter(pattern) ""
        set Filter(widgets) {}
        
        $self setNodeIcons [list directory $Tmw::Icons(FileOpen) \
            webscript $Tmw::Icons(WebFile) \
            tclfile $Tmw::Icons(TclFile) \
            starkit $Tmw::Icons(KitFile) \
            image $Tmw::Icons(ImageFile) \
            exefile $Tmw::Icons(ExeFile) \
            file $Tmw::Icons(DocumentFile)]
        
        $self configurelist $args
    }
    
    # @c adds a filesystem to the browser. This involves
    # @c building the file system and - for virtual file
    # @c systems - eventually extracting them.
    method addFileSystem {root {fstype ""}} {
        if {![file exists $root]} {
            error "$root does not exist"
        }
        ::Tmw::Fs::filesystem -name $root -type "filesystem" -expanded 0
    }
        
    # @r returns a list of file systems
    method getFileSystems {} {
        lsort -unique [concat $FileSystems [children {}]]
    }
        
    method getFilesys {namePattern} {
        foreach {fs} [getFileSystems] {
            if {[string match $namePattern [$fs cget -name]]} {
                return $fs
            }
        }
    }
        
    # @c refresh a filesystem in this browser
    method refresh {{fsys ""}} {
        if {$fsys == ""} {
            set fsys [$self selection]
        }
        if {[$fsys getParent] != {}} {
            set fsys [$fsys getTopnode]
        }
        
        set newList {}
        set oldList {}
        Tmw::Fs::rebuild $fsys $options(-ignorebackup) newList oldList
        $self remove $oldList
        $self add $newList 0 0
    }
        
    # @c callback for filtering code items
    method onFilter {method} {
        set FileSystems [lsort -unique [concat $FileSystems [$self children {}]]]
        if {$Filter(pattern) == ""} {
            $self configure -filter ""
        } else {
            $self configure -filter [list $method $Filter(pattern)]
        }
        
        $self remove [$self children {}]
        $self add $FileSystems 1 1
    
    }
    
}

} ;# namespace Tmw

package provide tmw::filebrowser 2.0.0


