
package require Itree 1.0

package provide parser::script 1.0

namespace eval ::Parser {}

# @c A general structured file. Can be any file with
# @c structured content
class ::Parser::StructuredFile {
    inherit ::itree::Node
    
    constructor {args} {
        eval configure $args
    }
    
    public {
        # @v file: the file name. Essentially a node name
        variable file "" {
            if {$file != ""} {
                configure -dirname [file dirname $file] \
                    -name [file tail $file]

            }
        }
        # @v dirname: directory of the file being parsed. This 
        # @v dirname: attribute is used for displaying the file in
        # @v dirname: a tree node
        variable dirname ""
        
        # @v byterange: the range in bytes
        variable byterange {-1 -1}
        
        # @c Parses a file. The default implementation does
        # @c nothing, Subclasses may override
        method parseFile {filename} {}
        
        # @c looks up the range of a file in the tree. Does
        # @c nothing by default, Subclasses should override
        method lookupRange {range} {}
        
        method getCommands {cmdsPtr {deep 0}} {}
        
    }
    
    protected {
    }
    
    private {
    }
    
}

# @c This class represents a Tcl script that contains Tcl
# @c commands, namespaces and classes 
class ::Parser::Script {
    inherit ::Parser::StructuredFile
    
    
    constructor {args} {
        set _Commands [concat $::Parser::CoreCommands $::Parser::ItclCoreCommands \
            $::Parser::XotclCoreCommands]
        eval configure $args
    }
    
    public variable name ""
        # @v defbrange: byte range for the definition
    public variable defbrange {}
    
        # @v definition: the text that makes up the code definition
    public variable definition ""
        # @v isvalid: used for reparsing. Indicates, whether the
        # @v isvalid: node still exists in the content. If not,
        # @v isvalid: it can be deleted.
    public variable isvalid 1
        # @v displayformat: overloads the display format
    public variable displayformat {"%s" -name}
    
    ## \brief The file where the script is defined
    public variable filename ""
    
    # @c parses the file content
    public method parseFile {filename} {
        if {[catch {set fh [open $filename "r"]} msg]} {
            return -code error "can not open file: $msg"
        }
        
        set definition [read $fh]
        close $fh
        set name [file tail $filename]
        set type "script"

        if {[catch {::Parser::parse $this 0 $definition} msg]} {
            ::log::log error "--------------------------------------"
            ::log::log error "::Parser::Script::parseFile "
            ::log::log error "  ($this, $filename)"
            ::log::log error $::errorInfo
        }
        
    }
    
    ## \brief Recursively set the filename for this and all children.
    public method setFilename {filename} {
        configure -filename $filename
        foreach {child} [getChildren] {
            $child setFilename $filename
        }
    }


    # @c lookus up a byte in all child nodes
    # @c recursively. Returns the node which range
    # @c includes the byte
    public method lookupRange {byte} {
        foreach child $_Children {
            set chd [$child lookupRange $byte]
            if {$chd != ""} {
                return $chd
            }
            set a [lindex [$child cget -byterange] 0]
            set e [expr {[lindex [$child cget -byterange] 1] + $a}]
            if {$byte > $a && $byte < $e} {
                return $child
            }
        }
        
        return ""
    }
    
    # @c pretty prints the content of the entire tree
    # @c into the variable var, if given.
    # @c Returns the result
    public method print {indent {var ""}} {
        if {$var != ""} {
            upvar $var ctn
        } else  {
            set ctn ""
        }
        
        append ctn [string repeat " " [expr {$indent * $level}]]
        switch -- $type {
            "access" {
                append ctn "[cget -name]: ([cget -level])\n"
            }
            "variable" {
                append ctn "[cget -type]: [cget -name] ([cget -level])\n"
                
                if {[cget -configcode] != ""} {
                    append ctn [string repeat " " \
                            [expr {$indent * ($level + 1)}]]
                    append ctn "configcode\n"
                }
                if {[cget -cgetcode] != ""} {
                    append ctn [string repeat " " \
                            [expr {$indent * ($level + 1)}]]
                    append ctn "cgetcode\n"
                }
            }
            "method" -
            "proc" {
                append ctn "[cget -type]: [cget -name] ([cget -level])\n"
                if {[cget -bodyextern]} {
                    append ctn [string repeat " " \
                            [expr {$indent * ($level + 1)}]]
                    append ctn "body\n"
                }
            }
            default {
                append ctn "[cget -type]: [cget -name] ([cget -level])\n"
            }
        }
        
        foreach ch $_Children {
            $ch print $indent ctn
        }
        
        return $ctn
    }
        
    # @c sets the command list cmds into
    # @c all siblings that follow this node
    # @c and all children
    public method setCommands {cmds} {
        # TODO: check for byte ranges...
        set _Commands [concat $cmds $::Parser::ItclCoreCommands]
        # set nsib [nextSibling]
        # while {$nsib != ""} {
            # puts [$nsib cget -name]
            # $nsib setCommands $cmds
            # set nsib [$nsib nextSibling]
        # }
        foreach ch $_Children {
            $ch setCommands $cmds
        }
    }
    
