# These routines are used when WiKit is called from CGI

package provide Web 1.0
package require cgi

# dump CGI env to file for debugging purposes
if {[catch {
  set logfd [open $env(WIKIT_DUMP) a]
  fconfigure $logfd -buffering line
  proc tclLog {msg} { puts $::logfd $msg }
  tclLog "#############################"
  foreach x [lsort [array names env]] {
    tclLog "\$$x = $env($x)"
  }
}]} {
  proc tclLog {msg} { }
}

tclLog ==============================

# 1-5-2001: new logic to work with a cache for *much* higher performance
# 
# To make this work, create a "main" dir, reachable from the web, and store
# a special ".htaccess" file in it, (adjust as needed):
#	DirectoryIndex /home/jcw/wikit.cgi/0
#	ErrorDocument 404 /home/jcw/wikit.cgi
#
# Then config this wikit to maintain pages in that cache:
#	WIKI_CACHE=/home/jcw/www/tcl ./wikit.tkd 
#
# Operation without this new env var, or with the CGI url remains unaffected.

if {[info exists env(WIKIT_CACHE)] && $env(WIKIT_CACHE) != ""} {
  set htmlcache $env(WIKIT_CACHE)
  tclLog "htmlcache = $htmlcache"
}

set EditInstructions {}
set ProtectedPages {}

# 3-5-2001: force graceful cleanup
proc cgi_mail_start {args} {
  catch {
    global _cgi env
    chdir /home/jcw/data
    file delete wikit.lock
    set fd [open errors.txt a]
    puts $fd {=================================================================}
    puts $fd [clock format [clock seconds]]
    puts $fd $_cgi(errorInfo)
    puts $fd $env(PATH_INFO)
    close $fd
  }
  exit
}

rename puts jcw_puts
proc puts {args} {
  # 3-5-2001: make sure broken pipes won't abort
  catch {eval jcw_puts $args}
  if {[info exists ::htmlcopy]} {
    lassign $args a0 a1
    if {[llength $args] == 1} {
      append ::htmlcopy $a0 \n
    } elseif {[llength $args] == 2 && $a0 == "-nonewline"} {
      append ::htmlcopy $a1
    }
  }
  return
}

