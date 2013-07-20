## \brief Provide some sugar macros for easier access to token content

package require sugar 0.1

## \brief Gets the token of a parse tree at specified index
::sugar::macro m-parse-token {cmd content tree idx} {
    list ::parse getstring $content \[lindex \[lindex $tree $idx\] 1\]
}

## \brief Gets the byterange of a definition in a parse tree at specified index
sugar::macro m-parse-defrange {cmd tree idx} {
    list list \[lindex \[lindex \[lindex \[lindex \[lindex $tree $idx\] 2\] 0\] 1\] 0\] \
        \[lindex \[lindex \[lindex \[lindex \[lindex $tree $idx\] 2\] 0\] 1\] 1\]
}

## \brief Get the byterange of a command
sugar::macro m-parse-cmdrange {cmd tree offset} {
    list list \[expr \{\[lindex \[lindex $tree 1\] 0\] + $offset\}\] \
        \[expr \{\[lindex \[lindex $tree 1\] 1\] - 1\}\]
}

package provide parser::macros 1.0
