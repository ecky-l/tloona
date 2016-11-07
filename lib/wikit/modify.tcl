# These are the main WiKit database modification routines

package provide Modify 1.0

# Structure of the database (wdb)
# 2 views: 'pages', and 'archive'.

# "pages" is the main view. It contains all pages managed by the wiki,
# and their contents.

# "archive" is a management view. It lists for all pages when they
# were modified, and by whom. Its contents are the basis for the
# special page "Recent Changes".

# pages
# - string      name    Title of page
# - string      page    Contents of page.
# - integer     date    date of last modification of the page as time_t value.
# - string      who     some string identifying who modified the page last.
# - integer     format  0 - verbatim page, 1 - standard wiki page
# - string      refs    List of page ids, the pages which reference this page vi
# archive
# - integer     date    date when page 'id' was modified, as time_t value.
# - string      who     See 'pages.who', the entity who modified tha page at tha# - integer     id      The page which was modified, as id (row-id) into the vie
#
# Note regarding "format". All pages whose title is ending in either
# .txt or .tcl are treated as verbatim pages, i.e. pages where all
# lines are treated verbatim, without visual markup, nor references to
# either external sites or other pages.
#
# Note II: The code here is able to maintain external copies for all
# pages (and all revisions) and an external log of changes. This
# functionality is activated if the directory containing the metakit
# datbase file also contains a directory named 'archive'. The system
# does not track page history inside of the metakit database.

# Helper for 'SavePage'. The id'd page newly refers to the pages
# listed in 'refs'. The 'refs' column of all referenced pages is
# updated to contain the 'id' of the referencing page. This happens if
# references were added during a change to page 'id'.

proc AddRefs {id refs} {
  foreach x $refs {
    set r [mk::get wdb.pages!$x refs]
    if {[lsearch -exact $r $id] < 0} {
      mk::set wdb.pages!$x refs [lappend r $id]
    }
  }
}

# Helper for 'SavePage'. Complement to 'AddRefs'. Removes 'id' from
# the 'refs' column of all pages listed in 'refs'. This happens if
# references were removed during a change to page 'id'.

proc DelRefs {id refs} {
  foreach x $refs {
    set r [mk::get wdb.pages!$x refs]
    set n [lsearch -exact $r $id]
    if {$n >= 0} {
      mk::set wdb.pages!$x refs [lreplace $r $n $n]
    }
  }
}

proc FixPageRefs {} {

    # first clear all references
  mk::loop c wdb.pages {
    mk::set $c refs ""
  }
    # then add all references back in
  mk::loop c wdb.pages {
    set id [mk::cursor position c]
    pagevars $id format date page
    if {$format == 1 && $date != 0} {
      AddRefs $id [StreamToRefs [TextToStream $page] InfoProc]
    }
  }
}

# Helper to 'SavePage'. Changes all references to page 'name'
# contained in the 'text' into references to page 'newName'. This is
# performed if a page changes its title, to keep all internal
# references in sync. Only pages which are known to refer to the
# changed page (see 'SavePage') are modifgied.

proc ReplaceLink {text old new} {
  # this code is not fullproof, it misses links in keyword lists
  # this means page renames are not 100% accurate (but refs still are)

  set newText ""
  foreach line [split $text \n] {
      # don't touch quoted lines, except if its a list item
    if {![regexp "^\[ \t\]\[^\\*0-9\]" $line] ||
        [regexp "^(   |\t)\[ \t\]*(\\*|\[0-9\]\\.) " $line]} {
      regsub -all -nocase "\\\[$old\\\]" $line "\[$new\]" line
    }
    lappend newText $line
  }
  join $newText \n
}

proc SavePage {id text who newName} {
  set changed 0
  pagevars $id name format refs page
  
  if {$newName != $name || $format == 0} {
    set changed 1
    mk::set wdb.pages!$id format [expr {![regexp {.\.(txt|tcl)$} $newName]}]
  
      # rename old names to new in all referencing pages
    foreach x $refs {
      set y [mk::get wdb.pages!$x page]
      mk::set wdb.pages!$x page [ReplaceLink $y $name $newName]
    }
    
      # don't forget to adjust links in this page itself
    set text [ReplaceLink $text $name $newName]
    
    mk::set wdb.pages!$id name $newName
  }
  
  set text [string trimright $text]
  
    # avoid creating a log entry and committing if nothing changed
  if {!$changed && $text == $page} return
  
  if {$format == 1} {
    set oldRefs [StreamToRefs [TextToStream $page] InfoProc]
    set newRefs [StreamToRefs [TextToStream $text] InfoProc]
    if {$oldRefs != $newRefs} {
      AddRefs $id $newRefs
      DelRefs $id $oldRefs
    }
  }
  if {$id == 3} {
    gButton::modify Help -text [lindex [Wikit::GetTitle 3] 0]
  }
  
  mk::set wdb.pages!$id date [clock seconds] page $text who $who
  AddLogEntry $id
  
  DoCommit
}

# Enters a log entry for a changed into the changelog view
# (archive). If an external 'archive' directory is present it will
# also maintain an external copy of all changed pages, and an external
# log of all changes. The names of the files for the changed pages
# contain their id and also data and changing entity. The date is
# encoded as time_t value. Sorting the filenames alpahabetically will
# allow other applications to created reports and diffs between
# revisions.

proc AddLogEntry {id} {
  pagevars $id date page who name
  
  if {[file isdirectory archive]} {
    set t [string trim $page]
    if {$t != ""} {
      set fd [open archive/$id-$date-$who w]
      puts $fd "Title: $name\n"
      puts $fd $t
      close $fd
    }
    set fd [open archive/.index a]
    puts $fd [list x $id $date $who $name]
    close $fd
  }

  mk::row append wdb.archive id $id name $name date $date who $who
}
