
package provide tloona::sdx 1.0

package require starkit 1.3.1

# fix bug in two mk4vfs revs (needed when "mkfile" and "local" differ)
#switch -- [package require starkit] {
#    1.0 - 1.1 {
#        proc vfs::mk4::Mount {mkfile local args} {
#            set db [eval [list ::mk4vfs::_mount $local $mkfile] $args]
#            ::vfs::filesystem mount $local [list ::vfs::mk4::handler $db]
#            ::vfs::RegisterMount $local [list ::vfs::mk4::Unmount $db]
#            return $db
#        }
#        proc mk4vfs::mount {local mkfile args} {
#            uplevel [list ::vfs::mk4::Mount $mkfile $local] $args
#        }
#    }
#}

set ::InitLog 0
proc ::tclLog {msg} {
    if {! $::InitLog} {
        set mode w
        set ::InitLog 1
    } else {
        set mode a
    }
    set LogFile [open [file join $::env(HOME) log.txt] $mode]
    puts $LogFile $msg
    close $LogFile
}


namespace eval ::sdx {}

namespace eval ::sdx::sync {

    #
    # Recursively sync two directory structures
    #
    proc rsync {arr src dest} {
        #tclLog "rsync $src $dest"
        upvar 1 $arr opts
    
        if {$opts(-auto)} {
    	       # Auto-mounter
    	       vfs::auto $src -readonly
    	       vfs::auto $dest
        }
    
        if {![file exists $src]} {
    	       return -code error "source \"$src\" does not exist"
        }
        if {[file isfile $src]} {
    	       #tclLog "copying file $src to $dest"
    	       return [rcopy opts $src $dest]
        }
        if {![file isdirectory $dest]} {
    	       #tclLog "copying non-file $src to $dest"
    	       return [rcopy opts $src $dest]
        }
        set contents {}
        eval lappend contents [glob -nocomplain -dir $src *]
        eval lappend contents [glob -nocomplain -dir $src .*]
    
        set count 0		;# How many changes were needed
        foreach file $contents {
    	       #tclLog "Examining $file"
    	       set tail [file tail $file]
    	       if {$tail == "." || $tail == ".."} {
    	           continue
    	       }
    	       set target [file join $dest $tail]
            
    	       set seen($tail) 1
            
    	       if {[info exists opts(ignore,$file)] || \
    	               [info exists opts(ignore,$tail)]} {
    	           if {$opts(-verbose)} {
    		            tclLog "skipping $file (ignored)"
    	           }
    	           continue
    	       }
    	       if {[file isdirectory $file]} {
    	           incr count [rsync opts $file $target]
    	           continue
    	       }
    	       if {[file exists $target]} {
    	           #tclLog "target $target exists"
    	           # Verify
    	           file stat $file sb
    	           file stat $target nsb
    	           #tclLog "$file size=$sb(size)/$nsb(size), mtime=$sb(mtime)/$nsb(mtime)"
    	           if {$sb(size) == $nsb(size)} {
                    # Copying across filesystems can yield a slight variance
    		            # in mtime's (typ 1 sec)
                    if { ($sb(mtime) - $nsb(mtime)) < $opts(-mtime) } {
                        # Good
                        continue
                    }
    	           }
    	           #tclLog "size=$sb(size)/$nsb(size), mtime=$sb(mtime)/$nsb(mtime)"
    	       }
    	       incr count [rcopy opts $file $target]
        }
        
        #
        # Handle stray files
        #
        if {$opts(-prune) == 0} {
    	       return $count
        }
        
        set contents {}
        eval lappend contents [glob -nocomplain -dir $dest *]
        eval lappend contents [glob -nocomplain -dir $dest .*]
        foreach file $contents {
    	       set tail [file tail $file]
    	       if {$tail == "." || $tail == ".."} {
    	           continue
    	       }
    	       if {[info exists seen($tail)]} {
    	           continue
    	       }
    	       rdelete opts $file
    	       incr count
        }
        
        return $count
    }
    
    proc _rsync {arr args} {
        upvar 1 $arr opts
        #tclLog "_rsync $args ([array get opts])"
        
        if {$opts(-show)} {
            # Just show me, don't do it.
            tclLog $args
    	       return
        }
        
        if {$opts(-verbose)} {
    	       tclLog $args
        }
        
        if {[catch {eval $args} err]} {
    	       if {$opts(-noerror)} {
    	           tclLog "Warning: $err"
    	       } else {
    	           return -code error -errorinfo ${::errorInfo} $err 
    	       }
        }
    }
    
