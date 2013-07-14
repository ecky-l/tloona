Tloona is an IDE for Tcl/Tk. Its main features are a syntax highlighted editor,
a code browser and a command "REPL". Projects are directories with the ending 
.vfs, which can later be deployed via Tclkits (nevertheless all directories can
be opened as projects). Procedures, classes etc. can be send to the integrated 
REPL or to another interpreter via the comm Package. Both of these features are
 very useful for dynamic development and testing.
The project was inspired by Eclipse and Lisp/SLIME, so the graphical environment
 is a mixture of parts of an Eclipse IDE and the SLIME environment for Emacs. 
This makes it a very good fit for the development of small to large Tcl/Tk 
applications, desktop and web. Nevertheless it is also useful for tiny 
administration scripts.

Tloona runs with ActiveTcl 8.4 or 8.5 (http://www.activestate.com/activetcl). 
The dependencies can be installed via teacup, which can be done with the script
 "install_dependencies.tcl" in the main directory of Tloona. Then click on 
"main.tcl" to run the program.

Release Notes
-------------

Tloona1.4.0 (2013/07/14):
 * Partial support for snit in Code browser and the "send to REPL" feature
 * Extends and fixes in Itcl/Itk support ("common", itk_component in methods)
 * sugar macro integration in REPL and code browser + sugar::proc icon
 * AppMain.tcl and .icns icon for .app on Mac OSX (see comments in AppMain.tcl)
 * Various code/speed optimizations and bugfixes