proc Wikit::ProcessCGI {} {
  variable readonly
  global htmlcopy htmlcache env roflag

  admin_mail_addr nowhere@to.go
  #debug -on
  
  # 2002-06-17: moved to app-wikit/start.tcl
  #input "n=1"
  suffix ""
  
  set ::script_name $::env(SCRIPT_NAME)

  # this code added 1-5-2001 to handle ErrorDocument redirection/caching
  if {[info exists ::env(REDIRECT_URL)]} {

    set r $env(REDIRECT_URL)
    if {[info exists env(PATH_INFO)]} { # DirectoryIndex case
      append r [string range $env(PATH_INFO) 1 end]
    } else {        # ErrorDocument case
      set env(PATH_INFO) /[file tail $r]
    }
    set env(SCRIPT_NAME) [file dirname $r]

      catch {set env(QUERY_STRING) $env(REDIRECT_QUERY_STRING)}

    if {[info exists htmlcache] && [regexp {\d+(\.html)?$} $r - x]} {
      tclLog "setting up cache copy - $r"
      set htmlcopy ""

      proc saveCopy {N} {
	global htmlcopy htmlcache
	set m {<meta http-equiv="Pragma" content="no-cache">}
	regsub ".*?\n\n" $htmlcopy "$m\n" htmlcopy
	if {$N == 2 || $htmlcopy == ""} return
	catch {
	  set fd [open [file join $htmlcache $N.html] w]
	  puts -nonewline $fd $htmlcopy
	  close $fd
	}
      }
    }
  }
  # end of new code

  cgi_eval {
  set host $::env(REMOTE_ADDR)
  catch {set host $::env(REMOTE_HOST)}

    set path ""
    catch {set path $::env(PATH_INFO)}
    
    set query ""
    catch {set query $::env(QUERY_STRING)}
    
    set cmd ""
    if {![regexp {^/([0-9]+)(.*)$} $path x N cmd] || $N >= [mk::view size wdb.pages]} {
      set N 0
    
        # try to locate a page by name, using various search heuristics
      if {[regexp {^/(.*)} $path x arg] && $arg != "" && $query == ""} {
        set N [mk::select wdb.pages name $arg -min date 1]
        switch [llength $N] {
          0 { # no match, try alternative approach
            # do a glob search, where AbCdEf -> *[Aa]b*[Cc]d*[Ee]f*
              # skip this if the search has brackets
            if {[string first \[ $arg] < 0} {
              regsub -all {[A-Z]} $arg \
                {*\\[&[string tolower &]\]} temp
              set temp "[subst -novariable $temp]*"
              set N [mk::select wdb.pages -glob name $temp -min date 1]
            }
            if {[llength $N] != 1} {
              set N 0
              set query $arg ;# turn it into a keyword search
            }
          }
          1 { # uniquely identified, done
          }
          default { # ambiguous, turn it into a keyword search
            set query $arg
          }
        }
      }
    }
    #tclLog "path $path query $query N $N"

    if {$query != ""} {
      set N 2
      variable searchKey 
      variable searchLong
      set searchKey [unquote_input $query]
      set searchLong [regexp {^(.*)\*$} $searchKey x searchKey]
      set query "?$query"
    }
    
    pagevars $N name refs date who
    set origtag [list $date $who]
    
    # if there is new page content, save it now
    if {$N != "" && [lsearch -exact $::ProtectedPages $N] < 0} {
      if {$roflag < 0 && ![catch {import C}] && [import C] != ""} {
	# added 2002-06-13 - edit conflict detection
	if {![catch {import O}] && $O != $origtag} {
	  tclLog "conflict, want $O, stored $origtag"
	  http_head {
	    content_type
	    pragma no-cache
	  }
	  head {
	    title $name
	    cgi_http_equiv Expire "Mon, 04 Dec 1999 21:29:02 GMT"
	  }
	  body {
	    h2 "Edit conflict on page $N - [Wiki $name $N]"
	    p "[bold {Your changes have NOT been saved}], because
	       someone (at IP address [lindex $origtag 1]) saved
	       a change to this page while you were editing."
	    p [italic {Please restart a new edit and merge your
	       version, which is shown in full below.}]
	    hr size=1
	    p "<pre>[quote_html $C]</pre>" 
	    hr size=1
	    p
	  }
	  return
	}
	# 1-5-2001
	catch {
	  file delete $::htmlcache/4.html
	  file delete $::htmlcache/$N.html
	}
	SavePage $N $C $host $name
	mk::file commit wdb
	# a general improvement: redirect through a fetch again
	if {![catch {import Z}]} {
	  tclLog "redirect $Z"
	  http_head {
	    content_type
	    pragma no-cache
	    #redirect $Z
	    #refresh 1 $Z
	  }
	  head {
	    title $name
	    http_equiv Refresh 1\;URL=$Z
	  }
	  body {
	    puts "Page saved... [link - $name $Z]"
	  }
	  return
	}
	# end of changes
      }
    }
    
    # set up a few standard URLs an strings
    
    switch [llength $refs] {
      0 {
        set Refs ""
        set Title $name
      }
      1 {
        set Refs "[Wiki Reference $refs] - " 
        set Title [Wiki $name $refs]
      }
      default {
        set Refs "[llength $refs] [Wiki References $N!] - "
        set Title [Wiki $name $N!]
      }
    }
    
    set Edit "Edit [Wiki - $N@]"
    set Home "Go to [Wiki - 0]"
    set About "About [Wiki - 1]"
    set Search "[Wiki Search 2] - "
    set Changes "[Wiki {Recent changes} 4] - "
    set Help "[Wiki - 3]"
    
    if {$date != 0} {
      set date [clock format $date -gmt 1 -format {%e %b %Y, %R GMT}]
    }
    
    if {[lsearch -exact $::ProtectedPages $N] >= 0} {
      set menu ""
      if {$N == 2} {
        set Search ""
      } else {
        set Changes ""
      }
    } elseif {$roflag >= 0 || $readonly} {
      set menu [italic "Updated on $date[nl]"]
    } else {
      set menu [italic "Updated on $date [nbspace] - [nbspace] $Edit[nl]"]
    }
    
    append menu [font size=-1 "$Search$Changes $Refs$About - $Home"]
    if {$N != 3} {
        append menu [font size=-1 " - $Help"]
    }
    
      # showScript is used to display one page
    set showScript {
      set C [GetPage $N]
      set U ""
      pagevars $N format
      if {$format == 0 && $N != 2} {
        set C "<pre>[quote_html $C]</pre>" 
      } else {
        foreach {C U} [Expand_HTML $C] break
      }
      p $C
    }
    
    cgi_http_head {
      cgi_content_type
      pragma no-cache
    }

    # now dispatch on the type of request
    
    switch -- $cmd {

      @ { # called to generate an edit page
	cgi_head {
	  cgi_title "Edit $name"
	  cgi_http_equiv Expire "Mon, 04 Dec 1999 21:29:02 GMT"
	}
        
        cgi_body bgcolor=#ffffff {
          cgi_puts [h2 [Wiki - $N]]
          
          cgi_form $::script_name/$N {
	    cgi_export O=$origtag
	    catch {
	      set z "http://$::env(HTTP_HOST)$::env(REDIRECT_URL)"
	      regsub {@$} $z {} z
	      cgi_export Z=$z
	    }
	    textarea C=[GetPage $N] rows=30 cols=72 wrap=virtual \
	      style=width:100%
            p
            submit_button "=  Save  "
            if {$date != 0} {
              cgi_puts " [nbspace] [nbspace] [nbspace] "
              cgi_puts [italic "Last saved on [bold $date]"]
            }
            p
            cgi_puts $::EditInstructions
          }
        }
      }
            
      ! { # called to generate a page with references
        cgi_title "References to $name"

        cgi_body bgcolor=#ffffff {
          cgi_puts [h2 "References to [Wiki - $N]"]
      
          set refList ""
          foreach r $refs {
            pagevars $r name who
            lappend refList [list $name $who $r]
          }
          
          bullet_list {
            foreach x [lsort $refList] {
              li "[Wiki - [lindex $x 2]] . . . [lindex $x 1]"
            }
          }
          
          hr noshade
          cgi_puts [font size=-1 "$Search - $Changes - $About - $Home"]
        }
      }

      default { # display one page, also handles expanded pages
	head {
	  title $name
	  cgi_http_equiv Expire "Mon, 04 Dec 1999 21:29:02 GMT"
	  if {$N != "2" && [info exists ::env(WIKIT_BASE)]} {
	    cgi_base href=$::env(WIKIT_BASE)
	  }
	}
        cgi_body bgcolor=#ffffff {
          cgi_puts [h2 $Title]
      
          if {$N == 2} {
            isindex
          }
          
          eval $showScript
        
          hr noshade
          cgi_puts $menu
      
	  if {[info exists ::htmlcopy]} { saveCopy $N } ;# 1-5-2001
        }
      }
    }
  }
}
