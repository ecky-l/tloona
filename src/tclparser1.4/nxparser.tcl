package require parser 1.4
package require Itree 1.0
package require log 1.2

package require parser::script 1.0
package require parser::tcl 1.0

package provide parser::nx 1.0


catch {
    namespace import ::itcl::*
}

namespace eval ::Parser {
    namespace eval Nx {}
    
    # @v NxCoreCommands: A list of core commands for nx
    variable NxCoreCommands {
	:method
	:object
	:property
	:protected
	:public
	:variable
	Class 
	Object 
	alias
	alloc 
	copy 
	create 
	current
	destroy 
	filter 
	filterguard 
	forward 
	is 
	method 
	mixin 
	move 
	new 
	noinit 
	nx::Class
	nx::Object
	object
	recreate 
	require 
	self 
	superclass 
	volatile
    }
    
}


# @c This class represents Attribute nodes for nx. So we can
# @c distinguish them from normal variables
class ::Parser::NxAttributeNode {
    inherit ::Parser::VarNode
    
    public variable kind instance
    public variable access none
    public variable deftype variable
    public variable initblock ""

    # @v getterproc: The getter method for this attribute
    public variable getterproc {}
    # @v getterproc: The getter method for this attribute
    public variable setterproc {}
    
    constructor {args} {
        eval configure $args

	# TODO: missing icons/types
	# - private/protected/public object variables 
	#   ("class variables"/"static variables" in C++)
	# - accessor might be "none"
	# - distinguish between defype "variable" and "property"

	if {[cget -type] eq "unknown"} {
	    if {[cget -kind] eq "object"} {
		set type variable
	    } else {
		set type [cget -access]_variable
	    }
	    configure -type $type
	}
    }
}


# @c This object can deal with pre- and post assertions
class ::Parser::NxProcNode {
    inherit ::Parser::OOProcNode
    
    # @v preassertion: Code that checks pre assertion for xotcl procs
    public variable preassertion ""
    # @v postassertion: Code that checks post assertion
    public variable postassertion ""
    # @v predefoffset: byte offset for preassertion code
    public variable predefrange {}
    # @v postdefoffset: byte offset for postassertion code
    public variable postdefrange {}
    public variable kind instance
    public variable access protected
    public variable deftype scripted
    constructor {args} {
        eval configure $args
	if {[cget -type] eq "unknown"} {
	    #
	    # TODO missing: 
	    # - distinguish between deftype "scripted", "alias", and "forward"
	    # - private/protected/public object method 
	    #   ("class method"/"static method" in C++)
	    #
	    if {[cget -kind] eq "object"} {
		set type proc
	    } else {
		set type [cget -access]_method
	    }
	    configure -type $type
	}
    }
}


class ::Parser::NxClassNode {
    inherit ::Parser::ClassNode
    
    # @v slotdefinition: Definition for slots. Contains Attributes
    # @v slotdefinition: Used for parsing the attributes
    public variable slotdefinition ""
    
    constructor {args} {
        eval configure $args
    }
    
}


proc ::Parser::Nx::configClassParams {parNode clsNode cTree content slotOffPtr} {
    upvar $slotOffPtr slotOff
    set slotOff -1
    # parse the -superclass parameter and slots
    set classes {}
    set clsStr ""
    for {set i 2} {$i < [llength $cTree]} {incr i} {
        set param [::parse getstring $content [lindex [lindex $cTree $i] 1]]
	#puts stderr "nx:configClassParams <$param>"

        switch -- $param {
            -superclass {
                set classes [::parse getstring $content [lindex [lindex $cTree [incr i]] 1]]
            }
            -slots {
                incr i
                set slotOff [lindex [lindex [lindex [lindex [lindex $cTree $i] 2] 0] 1] 0]
                set slotEnd [lindex [lindex [lindex [lindex [lindex $cTree $i] 2] 0] 1] 1]
                $clsNode configure -slotdefinition [::parse getstring $content \
                    [list $slotOff $slotEnd]]
            }
        }
    }
    
    if {$classes == {}} {
        return $clsNode
    }
    
    foreach {iCls} [lindex $classes 0] {
        set nsAll [regsub -all {::} [string trimleft $iCls :] " "]
        set iCls [lindex $nsAll end]
        append clsStr ", [string trimleft $iCls :]"
        if {[llength $nsAll] > 1} {
            # parent class has namespace qualifiers
            set tn [$parNode getTopnode]
            set iNode [$tn lookup $iCls [lrange $nsAll 0 end-1]]
        } else {
            set tn [expr {([$parNode getParent] == "") ? $parNode : [$parNode getParent]}]
            set iNode [$tn lookup $iCls]
        }
        
        if {$iNode != ""} {
            lappend classes $iNode
        }
    }
    $clsNode configure -inherits $classes -inheritstring [string range $clsStr 2 end]
    return $clsNode
}

