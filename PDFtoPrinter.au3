#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=pdftoprinter.ico
#AutoIt3Wrapper_Outfile=PDFtoPrinter.exe
#AutoIt3Wrapper_Res_Description=PDFtoPrinter.exe
#AutoIt3Wrapper_Res_Fileversion=3.0.0.1
#AutoIt3Wrapper_Res_Fileversion_AutoIncrement=y
#AutoIt3Wrapper_Res_ProductName=PDFtoPrinter.exe
#AutoIt3Wrapper_Res_SaveSource=y
#AutoIt3Wrapper_Res_Language=1033
#AutoIt3Wrapper_Res_requestedExecutionLevel=asInvoker
#AutoIt3Wrapper_Run_After=d:\dropbox\signfilesem.exe "%out%"
#AutoIt3Wrapper_Run_Tidy=y
#EndRegion ;**** Directives created by AutoIt3Wrapper_GUI ****

#include <GUIConstantsEx.au3>
#include <Array.au3>
#include <Constants.au3>
#include <WinAPI.au3>
#include <APIErrorsConstants.au3>
#include <Misc.au3>
#include <Math.au3>
#include <String.au3>
#include <File.au3>
#include <Date.au3>

; Force explicit variable declarations to catch typo-bugs.
Opt("MustDeclareVars", 1)
Opt("WinTitleMatchMode", -2)

; ----- Exit codes ------------------------------------------------------------
Global Const $EXIT_SUCCESS = 0
Global Const $EXIT_OS_TOO_OLD = 1
Global Const $EXIT_NO_ARGS = 2
Global Const $EXIT_NO_PRINTER = 3
Global Const $EXIT_BAD_COPIES = 4
Global Const $EXIT_BAD_RX = 5
Global Const $EXIT_PRINTER_INVALID = 6
Global Const $EXIT_NO_PDF_ARG = 7
Global Const $EXIT_NO_PDF_MATCH = 8
Global Const $EXIT_PRINT_ERRORS = 9
Global Const $EXIT_FILE_IN_USE = 10
Global Const $EXIT_ALREADY_RUNNING = 11
Global Const $EXIT_BAD_RECUR = 12
Global Const $EXIT_BAD_EXTENSION = 13

; ----- Script-level state ----------------------------------------------------
Global $msgTitle = "PDFtoPrinter.exe"
Global $specified = 0
Global $cli = 0
Global $debug = 0
Global $silent = 0       ; suppress popups
Global $printername = ""
Global $defaultprinter = ""
Global $code = 0

; GUI state used by the printer-selection dialog.
Global $gh
Global $printer_list[1]
Global $printer_list_ext[1]
Global $printer_radio_array[1]

; Working state populated as the script runs.
Global $pth = @WorkingDir
If StringRight($pth, 1) = "\" Then $pth = StringTrimRight($pth, 1) ; root, e.g. C:\
Global $fn = @ScriptName
Global $space = " "
Global $qt = Chr(34)

; Per-run options (set by command-line parsing).
Global $pdffile = ""
Global $showselptr = 0
Global $pgvar = ""
Global $copies = 1
Global $focus = ""
Global $recurLevel = 1    ; default: this folder only
Global $password = ""
Global $csv = 0
Global $mock = 0
Global $pageselector = ""
Global $printervalid = 1
Global $aMultiFiles[0]
Global $morethanone = 0
Global $myDir = @TempDir & "\PDFPrinterTmp"

; Build-time list of printers and matching PDF files.
Global $printerlist
Global $pdffiles

; Per-file scratch used between MainLoop iterations and helper funcs.
Global $errors = ""
Global $summary[1][12]

; ----- OS check --------------------------------------------------------------
CheckOSVersion()

; ----- Single-instance gate --------------------------------------------------
If Not ExecutableNameFlag("m") Then Handle_MultipleInstance()

; ----- Mode flags driven by the executable filename -------------------------
If ExecutableNameFlag("select") Then $showselptr = 1
If ExecutableNameFlag("debug") Then $debug = 1
If ExecutableNameFlag("cli") Then $cli = 1

; ----- No-arg usage screen ---------------------------------------------------
If $CmdLine[0] = 0 Then
	ShowUsage()
	Exit $EXIT_NO_ARGS
EndIf

; ----- Verify at least one printer exists -----------------------------------
$printerlist = GetPrinter("", 1)
If UBound($printerlist) = 0 And $mock = 0 Then
	Display("No printer found.")
	Exit $EXIT_NO_PRINTER
EndIf

; ----- Parse the command line ------------------------------------------------
ParseCmdLine()

