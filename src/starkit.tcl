
package require sdx 1.0

package provide tloona::starkit 1.0


namespace eval ::Tloona::Fs {}

## Extracts the application name from ReleaseNotes file, if present.
# Reads the ReleaseNotes.txt file in baseDir and returns the string 
# in ApplicationName : <appname>. This is useful for deployment
proc ::Tloona::Fs::getStarkitApplicationName {baseDir} {
    set appName [file tail [file root $baseDir]]
    set readMe [file join $baseDir README.txt]
    if {![file exist $readMe]} {
        throw README_NOT_EXIST "README.txt does not exist in this project. Please create one first."
    }
    set fh [open [file join $baseDir README.txt] r]
    while {[gets $fh line] >= 0} {
        if {[regexp ^ApplicationName $line] && [llength [split $line]] >= 3} {
            set appName [lindex [split $line] 2]
            break
        }
    }
    close $fh
    return $appName
}

## Read the version from ReleaseNotes file. 
#
# This requires that there is an entry with the most recent 
# version with the form "Release <version>", where <version> is
# extracted and set as the global version. The first of these
# entries is taken, others are ignored, as well as comments 
# starting with a #
proc ::Tloona::Fs::getStarkitVersion {baseDir} {
    set version ""
    set fh [open [file join $baseDir README.txt] r]
    while {[gets $fh line] >= 0} {
        if {[regexp ^Release $line] && [llength [split $line]] >= 2} {
            set version [lindex [split $line] 1]
            break
        }
    }
    close $fh
    return $version
}

## Recursively copy a directory, excluding certain patterns
proc ::Tloona::Fs::copyFiles {src dest exclude} {
    foreach {f} [glob -nocomplain [file join $src *]] {
        if {[apply $exclude [file tail $f]]} {
            continue
        }
        if {[file isdir $f]} {
            set newDest [file join $dest [file tail $f]]
            file mkdir $newDest
            copyFiles $f $newDest $exclude
        } else {
            file copy -force $f $dest
        }
        
    }
}

## Copies a starkit directory, excluding .svn, build/ and the like files
proc ::Tloona::Fs::copyForDeployment {src dest appName ver} {
    set rootDir [expr {
        ( $appName == "" ) ? [file tail [file rootname $src]] : $appName
    }]
    if {$ver != ""} {
        append rootDir - $ver
    }
    append rootDir [file ext $src]
    set baseDir [file join $dest $rootDir]
    file delete -force $baseDir
    file mkdir $baseDir
    
    set exclude {{name} {regexp {^#|~$|^target$|\.bak$} $name}}
    copyFiles $src $baseDir $exclude
    return $baseDir
}

## This class is used to represent starkits. 
# They can be extracted and wrapped. Besides that, configuration 
# of the -name attribute is special. Starkits are file systems and 
# can be displayed in the kit browser.
class ::Tloona::Fs::Starkit {
    inherit ::Tmw::Fs::FileSystem
    
    constructor {args} {
        eval configure $args
    }
    
    public {
        # @v name: overrides name attribute. Checks for extrated
        variable name "" {
            switch -- [file extension $name] {
                .kit {
                    extracted 0
                }
                default {
                    extracted 1
                }
            }
            configure -tail [file tail $name] -dirname [file dirname $name]
        }
        
        variable vfsid ""
        
        ## The subdirectory where deployed kit/pack files should go
        variable deploydir target
        
        ## Extracts a starkit. 
        # If wThread is not "", the extraction is done in this thread
        method extract {tPool varPtr} {
            if {[extracted]} {
                return
            }
            
            upvar $varPtr var
            
            set script "eval sdx::unwrap::unwrap [cget -name] \n"
            #thread::send -async $wThread $script var
            if {$tPool != ""} {
                set job [tpool::post -nowait $tPool $script]
                tpool::wait $tPool $job
            } else {
                eval $script
            }
            configure -name [file rootname [cget -name]].vfs
            
            return ""
        }
        
        ## Wraps a starkit. 
        # If wThread is not "", this is done in this thread
        method wrap {args} {
            global auto_path TloonaRoot UserOptions
            if {![extracted]} {
                return
            }
            
            set nargs {}
            set ktype "kit"
            set tPool ""
            set appName [file tail [file rootname [cget -name]]]
            set version ""
            while {$args != {}} {
                switch -- [lindex $args 0] {
                    -type {
                        set args [lrange $args 1 end]
                        set ktype [lindex $args 0]
                    }
                    -varptr {
                        set args [lrange $args 1 end]
                        upvar [lindex $args 0] var
                    }
                    -tpool {
                        set args [lrange $args 1 end]
                        set tPool [lindex $args 0]
                    }
                    -appname {
                        set args [lrange $args 1 end]
                        set appName [lindex $args 0]
                    }
                    -version {
                        set args [lrange $args 1 end]
                        set version [lindex $args 0]
                    }
                    default {
                        lappend nargs [lindex $args 0]
                    }
                }
                
                set args [lrange $args 1 end]
            }
            
            # copy the kit for deployment. First, determine value of tmp
            set tmpDir /tmp/
            if {$::tcl_platform(platform) == "windows"} {
                set tmpDir $::env(TEMP)
            }
            set tmpDir [file join $tmpDir TloonaDeploy]
            set deployDir [::Tloona::Fs::copyForDeployment [cget -name] $tmpDir $appName $version]
            
            set deployFile [file root $deployDir].[expr {
                ($ktype eq "pack") ? "exe" : "kit"
            }]
            
            # execute SDX wrap
            set curDir [pwd]
            cd $tmpDir 
            sdx::sdx wrap $deployFile {*}$nargs
            cd $curDir
            
            # copy the kit into the target folder
            set targetDir [file join [cget -name] [cget -deploydir]]
            file mkdir $targetDir
            set targetFile [file join $targetDir [file tail $deployFile]]
            file delete -force $targetFile
            file copy -force $deployFile $targetDir
            
            # delete the temporary directory
            file delete -force $tmpDir
            
            return $targetFile
            
        }
        
        ## Returns whether the starkit is extracted
        method extracted {{e -1}} {
            if {$e < 0} {
                return $_Extracted
            }
            
            if {![string is boolean -strict $e]} {
                error "argument e must be boolean"
            }
            set _Extracted $e
        }
        
    }
    
    private {
        variable _Extracted 0
    }
}


proc ::Tloona::Fs::starkit {args} {
    uplevel Tloona::Fs::Starkit ::#auto $args
}
