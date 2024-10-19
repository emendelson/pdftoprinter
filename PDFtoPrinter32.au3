#Region ;**** Directives created by AutoIt3Wrapper_GUI ****
#AutoIt3Wrapper_Icon=pdftoprinter.ico
#AutoIt3Wrapper_Outfile=PDFtoPrinter.exe
#AutoIt3Wrapper_Change2CUI=y
#AutoIt3Wrapper_Res_Description=PDFtoPrinter.exe
#AutoIt3Wrapper_Res_Fileversion=2.0.3.209
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
#include <string.au3>
#include <file.au3>
#include <Date.au3>

Global $msgTitle = "PDFtoPrinter.exe"
Global $specified = 0
Global $cli = 0
Global $debug = 0
Global $printername
Global $defaultprinter
Global $gh
Global $code
Global $silent = 0 ; Do not popup error or warning or password window.

Local $pth = @WorkingDir
If StringRight($pth, 1) = "\" Then $pth = StringTrimRight($pth, 1) ;Working directory is disk root, C:\
Local $fn = @ScriptName
Local $noprinter = 0
Local $space = " "
Local $qt = Chr(34)
Local $pdffile = ""
Local $showselptr = 0
Local $pgvar = " "
Local $copies = 1
Local $focus = ""
Local $printstring
Local $recurLevel = 1 ;Recur all files matching filename in this folder.
Local $password = ""
Local $csv = 0 ; Change to 1 to output csv.
Local $mock = 0 ; Really print or just simulate.
Local $pageselector = 0 ; no page selector
Local $pdfgiven = 0 ; What if a printfile name ends with .pdf? deal with it.
Local $printervalid = 1
Local $pageselector = ""
Local $aMultiFiles[0]
Local $morethanone = 0
;;;; new - disables qpdf
Local $qpdf = 0

Opt("WinTitleMatchMode", -2)

Global $OSBuild = 1
$OSBuild = FileGetVersion("user32.dll")
If (StringRegExp($OSBuild, "^(.*)\.(.+)\.(.+)\.(.*)$")) Then
	$OSBuild = StringRegExp($OSBuild, "^(.*)\.(.+)\.(.+)\.(.*)$", 1)
	$OSBuild = $OSBuild[2]
Else
	$OSBuild = @OSBuild
EndIf
If $OSBuild < 10000 Then
	Display("Windows 10, Windows Server 2016, or later required.")
	$code = 1
	Exit $code
EndIf

If Not ExecutableNameFlag("m") Then
	Handle_MultipleInstance()
EndIf

If ExecutableNameFlag("select") Then $showselptr = 1 ;Printer selection GUI popup
If ExecutableNameFlag("debug") Then $debug = 1
If ExecutableNameFlag("cli") Then $cli = 1 ;Commandline interface only, no gui window

Local $cmln = $CmdLine[0] ;Total commandline parameters entered.
If $cmln = 0 Then    ;If no paramters given
	Display("Usage:" & @CRLF & @CRLF _
			 & "PDFtoPrinter.exe [path\]filename.pdf [other filenames] [" & $qt & "printer name" & _
			$qt & "] [pages=#-#] [copies=#] [focus=" & $qt & "Window title" & $qt & "] [/debug] [/r] [/R[x]] [/s] [/p:password] [/csv] [/mock]" _
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
			 & @CRLF & @CRLF & "/r   Recursive directory listing (this folder only, " _
			 & "default when filename includes wildcard)." _
			 & @CRLF & @CRLF & "/s   Run silently; disable user interaction and focus=" _
			 & @CRLF & @CRLF & "/csv   Generate csv file listing file(s) printed. " _
			 & "CSV file written to %temp%\pdftoprintertmp." _
			 & @CRLF & @CRLF & "/mock   Generate csv file only; don't print PDF files." _
			 & @CRLF & @CRLF & "/Rn   Recursive directory listing to n depth of subfolders; " _
			 & "if n is absent, recurs through all subfolders." _
			 & @CRLF & @CRLF & "/p:password   Password for encrypted pdf." _
			 & @CRLF & @CRLF & "/debug   Copies print command to Windows clipboard.")
	$code = 2
	Exit $code
EndIf


;/r recursive this folder
;/Rn recursive directory listing this folder and sub folders to depth n
;/p pdf password
;/verbose not implemented
;/csv output csv
;/s(password) if no password or password is wrong or pdf corrupt or invalid pdf no warning gui popup, but log it.
;/mock generate csv, not real print command is run.


;If printer does not exist in this machine
$printerlist = GetPrinter("", 1)
If UBound($printerlist) = 0 And $mock = 0 Then
	Display("No printer found.")
	$code = 3
	Exit $code
EndIf