If $printervalid = 0 Then
	Display("Printer name """ & $printername & """ not found or argument """ & $printername & """ is not valid.")
	Exit $EXIT_PRINTER_INVALID
EndIf

If $pdffile = "" Then
	Display("Wrong arguments: no [path]filename with .pdf extension provided.")
	Exit $EXIT_NO_PDF_ARG
EndIf

; ----- Expand the PDF file list ---------------------------------------------
If $recurLevel <= 1 Then
	$pdffiles = getfilematched($pdffile, $recurLevel, $pth)
	If @error Then
		Display($pdffiles)
		Exit $EXIT_NO_PDF_MATCH
	EndIf
Else
	Local $singletonList[2] = [1, $pdffile]
	$pdffiles = $singletonList
EndIf

; If multiple PDFs were named on the command line, those win over the
; wildcard expansion above.
If $morethanone = 1 Then
	Local $fileCount = UBound($aMultiFiles)
	_ArrayInsert($aMultiFiles, 0, $fileCount)
	$pdffiles = $aMultiFiles
EndIf

; ----- Stage the embedded PDF-XChange Viewer to a working directory --------
StagePDFXChange()

; ----- CSV summary header ---------------------------------------------------
Local $csvHeader = "Index, Filepath, Filename, Datetime, IsEncrypted, PageCount," & _
		" Command string executed (can be used in bat), Page selector," & _
		" Total pages selected, Copies," & _
		" Result (actions requiring human interaction are assumed successful," & _
		" even if you cancelled the password input window)," & _
		" Error info"
_ArrayInsert($summary, 0, $csvHeader, 0, ",")

; ----- Main loop: print each matched PDF ------------------------------------
MainLoop()

; ----- Wrap up: report errors, write CSV, exit ------------------------------
If $errors <> "" Then
	If $cli = 0 And $silent = 0 Then MsgBox(0, "Error lists:", $errors)
	ConsoleWrite("Error lists: " & @CRLF & $errors)
	$code = $EXIT_PRINT_ERRORS
Else
	$code = $EXIT_SUCCESS
EndIf

If $csv = 1 Or $mock = 1 Then
	Local $output_file = $myDir & "\summary_utf8.csv"
	If DeleteFileSafe($output_file) Then
		FileWrite($output_file, _ArrayToCSV($summary))
	EndIf
EndIf

Exit $code

; =============================================================================
;                            Functions
; =============================================================================

Func CheckOSVersion()
	; PDF-XChange Viewer requires a recent VC runtime; gate on Windows build.
	Local $build = FileGetVersion("user32.dll")
	If StringRegExp($build, "^(.*)\.(.+)\.(.+)\.(.*)$") Then
		Local $parts = StringRegExp($build, "^(.*)\.(.+)\.(.+)\.(.*)$", 1)
		$build = $parts[2]
	Else
		$build = @OSBuild
	EndIf
	If $build < 10000 Then
		Display("Windows 10, Windows Server 2016, or later required.")
		Exit $EXIT_OS_TOO_OLD
	EndIf
EndFunc   ;==>CheckOSVersion

Func ShowUsage()
	Display("Usage:" & @CRLF & @CRLF _
			 & "PDFtoPrinter.exe [path\]filename.pdf [other filenames] [" & $qt & "printer name" & $qt & _
			"] [pages=#-#] [copies=#] [focus=" & $qt & "Window title" & $qt & "] [/debug] [/r] [/R[x]] [/s] [/p:password] [/csv] [/mock]" _
			 & @CRLF & @CRLF & "Use quotation marks around [path\]filename with spaces. " _
			 & "Relative paths and filename-wildcards (* and ?) are OK." _
			 & @CRLF & @CRLF & "If more than one filename, do not use wildcard or /r or /R  (recursive option). " _
			 & @CRLF & "Default printer is used unless printer name is specified." _
			 & @CRLF & @CRLF & "Rename to PDFtoPrinterSelect.exe for select-printer menu." _
			 & @CRLF & "(menu does not appear if printer name is specified)." _
			 & @CRLF & @CRLF & "Page-range examples: 3 [or] 2-4,6,8-9 [or] " _
			 & "8- [or] z-1 for reverse-print [or] z-1:odd|even reverse-print odd/even pages [or] " _
			 & "r5-r2 for 5th-to-last to 2nd-to-last page." _
			 & @CRLF & @CRLF & "focus=   Restores focus to specified window title." _
			 & @CRLF & @CRLF & "/mydir=   Specific temp folder; use quote marks for path " _
			 & "with spaces (default is in user's temp folder)." _
			 & @CRLF & @CRLF & "/r   Recursive directory listing (this folder only, " _
			 & "default when filename includes wildcard)." _
			 & @CRLF & @CRLF & "/s   Run silently; disable user interaction and focus=" _
			 & @CRLF & @CRLF & "/csv   Generate csv file listing file(s) printed. " _
			 & "CSV file written to %temp%\PDFPrinterTmp." _
			 & @CRLF & @CRLF & "/mock   Generate csv file only; don't print PDF files." _
			 & @CRLF & @CRLF & "/Rn   Recursive directory listing to n depth of subfolders; " _
			 & "if n is absent, recurs through all subfolders." _
			 & @CRLF & @CRLF & "/p:password   Password for encrypted pdf." _
			 & @CRLF & @CRLF & "/debug   Copies print command to Windows clipboard.")
EndFunc   ;==>ShowUsage

Func ParseCmdLine()
	; Walks $CmdLine and populates the script-level option variables.
	Local $arg
	For $x = 1 To $CmdLine[0]
		$arg = $CmdLine[$x]

		If StringLower(StringRight($arg, 4)) = ".pdf" Then
			Local $full = _PathFull($arg)
			If $pdffile = "" Then
				$pdffile = $full
				_ArrayAdd($aMultiFiles, $full)
			Else
				$morethanone = 1
				$pdffile = $full
				_ArrayAdd($aMultiFiles, $full)
			EndIf

		ElseIf StringLower(StringLeft($arg, 6)) = "pages=" Then
			$pageselector = $arg

		ElseIf StringLower(StringLeft($arg, 7)) = "copies=" Then ; per Peter Mickle
			$copies = StringMid($arg, 8)
			If Not @Compiled Then ConsoleWrite("Copies: " & $copies & @LF)
			If Not StringIsInt($copies) Then
				Display("The copies= parameter must use an integer.")
				Exit $EXIT_BAD_COPIES
			EndIf
			$copies = Abs($copies)

		ElseIf StringLower(StringLeft($arg, 6)) = "focus=" Then
			$focus = StringMid($arg, 7)
			; Wrap in quotes for WinActivate if user didn't.
			If StringLeft($focus, 1) <> $qt Then $focus = $qt & $focus
			If StringRight($focus, 1) <> $qt Then $focus = $focus & $qt
			If Not @Compiled Then ConsoleWrite("$focus = " & $focus & @LF)

		ElseIf StringLower(StringLeft($arg, 7)) = "/mydir=" Then
			$myDir = StringMid($arg, 8)
			If Not @Compiled Then ConsoleWrite("$mydir = " & $myDir & @LF)

		ElseIf $arg = "/debug" Then
			$debug = 1

		ElseIf StringCompare($arg, "/r", 1) = 0 Then
			$recurLevel = 1

		ElseIf StringCompare(StringLeft($arg, 2), "/R", 1) = 0 Then
			If $arg = "/R" Then
				$recurLevel = 0 ; unlimited depth
			Else
				If StringIsInt(StringTrimLeft($arg, 2)) Then
					$recurLevel = 0 - Abs(StringTrimLeft($arg, 2))
				Else
					Display("For /Rx x must be number.")
					Exit $EXIT_BAD_RX
				EndIf
			EndIf

		ElseIf StringLower(StringLeft($arg, 3)) = "/p:" Then
			$password = StringTrimLeft($arg, 3)

		ElseIf StringLower(StringLeft($arg, 4)) = "/csv" Then
			$csv = 1

		ElseIf StringLower(StringLeft($arg, 5)) = "/mock" Then
			$mock = 1

		ElseIf StringLower(StringLeft($arg, 2)) = "/s" Then
			$silent = 1

		Else
			; Anything else is treated as a printer name.
			$printervalid = 0
			$printername = $arg
			For $i = 0 To UBound($printerlist) - 1
				If $printerlist[$i] = $arg Then
					$specified = 1
					$showselptr = 0
					$printervalid = 1
					ExitLoop
				EndIf
			Next
			; UNC printer paths are accepted even if not in the local list.
			If StringLeft($printername, 2) = "\\" Then $printervalid = 1
		EndIf
	Next
EndFunc   ;==>ParseCmdLine

Func StagePDFXChange()
	; Extract the embedded PDF-XChange Viewer and its support files to $myDir,
	; then copy in the chosen settings.dat.
	;
	; PDF-XChange Viewer Settings.dat in the working directory has higher
	; priority than one in the script directory.
	Local $custom = 0
	If FileExists($pth & "\PDF-Xchange Viewer Settings.dat") Then $custom = 2
	If FileExists(@ScriptDir & "\PDF-Xchange Viewer Settings.dat") Then $custom = 1

	DirCreate($myDir)
	FileInstall(".\PDFXCview.exe", $myDir & "\PDFXCview.exe")
	FileInstall(".\msvcp140.dll", $myDir & "\msvcp140.dll")
	FileInstall(".\msvcp140_1.dll", $myDir & "\msvcp140_1.dll")
	FileInstall(".\msvcp140_2.dll", $myDir & "\msvcp140_2.dll")
	FileInstall(".\msvcp140_atomic_wait.dll", $myDir & "\msvcp140_atomic_wait.dll")
	FileInstall(".\msvcp140_codecvt_ids.dll", $myDir & "\msvcp140_codecvt_ids.dll")
	FileInstall(".\qpdf29.dll", $myDir & "\qpdf29.dll")
	FileInstall(".\resource.dat", $myDir & "\resource.dat", 1)
	FileDelete($myDir & "\settings.dat")

	; Settings.dat handling fixed by Wilberto Morales.
	If $custom = 1 Then
		FileCopy(@ScriptDir & "\PDF-Xchange Viewer Settings.dat", $myDir & "\settings.dat", 1)
	ElseIf $custom = 2 Then
		FileCopy($pth & "\PDF-Xchange Viewer Settings.dat", $myDir & "\settings.dat", 1)
	Else
		FileInstall(".\Settings.dat", $myDir & "\settings.dat", 1)
	EndIf
EndFunc   ;==>StagePDFXChange

Func MainLoop()
	; Iterate every matched PDF and print it.
	Local $i, $encrypted, $pdfpagecount, $tmpstr0, $tmpstr, $pageselectortmp
	Local $cmdstr, $printstring

	For $i = 1 To $pdffiles[0]
		$encrypted = 0
		$pdfpagecount = 0
		$cmdstr = ""
		Local $pageselectortmp_default[2] = [0, ""]
		$pageselectortmp = $pageselectortmp_default

		; tmpstr0 = "index\nfolder\nbasename\n", used to prefix each CSV row.
		Local $folder = StringMid($pdffiles[$i], 1, StringInStr($pdffiles[$i], "\", 0, -1))
		Local $basename = StringTrimLeft($pdffiles[$i], StringInStr($pdffiles[$i], "\", 0, -1))
		$tmpstr0 = $i & @CRLF & $folder & @CRLF & $basename & @CRLF

		If Not FileExists($pdffiles[$i]) Then
			Report($pdffiles[$i] & " - File not found.")
			$errors &= @CRLF & $pdffiles[$i] & " : file not found."
			$tmpstr = $tmpstr0 & _Now() & @CRLF & @CRLF & @CRLF & @CRLF & @CRLF & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "File not found."
			_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
			ContinueLoop
		EndIf

		; ----- Get page count via qpdf ---------------------------------------
		$pdfpagecount = qpdfgetpagecount($pdffiles[$i], $password, $myDir & "\qpdf29.dll")
		If @error Then
			Report($pdfpagecount)
			$errors &= @CRLF & $pdffiles[$i] & " : " & _
					"You should install the latest VC redistributable from Microsoft." & @CRLF & @CRLF & _
					"See the download page for PDFtoPrinter."
			$tmpstr = $tmpstr0 & _Now() & @CRLF & @CRLF & @CRLF & @CRLF & $pageselector & @CRLF & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "getPageCount() error, pdf may be invalid or corrupted."
			_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
			ContinueLoop
		EndIf

		; qpdf returns a negative page count if the PDF is encrypted.
		If $pdfpagecount < 0 Then $encrypted = 1
		$pdfpagecount = Abs($pdfpagecount)

		; ----- Parse page selector -------------------------------------------
		If $pageselector <> "" Then
			$pageselectortmp = parsepage($pageselector, $pdfpagecount)
			If @error Then
				Report($pageselectortmp)
				$errors &= @CRLF & $pdffiles[$i] & " : Page selector """ & $pageselector & """ error (not valid)."
				$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & @CRLF & $pageselector & @CRLF & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "Invalid page selector: " & $pageselectortmp
				_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
				ContinueLoop
			EndIf
		Else
			Local $allPages[2] = [$pdfpagecount, ""]
			$pageselectortmp = $allPages
		EndIf

		; Build the /pages= fragment for the PDFXCview command line.
		If $pageselectortmp[1] <> "" Then
			$pgvar = "&" & $pageselectortmp[1] & $qt & " "
		Else
			$pgvar = $qt
		EndIf
		If Not @Compiled Then ConsoleWrite("Pages: " & $pgvar & @LF)

		; ----- Decide /print: vs /printto: ----------------------------------
		Local $havePrinter = True
		If $specified = 1 Then
			$printstring = " " & $qt & "/printto:" & $pgvar & $qt & $printername & $qt
		Else
			If $showselptr = 1 Then
				If Not PromptForPrinter() Then $havePrinter = False
				If $havePrinter Then $printstring = " " & $qt & "/printto:" & $pgvar & $qt & $printername & $qt
			Else
				$printstring = " " & $qt & "/print:default=no" & $pgvar
			EndIf
		EndIf

		If Not $havePrinter Then
			If $mock <> 1 Then
				$errors &= @CRLF & $pdffiles[$i] & " : You did not select a printer."
				$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & $cmdstr & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & ": You had choice, but no printer is selected."
				_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
				ContinueLoop
			EndIf
		Else
			; ----- Actually print this PDF, $copies times --------------------
			Local $printOk = PrintOneFile($pdffiles[$i], $printstring, $encrypted, $i, $tmpstr0, $pageselectortmp, $pdfpagecount, $cmdstr)
			If Not $printOk Then ContinueLoop
		EndIf

		; ----- Record success if no row was already inserted ---------------
		If UBound($summary) = $i + 1 Then
			$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & $cmdstr & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Success" & @CRLF
			_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
		EndIf

		If $debug = 1 Then
			ClipPut($qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & " " & $qt & $pdffiles[$i] & $qt)
			Display("The PDFXCview.exe print command has been copied to the clipboard. " & _
					"In case of problems, open a command window, paste in the command, and experiment with it.")
		EndIf

		; Restore focus when NOT silent (silent mode disables focus=).
		If $focus <> "" And $silent = 0 Then WinActivate($focus)
	Next
EndFunc   ;==>MainLoop

Func PrintOneFile($pdfPath, $printstring, $encrypted, $i, $tmpstr0, ByRef $pageselectortmp, $pdfpagecount, ByRef $cmdstr)
	; Runs PDFXCview to print one file $copies times.
	; Returns True on success, False if the per-file loop should `ContinueLoop`.
	Local $j, $pid, $ireslt, $tmpstr

	For $j = 1 To $copies
		If Not @Compiled Then _
				ConsoleWrite($qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & " " & $qt & $pdfPath & $qt & @LF)

		; Re-import settings.dat each time. (Original code did this; preserved.)
		If $mock <> 1 Then RunWait($qt & $myDir & "\PDFXCview.exe" & $qt & " /importp settings.dat", $myDir, @SW_SHOW)

		$cmdstr = $qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & " " & $qt & $pdfPath & $qt

		If $encrypted Then
			; ----- Encrypted PDF path --------------------------------------
			If $cli Then
				$errors &= @CRLF & $pdfPath & " : This file is password protected, no way to enter password in commandline."
				$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "This file is password protected, no way to enter password in commandline."
				_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
				Return False
			EndIf

			If $password = "" Then
				$errors &= @CRLF & $pdfPath & " : This file is password protected, but password is not provided by /p:password."
				$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "This file is password protected, but password is not provided by /p:password."
				_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
				Return False
			EndIf

			; Have a password — run viewer and feed it in.
			If $mock <> 1 Then
				$pid = Run($cmdstr, $myDir, @SW_SHOW)
				$ireslt = sendpassword($password)
				If $ireslt Then ; wrong password
					If $silent Then
						$errors &= @CRLF & $pdfPath & " : This file is password protected, but password is wrong."
						$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "This file is password protected, but password is wrong"
						_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
						ProcessClose($pid)
					Else
						ProcessWaitClose($pid, 120) ; dialog closes after two minutes
					EndIf
				EndIf
			EndIf
		Else
			; ----- Non-encrypted PDF path ----------------------------------
			If $mock <> 1 Then RunWait($cmdstr, $myDir, @SW_SHOW)
		EndIf

		; Did the Run/RunWait itself fail?
		If @error Then
			Report(@error & @CRLF & @CRLF & "Could not run PDFXCview.EXE.")
			$errors &= @CRLF & $pdfPath & " : Could not run PDFXCview.EXE."
			$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & $cmdstr & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "Could not run PDFXCview.EXE."
			_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
			Return False
		EndIf
	Next

	Return True
EndFunc   ;==>PrintOneFile

Func PromptForPrinter()
	; Show the printer-select dialog and block until $printername is set.
	; Returns True if a printer was chosen, False if cancelled.
	Local $ptrselmsg = "Select a printer for this document:"
	$printername = 0
	GetPrinter($ptrselmsg)
	Do
		Sleep(100)
	Until $printername
	Return $printername <> "nul"
EndFunc   ;==>PromptForPrinter

; -----------------------------------------------------------------------------
;  Reporting helpers
; -----------------------------------------------------------------------------

Func Report($message)
	; Shows a message either via MsgBox (GUI mode) or ConsoleWrite (CLI),
	; honoring $silent.
	If $cli = 0 Then
		If $silent = 0 Then MsgBox(0, $msgTitle, $message, 3)
	Else
		ConsoleWrite($message)
	EndIf
EndFunc   ;==>Report

Func Display($message)
	; Like Report but with no auto-close timeout (used for hard errors / usage).
	If CLIMode() Then
		ConsoleWrite($message)
	Else
		If $silent = 0 Then MsgBox(0, $msgTitle, $message)
	EndIf
EndFunc   ;==>Display

Func Flash($message)
	If CLIMode() Then
		ConsoleWrite($message)
	Else
		If $silent = 0 Then MsgBox(0, $msgTitle, $message, 2)
	EndIf
EndFunc   ;==>Flash

Func CLIMode()
	Return $cli == 1
EndFunc   ;==>CLIMode

Func ExecutableNameFlag($flagname)
	; The application will behave differently based on its filename.
	; The user can rename it to trigger some features.
	Return StringInStr(@ScriptName, $flagname)
EndFunc   ;==>ExecutableNameFlag

Func Handle_MultipleInstance()
	If _Singleton(StringReplace(@ScriptFullPath, '\', '/'), 1) = 0 Then
		Flash("PDFtoPrinter.exe is already running. Please wait.")
		Exit $EXIT_ALREADY_RUNNING
	EndIf
EndFunc   ;==>Handle_MultipleInstance

; -----------------------------------------------------------------------------
;  CSV helpers
; -----------------------------------------------------------------------------

Func _ArrayToCSV($aArray, $sDelim = Default, $sNewLine = Default, $bFinalBreak = True)
	; #FUNCTION# ====================================================================================================================
	; Name...........: _ArrayToCSV
	; Description ...: Converts a two dimensional array to CSV format
	; Author ........: czardas
	; ===============================================================================================================================
	If Not IsArray($aArray) Or UBound($aArray, 0) > 2 Or UBound($aArray) = 0 Then Return SetError(1, 0, "")
	If $sDelim = Default Then $sDelim = ","
	If $sDelim = "" Then Return SetError(2, 0, "")
	If $sNewLine = Default Then $sNewLine = @LF
	If $sNewLine = "" Then Return SetError(3, 0, "")
	If $sDelim = $sNewLine Then Return SetError(4, 0, "")

	Local $iRows = UBound($aArray), $sString = ""
	If UBound($aArray, 0) = 2 Then
		Local $iCols = UBound($aArray, 2)
		For $i = 0 To $iRows - 1
			For $j = 0 To $iCols - 1
				If StringRegExp($aArray[$i][$j], '["\r\n' & $sDelim & ']') Then
					$aArray[$i][$j] = '"' & StringReplace($aArray[$i][$j], '"', '""') & '"'
				EndIf
				$sString &= $aArray[$i][$j] & $sDelim
			Next
			$sString = StringTrimRight($sString, StringLen($sDelim)) & $sNewLine
		Next
	Else
		For $i = 0 To $iRows - 1
			If StringRegExp($aArray[$i], '["\r\n' & $sDelim & ']') Then
				$aArray[$i] = '"' & StringReplace($aArray[$i], '"', '""') & '"'
			EndIf
			$sString &= $aArray[$i] & $sNewLine
		Next
	EndIf
	If Not $bFinalBreak Then $sString = StringTrimRight($sString, StringLen($sNewLine))
	Return $sString
EndFunc   ;==>_ArrayToCSV

Func DeleteFileSafe($file)
	; Try to delete $file; return True on success, False if the file is in use
	; (e.g. open in Excel). The original DeleteFile() called Exit on failure,
	; which threw away successful print results from the same run.
	Local $h = FileOpen($file, 1)
	If $h = -1 Then
		If $silent = 0 Then _
				MsgBox(0, @ScriptName, $file & " is in use." & @CRLF & "Please close it before continuing.")
		ConsoleWrite($file & " is in use; skipping CSV write." & @CRLF)
		Return False
	EndIf
	FileClose($h)
	If FileExists($file) Then FileDelete($file)
	Return True
EndFunc   ;==>DeleteFileSafe

; -----------------------------------------------------------------------------
;  Printer enumeration / selection GUI
; -----------------------------------------------------------------------------

Func GetPrinter($ptrselmsg, $flag = 0)
	; If $flag = 1: return an array of available printers, no UI.
	; If $flag = 0: pop up a radio-button dialog; selection lands in $printername
	;               (or "nul" if the user closes the dialog).
	;
	; Note: the three Globals ($printer_list, $printer_list_ext, $printer_radio_array)
	; are declared at script scope. We just re-initialize them here.
	Local $emptyList[1]
	$printer_list = $emptyList
	$printer_list_ext = $emptyList
	$printer_radio_array = $emptyList

	Local $regprinters = "HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Devices"
	Local $currentprinter = RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Windows\", "Device")
	$defaultprinter = StringLeft($currentprinter, StringInStr($currentprinter, ",") - 1)

	Local $i = 1
	Local $erreur_reg = False
	Local $imprimante
	While Not $erreur_reg
		$imprimante = RegEnumVal($regprinters, $i)
		$erreur_reg = @error
		If Not $erreur_reg Then
			_ArrayAdd($printer_list, $imprimante)
			_ArrayAdd($printer_list_ext, $imprimante & "," & RegRead($regprinters, $imprimante))
		EndIf
		$i += 1
	WEnd
	_ArrayDelete($printer_list, 0)
	_ArrayDelete($printer_list_ext, 0)

	If $flag = 1 Then Return $printer_list

	If UBound($printer_list) >= 2 Then
		Local $groupheight = (UBound($printer_list) + 1) * 25
		Local $guiheight = $groupheight + 50
		Local $buttontop = $groupheight + 20
		Local $font = "Verdana"

		Opt("GUIOnEventMode", 1)
		$gh = GUICreate($ptrselmsg, 400, $guiheight)
		GUISetFont(10, 400, 0, $font)
		GUISetOnEvent($GUI_EVENT_CLOSE, "CLOSEClicked")
		GUICtrlCreateGroup("Available printers:", 10, 10, 380, $groupheight)

		Local $position_vertical = 5
		Local $radio
		For $j = 0 To UBound($printer_list) - 1
			$position_vertical += 25
			$radio = GUICtrlCreateRadio($printer_list[$j], 20, $position_vertical, 350, 20)
			_ArrayAdd($printer_radio_array, $radio)
			If $currentprinter = $printer_list_ext[$j] Then GUICtrlSetState($radio, $GUI_CHECKED)
		Next
		_ArrayDelete($printer_radio_array, 0)

		Local $okbutton = GUICtrlCreateButton("OK", 10, $buttontop, 50, 25)
		GUICtrlSetOnEvent($okbutton, "OKButton")
		Local $AccelKeys[2][2] = [["{ENTER}", $okbutton], ["^O", $okbutton]]
		GUISetAccelerators($AccelKeys)
		GUISetState()
	EndIf
EndFunc   ;==>GetPrinter

Func OKButton()
	Local $i
	For $i = 0 To UBound($printer_radio_array) - 1
		If GUICtrlRead($printer_radio_array[$i]) = 1 Then
			$printername = StringLeft($printer_list_ext[$i], StringInStr($printer_list_ext[$i], ",") - 1)
		EndIf
	Next
	GUIDelete($gh)
	If Not @Compiled Then ConsoleWrite($printername & @LF)
EndFunc   ;==>OKButton

Func CLOSEClicked()
	GUIDelete($gh)
	$printername = "nul"
	If Not @Compiled Then ConsoleWrite($printername & @LF)
EndFunc   ;==>CLOSEClicked

; -----------------------------------------------------------------------------
;  WinAPI helpers
; -----------------------------------------------------------------------------

Func _FileIsUsed($sFilePath) ; By Nessie. Modified by guinness.
	Local Const $hFileOpen = _WinAPI_CreateFile($sFilePath, $CREATE_ALWAYS, (DriveGetType($sFilePath)) = 'NETWORK' ? $FILE_SHARE_READ : $FILE_SHARE_WRITE)
	Local $fReturn = True
	If $hFileOpen Then
		_WinAPI_CloseHandle($hFileOpen)
		$fReturn = False
	EndIf
	If $fReturn Then $fReturn = _WinAPI_GetLastError() = $ERROR_SHARING_VIOLATION
	Return $fReturn
EndFunc   ;==>_FileIsUsed

; -----------------------------------------------------------------------------
;  PDF-XChange Viewer password dialog automation
; -----------------------------------------------------------------------------

Func sendpassword($password)
	; Send password to PDFXCview's "Enter Document Password" dialog.
	; Returns 0 on success, SetError(1) if the password was rejected.
	Local $hWnd = WinWait("Enter Document Password", "Please enter valid user or owner password", 4)
	If Not WinExists($hWnd) Then Return 0 ; no dialog appeared at all
	ControlSetText("Enter Document Password", "", 1000, $password, 1)
	ControlClick("Enter Document Password", "OK", 1)
	$hWnd = WinWait("Enter Document Password", "Please enter valid user or owner password", 1)
	If $hWnd <> 0 Then
		Return SetError(1, 0, "Wrong password.")
	EndIf
	Return 0
EndFunc   ;==>sendpassword

; -----------------------------------------------------------------------------
;  Page-range parsing
; -----------------------------------------------------------------------------

Func parsepage($pagestr, $pagecount = 3000)
	; Input  : pages=1,2-10:even,11-3,r5-r2,z:odd,-7,8-:even
	; Output : two-element array.
	;          [0] = total pages selected.
	;          [1] = "pages=..." string that PDFXCview accepts.
	; Note: "pages=1-4,1-4" prints pages 1-4 twice -- a way to copy ranges.
	; XChange Viewer accepts page numbers beyond the actual count and ignores
	; the overflow, hence the default 3000 cap.
	Local $outpage = ""
	Local $pages = StringTrimLeft($pagestr, 6)
	Local $pagearray = StringSplit($pages, ",")
	Local $totalpages = 0
	Local $outpagetmp, $seperator, $i
	For $i = 1 To UBound($pagearray) - 1
		$outpagetmp = splitexpand($pagearray[$i], $pagecount)
		If @error Then Return SetError(1, 0, "Invalid page selector " & $pagearray[$i] & ". ")
		If $outpagetmp[1] <> "" Then
			$seperator = ","
			$outpage = $outpage & $seperator & $outpagetmp[1]
		EndIf
		$totalpages += $outpagetmp[0]
	Next

	If $outpage = "" Then Return SetError(2, 0, "No Page Selected")

	Local $finaloutput[2] = [$totalpages, "pages=" & StringTrimLeft($outpage, 1)]
	Return $finaloutput
EndFunc   ;==>parsepage

Func splitexpand($str, $pagecount = 3000)
	; Expands one piece of a page expression into a comma-listed range.
	;
	; Accepted forms:
	;   2-10        keep as is
	;   11-3:even   expand to 10,8,6,4
	;   r5-r2       5th-from-last to 2nd-from-last
	;   z-1         all pages reversed
	;   -7:even     2,4,6
	;   8-          page 8 to last
	;   11          single page
	Local $output = ""
	Local $arraysplit = StringSplit($str, ":")

	Local $dashleft = StringLeft($arraysplit[1], -1 + StringInStr($arraysplit[1], "-"))
	Local $dashright = StringRight($arraysplit[1], StringLen($arraysplit[1]) - StringInStr($arraysplit[1], "-"))

	; Single page (no dash) e.g. "z", "r1", "5".
	If StringInStr($arraysplit[1], "-") = 0 Then $dashleft = $dashright

	If StringLower($dashleft) = "z" Or StringLower($dashleft) = "r1" Then
		$dashleft = $pagecount
	ElseIf StringLower(StringLeft($dashleft, 1)) = "r" And StringIsInt(StringTrimLeft($dashleft, 1)) Then
		$dashleft = $pagecount - StringRight($dashleft, StringLen($dashleft) - 1) + 1
	ElseIf $dashleft = "" Then
		$dashleft = 0
	EndIf

	If (StringLower($dashright) = "z" Or StringLower($dashright) = "r1") Or $dashright = "" Then
		$dashright = $pagecount + 1
	ElseIf StringLower(StringLeft($dashright, 1)) = "r" And StringIsInt(StringRight($dashright, StringLen($dashright) - 1)) Then
		$dashright = $pagecount - StringRight($dashright, StringLen($dashright) - 1) + 1
	EndIf

	If Not StringIsInt($dashleft) Or Not StringIsInt($dashright) Then _
			Return SetError(1, 0, "Invalid page selector on either side of -")

	Local $i
	If Number($dashright) < Number($dashleft) Then
		For $i = $dashleft To $dashright Step -1
			$output = $output & "," & $i
		Next
	Else
		For $i = $dashleft To $dashright
			$output = $output & "," & $i
		Next
	EndIf
	$output = StringTrimLeft($output, 1)

	Local $singlepagearray = StringSplit($output, ",")

	; Drop pages outside [1, $pagecount].
	Local $j
	For $j = UBound($singlepagearray) - 1 To 1 Step -1
		If $singlepagearray[$j] > $pagecount Or $singlepagearray[$j] <= 0 Then _ArrayDelete($singlepagearray, $j)
	Next

	; Apply :odd / :even filter.
	If UBound($arraysplit) = 3 Then
		If StringLower($arraysplit[2]) = "even" Then
			For $j = UBound($singlepagearray) - 1 To 1 Step -1
				If $singlepagearray[$j] > $pagecount Or BitAND(Number($singlepagearray[$j]), 1) Then _ArrayDelete($singlepagearray, $j)
			Next
		ElseIf StringLower($arraysplit[2]) = "odd" Then
			For $j = UBound($singlepagearray) - 1 To 1 Step -1
				If $singlepagearray[$j] > $pagecount Or (Not BitAND(Number($singlepagearray[$j]), 1)) Then _ArrayDelete($singlepagearray, $j)
			Next
		Else
			Return SetError(2, 0, "Keyword error, not odd or even.")
		EndIf
	EndIf

	; Collapse runs of consecutive numbers, e.g. 1,2,3,4,5,6 -> 1-6.
	$output = ""
	Local $separator
	For $j = 1 To UBound($singlepagearray) - 1
		$separator = ","
		If $j >= 2 And Number($singlepagearray[$j]) = Number($singlepagearray[$j - 1]) + 1 Then
			$separator = "-"
			If $j = UBound($singlepagearray) - 1 Then $output = $output & $separator & $singlepagearray[$j]
		Else
			$output = $output & $separator & $singlepagearray[$j]
		EndIf
	Next
	$output = StringTrimLeft($output, 1)
	Local $finaloutput[2] = [-2 + UBound(_ArrayUnique($singlepagearray)), $output]
	Return $finaloutput
EndFunc   ;==>splitexpand

; -----------------------------------------------------------------------------
;  PDF file enumeration
; -----------------------------------------------------------------------------

Func getfilematched($pdffile, $irecur, $pth = @ScriptDir)
	; Returns an array of matching PDF files. $pdffile may contain * or ?.
	;   $irecur =  0  recurse subfolders to unlimited depth
	;   $irecur =  1  current folder only
	;   $irecur = -x  recurse to x levels deep
	$pdffile = _PathFull($pdffile)

	If StringLower(StringRight($pdffile, 4)) <> ".pdf" Then
		Return SetError(2, 0, "Error: [path]Filename must end with .pdf, but filename supports wildcard * and ? (path does not support wildcards.)")
	EndIf

	$pth = StringMid($pdffile, 1, StringInStr($pdffile, "\", 0, -1))
	Local $filter = StringTrimLeft($pdffile, StringInStr($pdffile, "\", 0, -1))
	Local $aArray

	If $irecur = 0 Then
		$aArray = _FileListToArrayRec($pth, $filter, $FLTAR_FILES, $FLTAR_RECUR, $FLTAR_NOSORT, $FLTAR_FULLPATH)
	ElseIf $irecur = 1 Then
		$aArray = _FileListToArray($pth, $filter, $FLTAR_FILES, True)
	ElseIf $irecur < 0 And IsInt($irecur) Then
		$aArray = _FileListToArrayRec($pth, $filter, $FLTAR_FILES, $irecur, $FLTAR_NOSORT, $FLTAR_FULLPATH)
	Else
		Return SetError(1, 0, "getfilematched($pdffile,$irecur). Unsupported $irecur, only 0, 1, or a negative integer are supported.")
	EndIf

	If $aArray = "" Then Return SetError(3, 0, "No pdf file matched.")
	Return $aArray
EndFunc   ;==>getfilematched

; -----------------------------------------------------------------------------
;  qpdf integration -- get page count, handle encryption detection
; -----------------------------------------------------------------------------

Func qpdfgetpagecount($pdffilename, $pdfpassword = "", $qpdfdll = "qpdf29.dll")
	; Returns the page count. A negative result means the PDF is encrypted.
	Local $encrypted = 0

	If Not FileExists($pdffilename) Then Return SetError(1, 0, "Can't find " & $pdffilename & ".")
	If Not FileExists($qpdfdll) Then Return SetError(1, 0, "Can't find " & $qpdfdll & ".")

	; qpdf29.dll uses ANSI strings. Going via a hex/byte buffer avoids data
	; loss when the file path contains non-ASCII characters.
	Local $pdffilenameHex = StringToBinary($pdffilename, 4)
	Local $BufferSize = StringLen($pdffilenameHex) * 2
	Local $pdffilenameptr = DllStructCreate("byte[" & $BufferSize & "]")
	DllStructSetData($pdffilenameptr, 1, $pdffilenameHex)

	Local $hDLL = DllOpen($qpdfdll)
	If $hDLL = -1 Then Return SetError(2, 0, "DllOpen() error: Can't open " & $qpdfdll & ".")

	; qpdf_data qpdf_init();
	Local $qpdfhdl = DllCall($hDLL, "PTR:cdecl", "qpdf_init")
	If @error Then
		DllClose($hDLL)
		Return SetError(3, 0, "Dllcall() qpdf_init error: error code: " & @error)
	EndIf

	; QPDF_ERROR_CODE qpdf_read(qpdf_data, char const* filename, char const* password);
	Local $pdfopen = DllCall($hDLL, "INT:cdecl", "qpdf_read", _
			"PTR", $qpdfhdl[0], _
			"PTR", DllStructGetPtr($pdffilenameptr), _
			"STR", Null)
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(4, 0, "Dllcall() qpdf_read error.")
	EndIf

	Local $pdfencrypt
	If $pdfopen[0] <> 0 Then
		$pdfencrypt = DllCall($hDLL, "Boolean:cdecl", "qpdf_is_encrypted", "PTR", $qpdfhdl[0])
		If @error Then
			cleanup($qpdfhdl[0], $hDLL)
			Return SetError(4, 0, "Dllcall() qpdf_is_encrypted error.")
		EndIf
		If $pdfencrypt[0] Then $encrypted = 1
	EndIf

	If $encrypted And $pdfpassword <> "" Then
		$pdfopen = DllCall($hDLL, "INT:cdecl", "qpdf_read", _
				"PTR", $qpdfhdl[0], _
				"PTR", DllStructGetPtr($pdffilenameptr), _
				"STR", $pdfpassword)
		If @error Then
			cleanup($qpdfhdl[0], $hDLL)
			Return SetError(4, 0, "Dllcall() qpdf_read error.")
		EndIf
	EndIf

	; QPDF_BOOL qpdf_has_error(qpdf_data);
	Local $pdfhaserror = DllCall($hDLL, "Boolean:cdecl", "qpdf_has_error", "PTR", $qpdfhdl[0])
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(4, 0, "Dllcall() qpdf_has_error.")
	EndIf
	If $pdfhaserror[0] Then
		Local $pdferror = DllCall($hDLL, "INT:cdecl", "qpdf_get_error", "PTR", $qpdfhdl[0])
		Local $pdferrorcode = DllCall($hDLL, "INT:cdecl", "qpdf_get_error_code", "PTR", $qpdfhdl[0], "INT", $pdferror[0])
		If $pdferrorcode[0] <> 4 Then ; 4 = encrypted; treat anything else as fatal
			Local $pdffullerror = DllCall($hDLL, "STR*:cdecl", "qpdf_get_error_full_text", "PTR", $qpdfhdl[0], "INT", $pdferror[0])
			Return SetError(4, 0, "QPDF open_pdf_has_error, PDF file might be corrupted. Error detail: " & @CRLF & $pdffullerror[0])
		EndIf
	EndIf

	; Navigate /Root -> /Pages -> /Count.
	Local $pdfroot = DllCall($hDLL, "INT:cdecl", "qpdf_get_root", "PTR", $qpdfhdl[0])
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(5, 0, "Dllcall() qpdf_get_root error.")
	EndIf

	Local $pdfrootisdict = DllCall($hDLL, "boolean:cdecl", "qpdf_oh_is_dictionary", "PTR", $qpdfhdl[0], "int", $pdfroot[0])
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(6, 0, "Dllcall() qpdf_oh_is_dictionary error.")
	EndIf

	Local $pdfroothaskey = DllCall($hDLL, "boolean:cdecl", "qpdf_oh_has_key", "PTR", $qpdfhdl[0], "int", $pdfroot[0], "STR", "/Pages")
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(7, 0, "Dllcall() qpdf_oh_has_key error.")
	EndIf

	Local $pdfpagesobjnum = DllCall($hDLL, "INT:cdecl", "qpdf_oh_get_key", "PTR", $qpdfhdl[0], "int", $pdfroot[0], "STR", "/Pages")
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(8, 0, "Dllcall() qpdf_oh_get_key(/Root/Pages) error.")
	EndIf

	Local $pdfpagescount = DllCall($hDLL, "INT:cdecl", "qpdf_oh_get_key", "PTR", $qpdfhdl[0], "int", $pdfpagesobjnum[0], "STR", "/Count")
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(9, 0, "Dllcall() qpdf_oh_get_key(/Root/Pages/Count) error.")
	EndIf

	Local $pdfPages = DllCall($hDLL, "STR*:cdecl", "qpdf_oh_unparse_resolved", "PTR", $qpdfhdl[0], "int", $pdfpagescount[0])
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(9, 0, "Dllcall() qpdf_oh_unparse_resolved error.")
	EndIf

	cleanup($qpdfhdl[0], $hDLL)
	If $encrypted Then Return 0 - $pdfPages[0]
	Return $pdfPages[0]
EndFunc   ;==>qpdfgetpagecount

Func cleanup($qpdfhdl, $hDLL)
	; void qpdf_cleanup(qpdf_data* qpdf);  -- note PTR* (pointer to pointer).
	DllCall($hDLL, "NONE:cdecl", "qpdf_cleanup", "PTR*", $qpdfhdl)
	DllClose($hDLL)
EndFunc   ;==>cleanup
