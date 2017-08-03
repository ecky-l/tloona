
package require img::png 1.4.2
package provide tmw::icons 1.0


namespace eval ::Tmw {
    # @v IconPath: path to the icon images
    variable IconPath [file join [file dirname [info script]] icons]
    # @v Icons: the array variable holding all icons defined here
    variable Icons
    array set Icons {}
    
    set Icons(FileNew) [image create photo -file [file join $IconPath filenew.png]]
    set Icons(FileOpen) [image create photo -file [file join $IconPath fileopen.png]]
    set Icons(FileClose) [image create photo -file [file join $IconPath fileclose.png]]
    set Icons(FileSave) [image create photo -file [file join $IconPath filesave.png]]
    set Icons(ActExit) [image create photo -file [file join $IconPath actexit.png]]
    
    set Icons(ConsoleBlack) [image create photo -file [file join $IconPath console_black18.png]]
    set Icons(ConsoleRed) [image create photo -file [file join $IconPath console_red18.png]]
    set Icons(ConsoleClose) [image create photo -file [file join $IconPath console_close18.png]]

    set Icons(ActUndo) [image create photo -file [file join $IconPath actundo.png]]
    set Icons(ActRedo) [image create photo -file [file join $IconPath actredo.png]]
    set Icons(ActReload) [image create photo -file [file join $IconPath actreload18.png]]
    set Icons(ActCross) [image create photo -file [file join $IconPath actcross16.png]]
    set Icons(ActItemAdd) [image create photo -file [file join $IconPath actitemadd16.png]]
    set Icons(ActItemDelete) [image create photo -file [file join $IconPath actitemdelete16.png]]
    set Icons(ActFileFind) [image create photo -file [file join $IconPath filefind18.png]]
    set Icons(ActFilter) [image create photo -file [file join $IconPath filter18.png]]
    set Icons(ActWatch) [image create photo -file [file join $IconPath watch18.png]]
    set Icons(ActCheck) [image create photo -file [file join $IconPath actcheck18.png]]
    set Icons(EditCut) [image create photo -file [file join $IconPath editcut.png]]
    set Icons(EditCopy) [image create photo -file [file join $IconPath editcopy.png]]
    set Icons(EditPaste) [image create photo -file [file join $IconPath editpaste.png]]
    
    set Icons(AppTools) [image create photo -file [file join $IconPath apptools18.png]]
    set Icons(SortAlpha) [image create photo -file [file join $IconPath sortalpha.png]]
    set Icons(NavUp) [image create photo -file [file join $IconPath navup18.png]]
    set Icons(NavDown) [image create photo -file [file join $IconPath navdown18.png]]
    
    set Icons(TclFile) [image create photo -file [file join $IconPath tclfile.png]]
    set Icons(KitFile) [image create photo -file [file join $IconPath kitfile.png]]
    set Icons(ImageFile) [image create photo -file [file join $IconPath gimpimage18.png]]
    set Icons(ExeFile) [image create photo -file [file join $IconPath actrun18.png]]
    set Icons(DocumentFile) [image create photo -file [file join $IconPath filedocument18.png]]
    set Icons(WebFile) [image create photo -file [file join $IconPath globe16.png]]
    set Icons(WebScript) [image create photo -file [file join $IconPath tclglobe.png]]

    
}