; Parse command-line parameters.
If $cmln >= 1 Then
	For $x = 1 To $CmdLine[0]
		If StringLower(StringRight($CmdLine[$x], 4)) = ".pdf" Then
			; If first parameter ends with .pdf: If printer name also ends with .pdf, pdf filename should appear before printer name.
			If $pdfgiven = 0 Then
				$pdfgiven = 1
				$pdffile = $CmdLine[$x]
				$pdffile = _PathFull($pdffile)
				_ArrayAdd($aMultiFiles, $pdffile)
			Else
				$morethanone = 1
				$pdffile = $CmdLine[$x]
				$pdffile = _PathFull($pdffile)
				_ArrayAdd($aMultiFiles, $pdffile)
			EndIf
		ElseIf StringLower(StringLeft($CmdLine[$x], 6)) = "pages=" Then
			$pageselector = $cmdline[$x]
		ElseIf StringLower(StringLeft($CmdLine[$x], 7)) = "copies=" Then ; per Peter Mickle
			$copies = (StringMid($CmdLine[$x], 8, -1))
			If Not @Compiled Then ConsoleWrite("Copies: " & $copies & @LF)
			If Not StringIsInt($copies) Then
				Display("The copies= parameter must use an integer.")
				$code = 4
				Exit $code
			EndIf
			$copies = Abs($copies) ; negative integer is interger too.
		ElseIf StringLower(StringLeft($CmdLine[$x], 6)) = "focus=" Then ; return Focus
			$focus = (StringMid($CmdLine[$x], 7, -1))
			If Not StringLeft($focus, 1) = Chr(34) Then $focus = Chr(34) & $focus
			If Not StringRight($focus, 1) = Chr(34) Then $focus = $focus & Chr(34)
			If Not @Compiled Then ConsoleWrite("$focus = " & $focus & @LF)
		ElseIf $CmdLine[$x] = "/debug" Then
			$debug = 1
		ElseIf StringCompare($CmdLine[$x], "/r", 1) = 0 Then
			$recurLevel = 1
		ElseIf StringCompare(StringLeft($CmdLine[$x], 2), "/R", 1) = 0 Then
			If $CmdLine[$x] = "/R" Then
				$recurLevel = 0 ; recursive directory listing to unlimited depth
			Else
				If StringIsInt(StringTrimLeft($CmdLine[$x], 2)) Then
					$recurLevel = 0 - Abs(StringTrimLeft($CmdLine[$x], 2))
				Else
					Display("For /Rx x must be number.")
					$code = 5
					Exit $code
				EndIf
			EndIf
		ElseIf StringLower(StringLeft($CmdLine[$x], 3)) = "/p:" Then
			$password = StringTrimLeft($cmdline[$x], 3)
		ElseIf StringLower(StringLeft($CmdLine[$x], 4)) = "/csv" Then
			$csv = 1
		ElseIf StringLower(StringLeft($CmdLine[$x], 2)) = "/s" Then
			$silent = 1
		ElseIf StringLower(StringLeft($CmdLine[$x], 5)) = "/mock" Then
			$mock = 1
		Else
			$printervalid = 0
			$printername = $CmdLine[$x]
			For $i = 0 To UBound($printerlist) - 1
				If $printerlist[$i] = $CmdLine[$x] Then
					$specified = 1
					$showselptr = 0
					$printervalid = 1
					ExitLoop
				EndIf
			Next
			If StringLeft($printername, 2) = "\\" Then
				$printervalid = 1
			EndIf
		EndIf
	Next
EndIf

