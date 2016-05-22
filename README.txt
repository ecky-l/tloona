ApplicationName : Tloona

==

Description :
Tloona is an advanced editor for Tcl/Tk. Main features are project management, 
extensive code browsing, syntax highlighting / command expansion, and a command 
REPL (Read/Eval/Print Loop). Directories with .vfs extension are threated as 
Projects and can be deployed as starkits or starpacks. Procedures, classes, 
namespace definitions etc. can be send to the REPL or to another interpreter 
for agile and dynamic development. Even the Tclhttpd web server can be started
inside the REPL and .tml files are supported to a certain grade.
The project was inspired by Eclipse and Lisp/SLIME.

Tloona is deployed as a starkit and works with ActiveTcl 8.5 or Tclkit 8.5, on 
Windows and Mac OSX out of the box. It should also work on Linux with a decent 
ActiveTcl 8.5 installation, but binary dependencies are not included in the 
starkit (due to the fact that the author is not in the mood to test another 
platform) 

==

Release 1.6.2 : Date 2016/05/20 :
 * Enhancement for dynamic REPLS: if semicolon is typed after a statement, the
   result of that statement is not displayed. Useful if output should be prevented,
   e.g. if the result is huge or binary
 * Added REPL menu, ability to create more REPLs and close them
 * Bugfix for open .test files, error occured
 * Removed building of code tree in Workspace browser. Tree is shown in Outline only
   (faster, less buggy and cluttered)
 * parser understands ::oo::define and ::oo::objdefine for methods and variables
 * removed empty projectoutline window
 
Release 1.6.1 : Date 2016/05/02 :
 * Bugfix for connection lost from remote comm interp
 * Enabled cd there in comm interp console
 * Added "source complete script to console" feature
 * switch between Tcl files and currently selected console via Ctrl-Tab works

Release 1.6.0 : Date 2016/04/30 :
 * new feature Remote Console, to attach remote Tcl Interp via comm

Release 1.5.5 : Date 2016/01/25 :
 * Fixed Splash position on windows

Release 1.5.4 : Date 2015/08/29 :
 * bugfix token definition for TclOO parser
 * integrated new, vimode enabled snit Tmw::console

Release 1.5.3 : Date 2015/08/20 :
 * Bugfixes
 * support for some self defined tcloo commands ( (class), (variable), (superclass), (constructor) )
 * support for sending tcltest to consoles or other (comm) interp

Release 1.5.2 : Date 2015/03/20 :
 * Fixed create file on right click in directory in project browser
 * Enabled CD to directory inside starkit project directories
 * Fixed code sending to console for TclOO methods and defines

Release 1.5.1 : Date 2015/03/20 :
 * Updated Itcl to 3.4.2 and Itk to 3.4.1
 * Does _not_ run with Tcl 8.5, but instead with Tcl 8.6

Release 1.5.0 : Date 2015/03/07 :
 * Does _not_ run with latest versions of Tcl 8.6 (due to Itcl/Itk bugs)
 * Startup Splash screen
 * Enhanced snit parser and code completion feature
 * Included tcl package and lib dependencies for Mac OSX and Win32 in the starkit
 * Polishing and bug fixing
 * Move to git
 * changed version handling. A global variable tloona_version is set
   to the slave interpreter. The version is read from this file
 * Updated Description and Release Notes

Release 1.4.2 : Date 2013/08/01 : 
 * Runs with Tcl/Tk 8.6
 * Partial Support for TclOO (oo::define, class, methods, constructor)
 * Critical fix for expand {*} syntax with new version of Tclparser
 * Many bugfixes

Release 1.4.0 : Date 2013/07/14 : 
 * Partial support for snit in Code browser and the "send to REPL" feature
 * Extends and fixes in Itcl/Itk support ("common", itk_component in methods)
 * sugar macro integration in REPL and code browser + sugar::proc icon
 * AppMain.tcl and .icns icon for .app on Mac OSX (see comments in AppMain.tcl)
 * Various code/speed optimizations and bugfixes
==
