# Tloona

Tloona is an IDE for Tcl/Tk. Its main features are a syntax highlighted editor, 
project manager and -browser and a command REPL (Read-Eval-Print Loop). Among 
these and some other features, Tloona makes it easy to deploy programs as starkits
or even cross platform starpacks by means of a deployment wizzard. Directories 
with the ending .vfs are treated as projects. Procedures, classes and definitions
can be send to the integrated REPL or to other Tcl interpreters via comm. This
makes runtime debugging, testing and real time development as easy as it can get 
with a dynamic language. Various object systems are supported in the code browsers
and REPL interaction: IncrTcl, TclOO and Snit (to some extend also XoTcl and NX).

Modern OO systems in Tcl enable the dynamic definition or redefinition of classes, 
objects, variables and methods at runtime, object and class mixins, filters etc. 
With the Tloona REPL interaction it is easy to use and keep track of these powerful 
features in large projects.

The minimum Tcl version required to run Tloona is 8.6.

# Release Notes

### Release 2.0b8 : Date 2017/07/11 :
  * switch from Itk to snit
  * removed Itcl 3.4 and Itk 3.4 from libs directory
  * added itcl 4.0.3 to libs directory
  * linux lib binaries added, runs on linux again
  * deploy output directory is configurable underneath project dir
  * fixed destructor to REPL creation bug for TclOO classes
  * tm modules are displayed with tcl icon in browser
  * deployment via external SDX, since internal always makes trouble

### Release 1.7.1 : Date 2016/06/18 :
  *  Bugfix: openFile from Workspace browser didn't generate tree properly
     (removed dead code with side effects)

### Release 1.7.0 : Date 2016/06/12 :
  *  Enhancement for dynamic REPLS: if semicolon is typed after a statement, the
     result of that statement is not displayed. Useful if output should be prevented,
     e.g. if the result is huge or binary
  *  Added REPL menu, ability to create more REPLs and close them
  *  Bugfix for open .test files, error occured
  *  Bugfix starkit creation, recovery after error
  *  Removed building of code tree in Workspace browser. Tree is shown in Outline only,
     which is faster and less cluttered.
  *  parser understands ::oo::define and ::oo::objdefine for methods and variables
  *  removed empty projectoutline window
  *  version display in lower right corner (in status line)
  *  introduced lineendings save translation (can be set in ~/.tloonarc): lf for unix
     line endings, crlf for windows line endings, auto for automatic line endings
  *  bugfixes for sending ::oo::define, ::oo::objdefine commands and ::itcl::destructor 
     to console
  *  minor parser enhancements: namespace eval's don't appear in procs/methods etc.
  *  fixed history cut at wrong place bug
  *  fixed problem that only *.exe files can be loaded as tclkit for deployment. Now it 
     is possible to load tclkits w/o .exe extension to create starpacks for other 
     platforms (e.g. linux starpack on windows)

### Release 1.6.1 : Date 2016/05/02 :
  *  Bugfix for connection lost from remote comm interp
  *  Enabled cd there in comm interp console
  *  Added "source complete script to console" feature
  *  switch between Tcl files and currently selected console via Ctrl-Tab works

### Release 1.6.0 : Date 2016/04/30 :
  *  new feature Remote Console, to attach remote Tcl Interp via comm

### Release 1.5.5 : Date 2016/01/25 :
  *  Fixed Splash position on windows

### Release 1.5.4 : Date 2015/08/29 :
  *  bugfix token definition for TclOO parser
  *  integrated new, vimode enabled snit Tmw::console

### Release 1.5.3 : Date 2015/08/20 :
  *  Bugfixes
  *  support for some self defined tcloo commands ( (class), (variable), (superclass), (constructor) )
  *  support for sending tcltest to consoles or other (comm) interp

### Release 1.5.2 : Date 2015/03/20 :
  *  Fixed create file on right click in directory in project browser
  *  Enabled CD to directory inside starkit project directories
  *  Fixed code sending to console for TclOO methods and defines

### Release 1.5.1 : Date 2015/03/20 :
  *  Updated Itcl to 3.4.2 and Itk to 3.4.1
  *  Does _not_ run with Tcl 8.5, but instead with Tcl 8.6

### Release 1.5.0 : Date 2015/03/07 :
  *  Does _not_ run with latest versions of Tcl 8.6 (due to Itcl/Itk bugs)
  *  Startup Splash screen
  *  Enhanced snit parser and code completion feature
  *  Included tcl package and lib dependencies for Mac OSX and Win32 in the starkit
  *  Polishing and bug fixing
  *  Move to git
  *  changed version handling. A global variable tloona_version is set
     to the slave interpreter. The version is read from this file
  *  Updated Description and Release Notes

### Release 1.4.2 : Date 2013/08/01 : 
  *  Runs with Tcl/Tk 8.6
  *  Partial Support for TclOO (oo::define, class, methods, constructor)
  *  Critical fix for expand {*} syntax with new version of Tclparser
  *  Many bugfixes

### Release 1.4.0 : Date 2013/07/14 : 
  *  Partial support for snit in Code browser and the "send to REPL" feature
  *  Extends and fixes in Itcl/Itk support ("common", itk_component in methods)
  *  sugar macro integration in REPL and code browser + sugar::proc icon
  *  AppMain.tcl and .icns icon for .app on Mac OSX (see comments in AppMain.tcl)
  *  Various code/speed optimizations and bugfixes

