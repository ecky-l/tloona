# Formatter for wiki markup text, CGI as well as GUI

package provide Wikit::Format 1.0

namespace eval Wikit::Format {
  namespace export TextToStream StreamToTk StreamToHTML StreamToRefs
  
# In this file:
#
# proc TextToStream {text} -> stream   
# proc StreamToTk {stream infoProc} -> {{tagged-text} {urls}}   
# proc StreamToHTML {stream cgiPrefix infoProc} -> {{html} {urls}}
# proc StreamToRefs {stream infoProc} -> {pageNum ...}
#
# The "Text" format is a Wiki-like one you can edit with a text editor.
# The "Tk" format can insert styled text information in a text widget.
# The "HTML" format is the format generated for display by a browser.
# The "Refs" format is a list with details about embedded references.
# The "Stream" format is a Tcl list, it's only used as interim format.

proc FixupRE {re} {
  regsub -all {\\t} $re \t re
  regsub -all {\\s} $re \ \t re
  return $re
}

  # a set of regular expressions used to categorize line types
variable lineCategories ""

  # Note that all RE's below have exactly five (), sometimes empty
  # This ensures that all variables are set to something.

foreach {type re} {
  H {^(----+)()()()()$}
  U {^((   |\t)[\s]*)\* (.*)()()$}
  O {^((   |\t)[\s]*)[1-9]\. (.*)()()$}
  D {^((   |\t)[\s]*)([^\t:]+):(   |\t)[\s]*(.+)$}
  Q {^([\s]+)(.+)()()()$}
  T {^(.+)()()()()$}
} {
  lappend lineCategories $type [FixupRE $re]
}

  # Here is the mapping of information to variables
  # This mapping is reelevant for the state machine.

  # H = hrule ....... a1 = rule text, a2 ... a5 are empty.
  # U = itemized .... a1 = full prefix, a2 = space prefix, a3 = text, a4 ... a    # O = enumerated .. s.a.
  # D = term ........ a1 = full prefix, a2 = space prefix, a3 = term, a4 = spa    # Q = quote ....... a1 = prefix, a2 = line, a3 ... a5 empty
  # T = text ........ a1 = text, a2 ... a5 empty
  # $ = closing tag . a1 ... a5 empty


  # works in reverse, skipping as far as possible before matching
variable urlRE [FixupRE {(.*[]['\-\*\s]|^)(https?|ftp|news|mailto|image):([^[\s:]+[^[\s\.,!\?;:'>])(.*)}]

proc ParseURLs {text} {
  # Convert urls into a generating command.
  variable urlRE
  
  set result ""
  while {[regexp $urlRE $text all text a2 a3 a4]} {
    set result "\[=u [QuoteItem $a2:$a3]\]$a4$result"
  }
  append text $result
}

proc FixParseItem {a} {
  regsub -all {\]} $a {[=r]} a
  regsub -all !C $a {[=r]} a
  regsub -all !B $a {]} a
  regsub -all !A $a ! a
  return $a
}

