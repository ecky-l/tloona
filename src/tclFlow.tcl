#!/bin/sh

# Rework to use more procs and be able to embed into another 
# application

# The idea here is to scan the files in one pass to extract all of the 
# proc definitions, and build an array of procnames and the files they exist
# in (make that a list -  ;# flowProcDefs($procName) [list $fileName $lineNumber] 
#  
# Then, scan the files again, this time marking down which procs are called 
# from within other procs, and creating an array 
#   flowCallTree($procName) [list $firstProc $nextProc $nextProc] 
#  
# Then figure out what's going on from the calltree list with a toposort.


namespace eval tclFlow {

  variable flowArray
  variable flowProcDefs
  variable flowCallTree

  proc DEBUG {string {mark {1}} } {
    variable flowArray

    if {$flowArray(debugLevel) >$mark} {
      puts $flowArray(debugChannel) $string
    }
  }
  
################################################################
#   proc init {tree}--
#    Initialize retained variables.
# Arguments
#   tree 	A tree widget if displayFlow will be used.
# 
# Globals
#   NONE
# 
# Results
#   Updates flowArray
# 
  proc init {{tree {}} } {
    variable flowArray
    set flowArray(tree) $tree
    set flowArray(debugChannel) stderr
    set flowArray(debugLevel) 0
    set flowArray(filelist) {}
  }
  
################################################################
#   proc addFile {args}--
#    Add a file to the list of files to check.
#    Only adds files once, no duplicates in list.
# Arguments
#   args	List of files to add
# 
# Globals
#   NONE
# 
# Results
#   Update flowArray
# 
  proc addFile {args} {
    variable flowArray
    foreach fileName $args {
      if {[lsearch $flowArray(filelist) $fileName] < 0} {
        lappend flowArray(filelist) $fileName
      }
    }
  }
  
################################################################
#   proc showFlow {start}--
#    Show the flow in a tree widget
# Arguments
#   start	The top of the flow diagram
# 
# Globals
#   NONE
# 
# Results
#   Updates flowArray, modified widget.
# 
  proc showFlow {} {
    variable flowArray

    $flowArray(tree) delete [$flowArray(tree) children {}]
    foreach ff $flowArray(filelist) {
      scanForSource [file tail $ff] [file dirname $ff]
    }

    walkFilelist 
    extractDefinedProcs 
    extractRelationShips 
    set sorted [tclFlow::sortEm]
    displayTree  {} [lindex $sorted end]
  }

################################################################
#   proc printFlow {start}--
#    Show the flow in a tree widget
# Arguments
#   start	The top of the flow diagram
# 
# Globals
#   NONE
# 
# Results
#   Updates flowArray, modified widget.
# 
  proc printFlow {} {
    variable flowArray

    $flowArray(tree) delete [$flowArray(tree) children {}]
    foreach ff $flowArray(filelist) {
      scanForSource [file tail $ff] [file dirname $ff]
    }

    walkFilelist 
    extractDefinedProcs 
    extractRelationShips 
    set sorted [tclFlow::sortEm]
    printTree 0 [lindex $sorted end] $sorted
  }

################################################################
#   proc scanForSource {filename {path {}}}--
#    Scans files recursively for "source" commands
#    Does NOT follow package requires (yet)
# Arguments
#   filename	Name of file to scan
#   path	Optional path to prepend
# 
# Globals
#   
# 
# Results
#   Updates flowArray(fileList)
# 
  proc scanForSource {filename {path {}}} {
    variable flowArray

#    set filename [file join $path $filename]
    DEBUG "Scanning $filename"

    addFile $path/$filename

    set fail [catch {open $path/$filename "r"} infl]
    if {$fail} {
      puts "Can't open $filename"
      puts "$::errorInfo"
      return -1
    }
    
    set d [read $infl]

    foreach line [split $d \n] {
      set lst [split $line ";"]
      foreach ln $lst {
	set ln [string trim $ln]
	if {[string first source $ln] == 0} {
	  set newfile [lindex $ln 1]
	  set fail [catch {subst $newfile} newfile]
	  DEBUG "NEW FILE: $newfile"
	  if {$fail} {return 1}
	  set fail [catch {scanForSource $newfile $path}]
	  if {$fail} {
	    error "FAILED TO LOAD: $newfile"
	  }
	}
      }
    }
    close $infl
    return 0
  }

