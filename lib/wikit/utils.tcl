# This used to be called cli.tcl, now moved into Wikit

package provide Wikit::Utils 1.0

namespace eval Wikit {
  variable readonly -1  ;# use the file permissions

  # needed because non-readonly mode hasn't been moved into namespace
  namespace export pagevars InfoProc DoCommit Wiki GetPage

  # get page info into specified var names
  proc pagevars {num args} {
    foreach x $args y [eval mk::get wdb.pages!$num $args] {
      uplevel 1 [list set $x $y]
    }
  }

  # Code for opening, closing, locking, searching, and modifying views
  # Comment: nah, quite a messy collection of loose ends, really.

  proc DoCommit {} {
    mk::file commit wdb
  }

  proc AcquireLock {lockFile {maxAge 900}} {
    for {set i 0} {$i < 60} {incr i} {
      catch {
        set fd [open $lockFile]
        set opid [gets $fd]
        close $fd
        if {$opid != "" && ![file exists [file join / proc $opid]]} {
	  file delete $lockFile
	  set fd [open savelog.txt a]
	  set now [clock format [clock seconds]]
	  puts $fd "# $now drop lock $opid -> [pid]" close $fd
        }
      }
      catch {close $fd}

      if {![catch {open $lockFile {CREAT EXCL WRONLY}} fd]} {
        puts $fd [pid]
        close $fd
        return 1
      }
      after 1000
    }

      # if the file is older than maxAge, we grab the lock anyway
    if {[catch {file mtime $lockFile} t]} { return 0 }
    return [expr {[clock seconds] > $t + $maxAge}]
  }

  proc ReleaseLock {lockFile} {
    file delete $lockFile
  }

  proc LookupPage {name} {
    if {[regexp {^[0-9]+$} $name]} {
      set n $name
    } else {
      set n [mk::select wdb.pages -count 1 name $name]
    }
    if {$n == ""} {
      set n [mk::view size wdb.pages]
      mk::set wdb.pages!$n name $name
      DoCommit
    }
    return $n
  }

  proc GetTimeStamp {{t ""}} {
    if {$t == ""} { set t [clock seconds] }
    clock format $t -gmt 1 -format {%Y/%m/%d %T}
  }

  # Code for opening, closing, locking, searching, and modifying views

  proc WikiDatabase {name} {
    global tcl_version
    variable readonly
    if {[lsearch -exact [mk::file open] wdb] == -1} {
        if {$readonly == -1} {
          if {[file exists $name] && ![file writable $name]} {
            set readonly 1
          } else {
            set readonly 0
          }
        }
        if {$readonly} {
            set flags "-readonly"
            set tst readable
        } else {
            set flags ""
            set tst writable
        }
        set msg ""
        if {[catch {mk::file open wdb $name -nocommit $flags} msg] \
                && [file $tst $name]} {
            # if we can write and/or read the file but can't open
            # it using mk then it is almost almost inside a
            # scripted document, so we copy it to memory and
            # open it from there
            set readonly 1
            mk::file open wdb
            set fd [open $name]
            mk::file load wdb $fd
            close $fd
            set msg ""
        }
        if {$msg != "" && ![string equal $msg wdb]} {
            error $msg
        }
        mk::view layout wdb.pages   {name page date:I who format:I refs}
        mk::view layout wdb.archive {name date:I who id:I}
    }
    #FixPageRefs
  }

  proc GetPage {id} {
    switch $id {
      2   	{ SearchResults [SearchList] }
      4   	{ RecentChanges }
      default 	{ return [mk::get wdb.pages!$id page] }
    }
  }

  proc Wiki {name args} {
    if {$name == "-"} {
      catch { set name [mk::get wdb.pages![lindex $args 0] name] }
    }
    link - $name [join $args ?]
  }

  # Helper for Recent Changes. Invoked if an external archive directory
  # is present. Uses the contents of that directory to compute to the
  # list of recent changes.

