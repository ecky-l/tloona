# Sugar - a macro system for Tcl
# Copyright (C) 2004 Salvatore Sanfilippo
# Under the same license as Tcl version 8.4

### Changes
#
# 25Mar2004 - Added support for unique identifiers (sugar::uniqueName).
# 25Mar2004 - Now macros can specify a list of arguments instead of
#             a unique argument that will receive a list. For old behaviour
#             just use 'args'.
# 24Mar2004 - Modified the tailcal_proc transformer to use [foreach] for
#             multiple assignments instead to create temp vars. Thanks
#             to Richard Suchenwirth for the suggestion.

### TODO
#
# - better macro error reporting (line numbers).
# - call the macro system recursively for variable expansions?
#   this allows to expand syntax that have to deal with
#   variables interpolated inside other strings. (probably not).
# - Write a better macro for [switch] using sugar::scriptToList.
# - Write a macro that convert a subset of Tcl to critcl.
# - sugar::interleaveSpace should remove spaces before the first
#   element of type TOK from the original parsed command.
#   This is not needed for simple macro expansion because the
#   sugar::expand function does this automatically, but it's needed
#   when playing raw with the output of sugar::scriptToList.
# - Investigate on indentation changes with the tailrec macro
#   (DONE: Fixed thanks to another related bug found by NEM).
# - An API to provide unique variable names for macro expansions.

package provide sugar 0.1

namespace eval sugar {}
namespace eval sugar::macro {}
namespace eval sugar::syntaxmacro {}
namespace eval sugar::transformermacro {}

# An incremental id used to create unique identifiers.
set sugar::unique_id 0

# This global variable contains the name of the procedure being
# expanded.
set sugar::currentprocedure {}

# Return the fully-qualified name of the current procedure.
proc sugar::currentProcName {} {
    return $sugar::currentprocedure
}

# Return the "tail" of the current procedure name.
proc sugar::currentProcTail {} {
    namespace tail $sugar::currentprocedure
}

# Return the namespace of the current procedure name.
proc sugar::currentProcNamespace {} {
    namespace qualifiers $sugar::currentprocedure
}

# Return an unique identifier that macros can use as variable/proc names.
proc sugar::uniqueName {} {
    set id [incr sugar::unique_id]
    return __sugarUniqueName__$id
}

# Initialize the state of the interpreter.
# Currently this parser is mostly stateless, it only needs
# to save the type of the last returned token to know
# if something starting with '#' is a comment or not.
proc sugar::parserInitState statevar {
    upvar $statevar state
    set state [list EOL]
}