proc ::Parser::Nx::parseClass {node cTree content defOffPtr slotOffPtr} {
    upvar $defOffPtr defOff
    upvar $slotOffPtr slotOff
    
    set idx 1
    set clsName [getString $cTree $content $idx]
    if {$clsName eq "create"} {
        incr idx
	set clsName [getString $cTree $content $idx]
    }

    #set nsAll [regsub -all {::} [string trimleft $clsName :] " "]
    #set clsName [lindex $nsAll end]

    set nsNode [::Parser::Util::getNamespace $node \
        [lrange [split [regsub -all {::} $clsName ,] ,] 0 end-1]]
    set clsName [namespace tail $clsName]
    #set nsNode [::Parser::Util::getNamespace $node [lrange $nsAll 0 end-1]]
    set clsNode [$nsNode lookup $clsName]

    # let us assume for the time being, that we have just definitions
    # with scripted bodies. Then the last argument is the scripted body.
    set clsDef [getString $cTree $content end]

    if {$clsNode ne ""} {
        $clsNode configure -isvalid 1
    } else {
        set clsNode [::Parser::NxClassNode ::#auto -type class -expanded 0 \
                -name $clsName -isvalid 1]
        $nsNode addChild $clsNode
    }

    #
    # The following check tries to figure out, if we have a scripted body of the definition.
    # It is a heuristic but not foolproof
    #
    if {[regexp {\s:(method|alias|forward|public|protected|private|object)\s} $clsDef]} {

	set byteRange [getByteRange $cTree end]
	# pass defOff upwards
	set defOff [lindex $byteRange 0]
	$clsNode configure \
	    -isvalid 1 \
	    -definition [string trim $clsDef "{}"] \
	    -defbrange $byteRange \
	    -token [getString $cTree $content 0]
    }
    
    configClassParams $node $clsNode $cTree $content sloto
    set slotOff $sloto
    return $clsNode
}

proc ::Parser::Nx::getToken {cTree content idx} {
    lassign [lindex [lindex $cTree $idx] 1] off len
    return [string range $content $off [expr {$off + $len -1}]]
}

proc ::Parser::Nx::getString {cTree content idx} {
    return [lindex [::parse getstring $content [lindex $cTree [list $idx 1]]] 0]
    #return [::parse getstring $content [lindex $cTree [list $idx 0]]]
}

proc ::Parser::Nx::getByteRange {cTree idx} {
    return [lindex $cTree [list $idx 2 0 1]]
}

proc ::Parser::Nx::addVariable {node kind access cTree idx content} {
#
    # NX arguments:
    #    {-accessor "none"}
    #    {-incremental:switch}
    #    {-class ""}
    #    {-configurable:boolean false}
    #    {-initblock ""}
    #    spec:parameter
    #    defaultValue:optional
    #    
    #
    # TODO: the correct access is "none". Tloona does not render this currently properly,
    # so we set it to "protected".
    #
    # Background:
    #   - a "property" is a configurable "variable" 
    #    (can be set via "configure", read via "cget")
    #   - nx can define extra same-named accessors, which are
    #     "public", "protected" or "private". Default is "none".
    #   - the variable as such is always "protected"
    #
    set access none
    set access protected
    set deftype variable
    set initblock ""
    set nmIdx 1
    while {1} {
	set token [getString $cTree $content $idx+$nmIdx]
	switch -- $token {
	    "-accessor" {
		set access [getString $cTree $content [expr {$idx + $nmIdx + 1}]]
		incr nmIdx 2
	    }
	    "--" -
	    "-incremental" -
	    "-nocomplain" {
		# TODO: currently ignored
		incr nmIdx 1
	    }
	    "-configurable" {
		set bool [getString $cTree $content [expr {$idx + $nmIdx + 1}]]
		if {[string is boolean -strict $bool] && $bool} {
		    set deftype property
		}
		incr nmIdx 2
	    }
	    "-initblock" {
		set initblock [getString $cTree $content [expr {$idx + $nmIdx + 1}]]
		incr nmIdx 2
	    }

	    "-class" {
		# TODO: currently ignored
		incr nmIdx 2
	    }
	    default {break}
	}
    }
    set varNode [::Parser::NxAttributeNode ::#auto \
		     -kind       $kind \
		     -access     $access \
		     -deftype    $deftype \
		     -name       [getString $cTree $content $idx+$nmIdx] \
		     -definition [getString $cTree $content [expr {$idx + $nmIdx + 1}]] \
		     -initblock  $initblock \
		    ]
		    $node addChild $varNode
    return $varNode
}