    # This procedure is better than just 'file copy' on Windows,
    # MacOS, where the source files probably have native eol's,
    # but the destination should have Tcl/unix native '\n' eols.
    # We therefore need to handle text vs non-text files differently.
    proc file_copy {src dest {textmode 0}} {
        set mtime [file mtime $src]
        if {!$textmode} {
            catch {file copy -force $src $dest}
        } else {
            switch -- [file extension $src] {
    	           ".tcl" -
    	           ".txt" -
    	           ".msg" -
    	           ".test" -
    	           ".itk" {
    	           }
    	           default {
    	               if {[file tail $src] != "tclIndex"} {
                        # Other files are copied as binary
                        #return [file copy $src $dest]
                        file copy $src $dest
                        file mtime $dest $mtime
                        return
                    }
                }
            }
            # These are all text files; make sure we get
            # the translation right.  Automatic eol 
            # translation should work fine.
            set fin [open $src r]
            set fout [open $dest w]
            fcopy $fin $fout
            close $fin
            close $fout
        }
        
        file mtime $dest $mtime
    }
    
    proc rcopy {arr path dest} {
        #tclLog "rcopy: $arr $path $dest"
        upvar 1 $arr opts
        # Recursive "file copy"
        
        set tail [file tail $dest]
        if {[info exists opts(ignore,$path)] || \
    	           [info exists opts(ignore,$tail)]} {
    	       if {$opts(-verbose)} {
    	           ::tclLog "skipping $path (ignored)"
    	       }
    	       return 0
        }
        if {![file isdirectory $path]} {
    	       if {[file exists $dest]} {
    	           _rsync opts file delete $dest
    	       }
    	       _rsync opts file_copy $path $dest $opts(-text)
    	       return 1
        }
        set count 0
        
        if {![file exists $dest]} {
    	       _rsync opts file mkdir $dest
    	       set count 1
        }
        
        set contents {}
        eval lappend contents [glob -nocomplain -dir $path *]
        eval lappend contents [glob -nocomplain -dir $path .*]
        #tclLog "copying entire directory $path, containing $contents"
        foreach file $contents {
    	       set tail [file tail $file]
    	       if {$tail == "." || $tail == ".."} {
    	           continue
    	       }
    	       set target [file join $dest $tail]
    	       incr count [rcopy opts $file $target]
        }
        
        return $count
    }
    
    proc rdelete {arr path} {
        upvar 1 $arr opts 
        # Recursive "file delete"
        if {![file isdirectory $path]} {
    	_rsync opts file delete $path
    	return
        }
        set contents {}
        eval lappend contents [glob -nocomplain -dir $path *]
        eval lappend contents [glob -nocomplain -dir $path .*]
        foreach file $contents {
    	set tail [file tail $file]
    	if {$tail == "." || $tail == ".."} {
    	    continue
    	}
    	rdelete opts $file
        }
        _rsync opts file delete $path
    }
    proc rignore {arr args} {
        upvar 1 $arr opts 
    
        foreach file $args {
    	set opts(ignore,$file) 1
        }
    }
    proc rpreserve {arr args} {
        upvar 1 $arr opts 
    
        foreach file $args {
    	catch {unset opts(ignore,$file)}
        }
    }
    
    proc sync {args} {
        # 28-01-2003: changed -text default to 0, i.e. copy binary mode
        array set opts {
            -prune	0
            -verbose	1
            -show	0
            -ignore	""
            -mtime	1
            -compress	1
            -auto	1
            -noerror	1
            -text	0
        }
        # 2005-08-30 only ignore the CVS subdir
        #rignore opts CVS RCS core a.out
        rignore opts CVS .svn
        
        if {[llength $args] < 2} {
            return -code error "improper usage in sdx::wrap::wrap"
        }
        
        while {[llength $args] > 0} {
            set arg [lindex $args 0]
        
            if {![string match -* $arg]} {
        	       break
            }
            
            if {![info exists opts($arg)]} {
        	       error "invalid option $arg"
            }
            
            if {$arg == "-ignore"} {
        	       rignore opts [lindex $args 1]
            } elseif {$arg == "-preserve"} {
        	       rpreserve opts [lindex $args 1]
            } else {
        	       set opts($arg) [lindex $args 1]
            }
            
            set args [lrange $args 2 end]
        }
        
        catch {
            package require mk4vfs
            set mk4vfs::compress $opts(-compress)
        }
        
        set src [lindex $args 0]
        set dest [lindex $args 1]
        #
        # Load up sync params (tcl script)
        #
        if {[file exists $src/.rsync]} {
            upvar #0 opts cb
            source $src/.rsync
        }
        #
        # Perform actual sync
        #
        set n [rsync opts $src $dest]
    }

}

