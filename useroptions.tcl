
# the main window size
set ::UserOptions(MainGeometry) "800x500+10+10"
# the default theme
if {$tcl_platform(platform) == "windows"} {
    set ::UserOptions(Theme) "xpnative"
    set ::UserOptions(FileFont) {FixedSys 14}
    set ::UserOptions(ConsoleFont) {FixedSys 14}
    
    # syntax colors for Tcl files
    set ::UserOptions(TclSyntax) { \
            Keywords {darkred normal} \
            Braces {orange normal} \
            Brackets {red normal} \
            Parens {maroon4 normal} \
            Options {goldenrod normal} \
            Digits {darkviolet normal} \
            Strings {magenta normal} \
            Vars {green4 normal} \
            Comments {blue normal}
    }

    set ::UserOptions(HtmlSyntax) { \
        Tags {maroon4 normal} \
        TagOptions {goldenrod normal} \
        HtmlComment {blue normal}
    }
    
} else  {
    set ::UserOptions(Theme) "clam"
    set ::UserOptions(FileFont) {{Lucida Sans Typewriter} 13}
    set ::UserOptions(ConsoleFont) {{Lucida Sans Typewriter} 13}
    
    # syntax colors for Tcl files
    set ::UserOptions(TclSyntax) { \
            Keywords {darkred bold} \
            Braces {orange bold} \
            Brackets {red bold} \
            Parens {maroon4 bold} \
            Options {gold normal} \
            Digits {darkviolet normal} \
            Strings {magenta normal} \
            Vars {green4 normal} \
            Comments {blue normal}
    }
    
    set ::UserOptions(HtmlSyntax) { \
        Tags {maroon4 bold} \
        TagOptions {gold normal} \
        HtmlComment {blue normal}
    }

}

# the time that a selected code fragment flashes
set ::UserOptions(FlashTime) 1000
# file options
set ::UserOptions(FileExpandTabs) 1
set ::UserOptions(FileNTabs) 4
set ::UserOptions(File,InsertCodeTemplates) 1
set ::UserOptions(File,MatchParens) 1
set ::UserOptions(File,MatchBrackets) 1
set ::UserOptions(File,MatchBraces) 1
set ::UserOptions(File,MatchQuotes) 1
set ::UserOptions(File,Backup) 1
# browser options
set ::UserOptions(CodeBrowser,SortSeq) {
    package
    macro
    variable
    class
    itk_components
    public_component
    private_component
    snit_options
    snit_option
    snit_delegates
    snit_delegate
    public_common
    protected_common
    private_common
    public_variable
    protected_variable
    private_variable
    constructor
    destructor
    public_method
    protected_method
    private_method
    proc
    namespace
    test
}
set ::UserOptions(KitBrowser,SortSeq) {
    directory
    tclfile
    testfile
    file
    package
    macro
    variable
    class
    snit_options
    snit_option
    snit_delegates
    snit_delegate
    public_common
    protected_common
    private_common
    public_variable
    protected_variable
    private_variable
    constructor
    destructor
    public_method
    protected_method
    private_method
    proc
    namespace
    test
}
set ::UserOptions(CodeBrowser,SortAlpha) 1
set ::UserOptions(KitBrowser,SortAlpha) 1
# key bindings
set ::UserOptions(Key,Open) "<Control-o>"
set ::UserOptions(Key,Close) "<Control-w>"
set ::UserOptions(Key,Copy) "<Control-c>"
set ::UserOptions(Key,Cut) "<Control-x>"
set ::UserOptions(Key,Paste) "<Control-v>"
set ::UserOptions(Key,NewFile) "<Control-n>"
set ::UserOptions(Key,Save) "<Control-s>"
# view options
set ::UserOptions(View,browser) 1
set ::UserOptions(View,browserSash) -1
set ::UserOptions(View,textnb) 1
set ::UserOptions(View,console) 1
set ::UserOptions(View,editor) 1
set ::UserOptions(View,consoleSash) -1
set ::UserOptions(View,outline) 1
set ::UserOptions(View,consoleOnly) 0
set ::UserOptions(View,navigateSash) -1
# last open documents
set ::UserOptions(LastOpenDocuments) {}

# kit projects (starkits)
set ::UserOptions(KitProjects) {}

# Path to SDX for wrapping files
set ::UserOptions(PathToSDX) ""
set ::UserOptions(DefaultModifier) "Control"
