package re tmw::plugin   

plugin provide hans 0.1 {
    extensionpoint maff maffProc
    extensionpoint muff muffProc
}

plugin provide hugo 0.5 {
    extensionpoint moppi mappiproc
    
    extends hans muff muffproc
}

plugin provide erwin 0.2 {
    extensionpoint view testview
    extensionpoint menu dadaa
    
    extends hans maff maffArg
    extends hans muff muffArg
    #extends hans maff murrrrrrr
    
    extends hugo moppi moppiArg
}

#proc testview {args} {
#    puts "yay, $args"
#}
puts "hans: [plugin get hans]"
puts "erwin: [plugin get erwin]"