  ################################################################
  # ProcessArgs {}--
  # Evaluate the command line arguments, in particular, allows an global
  #  variable to be set from the command line.
  #
  # Arguments
  #   NONE
  # 
  # Globals
  #   Everything in flowGlobalList
  # 
  # Results
  #   Global variables may get modified
  # 
  proc ProcessArgs {argv} {
    variable flowArray

    for {set i 0} {$i < [llength $argv]} {incr i} {
      set arg [lindex $argv $i]

      if {[string first "-" $arg] == 0} {
	set arg [string range $arg 1 end]

	incr i

	set val [lindex $argv $i]
	set cmd [string range $arg 0 0]

	set arg [string range $arg 1 end]

	switch $cmd {
	"A" {
	    eval [list set flowArray($arg) $val]
	  }
	"S" {
	    eval [list set $arg $val]
	  }
	}
      } else {
	lappend flowArray(filelist) $arg
      }
    }
  }


  ################################################################
  # printTree {indent start {lst {}} }--
  #    Print a tree to the stdout
  # Arguments
  #   indent	Number of spaces to indent - call with 0 - 
  #               other values provided by recursion
  # 
  # Globals
  #   Everything in flowGlobalList
  # 
  # Results
  #   Generates output.
  # 
  proc printTree {indent start {lst {}}} {
    variable flowArray

    variable flowProcDefs
    variable flowCallTree

    set spaces "                                                           "


    puts -nonewline [string range $spaces 0 $indent]

;# Check that we have a valid name -  might be error return from tsort.

    if {![info exists flowCallTree($start)]} {return}

    set info ""
    if {[info exists flowProcDefs($start)]} {
      set info "<[lindex $flowProcDefs($start) 0]\
	[lindex $flowProcDefs($start) 1]>"
    }

    puts "$start $info"

    if {[llength $flowCallTree($start)] > 1} {
      set valid 1

      if {[string first "global." $start] == 0} {
	set valid 0

      }

      set ltmp [lrange $flowCallTree($start) $valid end]
      set last [expr {80 - $indent - 7}]

      if {[llength $ltmp] > 0} {
	# puts -nonewline [string range $spaces 0 $indent]
	# puts "(calls) $ltmp"

	while {$ltmp != ""} {
	  if {[string length $ltmp] <= $last} {
	    set prt $ltmp
	    set ltmp ""
	  } else {
	    set stmp [string range $ltmp 0 $last]
	    set end [string last " " $stmp]
	    set prt [string trim [string range $ltmp 0 $end]]
	    set ltmp [string trim [string range $ltmp $end end]]
	  }
	  puts -nonewline [string range $spaces 0 $indent]
	  #        puts "calls: $prt"
	  puts "----> $prt"
	}
      } else {
        puts ""
	return
      }

;# Check for cycles, and kill this run if one exists
      if {[lsearch $lst $start] >= 0} {return}

      lappend lst $start

      incr indent 4
      foreach nm $flowCallTree($start) {
	if {([info exists flowCallTree($nm)]) &&(![string match $start $nm])} {
	  printTree $indent $nm $lst
	}
      }
    }
  }

  ################################################################
  # displayTree {tree parent start {lst {}} }--
  #    Display a tree in a ttk::treeview widget
  # Arguments
  #   tree	Name of tree
  #   parent	Parent node - {} for start, other values via recursion
  #   start	What to insert
  #   lst		subordinate items to
  # Globals
  #   ALL
  # 
  # Results
  #   Widget display is modified
  # 
  proc displayTree {parent start {lst {}}} {
    variable flowArray
    variable flowProcDefs
    variable flowCallTree
    
    if {$flowArray(tree) eq ""} {return} else {set tree $flowArray(tree)}

    DEBUG "-&*-- displayTree tree $tree parent $parent start $start lst $lst "

;# Check that we have a valid name -  might be error return from tsort.

    if {![info exists flowCallTree($start)]} {return}

    set info ""
    if {[info exists flowProcDefs($start)]} {
      set info "<[lindex $flowProcDefs($start) 0]\
	[lindex $flowProcDefs($start) 1]>"
    }
    set useMe 1
    foreach ch [$tree children $parent] {
      if {[$tree item $ch -text] eq $start} {
	set useMe 0
	set id $ch
      }
    }
    DEBUG "CHILDREN: [$tree children $parent]"
    if {$useMe} {
      DEBUG "AA  set id \[$tree insert $parent end -text $start -values $info]"
      set id [$tree insert $parent end -text $start -values $info]
    }


    if {[llength $flowCallTree($start)] > 1} {
      set valid 1

      if {[string first "global." $start] == 0} {
	set valid 0

      }

      set ltmp [lrange $flowCallTree($start) $valid end]

      if {[llength $ltmp] > 0} {
	while {$ltmp != ""} {
	  set stmp [string range $ltmp 0 end]
	  set end [string last " " $stmp]
	  if {$end < 0} {
	    set end "end"
	  }
	  set prt [string trim [string range $ltmp 0 $end]]
	  set ltmp [string trim [string range $ltmp $end end]]
	  if {[string length $ltmp] == 1} {set ltmp ""}
	  DEBUG "XX	$tree insert $id end -text $prt "
	  #	$tree insert $id end -text $prt 
	}
      } else {
        return
      }

;# Check for cycles, and kill this run if one exists
      if {[lsearch $lst $start] >= 0} {return}

      lappend lst $start

      incr indent 4
      foreach nm $flowCallTree($start) {
	if {([info exists flowCallTree($nm)]) &&(![string match $start $nm])} {
	  displayTree $id $nm $lst
	}
      }
    }
  }