; if no printer or invalid parameters encountered:
If $printervalid = 0 Then
	Display("Printer name """ & $printername & """ not found or argument """ & $printername & """is not valid.")
	$code = 6
	Exit $code
EndIf


; if no pdf file name given:
If $pdffile = "" Then
	Display("Wrong arguments: no [path]filename with .pdf extension provided.")
	$code = 7
	Exit $code
EndIf

; get pdf file list
If $recurLevel <= 1 Then
	$pdffiles = getfilematched($pdffile, $recurLevel, $pth)
	If @error Then
		Display($pdffiles)
		$code = 8
		Exit $code
	EndIf
Else
	Local $pdffiles[2]
	$pdffiles[0] = 1
	$pdffiles[1] = $pdffile
EndIf

; if PDFXchange Viewer settings available in working directory or script directory, use it.
; PDF-Xchange Viewer Settings.dat in working directory has higher priority.
Local $custom = 0
If FileExists($pth & "\PDF-Xchange Viewer Settings.dat") Then $custom = 2
If FileExists(@ScriptDir & "\PDF-Xchange Viewer Settings.dat") Then $custom = 1

; extract PDFXChange Viewer and settings.dat and qpdf29.dll ... to %temp% directory.
Local $myDir = @TempDir & "\PDFPrinterTmp"
DirCreate($myDir)
$tmp = FileInstall(".\PDFXCview.exe", $myDir & "\PDFXCview.exe")
FileInstall(".\msvcp140.dll", $myDir & "\msvcp140.dll")
FileInstall(".\msvcp140_1.dll", $myDir & "\msvcp140_1.dll")
FileInstall(".\msvcp140_2.dll", $myDir & "\msvcp140_2.dll")
FileInstall(".\msvcp140_atomic_wait.dll", $myDir & "\msvcp140_atomic_wait.dll")
FileInstall(".\msvcp140_codecvt_ids.dll", $myDir & "\msvcp140_codecvt_ids.dll")
FileInstall(".\qpdf29.dll", $myDir & "\qpdf29.dll")
FileInstall(".\resource.dat", $myDir & "\resource.dat", 1)
FileDelete($myDir & "\settings.dat")

; next lines fixed by Wilberto Morales
If $custom = 1 Then
	FileCopy(@ScriptDir & "\PDF-Xchange Viewer Settings.dat", $myDir & "\settings.dat", 1)
ElseIf $custom = 2 Then
	FileCopy($pth & "\PDF-Xchange Viewer Settings.dat", $myDir & "\settings.dat", 1)
Else
	FileInstall(".\Settings.dat", $myDir & "\settings.dat", 1)
EndIf

$errors = "" ; variable to collect error information.

Local $summary[1][12] ; array variable to collect information for CSV.

; csv file title
$tmpstr = "Index, Filepath, Filename, Datetime, IsEntrypted, PageCount, Command string executed(can be used for bat), Page selector, Total pages selected, Copies,Result(assume all actions reqiuring human interaction is successful even you cancelled the password input window.), Error info"

_ArrayInsert($summary, 0, $tmpstr, 0, ",")

; if more than one file specified on the command line, then use those files as the pdf file list
If $morethanone = 1 Then
	$fileCount = UBound($aMultiFiles)
	_ArrayInsert($aMultiFiles, 0, $fileCount)
	$pdffiles = $aMultiFiles
EndIf
; _ArrayDisplay($pdffiles)
; _ArrayDisplay($aMultiFiles)
; Exit

; loop all matching pdf files
For $i = 1 To $pdffiles[0]
	$encrypted = 0 ;
	$tmpstr = ""
	$tmpstr0 = $i & @CRLF & StringMid($pdffiles[$i], 1, StringInStr($pdffiles[$i], "\", 0, -1)) & @CRLF & StringTrimLeft($pdffiles[$i], StringInStr($pdffiles[$i], "\", 0, -1)) & @CRLF

	If Not FileExists($pdffiles[$i]) Then
		If $cli = 0 Then
			If $silent = 0 Then MsgBox(0, $msgTitle, $pdffiles[$i] & " - File not found.", 3)
		Else
			ConsoleWrite($pdffile[$i] & " - File not found.")
		EndIf
		$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : file not found."
		$tmpstr = $tmpstr0 & _Now() & @CRLF & @CRLF & @CRLF & @CRLF & @CRLF & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "File not found."
		_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
		ContinueLoop ;loop next pdf file.
	EndIf

	;;; new - disables qpdf
	If $pageselector <> "" Then $qpdf = 1
	;;; new - disables qpdf
	If $qpdf = 1 Then
		; get page count of pdf file. If qpdf29.dll does not exist in %temp%\pdftoprintertmp, try to load qpdf29.dll in the script folder.
		$pdfpagecount = qpdfgetpagecount($pdffiles[$i], $password, $myDir & "\qpdf29.dll")
		If @error Then ; error getting pdf page count, means pdf is invalid or corrupted.
			; pdf viewer may able to repair some corrupted pdf file, no chance to do so now.
			; qpdf can get pagecount of encrypted pdf without password, so error is not set when pdf is encrypted.
			If $cli = 0 Then
				If $silent = 0 Then MsgBox(0, $msgTitle, $pdfpagecount, 3)
			Else
				ConsoleWrite($pdfpagecount)
			EndIf
			$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : getPageCount() error, pdf file Corrupted?"
			$tmpstr = $tmpstr0 & _Now() & @CRLF & @CRLF & @CRLF & @CRLF & $pageselector & @CRLF & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "getPageCount() error, pdf maybe invalid or corrupted."
			_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
			ContinueLoop ;loop next pdf file.
		EndIf

		;if pdfpagecount is less than 0, denote pdf is encrypted.
		If $pdfpagecount < 0 Then $encrypted = 1
		$pdfpagecount = Abs($pdfpagecount)

		;if pageseletor is not provided, all pages will be printed.
		If $pageselector <> "" Then
			Local $pageselectortmp = parsepage($pageselector, $pdfpagecount)
			If @error Then
				If $cli = 0 Then
					If $silent = 0 Then MsgBox(0, $msgTitle, $pageselectortmp, 3)
				Else
					ConsoleWrite($pageselectortmp)
				EndIf
				$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : Page selector """ & $pageselector & """ error(not valid)."
				$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & @CRLF & $pageselector & @CRLF & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "Invalid page selector: " & $pageselectortmp
				_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
				ContinueLoop ;loop next pdf file.
			EndIf
		Else
			Local $pageselectortmp[2] = [$pdfpagecount, ""]
		EndIf

		$pgvar = "&" & $pageselectortmp[1] & $qt & " " ;/Pages= variable
		If Not @Compiled Then ConsoleWrite("Pages: " & $pgvar & @LF)

		If $pgvar = " " Then $pgvar = $qt

	EndIf

	If $specified = 1 Then ; printer name specified in command line parameters.
		; $printstring = " /print:printer=" & $qt & $printername & $qt & $pgvar ; fixed per Peter Mickle
		$printstring = " " & $qt & "/printto:" & $pgvar & $qt & $printername & $qt

		For $j = 1 To $copies
			;msgbox(0,"",$qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & " " & $qt & $pdffiles[$i] & $qt)
			If Not @Compiled Then ConsoleWrite("specified: " & @LF & $qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & _
					" " & $qt & $pdffiles[$i] & $qt & @LF)
			If $mock <> 1 Then RunWait($qt & $myDir & "\PDFXCview.exe" & $qt & " /importp settings.dat", $myDir, @SW_SHOW)

			If $encrypted Then
				If $cli Then
					$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : This file is password protected, no way to enter password in commandline."
					$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "This file is password protected, no way to enter password in commandline."
					_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
					ContinueLoop 2
				EndIf
				If $password = "" Then
					$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : This file is password protected, but password is not provided by /p:password."
					$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "his file is password protected, but password is not provided by /p:password."
					_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
					ContinueLoop 2
				Else ;if pdf encryped and password given.
					$cmdstr = $qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & " " & $qt & $pdffiles[$i] & $qt
					If $mock <> 1 Then
						$pid = Run($qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & _
								" " & $qt & $pdffiles[$i] & $qt, $myDir, @SW_SHOW) ;run pdfxcview to print pdf.

						$ireslt = sendpassword($password) ;send password to password input window.

						If $ireslt Then ;if password is wrong
							If $silent Then
								$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : This file is password protected, but password is wrong."
								$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "This file is password protected, but password is wrong"
								_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
								ProcessClose($pid) ;force pdfxcview.exe to close
							Else ;open a dialog for entering password
								ProcessWaitClose($pid, 120)  ;dialog box closes after two minutes; what happens next?
							EndIf
						EndIf
					EndIf
				EndIf
			Else     ;pdf not encrypted.
				;Will any other warning or error windows pop up? I don't know, otherwise I should force close pdfxcview when silent=1.
				$cmdstr = $qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & " " & $qt & $pdffiles[$i] & $qt
				If $mock <> 1 Then RunWait($qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & _
						" " & $qt & $pdffiles[$i] & $qt, $myDir, @SW_SHOW)
			EndIf

			; error running pdfxcview.exe
			If @error Then
				If $cli = 0 Then
					If $silent = 0 Then MsgBox(0, $msgTitle, @error & @CRLF & @CRLF & "Could not run PDFXCview.EXE.", 3)
				Else
					ConsoleWrite(@error & @CRLF & @CRLF & "Could not run PDFXCview.EXE.")
				EndIf
				$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : Could not run PDFXCview.EXE."
				$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & $cmdstr & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "Could not run PDFXCview.EXE"
				_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
				ContinueLoop 2
			EndIf
		Next

	Else ;if printer is not specified in commandline, use default or let user select printer

		If $showselptr = 1 Then
			Local $ptrselmsg = "Select a printer for this document:"
			$printername = 0
			GetPrinter($ptrselmsg)
			Do
				Sleep(100)
			Until $printername
			$noprinter = 0
			If $printername = "nul" Then
				$noprinter = 1
			EndIf
			$printstring = " " & $qt & "/printto:" & $pgvar & $qt & $printername & $qt   ; fix by Mr. Liu
		Else
			$printstring = " " & $qt & "/print:default=no" & $pgvar ; & $qt
		EndIf

		If $noprinter = 0 Then
			For $j = 1 To $copies
				If $mock <> 1 Then RunWait($qt & $myDir & "\PDFXCview.exe" & $qt & " /importp settings.dat", $myDir, @SW_SHOW)
				If $encrypted Then
					If $cli Then
						$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : This file is password protected, no way to enter in commandline."
						$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "This file is password protected, no way to enter password in commandline."
						_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
						ContinueLoop 2
					EndIf

					If $password = "" Then
						$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : This file is password protected, but password is not provided by /p:password."
						$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "This file is password protected, but password is not provided by /p:password."
						_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
						ContinueLoop 2
					Else
						$cmdstr = $qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & " " & $qt & $pdffiles[$i] & $qt
						If $mock <> 1 Then
							$pid = Run($qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & " " & _
									$qt & $pdffiles[$i] & $qt, $myDir, @SW_SHOW)
							$ireslt = sendpassword($password)
							If $ireslt Then
								If $silent Then ; wrong password
									$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : This file is password protected, but password is wrong."
									$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "This file is password protected, but password is wrong"
									_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
									ProcessClose($pid)
								Else
									ProcessWaitClose($pid, 120)
									; dialog waits two minutes before closing; what happens next?
								EndIf
							EndIf
						EndIf
					EndIf
				Else
					$cmdstr = $qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & " " & $qt & $pdffiles[$i] & $qt
					If $mock <> 1 Then RunWait($qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & " " & _
							$qt & $pdffiles[$i] & $qt, $myDir, @SW_SHOW)
				EndIf
				If @error Then
					If $cli = 0 Then
						If $silent = 0 Then MsgBox(0, $msgTitle, @error & @CRLF & @CRLF & "Could not run PDFXCview.EXE.", 3)
					Else
						ConsoleWrite(@error & @CRLF & @CRLF & "Could not run PDFXCview.EXE.")
					EndIf
					$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : Could not run PDFXCview.EXE."
					$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & $cmdstr & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & "Could not run PDFXCview.EXE."
					_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
					ContinueLoop 2
				EndIf
			Next
		Else ; no printer selected
			If $mock <> 1 Then
				$errors = @CRLF & $errors & @CRLF & $pdffiles[$i] & " : You did not select a printer."
				$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & $cmdstr & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Fail" & @CRLF & ": You had choice, but no printer is selected."
				_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
				ContinueLoop
			EndIf
		EndIf

	EndIf
	If UBound($summary) = $i + 1 Then ; no error occured earlier; otherwise loop is skipped.
		$tmpstr = $tmpstr0 & _Now() & @CRLF & $encrypted & @CRLF & $pdfpagecount & @CRLF & $cmdstr & @CRLF & $pageselector & @CRLF & $pageselectortmp[0] & @CRLF & $copies & @CRLF & "Success" & @CRLF
		_ArrayInsert($summary, $i, $tmpstr, 0, @CRLF, @TAB)
	EndIf

	; script name has string "debug".
	If $debug = 1 Then
		ClipPut($qt & $myDir & "\PDFXCview.exe" & $qt & $printstring & _
				" " & $qt & $pdffiles[$i] & $qt)
		Display("The PDFXCview.exe print command has been copied to the clipboard. " & _
				"In case of problems, open a command window, paste in the command, and experiment with it.")
	EndIf
	If $focus <> "" And $silent <> 0 Then WinActivate($focus)
Next

If $errors <> "" Then
	If $cli = 0 Then
		If $silent = 0 Then MsgBox(0, "Error lists:", $errors)
	EndIf
	ConsoleWrite("Error lists: " & @CRLF & $errors)
	$code = 9
Else
	$code = 0
EndIf

;write csv file
If $csv = 1 Or $mock = 1 Then
	Local $output_file = $myDir & "\summary_utf8.csv"
	DeleteFile($output_file)
	FileWrite($output_file, _ArrayToCSV($summary))
EndIf

; cleanup $mydir?
;DeleteFile($myDir & "\PDFXCview.exe")
;DeleteFile($myDir & "\qpdf29.dll")
;DeleteFile($myDir & "\resource.dat")
;DeleteFile($myDir & "\settings.dat")

Exit $code    ;main script ends here.

Func _ArrayToCSV($aArray, $sDelim = Default, $sNewLine = Default, $bFinalBreak = True)
	; #FUNCTION# ====================================================================================================================
	; Name...........: _ArrayToCSV
	; Description ...: Converts a two dimensional array to CSV format
	; Syntax.........: _ArrayToCSV ( $aArray [, $sDelim [, $sNewLine [, $bFinalBreak ]]] )
	; Parameters ....: $aArray      - The array to convert
	;                  $sDelim      - Optional - Delimiter set to comma by default (see comments)
	;                  $sNewLine    - Optional - New Line set to @LF by default (see comments)
	;                  $bFinalBreak - Set to true in accordance with common practice => CSV Line termination
	; Return values .: Success  - Returns a string in CSV format
	;                  Failure  - Sets @error to:
	;                 |@error = 1 - First parameter is not a valid array
	;                 |@error = 2 - Second parameter is not a valid string
	;                 |@error = 3 - Third parameter is not a valid string
	;                 |@error = 4 - 2nd and 3rd parameters must be different characters
	; Author ........: czardas
	; Comments ......; One dimensional arrays are returned as multiline text (without delimiters)
	;                ; Some users may need to set the second parameter to semicolon to return the prefered CSV format
	;                ; To convert to TSV use @TAB for the second parameter
	;                ; Some users may wish to set the third parameter to @CRLF
	; ===============================================================================================================================
	If Not IsArray($aArray) Or UBound($aArray, 0) > 2 Or UBound($aArray) = 0 Then Return SetError(1, 0, "")
	If $sDelim = Default Then $sDelim = ","
	If $sDelim = "" Then Return SetError(2, 0, "")
	If $sNewLine = Default Then $sNewLine = @LF
	If $sNewLine = "" Then Return SetError(3, 0, "")
	If $sDelim = $sNewLine Then Return SetError(4, 0, "")

	Local $iRows = UBound($aArray), $sString = ""
	If UBound($aArray, 0) = 2 Then ; Check if the array has two dimensions
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
	Else ; The delimiter is not needed
		For $i = 0 To $iRows - 1
			If StringRegExp($aArray[$i], '["\r\n' & $sDelim & ']') Then
				$aArray[$i] = '"' & StringReplace($aArray[$i], '"', '""') & '"'
			EndIf
			$sString &= $aArray[$i] & $sNewLine
		Next
	EndIf
	If Not $bFinalBreak Then $sString = StringTrimRight($sString, StringLen($sNewLine)) ; Delete any newline characters added to the end of the string
	Return $sString
EndFunc   ;==>_ArrayToCSV

Func DeleteFile($file) ; è unito con  _Spediamo_it_CSV()

	$file_usage = FileOpen($file, 1)

	If $file_usage = -1 Then
		If $silent = 0 Then MsgBox(0, @ScriptName, $file & " is in use." & @CRLF & _
				'Please close it before continuing.')
		$code = 10
		Exit $code
	EndIf

	FileClose($file_usage)

	If FileExists($file) Then
		FileDelete($file)
	EndIf

EndFunc   ;==>DeleteFile

Func GetPrinter($ptrselmsg, $flag = 0)
	;$ptrselmsg set select printer GUI window title.
	;If flag=1, just get available printer list. No select window popup, return an array containing all printers
	;If flag=0, popup window for user to select printer, selected printer is returned, otherwise "nul" is returned.
	Global $printer_list[1]
	Global $printer_list_ext[1]
	Global $printer_radio_array[1]
	$regprinters = "HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Devices"
	$currentprinter = RegRead("HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\Windows\", "Device")
	$defaultprinter = StringLeft($currentprinter, StringInStr($currentprinter, ",") - 1)
	Local $i = 1   ; fix by Mr. Liu
	Dim $erreur_reg = False
	While Not $erreur_reg
		$imprimante = RegEnumVal($regprinters, $i)
		$erreur_reg = @error
		If Not $erreur_reg Then
			_ArrayAdd($printer_list, $imprimante)
			_ArrayAdd($printer_list_ext, $imprimante & "," & RegRead($regprinters, $imprimante))
		EndIf
		$i = $i + 1
	WEnd
	_ArrayDelete($printer_list, 0)
	_ArrayDelete($printer_list_ext, 0)
	If $flag = 1 Then Return $printer_list ;What if no printer added? what error?
	;msgbox(0,"",ubound($printer_list))

	If UBound($printer_list) >= 2 Then ;; if 2 or more printers available, we show the dialog
		Dim $groupheight = (UBound($printer_list) + 1) * 25 ;; 30
		Dim $guiheight = $groupheight + 50
		Dim $buttontop = $groupheight + 20
		Opt("GUIOnEventMode", 1)
		$gh = GUICreate($ptrselmsg, 400, $guiheight)
		Dim $font = "Verdana"
		GUISetFont(10, 400, 0, $font)
		GUISetOnEvent($GUI_EVENT_CLOSE, "CLOSEClicked")
		GUISetFont(10, 400, 0, $font)
		GUICtrlCreateGroup("Available printers:", 10, 10, 380, $groupheight)
		Dim $position_vertical = 5 ;; 0
		For $i = 0 To UBound($printer_list) - 1 Step 1
			GUISetFont(10, 400, 0, $font)
			$position_vertical = $position_vertical + 25 ;; 30
			$radio = GUICtrlCreateRadio($printer_list[$i], 20, $position_vertical, 350, 20)
			_ArrayAdd($printer_radio_array, $radio)
			If $currentprinter = $printer_list_ext[$i] Then
				GUICtrlSetState($radio, $GUI_CHECKED)
			EndIf
		Next
		_ArrayDelete($printer_radio_array, 0)
		GUISetFont(10, 400, 0, $font)
		$okbutton = GUICtrlCreateButton("OK", 10, $buttontop, 50, 25)
		GUICtrlSetOnEvent($okbutton, "OKButton")
		Local $AccelKeys[2][2] = [["{ENTER}", $okbutton], ["^O", $okbutton]]
		GUISetAccelerators($AccelKeys)
		GUISetState()
	EndIf
EndFunc   ;==>GetPrinter

Func OKButton()
	For $i = 0 To UBound($printer_radio_array) - 1 Step 1
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

;~ Func Cancelled()
;~ 	If $cli = 0 Then
;~ 		MsgBox(262144, $msgTitle, "Script cancelled.")
;~ 	EndIf
;~ 	Exit
;~ EndFunc   ;==>Cancelled

Func _FileIsUsed($sFilePath) ;; By Nessie. Modified by guinness.
	Local Const $hFileOpen = _WinAPI_CreateFile($sFilePath, $CREATE_ALWAYS, (DriveGetType($sFilePath)) = 'NETWORK' ? $FILE_SHARE_READ : $FILE_SHARE_WRITE)
	Local $fReturn = True
	If $hFileOpen Then
		_WinAPI_CloseHandle($hFileOpen)
		$fReturn = False
	EndIf

	If $fReturn Then
		$fReturn = _WinAPI_GetLastError() = $ERROR_SHARING_VIOLATION
	EndIf
	Return $fReturn
EndFunc   ;==>_FileIsUsed

Func Handle_MultipleInstance()
	If _Singleton(StringReplace(@ScriptFullPath, '\', '/'), 1) = 0 Then
		Flash("PDFtoPrinter.exe is already running. Please wait.")
		$code = 11
		Exit $code
	EndIf
EndFunc   ;==>Handle_MultipleInstance

Func sendpassword($password)
	;send password to pdfxcview.exe input password window.
	$hWnd = WinWait("Enter Document Password", "Please enter valid user or owner password", 4) ;wait at most 4 seconds for input password window to popup.
	If WinExists($hWnd) Then
		ControlSetText("Enter Document Password", "", 1000, $password, 1)
		ControlClick("Enter Document Password", "OK", 1)
		$hWnd = WinWait("Enter Document Password", "Please enter valid user or owner password", 1) ;wait 1 second to see if password is correct.
		If $hWnd <> 0 Then
			Return SetError(1, "Wrong password.")
		Else
			Return 0
		EndIf
	EndIf
EndFunc   ;==>sendpassword



Func parsepage($pagestr, $pagecount = 3000)
	;$pagestr  pages=1,2-10:even,11-3,r5-r2,z:odd,-7,8-:even
	;return  an array two elements. array[0] is the selected pages count, array[1]is string pages=1,2,4,6,11-3 that pdfxcview can accept.
	;pages=1-4,1-4 will print the document pages 1-4 twice, it's another way to print copies of a pdf of diffrent page ranges.
	;Xchange viewer support page number greater than the actual pagecount, but page number greater than pagecount is not printed(of cource), so default 3000 is added.
	Local $outpage = ""
	$pages = StringTrimLeft($pagestr, 6)
	$pagearray = StringSplit($pages, ",") ;split by comma
	$totalpages = 0
	For $i = 1 To UBound($pagearray) - 1
		$outpagetmp = splitexpand($pagearray[$i], $pagecount)
		If @error Then Return SetError(1, 0, "Invalid page selector " & $pagearray[$i] & ". ") ;invalid page selector
		If $outpagetmp[1] <> "" Then
			$seperator = ","
			$outpage = $outpage & $seperator & $outpagetmp[1]
		ElseIf $outpagetmp[1] = "" Then
			$seperator = ""
		EndIf
		$totalpages = $totalpages + $outpagetmp[0]
	Next

	If $outpage = "" Then
		Return SetError(2, 0, "No Page Selected") ;no page selected
	Else
		Local $finaloutput[2] = [$totalpages, "pages=" & StringTrimLeft($outpage, 1)]
		Return $finaloutput
	EndIf
EndFunc   ;==>parsepage

Func splitexpand($str, $pagecount = 3000)
	;deal with z-1 and so on.
	;$str example z-1
	;;return  an array two elements. array[0] is the selected pages count, array[1]is string pages=1,2,4,6,11-3 that pdfxcview can accept.
	;$pagecount 3000 is not used.

	; accept 2-10,11-3:even,r5-r2,z-1,3-z,-7,8-,11,z once a time.
	;2-10 keep it is
	;11-3:even expand to 10,8,6,4
	;r5-r2 last 5 to last 2, expand to z-4,z-3,z-2,z-1
	;z-1 all page in reverse order
	;-7:even 2,4,6
	;8- 8 to last pages
	;11?
	;11:even?

	$output = ""
	$tmpstr = ""
	$arraysplit = StringSplit($str, ":")

	;deal with r3 and z by replacement and calculation
	$dashleft = StringLeft($arraysplit[1], -1 + StringInStr($arraysplit[1], "-"))
	$dashright = StringRight($arraysplit[1], StringLen($arraysplit[1]) - StringInStr($arraysplit[1], "-"))

	;deal with single page such as z ,r1
	If StringInStr($arraysplit[1], "-") = 0 Then
		$dashleft = $dashright
	EndIf

	;deal with string before - and after -
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

	If Not StringIsInt($dashleft) Or Not StringIsInt($dashright) Then Return SetError(1, 0, "Invalid page selector on the either side of -")  ;invalid page selector on the either side of "-"

	;expand 10-6 to 10,9,8,7,6
	If Number($dashright) < Number($dashleft) Then
		For $i = $dashleft To $dashright Step -1
			$output = $output & "," & $i
		Next
	ElseIf Number($dashright) >= Number($dashleft) Then
		For $i = $dashleft To $dashright
			$output = $output & "," & $i
		Next
	EndIf
	$output = StringTrimLeft($output, 1)

	;singlepagearray contain separate page number.
	$singlepagearray = StringSplit($output, ",")

	;remove page number greater than total pagecount or page number less than 1
	For $j = UBound($singlepagearray) - 1 To 1 Step -1
		If $singlepagearray[$j] > $pagecount Or $singlepagearray[$j] <= 0 Then _ArrayDelete($singlepagearray, $j)
	Next

	If UBound($arraysplit) = 3 Then ;existing odd or even seletor
		If StringLower($arraysplit[2]) = "even" Then
			For $j = UBound($singlepagearray) - 1 To 1 Step -1
				If $singlepagearray[$j] > $pagecount Or BitAND(Number($singlepagearray[$j]), 1) Then _ArrayDelete($singlepagearray, $j)
			Next
		ElseIf StringLower($arraysplit[2]) = "odd" Then
			For $j = UBound($singlepagearray) - 1 To 1 Step -1
				If $singlepagearray[$j] > $pagecount Or (Not BitAND(Number($singlepagearray[$j]), 1)) Then _ArrayDelete($singlepagearray, $j)
			Next
		Else
			Return SetError(2, 0, "Keyword error, not odd or even.") ;keyword error, not "odd" or "even"
		EndIf
	EndIf
	$output = ""

	; Short 1,2,3,4,5,6 to 1-6
	For $j = 1 To UBound($singlepagearray) - 1
		$seperator = ","
		If $j >= 2 And Number($singlepagearray[$j]) = Number($singlepagearray[$j - 1]) + 1 Then
			$seperator = "-"
			If $j = UBound($singlepagearray) - 1 Then $output = $output & $seperator & $singlepagearray[$j]
		Else
			$output = $output & $seperator & $singlepagearray[$j]
		EndIf
	Next
	$output = StringTrimLeft($output, 1)
	Local $finaloutput[2] = [-2 + UBound(_ArrayUnique($singlepagearray)), $output]
	Return $finaloutput
EndFunc   ;==>splitexpand

Func getfilematched($pdffile, $irecur, $pth = @ScriptDir)
	;get a list of pdf files masked by $pdffile.
	;$pdffile is a path containing mask, ie c:\windows\*.pdf, d:\???.pdf, must ended by .pdf.
	;return an array contaning pdf file list, first element is the number of pdf files matched.
	;$irecur=0 recur subflolder to unlimit depth.
	;$irecur=1 recur this folder only
	;$irecur=-x recur subfolder to x depth

	;exand relative path to full path.
	$pdffile = _PathFull($pdffile)
	;File name ended with .pdf otherwise exit.
	If StringLower(StringRight($pdffile, 4)) = ".pdf" Then
		$pth = StringMid($pdffile, 1, StringInStr($pdffile, "\", 0, -1))
		$filter = StringTrimLeft($pdffile, StringInStr($pdffile, "\", 0, -1))
		If $irecur = 0 Then
			;Find all matching pdf file(s) in all sub folder(s).
			$aArray = _FileListToArrayRec($pth, $filter, $FLTAR_FILES, $FLTAR_RECUR, $FLTAR_NOSORT, $FLTAR_FULLPATH)
		ElseIf $irecur = 1 Then
			;Find all matching pdf file(s) in this folder only.
			$aArray = _FileListToArray($pth, $filter, $FLTAR_FILES, True)
		ElseIf $irecur < 0 And IsInt($irecur) Then
			;Find all matching pdf file(s) in one folder.
			$aArray = _FileListToArrayRec($pth, $filter, $FLTAR_FILES, $irecur, $FLTAR_NOSORT, $FLTAR_FULLPATH)
		Else
			Return SetError(1, 0, "getfilematched($pdffile,$irecur). Unsupported $irecur, only 0 or 1 or negative integer number are supported.")
			$code = 12
			Exit $code
		EndIf
	Else
		Return SetError(2, 0, "Error: [path]Filename must end with .pdf, but filename supports wildcard * and ?(path does not support wildcards.)")
		$code = 13
		Exit $code
	EndIf
	If $aArray = "" Then
		Return SetError(3, 0, "No pdf file matched.")
	EndIf

	Return $aArray
EndFunc   ;==>getfilematched

Func qpdfgetpagecount($pdffilename, $pdfpassword = "", $qpdfdll = "qpdf29.dll")
	;$pdffilename pdf file name full path only.
	;$pdfpassword optional
	;$qpdfdll location of qpdf29.DllCall
	;return int pdf pagecount. negative number means pdf is encryped.
	$encrypted = 0
	If Not FileExists($pdffilename) Then
		Return SetError(1, 0, "Can't find " & $pdffilename & ".")
	EndIf

	If Not FileExists($qpdfdll) Then
		Return SetError(1, 0, "Can't find " & $qpdfdll & ".")
	EndIf

	;Create a pointer to pdf filename since qpdf29.dll supoorts only ansi encoding,
	; but convert utf8 string to ansi string directly may cause file not found error,
	; especially when filename contain no ascii characters.
	Local $pdffilenameHex = StringToBinary($pdffilename, 4)
	Local $BufferSize = StringLen($pdffilenameHex) * 2
	Local $pdffilenameptr = DllStructCreate("byte[" & $BufferSize & "]")
	DllStructSetData($pdffilenameptr, 1, $pdffilenameHex)

	Global $hDLL = DllOpen($qpdfdll)
	If $hDLL = -1 Then
		Return SetError(2, 0, "DllOpen() error: Can't open " & $qpdfdll & ".") ;  msgbox(0,"","dllOpen() error") ;-1=dllopen() error.
	EndIf

	;typedef struct _qpdf_data* qpdf_data;
	;typedef struct _qpdf_error* qpdf_error;
	; /* Returns dynamically allocated qpdf_data pointer; must be freed
	;  * by calling qpdf_cleanup.
	;  */
	; QPDF_DLL
	; qpdf_data qpdf_init();
	$qpdfhdl = DllCall($hDLL, "PTR:cdecl", "qpdf_init")
	; above: Since the returned type is qpdf_data, which is a qpdf_data pointer, can I use PTR?
	If @error Then
		DllClose($hDLL)
		Return SetError(3, 0, "Dllcall() qpdf_init error: error code: " & $qpdfhdl)
	EndIf

	;typedef int QPDF_ERROR_CODE;
	;#   define QPDF_SUCCESS 0
	;#   define QPDF_WARNINGS 1 << 0
	;#   define QPDF_ERRORS 1 << 1
	;/* Calling qpdf_read causes processFile to be called in the C++
	;    * API.  Basic parsing is performed, but data from the file is
	;    * only read as needed.  For files without passwords, pass a null
	;    * pointer as the password.
	;    */
	;   QPDF_DLL
	;   QPDF_ERROR_CODE qpdf_read(qpdf_data qpdf, char const* filename,
	;			      char const* password);
	$pdfopen = DllCall($hDLL, "INT:cdecl", "qpdf_read", "PTR", $qpdfhdl[0], "PTR", DllStructGetPtr($pdffilenameptr), "STR", Null) ;pdf not encrypted no password is blank
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(4, 0, "Dllcall() qpdf_read error. error code: " & $pdfopen)
	EndIf

	;QPDF_DLL
	;QPDF_BOOL qpdf_is_encrypted(qpdf_data qpdf);
	If $pdfopen[0] <> 0 Then
		$pdfencrypt = DllCall($hDLL, "Boolean:cdecl", "qpdf_is_encrypted", "PTR", $qpdfhdl[0])
		If @error Then
			cleanup($qpdfhdl[0], $hDLL)
			Return SetError(4, 0, "Dllcall() qpdf_is_encrypted error. error code: " & $pdfencrypt)
		EndIf
		If $pdfencrypt[0] Then $encrypted = 1
	Else ;pdf is encrypted but password is blank.
		$encrypted = 0
	EndIf

	If $encrypted Then
		If $pdfpassword <> "" Then
			$pdfopen = DllCall($hDLL, "INT:cdecl", "qpdf_read", "PTR", $qpdfhdl[0], "PTR", DllStructGetPtr($pdffilenameptr), "STR", $pdfpassword)
			;Else
			;Return SetError(4, 0, "PDF file has password, but no password provided.")
		EndIf
	EndIf
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(4, 0, "Dllcall() qpdf_read error. error code: " & $pdfopen)
	EndIf

	;    QPDF_DLL
	;    QPDF_BOOL qpdf_has_error(qpdf_data qpdf);
	$pdfhaserror = DllCall($hDLL, "Boolean:cdecl", "qpdf_has_error", "PTR", $qpdfhdl[0])
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(4, 0, "Dllcall() qpdf_has_error. error code: " & $pdfhaserror)
	EndIf
	If $pdfhaserror[0] Then
		;QPDF_DLL
		;qpdf_error qpdf_get_error(qpdf_data qpdf);
		$pdferror = DllCall($hDLL, "INT:cdecl", "qpdf_get_error", "PTR", $qpdfhdl[0])
		$pdferrorcode = DllCall($hDLL, "INT:cdecl", "qpdf_get_error_code", "PTR", $qpdfhdl[0], "INT", $pdferror[0])
		;QPDF_DLL
		;char const* qpdf_get_error_full_text(qpdf_data q, qpdf_error e);
		If $pdferrorcode[0] <> 4 Then ;encrypted pdf.
			$pdffullerror = DllCall($hDLL, "STR*:cdecl", "qpdf_get_error_full_text", "PTR", $qpdfhdl[0], "INT", $pdferror[0])
			Return SetError(4, 0, "QPDF open_pdf_has_error, PDF file might be corrupted. Error detail: " & @CRLF & $pdffullerror[0])
		EndIf
	EndIf

	;  /* Object handling.
	;     *
	;     * These methods take and return a qpdf_oh, which is just an
	;     * unsigned integer. The value 0 is never returned, which makes it
	;     * usable as an uninitialized value.
	;QPDF_DLL
	;qpdf_oh qpdf_get_root(qpdf_data data);
	$pdfroot = DllCall($hDLL, "INT:cdecl", "qpdf_get_root", "PTR", $qpdfhdl[0])
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(5, 0, "Dllcall() qpdf_get_root error: error code: " & $pdfroot)
	EndIf

	;    QPDF_DLL
	;    QPDF_BOOL qpdf_oh_is_dictionary(qpdf_data data, qpdf_oh oh);
	$pdfrootisdict = DllCall($hDLL, "boolean:cdecl", "qpdf_oh_is_dictionary", "PTR", $qpdfhdl[0], "int", $pdfroot[0])
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(6, 0, "Dllcall() qpdf_oh_is_dictionary(RootIsDict) error: error code: " & $pdfrootisdict)
	EndIf

	;    QPDF_DLL
	;    QPDF_BOOL qpdf_oh_has_key(qpdf_data data, qpdf_oh oh, char const* key);
	$pdfroothaskey = DllCall($hDLL, "boolean:cdecl", "qpdf_oh_has_key", "PTR", $qpdfhdl[0], "int", $pdfroot[0], "STR", "/Pages")
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(7, 0, "Dllcall() qpdf_oh_has_key(rootHas/Pages) error: error code: " & $pdfroothaskey)
	EndIf

	;    QPDF_DLL
	;    qpdf_oh qpdf_oh_get_key(qpdf_data data, qpdf_oh oh, char const* key);
	$pdfpagesobjnum = DllCall($hDLL, "INT:cdecl", "qpdf_oh_get_key", "PTR", $qpdfhdl[0], "int", $pdfroot[0], "STR", "/Pages")
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(8, 0, "Dllcall() qpdf_oh_get_key(/Root/Pages) error: error code: " & $pdfpagesobjnum)
	EndIf

	$pdfpagescount = DllCall($hDLL, "INT:cdecl", "qpdf_oh_get_key", "PTR", $qpdfhdl[0], "int", $pdfpagesobjnum[0], "STR", "/Count")
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(9, 0, "Dllcall() qpdf_oh_get_key(/Root/Pages/Count) error: error code: " & $pdfpagescount)
	EndIf

	;    QPDF_DLL
	;    char const* qpdf_oh_unparse_resolved(qpdf_data data, qpdf_oh oh);
	$pdfPages = DllCall($hDLL, "STR*:cdecl", "qpdf_oh_unparse_resolved", "PTR", $qpdfhdl[0], "int", $pdfpagescount[0])
	If @error Then
		cleanup($qpdfhdl[0], $hDLL)
		Return SetError(9, 0, "Dllcall() qpdf_oh_unparse_resolved(/Root/Pages/Count) error: error code: " & $pdfPages)
	EndIf
	cleanup($qpdfhdl[0], $hDLL)
	If $encrypted Then
		Return 0 - $pdfPages[0]
	Else
		Return $pdfPages[0]
	EndIf
EndFunc   ;==>qpdfgetpagecount

Func cleanup($qpdfhdl, $hDLL)
	;cleanup qpdf handle and dll handle
	;$qpdfhdl is a qpdf pointer
	;$hdll is a dll handle.

	;    /* Pass a pointer to the qpdf_data pointer created by qpdf_init to
	;    * clean up resources.
	;     */
	;    QPDF_DLL
	;    void qpdf_cleanup(qpdf_data* qpdf);
	$qpdfcleanup = DllCall($hDLL, "NONE:cdecl", "qpdf_cleanup", "PTR*", $qpdfhdl) ; PTR will crash, but PTR* not why?
	DllClose($hDLL)
EndFunc   ;==>cleanup

Func ExecutableNameFlag($flagname)
	;
	; The application will behave differently based on it's filename.
	; The user can rename it to trigger some features.
	;
	Return StringInStr(@ScriptName, $flagname)
EndFunc   ;==>ExecutableNameFlag

Func CLIMode()
	Return $cli == 1
EndFunc   ;==>CLIMode

Func Display($message)
	;
	; The application can be run on CLI mode or GUI mode.
	; When in CLI mode we write to the console.
	; When in GUI mode display a message box.
	;
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