namespace eval ::sdx::wrap {
    variable header \
{#!/bin/sh
# %
exec @PROG@ "$0" ${1+"$@"}
package require starkit
starkit::header @TYPE@ @OPTS@
}

    append header \32
    regsub % $header \\ header

    proc readfile {name} {
        set fd [open $name]
        fconfigure $fd -translation binary
        set data [read $fd]
        close $fd
        return $data
    }
    
    proc writefile {name data} {
        set fd [open $name w]
        fconfigure $fd -translation binary
        puts -nonewline $fd $data
        close $fd
    }
    
    # decode Windows .ICO file contents into the individual bit maps
    proc decICO {dat} {
        set result {}
        binary scan $dat sss - type count
        for {set pos 6} {[incr count -1] >= 0} {incr pos 16} {
            binary scan $dat @${pos}ccccssii w h cc - p bc bir io
            if {$cc == 0} {
                set cc 256
            }
            binary scan $dat @${io}a$bir image
            lappend result ${w}x${h}/$cc $image
        }
        return $result
    }
    
    proc LoadHeader {filename} {
        set normFile [file normalize $filename]
        if {$normFile == [info nameofexe]} {
            error "file in use, cannot be prefix: $normFile"
        }
        
        set size [file size $filename]
        catch {
            vfs::mk4::Mount $filename hdr -readonly
            # we only look for an icon if the runtime is called *.exe (!)
            if {[string tolower [file extension $filename]] == ".exe"} {
                catch { set ::origicon [readfile hdr/tclkit.ico] }
            }
            
            # 2003-02-08: this logic is not being used
            if 0 {
                set fd [open [join $filename .original]]
                set n [gets $fd]
                close $fd
                if {0 <= $n && $n < $size} {
    	               set size $n
    	               set ::origtime [file mtime $filename]
                }
            }
        }
        
        catch { vfs::unmount $filename }
        return [readfile $filename]
    }