  ################################################################
  # extractDefinedProcs {}--
  #    Find all the procs defined with a "proc" call.
  # Arguments
  #   NONE
  # 
  # Globals
  #   ALL
  # 
  # Results
  #   Updates flowProcDefs
  # 
  proc extractDefinedProcs {} {
    variable flowArray

    variable flowProcDefs
    variable flowCallTree

    # extract all of the defined procs from the files,
    # and put them into a list.

    foreach fl $flowArray(filelist) {
      set fail [catch {open $fl "r"} infl]
      if {$fail} {
	puts "Failed to open $fl"
	puts "$::errorCode: $::errorInfo"
	set ::errorInfo ""
	set ::errorCode ""
	continue
      }

      set lineNum 0

      set flowProcDefs(global.$fl) [list $fl 0 global]

      while {![eof $infl]} {
	set len [gets $infl line]
	incr lineNum

	if {$len > 2} {
	  set line [string trim $line]
	  set type ""
	  lassign [regexp -all -inline {\S+} $line] type name

	  if {($type eq "proc") ||($type eq "method")} {
	    set m1 ""
	    set m2 ""
	    set m3 ""
	    set mm [regexp "$type\[ 	]+(\[^ ]+)\[ 	]+\{\[ 	]*(\[^\}]*)\[\
	      	]*\}" $line m1 m2 m3]
	    DEBUG "regexp result: $mm -- $line" 1
	    DEBUG "$m1 $m2 $m3" 1
	    if {$mm} {
	      set flowProcDefs($m2) [list $fl $lineNum $m3]
	      if {![info exists flowCallTree($m2)]} {
		set flowCallTree($m2) $m2
		lappend flowDefine(global.$fl) $m2
	      } 
	    }
	  }
	}
      }
      close $infl
    }

    foreach proc [array names flowProcDefs] {
      DEBUG "$proc : $flowProcDefs($proc)" 4
    }
  }