  proc NewRecentChanges {} {
    set count 0
    set result ""
    set lastDay 0
    set threshold [expr {[clock seconds] - 7 * 86400}]
    array set pageDays {}
    array set listed {}

    set fd [open archive/.index]
    set entries [split [read -nonewline $fd] \n]
    close $fd

    for {set i [llength $entries]} {[incr i -1] >= 0} {} {
      foreach {x p s w t} [lindex $entries $i] break

        # these are fake pages, don't list them
      if {$p == 2 || $p == 4} continue

        # only report last change to a page on each day
      set day [expr {$s/86400}]
      if {[info exists pageDays($p)] && $day == $pageDays($p)} continue
      set pageDays($p) $day

        #insert a header for each new date
      incr count
      if {$day != $lastDay} {
          # only cut off on day changes and if over 7 days reported
        if {$count > 100 && $s < $threshold} {
          append result "''Older entries omitted...''"
          break
        }

        set lastDay $day
        append result "'''[clock format $s -gmt 1 -format {%B %e, %Y}]'''\n"
      }

        # only make the first reference a hyperlink
      set ob \[
      set cb \]
      if {[info exists listed($p)]} {
        set ob ""
        set cb ""
      }
      set listed($p) ""

      append result "   * $ob$t$cb . . . $w\n"
    }

    return $result
  }

  # Special page: Recent Changes.
  #
  # Uses the 'archive' view to get a list of the 100 most recent changes
  # to a page and converts that into wiki markup.
  #
  # If an external archive directory is present the system will consult
  # the contents of this directory instead of the metakit database.

  proc RecentChanges {} {
    if {[file isdirectory archive]} { return [NewRecentChanges] }

    set count 0
    set result ""
    set lastDay 0
    set threshold [expr {[clock seconds] - 7 * 86400}]
    array set pageDays {}
    array set listed {}
    
    foreach i [mk::select wdb.archive -rsort date] {
      lassign [mk::get wdb.archive!$i id date name who] id date name who
      
        # these are fake pages, don't list them
      if {$id == 2 || $id == 4} continue
      
        # only report last change to a page on each day
      set day [expr {$date/86400}]
      if {[info exists pageDays($id)] && $day == $pageDays($id)} continue
      set pageDays($id) $day
      
        #insert a header for each new date
      incr count
      if {$day != $lastDay} {
          # only cut off on day changes and if over 7 days reported
        if {$count > 100 && $date < $threshold} {
          append result "''Older entries omitted...''"
          break
        }

        set lastDay $day
        append result "'''[clock format $date -gmt 1 \
                -format {%B %e, %Y}]'''\n"
      }
      
        # only make the first reference a hyperlink
      set ob \[
      set cb \]
      if {[info exists listed($id)]} {
        set ob ""
        set cb ""
      }
      set listed($id) ""
      
      append result "   * $ob$name$cb . . . $who\n"        
    }
    
    return $result
  }

  set searchKey ""
  set searchLong 0

  proc SearchList {} {
    variable searchKey
    variable searchLong
    
    if {$searchKey == ""} {return ""}
    
    set fields name
    if {$searchLong} {
      lappend fields page
      append result { and contents}
    }
    
    return [mk::select wdb.pages -rsort date -keyword $fields $searchKey]
  }
    
  proc SearchResults {rows} {
    variable searchKey
    variable searchLong

    # tclLog "SearchResults key <$searchKey> long <$searchLong>"
    if {$searchKey == ""} {return ""}
    
    set count 0

    set result "Searched for \"'''$searchKey'''\" (in page titles"
    if {$searchLong} {
      append result { and contents}
    }
    append result "):\n\n"
    
    foreach i $rows {
      pagevars $i date name
      
        # these are fake pages, don't list them
      if {$i == 2 || $i == 4 || $date == 0} continue
      
      incr count
      if {$count > 100} {
        append result "''Remaining matches omitted...''"
        break
      }

      append result "   * [GetTimeStamp $date] . . . \[$name\]\n"        
    }
    
    if {$count == 0} {
      append result "   * '''''No matches found'''''\n"
    }
    
    if {!$searchLong} {
      append result "\n''Tip: append an asterisk\
                to search the page contents as well as titles.''"
    }
    
    return $result
  }

  # Rendering Wiki pages in HTML and as styled text in Tk

  proc InfoProc {ref} {
    set id [LookupPage $ref]
    pagevars $id date name

    if {$date == 0} {
      append id @ ;# enter edit mode for missing links
    } else {
      #append id .html
    }
    
    return [list /$id $name $date]
  }

  proc Expand_HTML {str} {
    StreamToHTML [TextToStream $str] $::env(SCRIPT_NAME) InfoProc
  }

  proc GetTitle {id} {
      set title [mk::get wdb.pages!$id name]
      return $title
      # the following allows links in titles to be followed - originally
      # used for following a Page 3 link for the Help button. Not used now
      # (regarded as feeping creaturism) but left here in case
      set ref [StreamToRefs [TextToStream $title] InfoProc]
      if {$ref == ""} {
          set ref $id
      } else {
          set title [mk::get wdb.pages!$ref name]
      }
      return [list $ref $title]
  }
}