    proc wrap {args} {
        variable header
        global tcl_platform
        
        set out [lindex $args 0]
        #set idir [file root [file tail $out]].vfs
        set idir [file join [file dirname $out] \
            [file root [file tail $out]].vfs]
        set compress 1
        set verbose 0
        set ropts -readonly
        set prefix 0
        set reusefile 0
        set prog tclkit
        set type mk4
        set macbin 0
        set explist {}
        set syncopts {}
        
        set a [lindex $args 1]
        while {[string match -* $a]} {
            switch -- $a {
                -interp {
                    set prog [lindex $args 2]
                    set args [lreplace $args 1 2]
                }
                -runtime {
                    set pfile [lindex $args 2]
                    if {$pfile == $out} {
                        set reusefile 1
                    } else {
                        set header [LoadHeader [lindex $args 2]]
                    }
                    set args [lreplace $args 1 2]
                    set prefix 1
                }
                -macbinary {
                    set macbin 1
                    set args [lreplace $args 1 1]
                }
                -writable -
                -writeable {
                    #set ropts "-nocommit"
                    set ropts ""
                    set args [lreplace $args 1 1]
                }
                -nocomp -
                -nocompress {
                    set compress 0
                    set args [lreplace $args 1 1]
                }
                -verbose {
                    set verbose 1
                    set args [lreplace $args 1 1]
                }
                -zip {
                    set type zip
                    set args [lreplace $args 1 1]
                }
                -uncomp {
                    lappend explist [lindex $args 2]
                    set args [lreplace $args 1 2]
                }
                default {
                    lappend syncopts [lindex $args 1] [lindex $args 2]
                    set args [lreplace $args 1 2]
                }
            }
            
            set a [lindex $args 1]
        }
        
        if {![file isdir $idir]} {
            error "Input directory not found: $idir"
        }
        
        if {!$prefix} {
            regsub @PROG@ $header $prog header
            regsub @OPTS@ $header $ropts header
            regsub @TYPE@ $header $type header
            
            set n [string length $header]
            while {$n <= 240} {
                append header ################
                incr n 16
            }
            
            set slop [expr { 15 - (($n + 15) % 16) }]
            for {set i 0} {$i < $slop} {incr i} {
                append header #
            }
            
            set n [string length $header]
            if {$n % 16 != 0} {
                error "Header size is $n, should be a multiple of 16"
            }
        }

        # pull apart macbinary file, if asked (and if it looks like one)
        if {$macbin} {
            binary scan $header cc@122cc c1 c2 c3 c4
            if {$c1 != 0 || $c1 < 0 || $c1 > 63 || $c2 >= 0 || $c3 >= 0} {
                error "runtime file is not in MacBinary format"
            }
            binary scan $header a83Ia37Sa2 mb_hd1 mb_dlen mb_hd2 mb_crc mb_end
            binary scan $header @128a${mb_dlen}a* header mb_tail
        }
        
        if {!$reusefile} {
            writefile $out $header
        }
        
        set origsize [file size $out]
        
        switch $tcl_platform(platform) {
            unix {
                catch {file attributes $out -permissions +x}
            }
            windows {
                set batfile [file root $out].bat
                # 2005-03-18 don't create a batfile if "-runtime" is specified
                if {![file exists $batfile] && ![info exists pfile]} {
                    set fd [open $batfile w]
                    puts -nonewline $fd \
    	            "@$prog [file tail $out] %1 %2 %3 %4 %5 %6 %7 %8 %9"
                    close $fd
                }
            }
            macintosh {
                catch {file attributes $out -creator TKd4}
            }
        }
        
        # 2003-02-08: added code to patch icon in windows executable
        # triggered by existence of tclkit.ico in vfs dir *and* tclkit.ico in orig
        
        # careful: this applies only to windows executables, but the
        # icon replacement can in fact take place on any platform...
        
        if {[info exists origicon] && [file exists [file join $idir tclkit.ico]]} {
            set custicon [readfile [file join $idir tclkit.ico]]
            array set newimg [decICO $custicon]
            foreach {k v} [decICO $origicon] {
                if {[info exists newimg($k)]} {
                    set len [string length $v]
                    set pos [string first $v $header]
                    
                    if {$pos < 0} {
                        #puts "  icon $k not found"
                    } elseif {[string length $newimg($k)] != $len} {
        	               #puts "  icon $k: NOT SAME SIZE"
                    } else {
        	               binary scan $header a${pos}a${len}a* prefix - suffix
        	               set header "$prefix$newimg($k)$suffix"
        	               #puts "  icon $k: replaced"
                    }
                }
            }
            
            writefile $out $header
        }
        
        # 2005-03-15 added AF's code to customize version/description strings in exe's
        if {[info exists pfile] && 
                [string tolower [file extension $pfile]] == ".exe" &&
                [file exists [file join $idir tclkit.inf]]} {
            
            package require stringfileinfo
            set fd [open [file join $idir tclkit.inf]]
            array set strinfo [read $fd]
            close $fd
            ::stringfileinfo::writeStringInfo $out strinfo
        }
        
        switch $type {
            mk4 {
                vfs::mk4::Mount $out $out
                set argv $syncopts
                lappend argv -compress $compress -verbose $verbose \
                    -noerror 0 $idir $out
                eval sdx::sync::sync $argv
                #source [file join [file dirname [info script]] sync.tcl] 
                
                # leave a marker inside the scripted doc about the header
                # 2002-07-07, disabled, until need is properly determined
                
                if {0 && $prefix} {
                    set ofile [file join $out .original]
                    set fd [open $ofile w]
                    puts $fd $origsize
                    close $fd
                    file mtime $ofile $origtime
                }
                
                # 2003-06-19: new "-uncomp name" option to store specific file(s)
                #		    in uncompressed form, even if the rest is compressed
                set o $mk4vfs::compress
                set mk4vfs::compress 0
                foreach f $explist {
                    file delete -force [file join $out $f]
                    file copy [file join $idir $f] [file join $out $f]
                }
                
                set mk4vfs::compress $o
                
                vfs::unmount $out
            }
        }
    
        # re-assemble mac binary file if we pulled it apart before
        if {[info exists mb_end]} {
            source [file join [file dirname [info script]] crc16.tcl]
            
            set newdata [readfile $out]
            
            set h $mb_hd1
            append h [binary format I [string length $newdata]]
            append h $mb_hd2
            append h [binary format S [crc::crc-ccitt -seed 0 $h]]
            append h mb_end
            
            set fd [open $out w]
            fconfigure $fd -translation binary
            puts -nonewline $fd $h
            puts -nonewline $fd $newdata
            puts -nonewline $fd $mb_tail
            close $fd
        }
    
    }
    
}

namespace eval ::sdx::unwrap {
    proc unwrap {args} {
        if {[llength $args] != 1} {
            error "Usage: $argv0 sdocfile"
        }
        
        set sdoc $args
        set odir [file join [file dirname $sdoc] \
            [file root [file tail $sdoc]].vfs]
        
        if {[file exists $odir] || [catch {file mkdir $odir}]} {
            error "Cannot create '$odir' directory"
        }
        
        mk4vfs::mount sddb $sdoc -readonly
        
        set argv [list -verbose 0 -noerror 0 sddb $odir]
        eval sdx::sync::sync $argv
    }
}