proc ::Parser::Nx::addProperty {node kind access cTree idx content} {
    #
    # NX arguments:
    #    {-accessor ""}
    #    {-configurable:boolean true}
    #    {-incremental:switch}
    #    {-class ""}
    #    {-nocomplain:switch}
    #    spec:parameter
    #    {initblock ""}
    #
    # TODO: the correct access is "none". Tloona does not render this currently properly,
    # so we set it to "protected". See addVariable...
    #
    set access none
    set access protected
    set deftype property
    set nmIdx 1
    while {1} {
	set token [getString $cTree $content $idx+$nmIdx]
	switch -- $token {
	    "-accessor" {
		set access [getString $cTree $content [expr {$idx + $nmIdx + 1}]]
		incr nmIdx 2
	    }
	    "-configurable" {
		# TODO: currently ignored
		set bool [getString $cTree $content [expr {$idx + $nmIdx + 1}]]
		if {[string is boolean -strict $bool] && !$bool} {
		    set deftype variable
		}
		incr nmIdx 2
	    }
	    "--" -
	    "-incremental" -
	    "-nocomplain" {
		# TODO: currently ignored
		incr nmIdx 1
	    }
	    "-class" -
	    "-initblock" {
		# TODO: currently ignored
		incr nmIdx 2
	    }
	    default {break}
	}
    }
    set name [getString $cTree $content $idx+$nmIdx]
    if {[llength $name] > 0} {
	lassign $name name default
    } else {
	#not completely correct, no default is different from default ""
	set default unknown
    }
    set varNode [::Parser::NxAttributeNode ::#auto \
		     -kind       $kind \
		     -access     $access \
		     -deftype    $deftype \
		     -name       $name \
		     -definition $default \
		     -initblock  [getString $cTree $content [expr {$idx + $nmIdx + 1}]] \
		    ]
    $node addChild $varNode
    return $varNode
}

proc ::Parser::Nx::addMethod {node kind access cTree idx content} {
    #
    # NX arguments:
    #   name arguments:parameter,0..* -returns body -precondition -postcondition
    #
    set nmIdx 1
    while {1} {
	set token [getString $cTree $content $idx+$nmIdx]
	switch -- $token {
	    "-returns" {
		# TODO: ignored
		incr nmIdx 2
	    }
	    default {break}
	}
    }
    
    set idx [expr {$idx + $nmIdx}]
    set cmdNode [::Parser::NxProcNode ::#auto \
		     -kind       $kind \
		     -access     $access \
		     -name       [getString $cTree $content $idx] \
		     -arglist    [getString $cTree $content $idx+1] \
		     -definition [getString $cTree $content $idx+2] \
		     -defoffset  [lindex [getByteRange $cTree $idx+2] 0] \
		    ]
    set nmIdx 3
    while {1} {
	set token [getString $cTree $content $idx+$nmIdx]
	switch -- $token {
	    "-precondition" {
		$cmdNode configure \
		    -preassertion [getString $cTree $content [expr {$idx $nmIdx +1}]]
		incr nmIdx 2
	    }
	    "-postcondition" {
		$cmdNode configure \
		    -postassertion [getString $cTree $content [expr {$idx $nmIdx +1}]]
		incr nmIdx 2
	    }
	    default {break}
	}
    }    

    $node addChild $cmdNode
    return $cmdNode
}