# The parser. It does not discard info about space and comments.
# The return value is the "type" of the token (EOF EOL SPACE TOKEN).
#
# It may be interesting to note that this is half of a simple
# Tcl interpreter. variable expansions is ignored, while command
# expansion is performed expanding macros if needed.
#
# The fact that it is still so simple, compared to what it can
# be in Python just to say one (much worst in Perl), it's an advice
# that to add syntax to Tcl is a bad idea.
proc sugar::parser {text tokenvar indexvar statevar {dosubst 0}} {
    upvar $tokenvar token $indexvar i $statevar state
    set token {}
    set inside {}
    set dontstop $dosubst
    while 1 {
	# skip spaces
	while {!$dontstop && [string match "\[ \t\]" [string index $text $i]]} {
	    append token [string index $text $i]
	    incr i
	}
	# skip comments
	if {$state eq {EOL} && !$dontstop && [string equal [string index $text $i] #]} {
	    while {[string length [string index $text $i]] &&
	          ![string match [string index $text $i] \n]} \
	    {
		append token [string index $text $i]
		incr i
	    }
	}
	# return a SPACE token if needed
	if {[string length $token]} {return [set state SPACE]}
	# check for special conditions
	if {!$dontstop} {
	    switch -exact -- [string index $text $i] {
		{} {return [set state EOF]}
		{;} -
		"\n" {
		    append token [string index $text $i]
		    incr i
		    return [set state EOL]
		}
	    }
	}
	# main parser loop
	while 1 {
	    switch -exact -- [string index $text $i] {
		{} break
		{ } -
		"\t" -
		"\n" -
		";" {
		    if {!$dontstop} {
			break;
		    }
		}
		\\ {
		    incr i
		    append token \\ [string index $text $i]
		    incr i
		    continue
		}
		\" {
		    if {[string equal $inside {}]} {
			incr dontstop
			set inside \"
			append token \"
			incr i
			continue
		    } elseif {[string equal $inside \"]} {
			incr dontstop -1
			set inside {}
			append token \"
			incr i
			continue
		    }
		}
		"\{" {
		    if {[string equal $inside {}]} {
			incr dontstop
			set inside "\{"
			append token "\{"
			incr i
			continue
		    } elseif {[string equal $inside "\{"]} {
			incr dontstop
		    }
		}
		"\}" {
		    if {[string equal $inside "\{"]} {
			incr dontstop -1
			if {$dontstop == 0} {
			    set inside {}
			    append token "\}"
			    incr i
			    continue
			}
		    }
		}
		\$ {
		    if {![string equal $inside "\{"]} {
			if {![string equal [string index $text [expr {$i+1}]] $]} {
			    set res [LctSubstVar $text i]
			    append token "$$res"
			    continue
			}
		    }
		}
		\[ {
		    if {![string equal $inside "\{"]} {
			set res [LctSubstCmd $text i]
			append token "\[$res\]"
			continue
		    }
		}
	    }
	    append token [string index $text $i]
	    incr i
	}
	return [set state TOK]
    }
}

# Actually does not really substitute commands, but
# exapands macros inside.
proc LctSubstCmd {text indexvar} {
    upvar $indexvar i
    set go 1
    set cmd {}
    incr i
    while {$go} {
	switch -exact -- [string index $text $i] {
	    {} break
	    \[ {incr go}
	    \] {incr go -1}
	}
	append cmd [string index $text $i]
	incr i
    }
    set cmd [string range $cmd 0 end-1]
    return [::sugar::expand $cmd]
}

# Get the control when a '$' (not followed by $) is encountered,
# extract the name of the variable, and return it.
proc LctSubstVar {text indexvar} {
    upvar $indexvar i
    set dontstop 0
    set varname {}
    incr i
    while {1} {
	switch -exact -- [string index $text $i] {
	    \[ -
	    \] -
	    "\t" -
	    "\n" -
	    "\"" -
	    \; -
	    \{ -
	    \} -
	    \$ -
	    ( -
	    ) -
	    { } -
	    "\\" -
	    {} {
		if {!$dontstop} {
		    break
		}
	    }
	    ( {incr dontstop}
	    ) {incr dontstop -1}
	    default {
		append varname [string index $text $i]
	    }
	}
	incr i
    }
    return $varname
}

# Return the number of lines in a string
proc countlines {string} {
    llength [split $string "\n"]
}

# interleave SPACE and EOL tokens in a Tcl list $tokens
# representing a command. Also every token is
# converted to the two-elements list representation
# with type TOK.
#
# The $origargv list is the output of the parser
# for that command, and is used by interleaveSpaces
# to make the indentation of the expanded macro as
# similar as possible to what the used typed in the source
# code.
proc sugar::interleaveSpaces {tokens origargv} {
    set newargv {}
    for {set j 0} {$j < [llength $tokens]} {incr j} {
	lappend newargv [list TOK [lindex $tokens $j]]
	set idx [::sugar::indexbytype $origargv SPACE $j]
	if {$idx == -1} {
	    lappend newargv [list SPACE " "]
	} else {
	    # If possible, try to use the same argument
	    # separator as the user typed it.
	    lappend newargv [lindex $origargv $idx]
	}
    }
    # Use the same EOL string. That's always possible
    if {![llength $newargv]} {
	set newargv [list ";"]
    }
    lset newargv end [lindex $origargv end]
    return $newargv
}

# Tranform a script to a list of lists, where every list is
# a command, and every element of the list is an argument,
# and is itself a two elements of list. The first element
# is the token type, the second the toke value. The following
# toke types are defined.
#
# SPACE - Spaces, non significative for the execution, just separate arguments.
# TOK   - Any significative token. The first element of type TOK is
#         the command name.
# EOL   - End of line.
#
# This function is intended to be used directly or indirectly by macro,
# that will do the processing, and then call listToScript to convert
# it back in script.
#
# Macros may want to call sugar::tokens for every command to work
# more comfortably with it, and than reconvert to the
# original format with sugar::interleaveSpaces.
#
# ----------------------------------------------------------------------
# In theory sugar::expand should be modified to directly use this
# instead of a local copy of almost the same code. They are actually
# a bit different because sugar::expand does the processing for every
# command, not in the entire script at once.
proc sugar::scriptToList script {
    set i 0
    set result {}
    ::sugar::parserInitState parserState

    set eof 0
    while 1 {
	set command {}
	while 1 {
	    set type [::sugar::parser $script token i parserState]
	    switch $type {
		EOF {lappend command [list EOL {}]; set eof 1; break}
		default {
		    lappend command [list $type $token]
		    if {$type eq {EOL}} break
		}
	    }
	}
	lappend result $command
	if {$eof} break
    }
    return $result
}

# That's really trivial ;)
# The macro specification should guarantee that the list
# is transformed into the source code by simple concatenation
# of all the tokens.
proc sugar::listToScript list {
    set result {}
    foreach c $list {
	foreach t $c {
	    append result [lindex $t 1]
	}
    }
    return $result
}

# Return true if the named macro exists, and store in macroName var
# the fully qualified name of the procedure in charge to do expansion for it.
proc sugar::lookupMacro {macroname procnameVar} {
    upvar 1 $procnameVar procname
    if {[catch {info args ::sugar::macro::__macroproc__$macroname}]} {
	return 0
    }
    set procname ::sugar::macro::__macroproc__$macroname
    return 1
}

# Macro expansion. It trys to take indentation unmodified.
proc sugar::expand script {
    while 1 {
	set eof 0
	set i 0
	set result {}
	::sugar::parserInitState parserState
	while {!$eof} {
	    set argv {}
	    set argc 0
	    # Collect a command in $argv. Every token is a two-elements
	    # List with the token type and value, as returned by expr.
	    # Significative tokens are interleaved with space tokens:
	    # syntax  macros will have a way to know how arguments where
	    # separated.
	    while 1 {
		set type [::sugar::parser $script token i parserState]
		if {[string equal $type EOF]} {
		    set eof 1
		}
		switch $type {
		    EOF {lappend argv [list EOL {}]; break}
		    default {
			if {$type eq {SPACE} && $argc == 0} {
			    append result $token
			} else {
			    lappend argv [list $type $token]
			    incr argc
			    if {$type eq {EOL}} break
			}
		    }
		}
	    }
	    # Call macros for this statement
	    if {[lindex $argv 0 0] ne {EOL}} {
		# Check if there is a macro defined with that name
		set cmdname [lindex $argv 0 1]
		# Call the macro associated with that command name, if any.
		if {[sugar::lookupMacro $cmdname expander]} {
		    #puts "executing macro for $cmdname in procedure [::sugar::currentProcName]"
		    if {[catch {set tokens [eval $expander [::sugar::tokens $argv]]} errstr]} {
			error "Macro '$cmdname' expansion error in procedure '$::sugar::currentprocedure': $errstr" $::errorInfo
		    }
		    set argv [::sugar::interleaveSpaces $tokens $argv]
		}
		# Call all the syntax macros. For now in random order.
		foreach syntaxmacro [info command ::sugar::syntaxmacro::__macroproc__*] {
		    set argv [::sugar::interleaveSpaces [eval $syntaxmacro [::sugar::tokens $argv]] $argv]
		}
	    }
	    foreach arg $argv {
		append result "[lindex $arg 1]"
	    }
	}
	# Call all the transformer macros. For now in random order.
	# TODO: consider if it's better to move this as first
	# transformation.
	foreach trmacro [info command ::sugar::transformermacro::__macroproc__*] {
	    set list [::sugar::scriptToList $result]
	    set list [$trmacro $list]
	    set result [::sugar::listToScript $list]
	}
	# Reiterate if needed, otherwise exit.
	if {[string equal $script $result]} break
	#puts "AFTER:  '$script'"
	#puts "BEFORE: '$result'"
	#puts "---"
	set script $result
    }
    return $result
}

# Return the index of the $num-Th element of type $type in a list
# of tokens.
proc ::sugar::indexbytype {argv type num} {
    set idx 0
    foreach a $argv {
	foreach {t _} $a break
	if {$type eq $t} {
	    if {!$num} {
		return $idx
	    }
	    incr num -1
	}
	incr idx
    }
    return -1
}

# Wrapper for [proc] that expands macro in the body
# TODO: add a switch -nomacro to avoid macro expansion
# for the given procedure.
proc sugar::proc {name arglist body} {
    # Get the fully qualified name of the proc
    set ns [uplevel [list namespace current]]
    # If the proc call did not happen at the global context and it did not
    # have an absolute namespace qualifier, we have to prepend the current
    # namespace to the command name
    if { ![string equal $ns "::"] } {
	if { ![string match "::*" $name] } {
	    set name "${ns}::${name}"
	}
    }
    if { ![string match "::*" $name] } {
	set name "::$name"
    }

    set oldprocedure $::sugar::currentprocedure
    set ::sugar::currentprocedure $name
    # puts "+ $name"
    set body [::sugar::expand $body]
    # Call the real [proc] command.
    uplevel 1 [list ::proc $name $arglist $body]
    set ::sugar::currentprocedure $oldprocedure
    return
}

# Number of tokens of type TOK. Useful for arity checking in macros.
proc sugar::tokensnum argv {
    set c 0
    foreach a $argv {
	if {[lindex $a 0] eq {TOK}} {
	    incr c
	}
    }
    return $c
}

# Return values of all the tokens of type TOK as a list.
proc sugar::tokens argv {
    set tokens {}
    foreach a $argv {
	if {[lindex $a 0] eq {TOK}} {
	    lappend tokens [lindex $a 1]
	}
    }
    return $tokens
}

# Define a new macro
proc sugar::macro {names arglist body} {
    foreach name $names {
	uplevel 1 [list ::proc ::sugar::macro::__macroproc__$name $arglist $body]
    }
}

# Define a new syntax macro
proc sugar::syntaxmacro {name arglist body} {
    uplevel 1 [list ::proc ::sugar::syntaxmacro::__macroproc__$name $arglist $body]
}

# Define a new transformer macro
proc sugar::transformermacro {name arglist body} {
    uplevel 1 [list ::proc ::sugar::transformermacro::__macroproc__$name $arglist $body]
}

# That's used to create macros that expands arguments that are
# scripts. This kind of macros are used for [while], [for], [if],
# and so on.
proc sugar::expandScriptToken tok {
    set t [lindex $tok 0]
    set res [::sugar::expand $t]
    if {[string equal $t $res]} {
	return $tok
    } else {
	list $res
    }
}

# Macro substitution. Like [subst] but for macros.
proc sugar::dosubst string {
    sugar::parserInitState state
    set idx 0
    sugar::parser $string result idx state 1
    return $result
}

# Expand Expr's expressions. Try to don't mess with quoting.
proc sugar::expandExprToken tok {
    set quoted 0
    if {[string index $tok 0] == "\{" && [string index $tok end] == "\}"} {
	set quoted 1
	set tok [string range $tok 1 end-1]
    }
    set tok [sugar::dosubst $tok]
    if {$quoted} {
	set tok "{$tok}"
    }
    return $tok
}

# Get the N-th element with type $type from the list of tokens.
proc sugar::gettoken {argv type n} {
    set idx [::sugar::indexbytype $argv $type $n]
    if {$idx == -1} {
	error "bad index for gettoken (wrong number of args for macro?)"
    }
    lindex $argv $idx 1
}

# Set the N-th $type element in the list of tokens to the new $value.
proc sugar::settoken {argvVar type n value} {
    upvar $argvVar argv
    set idx [::sugar::indexbytype $argv $type $n]
    if {$idx == -1} {
	error "bad index for gettoken (wrong number of args for macro?)"
    }
    lset argv $idx 1 $value
}

################################################################################
# Macros to allow macros inside conditionals, loops and other Tcl commands
# that accept scripts or [expr] expressions as arguments.
################################################################################

sugar::macro while args {
    lset args 1 [sugar::expandExprToken [lindex $args 1]]
    lset args 2 [sugar::expandScriptToken [lindex $args 2]]
}

sugar::macro foreach args {
    lset args end [sugar::expandScriptToken [lindex $args end]]
}

sugar::macro time args {
    lset args 1 [sugar::expandScriptToken [lindex $args 1]]
}

sugar::macro if args {
    lappend newargs [lindex $args 0]
    lappend newargs [sugar::expandExprToken [lindex $args 1]]
    set args [lrange $args 2 end]
    foreach a $args {
	switch -- $a {
	    else - elseif {
		lappend newargs $a
	    }
	    default {
		lappend newargs [sugar::expandScriptToken $a]
	    }
	}
    }
    return $newargs
}

sugar::macro for args {
    lset args 1 [sugar::expandScriptToken [lindex $args 1]]
    lset args 3 [sugar::expandScriptToken [lindex $args 3]]
    lset args 4 [sugar::expandScriptToken [lindex $args 4]]
    return $args
}

# That's still not perfect because messes with indentation.
# Should use new scriptToList API to do it better.
sugar::macro switch args {
    lappend result [lindex $args 0]
    set idx 0
    set isquoted 0
    while 1 {
	incr idx
	set arg [lindex $args $idx]
	if {$arg eq {--}} {
	    lappend result $arg
	    incr idx
	    break
	}
	if {[string index $arg 0] ne {-}} break
	lappend result $arg
    }
    lappend result [lindex $args $idx]
    incr idx
    # Handle the two forms in two different ways
    if {[llength $args]-$idx == 1} {
	set l [lindex $args $idx 0]
	set isquoted 1
    } else {
	set l [lrange $args $idx end]
    }
    # Expand scripts inside
    set temp {}
    foreach {pattern body} $l {
	if {$body ne {-}} {
	    if {$isquoted} {
		set body [lindex [sugar::expandScriptToken [list $body]] 0]
	    } else {
		set body [sugar::expandScriptToken $body]
	    }
	}
	lappend temp $pattern $body
    }
    # Requote it if needed.
    if {$isquoted} {
	return [concat $result [list [list $temp]]]
    } else {
	return [concat $result $temp]
    }
}

################################################################################
# Transformers included in sugar
################################################################################

################ a macro for tail recursion ##############
# TODO: give a name to this kind of macros, and maybe provide
# a function to 'encapsulate' the common part of this
# kind of macros involving the redefinition of proc.
proc sugar::tailrecproc {name arglist body} {
    # Convert the script into a Tcl list
    set l [sugar::scriptToList $body]
    # Convert tail calls
    set l [sugar::tailrec_convert_calls $name $arglist $l]
    # Add the final break
    lappend l [list {TOK break} {EOL "\n"}]
    # Convert it back to script
    set body [sugar::listToScript $l]
    # Add the surrounding while 1
    set body "while 1 {$body}"
    # Call [proc]
    uplevel ::proc [list $name $arglist $body]
}

# Convert tail calls. Helper for tailrec_proc.
# Recursively call itself on [if] script arguments.
proc sugar::tailrec_convert_calls {name arglist code} {
    # Search the last non-null command.
    set lastidx -1
    for {set j 0} {$j < [llength $code]} {incr j} {
	set cmd [lindex $code $j]
	if {[sugar::indexbytype $cmd TOK 0] != -1} {
	    set lastidx $j
	    set cmdidx [sugar::indexbytype $cmd TOK 0]
	}
    }
    if {$lastidx == -1} {
	return $code
    }
    set cmd [lindex $code $lastidx]
    set cmdname [lindex $cmd $cmdidx 1]
    if {[lindex $cmd 0 0] eq {SPACE}} {
	set space [lindex $cmd 0 1]
    } else {
	set space " "
    }
    if {$cmdname eq $name} {
	#puts "TAILCALL -> $cmdname"
	set recargs [lrange [sugar::tokens $cmd] 1 end]
	set t [list [list SPACE $space] [list TOK foreach] [list SPACE " "]]
	lappend t [list TOK "\[list "]
	foreach a $arglist {
	    lappend t [list TOK $a] [list SPACE " "]
	}
	lappend t [list TOK "\] "]
	lappend t [list TOK "\[list "]
	foreach a $recargs {
	    lappend t [list TOK $a] [list SPACE " "]
	}
	lappend t [list TOK "\] "]
	lappend t [list TOK break] [list EOL "\n"]
	set code [linsert $code $lastidx $t]
	incr lastidx
	lset code $lastidx [list [list SPACE $space] [list TOK continue] [list EOL "\n"]]
    } elseif {$cmdname eq {if}} {
	#puts "IF CALL"
	for {set j 0} {$j < [llength $cmd]} {incr j} {
	    if {[lindex $cmd $j 0] ne {TOK}} continue 
	    switch -- [lindex $cmd $j 1] {
		if - elseif {
		    incr j 2
		}
		else {
		    incr j 1
		}
		default {
		    set script [lindex $code $lastidx $j 1]
		    #puts "$j -> $script"
		    set scriptcode [sugar::scriptToList [lindex $script 0]]
		    set converted [sugar::tailrec_convert_calls $name $arglist $scriptcode]
		    lset code $lastidx $j 1 [list [sugar::listToScript $converted]]
		}
	    }
	}
    }
    return $code
}