    # @c get the commands defined in this script. Walks up
    # @c the code hierarchy and looks for package definitions
    # @c then executes "package re" in a sub interpreter
    # @c to find commands provided by the packages
    public method getCommands {cmdPtr {deep 0}} {
        upvar $cmdPtr cmdList
        
        set pkgList ""
        set modified 0
        set pkgNames ""
        #set procedures [[getTopnode] getProcs]
        
        if {$deep} {
            getPackages pkgList
        } else  {
            foreach ch $_Children {
                if {[$ch cget -type] != "package"} {
                    continue
                }
                
                lappend pkgList $ch
                if {![lcontain $_Packages [$ch cget -name]]} {
                    set modified 1
                }
                lappend pkgNames [$ch cget -name]
            }
        }
        
        if {! $modified} {
            foreach pkn $_Packages {
                if {![lcontain $pkgNames $pkn]} {
                    set modified 1
                }
            }
        }
        
        #getProcs
        set cmdList [lsort [concat [getProcs] $_Commands]]
        #if {! $modified} {
        #    set cmdList [lsort [concat [getProcs] $_Commands]]
        #    return -code ok ""
        #}
        
        # TODO: this code doesn't work anymore. With multiple threads it is
        # TODO: tricky to use child interpreters, as is to create threads from
        # TODO: sub threads. Find another way to get commands and variables
        # TODO: from packages, maybe parsing them?
    }
    
    public method appendError {range error} {
        lappend Errors $range $error
    }
        
    public method getErrors {} {
        return $ParseErrors
    }
    
    public method getVariables {{deep 0}} {
        set pkgList ""
        set modified 0
        set pkgNames ""
        if {$deep} {
            getPackages pkgList
        } else  {
            foreach ch $_Children {
                if {[$ch cget -type] != "package"} {
                    continue
                }
                
                lappend pkgList $ch
                if {![lcontain $_Packages [$ch cget -name]]} {
                    set modified 1
                }
                lappend pkgNames [$ch cget -name]
            }
        }
        
        # TODO: this code doesn't work anymore. With multiple threads it is
        # TODO: tricky to use child interpreters, as is to create threads from
        # TODO: sub threads. Find another way to get commands and variables
        # TODO: from packages, maybe parsing them?
        
        return $_Variables
        #return [concat $rres $_Variables]
    }
            
    public method removeVariables {} {
        set _Variables {}
    }
        
    public method getProcs {} {
        set res {}
        foreach {p a acc} $_Procedures {
            lappend res $p
        }
        
        return $res
    }

        
    ##
    # add a variable and its value to the node and, if
    # deep is true, to its child nodes
    public method addVariable {var value {deep 0}} {
        if {![lcontain $_Variables $var]} {
            lappend _Variables $var $value
        }
        if {$deep} {
            foreach {child} $_Children {
                $child addVariable $var $value $deep
            }
        }
    }
        
    ##
    # add a procedure
    public method addProc {procNode} {
        # get namespace qualifiers
        set compName [$procNode cget -name]
        set prtIsClass 0
        set prt [$procNode getParent]
        while {$prt != ""} {
            if {[$prt cget -type] == "access" || \
                [$prt cget -type] == "script"} {
                set prt [$prt getParent]
                continue
            }
            set compName "[$prt cget -name]::$compName"
            set prt [$prt getParent]
        }
            
        if {![lcontain $_Procedures $compName]} {
            lappend _Procedures $compName \
                [$procNode cget -arglist] ""
        }
            
        foreach {child} $_Children {
            $child addProc $procNode
        }
    }
        
    ## \brief virtual method for adding method. 
    public method addMethod {methNode} {
        set mname [$methNode cget -name]
        set alist [$methNode cget -arglist]
        if {![lcontain $_Procedures $mname]} {
            lappend _Procedures $mname $alist ""
        }
            
        foreach {child} $_Children {
            if {[$child cget -type] == "proc"} {
                # don't add the method to proc's, it is
                # not visible there
                continue
            }
            $child addMethod $methNode
        }
        
    }
    
    # @c returns all XOTcl classes in this script. Useful for
    # @c parsing instprocs, object procs etc.
    public method xotclClasses {} {
        set res {}
        foreach {chd} [getChildren 1] {
            if {[$chd cget -isxotcl]} {
                lappend res $chd
            }
        }
        return $res
    }
    
    public method isXotclClass {name} {
        set childs [getChildren 1]
        set idx [lsearch -glob -all $childs *$name]
        if {$idx == {}} {
            return 0
        }
        
        foreach {i} $idx {
            set cls [lindex $childs $i]
            if {[$cls isa ::Parser::ClassNode] && [$cls cget -isxotcl]} {
                return 1
            }
        }
        return 0
    }
    
    protected variable _Commands {}
    # @v _Commands: list of commands available in the script
    protected variable _Variables {}
    # @v _Variables: list of variables set by some commands
    protected variable _GobalVariables {}
    # @v _GlobalVariables: list of global variables
    protected variable _Packages {}
    # @v _Packages: package names
    protected variable Errors {}
    # @v Errors: a list of potential errors that came up
    # @v Errors: during the parse process
    protected variable _Procedures {}
    # @v _Procedures: list of procedures
    
    private method getPackages {pkgListPtr} {
        # @c get the packages in the tree
        upvar $pkgListPtr pkgList
        
        foreach ch $_Children {
            if {[$ch cget -type] == "package"} {
                lappend pkgList $ch
            } else {
                $ch getPackages pkgList
            }
        }
        
    }
    
}