  ################################################################
  # proc extractRelationShips {}--
  #    Extract the relationships.
  #    Find out who calls who
  # Arguments
  #   NONE
  # 
  # Globals
  #   ALL
  # 
  # Results
  #   Updates flowCallTree, afterCallTree flowProcDefs and more
  # 
  proc extractRelationShips {} {
    variable flowArray

    variable flowProcDefs
    variable flowCallTree

    foreach fl $flowArray(filelist) {
      set fail [catch {open $fl "r"} infl]
      if {$fail} {
	puts "Failed to open $fl"
	puts "$::errorCode: $::errorInfo"
	set ::errorInfo ""
	set ::errorCode ""
	continue
      }

      set lineNum 0

      # A proc can be invoked:
      # 1) by itself
      # 2) as part of an if conditional
      # 3) within an inline if action
      # 4) as part of a for conditional
      # 5) as part of a while conditional
      # 6) as part of an inline for/while action
      # 7) as a catch argument
      # 8) as an eval argument
      #
      #  Perhaps all of this can be ignored for a first pass, though...
      #  just do a check to see if a word is in my proc list.


      set lineNum 0
      set current global.$fl

      # These are used to see if the script is currently looking at a proc
      #  definition.  It moves the 'current' pointer back to global space
      #  when procs are not being defined.

      set scr ""
      set inproc 0


      while {![eof $infl]} {
	set len [gets $infl line]
	incr lineNum

	if {$len > 2} {
	  set line [string trim $line]
	  lassign [regexp -all -inline {\S+} $line] type name

	  if {($type eq "proc") ||($type eq "method")} {
	    set inproc 1

	    set scr $line

	    set mm [regexp "$type +(\[^ ]+) +\{ *(\[^\}]*) *\}" $line m1 m2 m3]
	    if {$mm} {
	      set current $m2
	    }
	  } else {
	    if {$inproc} {
	      append scr $line

	      if {[info complete $scr]} {
		# puts "SET INPROC 0 - $name"
		set inproc 0

		set current global.$fl
	      }
	    }
	    regsub -all ";" $line " " line
	    set line [string trim $line] 
	    # puts "LINE: [string first "#" $line] -- $line"
	    if {([string first "#" $line] != 0) &&
	        ([string first "bind" $line] != 0)} {
	      set lst [split $line " {}\[\]\(\)"] 
	      # puts "LINE: $line :: $lst :: $current :: $inproc"
	      foreach word $lst {
		set word [string trim $word]
		if {([info exists flowProcDefs($word)]) &&([string first\
		  "after " $line] < 0) &&((![info exists\
		  flowCallTree($current)]) ||([lsearch $flowCallTree($current)\
		  $word] == -1))} {
		  lappend flowCallTree($current) $word
		}
		if {([info exists flowProcDefs($word)]) &&
		    ([string first "after " $line] >= 0) &&
		    ((![info exists afterCallTree($current)]) ||
		     ([lsearch $afterCallTree($current) $word] == -1))} {
		  lappend afterCallTree($current) $word
		}
	      }
	    }
	  }
	}
      }
      close $infl
    }
  }

  ################################################################
  # proc sortEm {}--
  #    Return a topo-sorted list of stuff 
  # Arguments
  #   NONE
  # 
  # Globals
  #   flowCallTree, flowDefine, 
  # 
  # Results
  #   
  # 

  proc sortEm {} {
    variable flowArray

    variable flowCallTree

    foreach aname {flowDefine flowCallTree afterCallTree} {
      foreach {k v} [array get $aname] {
	lappend lst [list $k $v]
      }
    }

    set sorted [topoSort::topoSort $lst]

    # DEBUG OUTPUT
    if {0} {
      set of [open sorted w]
      puts $of $sorted
      close $of
      puts "----- SORTED ----- "
      puts "$sorted"
      puts "----- END SORTED ----- "
    }

    if {0} {
      puts "...... Contingency Tree ...... "
      foreach nm $sorted {
	printTree 0 $nm
      }
    }

    return $sorted
  }

  ################################################################
  # proc walkFilelist {}--
  # Walk down the tree and see what we can find in order.
  #  This expects the files to be in *some* rough order
  # Arguments
  #   NONE
  # 
  # Globals
  #   Uses flowArray(filelist)
  # 
  # Results
  #   Updates tables in flowArray
  # 
  proc walkFilelist {} {
    variable flowArray

    variable flowProcDefs

    DEBUG "FLOW TREES"

    foreach fl $flowArray(filelist) {
      set fail [catch {open $fl "r"} infl]
      if {$fail} {
	puts "Failed to open $fl"
	puts "$::errorCode: $::errorInfo"
	set ::errorInfo ""
	set ::errorCode ""
	continue
      }

      set lineNum 0

      set current global

      while {![eof $infl]} {
	set len [gets $infl line]
	incr lineNum

	if {$len > 2} {
	  set line [string trim $line]
	  if {([string first "proc " $line] == 0) ||([string first\
	    "proc	" $line] == 0)} {
	    set mm [regexp "proc +(\[^ ]+) +\{ *(\[^\}]*) *\}" $line m1 m2 m3]
	    if {$mm} {
	      set current $m2
	    }
	  } else {
	    regsub -all ";" $line " " line
	    set line [string trim $line] 
	    # puts "LINE: [string first  "#" $line] -- $line"
	    if {[string first "#" $line] != 0} {
	      set lst [split $line " {}\[\]\(\)"]
	      foreach word $lst {
		set word [string trim $word]
		if {([info exists flowProcDefs($word)])} {
		  # puts "INFO EXISTS: $word - $flowProcDefs($word)"
		}
	      }
	    }
	  }
	}
      }
      close $infl
    }
  }

  proc loadRef {tree x y} {
    variable flowProcDefs
    set id [$tree identify item $x $y]
    set txt [$tree item $id -text]
    set fileNm [lindex $flowProcDefs($txt) 0]
    $::TloonaApplication openFile $fileNm 0
  }
}