variable refRE [FixupRE {^[-_\.,/'a-zA-Z0-9 \t!\(\):]+$}]

proc QuoteItem {s} {
  set r [list $s]
  if {$r == $s} {
    return "{$s}"
  }
  return $r
}

proc ParseRefs {a} {
  # Look for and convert wiki internal references
  variable urlRE
  variable refRE
  
  regsub -all ! $a !A a
  regsub -all {\[\[} $a !Q a
  regsub -all {([^\]]*)\]\]} $a {\1!C} a

  set first 1
  set buf ""
  foreach b [split $a \[] {
    regsub -all !Q $b {[=l!B} b
    
    if {$first} {
      set first 0
      set buf [FixParseItem $b]
      continue
    }
    
    if {[regexp {^([^]]+)\](.*)$} $b x ref tail]} {
      if {[regexp $urlRE $ref all a1 a2 a3 a4] && $a1 == "" && $a4 == ""} {
        set b "\[=x [QuoteItem $a2:$a3]!B$tail"
      } elseif {[regexp $refRE $ref]} {
        set b "\[=g [QuoteItem $ref]!B$tail"
      }
    } else {
      append buf {[=l]}
    }
    
    append buf [FixParseItem $b]
  }
  
  return $buf
}

proc TextToScript {text} {
  # Breaks the wiki markup contained in text into lines, categorizes
  # them and then uses [Process] to convert them into a tcl script
  # according to their category. The conversion is implicitly driven
  # by a finite state machine / virtual processor where line
  # categories are instructions.

  # The resulting script contains the folllowing commands:
  #
  # =T text     | simple text
  # =l          | left bracket
  # =r          | right bracket
  # =s          | backslash
  # =o          | left brace (open)
  # =c          | right brace (close)
  # =b text     | bold
  # =i text     | italic
  # =H          | horizontal rule
  # =U text     | unordered item
  # =O text     | enumerated item
  # =D term def | definition item
  # =Q text     | verbatim text
  # =u url      | url in text
  # =x url      | bracketed url in text [url]
  # =g name     | page reference
  #

  variable lineCategories
  variable state
  variable buffer
  
  set result ""
  set state ^
  set buffer ""
  set lines 0
  
  foreach line [split $text \n] {
    if {[string trim $line] == ""} {incr lines; continue}    
     
    foreach {type re} $lineCategories {
      if {[regexp $re $line all a1 a2 a3 a4 a5]} {
        break
      }
    }
        
    append result [Process $a1 $a2 $a3 $a4 $a5 $type $lines]
    set lines 0
  }
  
  append result [Process "" "" "" "" "" \$ $lines]
}

variable FSM_Commands

  # Defined behaviour for the various categories
  #
  # H .. Close preceding text, add rule command
  # U .. s.a., prep. new chunk, add item command
  # O .. s.a.
  # D .. s.a. prep. 2 chunks, add item command
  # Q .. s.a., prep. verbatim chunk!
  # T .. Close text, if more than one line, prepare new chunk, and add to text    # $ .. s.a.,

array set FSM_Commands {
  ^ {                 }
  H {t -      e {=H}        }
  U {t -  h a3  e {=U [list $a3]}    }
  O {t -  h a3  e {=O [list $a3]}    }
  D {t -  h a3 h a5 e {=D [list $a3] [list $a5]}  }
  Q {t -  u a2  e {=Q [list $a1$a2]}   }
  T {p -  h a1  c -         }
  $ {t -                }
}

proc Process {a1 a2 a3 a4 a5 next lines} {
  # Helper for [TextToScript] above. Contains the logic to access
  # the state machine driving the converion.

  # "next" is actually the category of the current line, and a1 ...
  # a5 contain the various elements of said line.

  variable state
  variable FSM_Commands
  variable buffer
  
  set result ""
  
  # For each category the FSM is driven through a sequence of
  # micro-operations. IOW this can also be seen as a simple virtual
  # processor whose instructions (line categories) are translated
  # into micro code doing the actual work.

  foreach {cmd arg} $FSM_Commands($next) {
  
    switch $cmd {
    
      p {
	# Close simple text if more than one line was
	# collected so far. Add generator command to result.
        if {$lines > 0 && $buffer != ""} {
          append result "=T [list $buffer]\n"
          set buffer ""
        }
      }
      
      t {
	# Close simple text and append to result.
        if {$buffer != ""} {
          append result "=T [list $buffer]\n"
          set buffer ""
        }
      }
      
      u {
	# Verbatim chunk of text. Escape special characters
	# with generation commands.

        if {$lines != 0} { append result "=Q {}\n" }
        
        set a [string trimright [set $arg]]
        regsub -all ! $a !A a
        regsub -all {\[} $a {[=l!B} a
        regsub -all {\]} $a {[=r]} a
        regsub -all \\\\ $a {[=s]} a
        regsub -all {\{} $a {[=o]} a
        regsub -all {\}} $a {[=c]} a
        regsub -all !B $a {]} a
        regsub -all !A $a ! a
        set $arg [ParseURLs $a]
      }
      
      h {
	# Markup references (wiki, external) in block of text,
	# convert visual markup too.
        set a [ParseRefs [set $arg]]
        set a [ParseURLs $a]
          # a horrendous hack to emulate non-greedy regexps
        regsub -all {'''([^']+('?'?[^']+)?)'''} $a {[=b {\1}]} a
        regsub -all {''([^']+('?[^']+)?)''} $a {[=i {\1}]} a
        set $arg $a
      }
      
      c {
	# Add text to the buffer where we collect simple text.
        set a1 [string trim $a1]
        if {$a1 != ""} {
          if {$buffer != ""} {
            append buffer " "
          }
          append buffer $a1
        }
      }
      
      e {
        append result "[subst $arg]\n"
      }
    }
  }
  
  set state $next
    
  return $result
}

proc EmitText {type body} {
  # Helper command. Used in the definition of generation
  # commands. The "type" is the name of the generation command
  # without the prefixed "=".

  # Appends tag and pertaining text to the output stream of tokens.
  # Recursively executes the generation commands found in the text
  # associated with a tag.

  variable vec
  variable stream
  
  set keep $vec
  
  if {![string match {[A-Z]} $type]} {
    if {$type != "-"} {
      lappend vec $type 
    }
    set type ""
  }

  set mode [join [lsort $vec] ""]
  
  if {[regexp {^([^[]*)(\[.+])(.*)$} $body x a b c]} {
    if {$a != "" || $type != ""} {lappend stream $type$mode $a}
    subst -nobackslash -novariable $b
    if {$c != ""} {lappend stream $mode $c}
  } else {
    lappend stream $type$mode $body
  }

  set vec $keep
}

# The second stage of the conversion. Uses TextToStream to get a
# script of generation commands and evaluates this script to get a
# list data structure.

# NOTE: The =... procedures are always the same and should be moved
# outside [TextToStream]. This avoids their repeated definition and
# should make text to stream faster.

# NOTE 2: Given the exact data structure we generate I believe that it
# makes sense to skip the step with the generation of a script and use
# a FSM/virtual processor like in TextToScript to generate the
# structure directly.

proc TextToStream {text} {
  variable vec
  variable stream

  foreach type {U O T Q b i g u x} {
    proc =$type {a} "EmitText $type \$a"
  }
  
  proc =D {a b} {
    EmitText I $a
    EmitText D $b
  }
  
  proc =X {a} {EmitText "" $a}
  proc =H {} {EmitText H -}
  proc =l {} {EmitText l (}
  proc =r {} {EmitText r )}
  proc =s {} {EmitText s \\}
  proc =o {} {EmitText "" \{}
  proc =c {} {EmitText "" \}}
  
  set script [TextToScript $text]

  # This regex grabs all text outside of generation commands and
  # wraps them into a command too (=X) so that everything is in a
  # command. This usually pertains to text inside of the argument of
  # an item command as such text can be bounded by commands for
  # references and visual markup.

  regsub -all {]([^\{\}[]+)\[} $script {][=X {\1}][} script
  set vec ""
  set stream ""
  
  eval $script
           
  # The generated stream has the following format:
  #
  #    tag1 text1 tag2 text2 ...
  #
  # where tagX applies to the text immediately following it.
  #
  # The tags are the generation command, without their prefix
  # character, i.e. without "=".

  return $stream
}

# Output specific conversion. Takes a token stream and converts this
# into a series of commands for a tk text widget. The result is a
# 2-element list. The first element is a script which when executed
# adds all relevant text (and text tags) to a text widget. The second
# element is alist of triplets listing all references found in the
# stream (each triplet consists reference type, page-local numeric id
# and reference text).

proc StreamToTk {s {ip ""}} {
  set urls ""
  set result ""
  set state ""
  set count 0
  set number 0
  set xcount 0
  
  array set stateNames {
    T body
    Q fixed
    H thin
    U ul
    O ol
    I dt
    D dl
  }
  
  foreach {mode text} $s {

    if {[string first $mode "HUOIDQT"] >= 0} {

        # work around a flaw in the above text to stream logic
      if {$mode == "Q" && $state == "T" && $text == ""} continue
      
      set text "\n$text"

      if {$mode == "D"} { 
        set state D
      }
      
      if {$mode != $state} {
        set number 0
        if {[string first $state$mode "UT DT IT OT QT TU TD TI TO TQ"] >= 0 ||
            $state == "Q" || $mode == "Q"} {
          set text "\n$text" 
        }
      } elseif {$mode == "T"} {
        set text "\n$text"
      }
      
      set state $mode

      switch $mode {
        H {
            lappend result \n\n body "\t" {hr thin} \n thin
            continue
          }
        U { regsub "\n(\[^\n\]|$)" $text "\n   *\t\\1" text }
        O { regsub "\n(\[^\n\]|$)" $text "\n   [incr number].\t\\1" text }
      }
      
      set tags $stateNames($state)
    
    } else { 
    
      set tags $stateNames($state)

      if {[string first l $mode] >= 0} {
        set text \[ 
      }
      if {[string first r $mode] >= 0} {
        set text \] 
      }
      
      if {[string match *b*i* $mode]} {
        lappend tags bi 
      } else {
        if {[string first i $mode] >= 0} { 
          lappend tags i 
        }
        if {[string first b $mode] >= 0} { 
          lappend tags b 
        }
      }
      
      if {[string first g $mode] >= 0} {
        set n [incr count]
        lappend tags url g$n
        lappend urls g $n $text
        
        if {$ip != ""} {
          set info [lindex [$ip $text] 2]
          if {$info == "" || $info == 0} {
            lappend result \[ $tags $text body \] $tags
            set text ""
          }
        }
      }
      if {[string first u $mode] >= 0} {
        set n [incr count]
        lappend tags url u$n
        lappend urls u $n $text
      }
      if {[string first x $mode] >= 0} {
        if {[regexp "image:(.+)" $text all imagefile]} {
            # lappend urls x $n $text
        } else {
            set n [incr xcount]
            lappend tags url x$n
            lappend urls x $n $text
            lappend result \[ body $n $tags \] body
        }
        set text ""
      }
    }

    if {$text != ""} {
      lappend result $text $tags
    }
  }
  
  list [lappend result "" body] $urls
}

# Output specific conversion. Takes a token stream and converts this
# into HTML. The result is a 2-element list. The first element is the
# HTML to render. The second element is alist of triplets listing all
# references found in the stream (each triplet consists reference
# type, page-local numeric id and reference text).

proc StreamToHTML {s {cgi ""} {ip ""}} {
  set urls ""
  set result ""
  set state ""
  set after ""
  set count 0
  
  foreach {mode text} $s {
    set q $text
    regsub -all {&} $q {\&amp;} q
    regsub -all {"} $q {\&quot;} q
    regsub -all {<} $q {\&lt;} q
    regsub -all {>} $q {\&gt;} q
    
    if {[string first $mode "HUOIDQT"] >= 0} {

      append result \n 

      if {$mode == "D"} { 
        set state D
        append result "  <dd>" 
      }
      
      if {$mode != $state && "$state$mode" != "DI"} {
        append result $after
        set after ""
        
        foreach {match start finish} {
          Q "<pre>"   "</pre>\n"
          U "<ul>\n"  "</ul>\n"
          O "<ol>\n"  "</ol>\n"
          I "<dl>\n"  "</dl>\n"
        } {
          if {$mode == $match} {
            append result $start
            set after $finish
          }
        }
      } elseif {$mode == "T"} {
        append result "<p>\n"
      }
      
      switch $mode {
        H { append result "<hr size=1>"; set q "" }
        U { append result " <li>" }
        O { append result " <li>" }
        I { append result " <dt>" }
      }
      
      set state $mode

      append result $q
    
    } else { 
    
      set pre ""
      set post ""
      
      if {[string first l $mode] >= 0} {
        set q \[ 
      }
      if {[string first r $mode] >= 0} {
        set q \] 
      }
      if {[string first g $mode] >= 0} {
        lappend urls $text g
        
        if {$cgi != ""} {
          if {$ip != ""} {
            set info [$ip $text]
            foreach {id name date} $info break
            if {$id != ""} {
	      regsub {^/} $id {} id
              if {$date > 0} { # exists, use ID
                set pre "<a href=\"$id\">$pre"
                append post </a>
              } else { # missing, use ID
                set pre "<a href=\"$id\">\[</a>$pre"
                append post "<a href=\"$id\">\]</a>"
              }
            } else { # not found, don't turn into an URL
              set pre "\[$pre"
              append post \]
            }
          } else { # no lookup, turn into a search arg
            set pre "<a href=\"$cgi$text\">$pre"
            append post </a>
          }
        } else { # cannot turn into an URL
          set pre "\[$pre"
          append post \]
        } 
      }
      if {[string first u $mode] >= 0} {
    lappend urls $text u
    set pre "<a href=\"$q\">$pre"
    append post </a> 
      }
      if {[string first x $mode] >= 0} {
    if {[regexp {\.(gif|jpg|png)$} $q]} {
      append pre "<img src=\""
      set post "\">$post"
    } else {
      set pre "\[<a href=\"$q\">$pre"
      append post </a>\]
      set q [incr count]
      lappend urls $text $q
    }
      }
      if {[string first i $mode] >= 0} { 
        set pre <i>$pre
        append post </i> 
      }
      if {[string first b $mode] >= 0} { 
        set pre <b>$pre
        append post </b> 
      }
      
      append result $pre $q $post 
    }
  }
  
  list [append result $after] $urls
}

# Output specific conversion. Extracts all wiki internal page
# references from the token stream and returns them as a list of page
# id's.

proc StreamToRefs {s ip} {
  array set pages {}
  
  foreach {mode text} $s {
    if {[string first g $mode] >= 0} {
      set info [$ip $text]
      foreach {id name date} $info break
      if {$id != ""} {
        regexp {[0-9]+} $id id
        set pages($id) ""
      }
    }
  }
  
  array names pages
}

} ;# end of namespace