proc ::Parser::Nx::addAlias {node kind access cTree idx content} {
    # NX arguments:
    #
    #     methodName -returns {-frame default} cmd
    #
    # can ignore -returns, -frame, cmd, since it makes no harm.
    # TODO: maybe add these for informational purposes
    #
    set cmdNode [::Parser::NxProcNode ::#auto \
		     -kind       $kind \
		     -access     $access \
		     -deftype    alias \
		     -name       [getString $cTree $content $idx+1] \
		    ]
    $node addChild $cmdNode
    return $cmdNode
}

proc ::Parser::Nx::addForward {node kind access cTree idx content} {
    # NX arguments:
    #
    #   methodName  -default -methodprefix -objframe:switch 
    #   -onerror -returns -verbose:switch target:optional args
    #
    # can ignore everything after methodNames
    # TODO: maybe add these for informational purposes
    #
    set cmdNode [::Parser::NxProcNode ::#auto \
		     -kind       $kind \
		     -access     $access \
		     -deftype    forward \
		     -name       [getString $cTree $content $idx+1] \
		    ]
    $node addChild $cmdNode
    return $cmdNode
}

   
## \brief Parse the scripted body of a class
proc ::Parser::Nx::parseScriptedBody {node offSet content} {
    set off $offSet
    #puts "======parseScriptedBody offset $off"
    while {$content ne ""} {
	#puts stderr "parseScriptedBody <$content>"
	set res [::parse command $content {0 end}]
	#puts stderr res=$res
	lassign [lindex $res 1] start len
	#puts "off $off (start $start len $len)"
	set cTree [lindex $res 3]
	set access protected
	set kind instance
	set idx 0
	while {1} {
	    set token [getString $cTree $content $idx]
	    #puts "nx::parseScriptedBody $idx: <$token> start $start off=$off"
	    switch -- $token {
		":public"    {set access public;    incr idx; continue}
		":protected" {set access protected; incr idx; continue}
		":private"   {set access private;   incr idx; continue}
		"object" -
		":object"    {set kind object;      incr idx; continue}
		":variable" -
		"variable" {
		    set varNode [addVariable $node $kind $access $cTree $idx $content]
		    $varNode configure -byterange [list [expr {$start + $off}] $len]
		}
		":property" -
		"property" {
		    set varNode [addProperty $node $kind $access $cTree $idx $content]
		    $varNode configure -byterange [list [expr {$start + $off}] $len]
		}
		":method" -
		"method" {
		    set cmdNode [addMethod $node $kind $access $cTree $idx $content]
		    $cmdNode configure -byterange [list [expr {$start + $off}] $len]
		}
		":alias" -
		"alias" {
		    set cmdNode [addAlias $node $kind $access $cTree $idx $content]
		    $cmdNode configure -byterange [list [expr {$start + $off}] $len]
		}
		":forward" -
		"forward" {
		    set cmdNode [addForward $node $kind $access $cTree $idx $content]
		    $cmdNode configure -byterange [list [expr {$start + $off}] $len]
		}
		default {}
	    }
	    break
	}
	incr off $start
	incr off $len
	set content [::parse getstring $content [list [lindex $res {2 0}] end]]
    }
}


proc ::Parser::Nx::parseDefinitionCmd {node cTree content defOffPtr preOffPtr postOffPtr} {
    upvar $defOffPtr cmdDefOff
    upvar $preOffPtr preOff
    upvar $postOffPtr postOff

    set access protected
    set kind instance
    set idx 1
    while {1} {
	set token [getString $cTree $content $idx]
	#puts token=$token
	switch -- $token {
	    "public"    -
	    "protected" -
	    "public"    {set accessor $token; incr idx; continue}
	    "object"    {set kind $token; incr idx; continue}
	    "variable" { return [addVariable $node $kind $access $cTree $idx $content] }
	    "property" { return [addProperty $node $kind $access $cTree $idx $content] }
	    "method"   { return [addMethod   $node $kind $access $cTree $idx $content] }
	    "alias"    { return [addAlias    $node $kind $access $cTree $idx $content] }
	    "forward"  { return [addForward  $node $kind $access $cTree $idx $content] }
	}
	break
    }
    
}
