# pdftoprinter
AutoIt project for a PDF-to-printer application for Windows

This application is described in detail here:

https://mendelson.org/pdftoprinter.html

This respository includes the files needed for compiling and running the application. They should be copied to the same folder that contains the au3 file. 

Note that this application includes the freely-distributable but copyrighted commercial software PDF-Xchange Viewer from Tracker Software.

19 October 2024: The compiled version of the app and the source code now require 64-bit Windows. The older 32-bit version of the app and source code are still available; both have `32` in their filenames.

If you get an error message about qpdf##.dll, then download and install the x86 version of the Microsoft VC redistributables from this page: https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist?view=msvc-170#latest-microsoft-visual-c-redistributable-version

Malware detection: Some anti-malware programs will report that my installer contains malware; this happens because the AutoIt scripting language has been used to create malware and anti-malware programs block anything created in AutoIt. If you don't trust my software, don't use my software! Find something else instead. (Or compile it yourself from the code in this repository.)

**You may not need this program at all.** Powershell can print PDF files from the command line. For example, to print to a specific printer, use:

`Start-Process -FilePath "path\to\file" -Verb PrintTo -ArgumentList "Name of Printer" -PassThru | %{sleep 10;$_} | kill`

To print to the default printer:

`Start-Process -FilePath "path\to\file" -Verb Print -PassThru | %{sleep 10;$_} | kill`

