VERSION 1.0 CLASS
BEGIN
  MultiUse = -1  'True
END
Attribute VB_Name = "CLRS232"
Attribute VB_GlobalNameSpace = False
Attribute VB_Creatable = False
Attribute VB_PredeclaredId = False
Attribute VB_Exposed = False
Option Explicit

'-------------------------------------------------------------------------------
' Basic Class Module created from (modComm by David M. Hitchner [see below])
'
' Version 1.00 by Brendan Lambe 21 Jan 2011
'
' Parameters :
' BaudRate      - (R/W) Default value = 9600
' Parity        - (R/W) Default Value = N
' Databits      - (R/W) Default Value = 8
' StopBits      - (R/W) Default Value = 1
' ComPort       - (R/W) Default Value = 1
' LineRTS       - (R/W) Default value = True
' LineDTR       - (R/W) Default value = True
' PostCommDelay - (W)   Default Value = 0 (Can be used to set a delay between
'                       comm operations
' Status        - (R)   Returns error code from methods below
'                       0 if no error (except for ReadComm)
'                       For WriteComm: if 0 characters sent then = -1
'                                      if wrong qty sent then = qty sent
' ErrorMsg      - (R)   Returns error message if error occurs
'
' Methods :
' OpenComms
' WriteComm
' ReadComm
' CloseComms
' FlushComms
'-------------------------------------------------------------------------------
' modCOMM - Written by: David M. Hitchner FlushComms
'
' This VB module is a collection of routines to perform serial port I/O without
' using the Microsoft Comm Control component.  This module uses the Windows API
' to perform the overlapped I/O operations necessary for serial communications.
'
' The routine can handle up to 4 serial ports which are identified with a
' Port ID.
'
' All routines (with the exception of CommRead and CommWrite) return an error
' code or 0 if no error occurs.  The routine CommGetError can be used to get
' the complete error message.
'-------------------------------------------------------------------------------

' Output Control Lines (CommSetLine)
Private Const LINE_BREAK = 1
Private Const LINE_DTR = 2
Private Const LINE_RTS = 3

' Input Control Lines  (CommGetLine)
Private Const LINE_CTS = &H10&
Private Const LINE_DSR = &H20&
Private Const LINE_RING = &H40&
Private Const LINE_RLSD = &H80&
Private Const LINE_CD = &H80&

'-------------------------------------------------------------------------------
' System Constants
'-------------------------------------------------------------------------------
Private Const ERROR_IO_INCOMPLETE = 996&
Private Const ERROR_IO_PENDING = 997
Private Const GENERIC_READ = &H80000000
Private Const GENERIC_WRITE = &H40000000
Private Const FILE_ATTRIBUTE_NORMAL = &H80
Private Const FILE_FLAG_OVERLAPPED = &H40000000
Private Const FORMAT_MESSAGE_FROM_SYSTEM = &H1000
Private Const OPEN_EXISTING = 3

' COMM Functions
Private Const MS_CTS_ON = &H10&
Private Const MS_DSR_ON = &H20&
Private Const MS_RING_ON = &H40&
Private Const MS_RLSD_ON = &H80&
Private Const PURGE_RXABORT = &H2
Private Const PURGE_RXCLEAR = &H8
Private Const PURGE_TXABORT = &H1
Private Const PURGE_TXCLEAR = &H4

' COMM Escape Functions
Private Const CLRBREAK = 9
Private Const CLRDTR = 6
Private Const CLRRTS = 4
Private Const SETBREAK = 8
Private Const SETDTR = 5
Private Const SETRTS = 3

'-------------------------------------------------------------------------------
' System Structures
'-------------------------------------------------------------------------------
Private Type COMSTAT
    fBitFields As Long                                ' See Comment in Win32API.Txt
    cbInQue    As Long
    cbOutQue   As Long
End Type

Private Type COMMTIMEOUTS
    ReadIntervalTimeout As Long
    ReadTotalTimeoutMultiplier As Long
    ReadTotalTimeoutConstant As Long
    WriteTotalTimeoutMultiplier As Long
    WriteTotalTimeoutConstant As Long
End Type
'
' The DCB structure defines the control setting for a serial
' communications device.
'
Private Type DCB
    DCBlength  As Long
    BaudRate   As Long
    fBitFields As Long                                ' See Comments in Win32API.Txt
    wReserved  As Integer
    XonLim     As Integer
    XoffLim    As Integer
    ByteSize   As Byte
    Parity     As Byte
    StopBits   As Byte
    XonChar    As Byte
    XoffChar   As Byte
    ErrorChar  As Byte
    EofChar    As Byte
    EvtChar    As Byte
    wReserved1 As Integer                             'Reserved; Do Not Use
End Type

Private Type OVERLAPPED
    Internal   As Long
    InternalHigh As Long
    offset     As Long
    OffsetHigh As Long
    hEvent     As Long
End Type

Private Type SECURITY_ATTRIBUTES
    nLength    As Long
    lpSecurityDescriptor As Long
    bInheritHandle As Long
End Type

'-------------------------------------------------------------------------------
' System Functions
'-------------------------------------------------------------------------------
'
' Fills a specified DCB structure with values specified in
' a device-control string.
'
Private Declare Function BuildCommDCB Lib "kernel32" Alias "BuildCommDCBA" _
                                      (ByVal lpDef As String, lpDCB As DCB) As Long
'
' Retrieves information about a communications error and reports
' the current status of a communications device. The function is
' called when a communications error occurs, and it clears the
' device's error flag to enable additional input and output
' (I/O) operations.
'
Private Declare Function ClearCommError Lib "kernel32" _
                                        (ByVal hFile As Long, lpErrors As Long, lpStat As COMSTAT) As Long
'
' Closes an open communications device or file handle.
'
Private Declare Function CloseHandle Lib "kernel32" (ByVal hObject As Long) As Long
'
' Creates or opens a communications resource and returns a handle
' that can be used to access the resource.
'
Private Declare Function CreateFile Lib "kernel32" Alias "CreateFileA" _
                                    (ByVal lpFileName As String, ByVal dwDesiredAccess As Long, _
                                     ByVal dwShareMode As Long, lpSecurityAttributes As Any, _
                                     ByVal dwCreationDisposition As Long, ByVal dwFlagsAndAttributes As Long, _
                                     ByVal hTemplateFile As Long) As Long
'
' Directs a specified communications device to perform a function.
'
Private Declare Function EscapeCommFunction Lib "kernel32" _
                                            (ByVal nCid As Long, ByVal nFunc As Long) As Long
'
' Formats a message string such as an error string returned
' by anoher function.
'
Private Declare Function FormatMessage Lib "kernel32" Alias "FormatMessageA" _
                                       (ByVal dwFlags As Long, lpSource As Any, ByVal dwMessageId As Long, _
                                        ByVal dwLanguageId As Long, ByVal lpBuffer As String, ByVal nSize As Long, _
                                        Arguments As Long) As Long
'
' Retrieves modem control-register values.
'
Private Declare Function GetCommModemStatus Lib "kernel32" _
                                            (ByVal hFile As Long, lpModemStat As Long) As Long
'
' Retrieves the current control settings for a specified
' communications device.
'
Private Declare Function GetCommState Lib "kernel32" _
                                      (ByVal nCid As Long, lpDCB As DCB) As Long
'
' Retrieves the calling thread's last-error code value.
'
Private Declare Function GetLastError Lib "kernel32" () As Long
'
' Retrieves the results of an overlapped operation on the
' specified file, named pipe, or communications device.
'
Private Declare Function GetOverlappedResult Lib "kernel32" _
                                             (ByVal hFile As Long, lpOverlapped As OVERLAPPED, _
                                              lpNumberOfBytesTransferred As Long, ByVal bWait As Long) As Long
'
' Discards all characters from the output or input buffer of a
' specified communications resource. It can also terminate
' pending read or write operations on the resource.
'
Private Declare Function PurgeComm Lib "kernel32" _
                                   (ByVal hFile As Long, ByVal dwFlags As Long) As Long
'
' Reads data from a file, starting at the position indicated by the
' file pointer. After the read operation has been completed, the
' file pointer is adjusted by the number of bytes actually read,
' unless the file handle is created with the overlapped attribute.
' If the file handle is created for overlapped input and output
' (I/O), the application must adjust the position of the file pointer
' after the read operation.
'
Private Declare Function ReadFile Lib "kernel32" _
                                  (ByVal hFile As Long, ByVal lpBuffer As String, _
                                   ByVal nNumberOfBytesToRead As Long, ByRef lpNumberOfBytesRead As Long, _
                                   lpOverlapped As OVERLAPPED) As Long
'
' Configures a communications device according to the specifications
' in a device-control block (a DCB structure). The function
' reinitializes all hardware and control settings, but it does not
' empty output or input queues.
'
Private Declare Function SetCommState Lib "kernel32" _
                                      (ByVal hCommDev As Long, lpDCB As DCB) As Long
'
' Sets the time-out parameters for all read and write operations on a
' specified communications device.
'
Private Declare Function SetCommTimeouts Lib "kernel32" _
                                         (ByVal hFile As Long, lpCommTimeouts As COMMTIMEOUTS) As Long
'
' Initializes the communications parameters for a specified
' communications device.
'
Private Declare Function SetupComm Lib "kernel32" _
                                   (ByVal hFile As Long, ByVal dwInQueue As Long, ByVal dwOutQueue As Long) As Long
'
' Writes data to a file and is designed for both synchronous and a
' synchronous operation. The function starts writing data to the file
' at the position indicated by the file pointer. After the write
' operation has been completed, the file pointer is adjusted by the
' number of bytes actually written, except when the file is opened with
' FILE_FLAG_OVERLAPPED. If the file handle was created for overlapped
' input and output (I/O), the application must adjust the position of
' the file pointer after the write operation is finished.
'
Private Declare Function WriteFile Lib "kernel32" _
                                   (ByVal hFile As Long, ByVal lpBuffer As String, _
                                    ByVal nNumberOfBytesToWrite As Long, lpNumberOfBytesWritten As Long, _
                                    lpOverlapped As OVERLAPPED) As Long

'-------------------------------------------------------------------------------
' Program Constants
'-------------------------------------------------------------------------------

Private Const MAX_PORTS = 100

'-------------------------------------------------------------------------------
' Program Structures
'-------------------------------------------------------------------------------

Private Type COMM_ERROR
    lngErrorCode As Long
    strFunction As String
    strErrorMessage As String
End Type

Private Type COMM_PORT
    lngHandle  As Long
    blnPortOpen As Boolean
    udtDCB     As DCB
End Type

'-------------------------------------------------------------------------------
' Program Storage
'-------------------------------------------------------------------------------

Private udtCommOverlap As OVERLAPPED
Private udtCommError As COMM_ERROR
Private udtPorts(1 To MAX_PORTS) As COMM_PORT
'-------------------------------------------------------------------------------

Private clBaud As Long
Private clParity As String * 1
Private clDatabits As Integer
Private clStopbits As Integer
Private clComport As Integer
Private clStatus As Long
Private clData As String
Private clPostCommDelay As Single
Private clErrorMsg As String
Private clLineRTS As Boolean
Private clLineDTR As Boolean
Private lngStatus As Long
Private strError As String

Sub OpenComms()

    Dim I      As Integer

    clStatus = CommOpen(clComport, "\\.\COM" & CStr(clComport), "baud=" & CStr(clBaud) & " parity=" & clParity & _
                                                                "data=" & CStr(clDatabits) & "stop=" & CStr(clStopbits))

    If clStatus <> 0 Then
        lngStatus = CommGetError(strError)
        clErrorMsg = strError
    Else
        clErrorMsg = ""
    End If

    Select Case clStatus
        Case -1
            I = MsgBox("Com Port " & CStr(clComport) & " is already in use." & Chr(10) & " Do you wish to attempt to close and Re-Open the Port?", vbYesNo, "Error")

            If I = 6 Then
                CommClose clComport
                OpenComms
            Else
                End
            End If
        Case 2
            I = MsgBox("Can't open the specified port", vbCritical, "Error")
            End
    End Select

    lngStatus = CommSetLine(clComport, LINE_RTS, True)
    lngStatus = CommSetLine(clComport, LINE_DTR, True)

End Sub

Sub WriteComm(strSend As String)

    clStatus = CommWrite(clComport, strSend)

    If clStatus = Len(strSend) Then
        clStatus = 0
        clErrorMsg = ""
    ElseIf clStatus = 0 Then
        clErrorMsg = "Zero characters sent"
        clStatus = -1
    Else
        clErrorMsg = "Invalid number of characters sent"
    End If

    Delay clPostCommDelay

End Sub

Sub ReadComm()

    Dim strData As String

    clStatus = CommRead(clComport, strData, 255)
    clData = strData

    Delay clPostCommDelay

End Sub

Sub CloseComms()
    CommClose clComport
End Sub

Sub FlushComms()
    clStatus = CommFlush(clComport)
End Sub

'-------------------------------------------------------------------------------
' GetSystemMessage - Gets system error text for the specified error code.
'-------------------------------------------------------------------------------
Private Function GetSystemMessage(lngErrorCode As Long) As String
    Dim intPos As Integer
    Dim strMessage As String, strMsgBuff As String * 256

    Call FormatMessage(FORMAT_MESSAGE_FROM_SYSTEM, 0, lngErrorCode, 0, strMsgBuff, 255, 0)

    intPos = InStr(1, strMsgBuff, vbNullChar)
    If intPos > 0 Then
        strMessage = Trim$(Left$(strMsgBuff, intPos - 1))
    Else
        strMessage = Trim$(strMsgBuff)
    End If

    GetSystemMessage = strMessage

End Function

'-------------------------------------------------------------------------------
' CommOpen - Opens/Initializes serial port.
'
'
' Parameters:
'   intPortID   - Port ID used when port was opened.
'   strPort     - COM port name. (COM1, COM2, COM3, COM4)
'   strSettings - Communication settings.
'                 Example: "baud=9600 parity=N data=8 stop=1"
'
' Returns:
'   Error Code  - 0 = No Error.
'
'-------------------------------------------------------------------------------
Private Function CommOpen(IntportID As Integer, strPort As String, _
                          strSettings As String) As Long

    Dim lngStatus As Long
    Dim udtCommTimeOuts As COMMTIMEOUTS

    On Error GoTo Routine_Error

    ' See if port already in use.
    If udtPorts(IntportID).blnPortOpen Then
        lngStatus = -1
        With udtCommError
            .lngErrorCode = lngStatus
            .strFunction = "CommOpen"
            .strErrorMessage = "Port in use."
        End With

        GoTo Routine_Exit
    End If

    ' Open serial port.
    udtPorts(IntportID).lngHandle = CreateFile(strPort, GENERIC_READ Or _
                                                        GENERIC_WRITE, 0, ByVal 0&, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0)

    If udtPorts(IntportID).lngHandle = -1 Then
        lngStatus = SetCommError("CommOpen (CreateFile)")
        GoTo Routine_Exit
    End If

    udtPorts(IntportID).blnPortOpen = True

    ' Setup device buffers (1K each).
    lngStatus = SetupComm(udtPorts(IntportID).lngHandle, 2048, 2048)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommOpen (SetupComm)")
        GoTo Routine_Exit
    End If

    ' Purge buffers.
    lngStatus = PurgeComm(udtPorts(IntportID).lngHandle, PURGE_TXABORT Or _
                                                         PURGE_RXABORT Or PURGE_TXCLEAR Or PURGE_RXCLEAR)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommOpen (PurgeComm)")
        GoTo Routine_Exit
    End If

    ' Set serial port timeouts.
    With udtCommTimeOuts
        .ReadIntervalTimeout = 1
        .ReadTotalTimeoutMultiplier = 1
        .ReadTotalTimeoutConstant = 1000
        .WriteTotalTimeoutMultiplier = 0
        .WriteTotalTimeoutMultiplier = 1000
    End With

    lngStatus = SetCommTimeouts(udtPorts(IntportID).lngHandle, udtCommTimeOuts)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommOpen (SetCommTimeouts)")
        GoTo Routine_Exit
    End If

    ' Get the current state (DCB).
    lngStatus = GetCommState(udtPorts(IntportID).lngHandle, _
                             udtPorts(IntportID).udtDCB)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommOpen (GetCommState)")
        GoTo Routine_Exit
    End If

    ' Modify the DCB to reflect the desired settings.
    lngStatus = BuildCommDCB(strSettings, udtPorts(IntportID).udtDCB)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommOpen (BuildCommDCB)")
        GoTo Routine_Exit
    End If

    ' Set the new state.
    lngStatus = SetCommState(udtPorts(IntportID).lngHandle, _
                             udtPorts(IntportID).udtDCB)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommOpen (SetCommState)")
        GoTo Routine_Exit
    End If

    lngStatus = 0

Routine_Exit:
    CommOpen = lngStatus
    Exit Function

Routine_Error:
    lngStatus = Err.Number
    With udtCommError
        .lngErrorCode = lngStatus
        .strFunction = "CommOpen"
        .strErrorMessage = Err.Description
    End With
    Resume Routine_Exit

End Function

Private Function SetCommError(strFunction As String) As Long

    With udtCommError
        .lngErrorCode = Err.LastDllError
        .strFunction = strFunction
        .strErrorMessage = GetSystemMessage(.lngErrorCode)
        SetCommError = .lngErrorCode
    End With

End Function

Private Function SetCommErrorEx(strFunction As String, lngHnd As Long) As Long
    Dim lngErrorFlags As Long
    Dim udtCommStat As COMSTAT

    With udtCommError
        .lngErrorCode = GetLastError
        .strFunction = strFunction
        .strErrorMessage = GetSystemMessage(.lngErrorCode)

        Call ClearCommError(lngHnd, lngErrorFlags, udtCommStat)

        .strErrorMessage = .strErrorMessage & "  COMM Error Flags = " & _
                           Hex$(lngErrorFlags)

        SetCommErrorEx = .lngErrorCode
    End With

End Function

'-------------------------------------------------------------------------------
' CommSet - Modifies the serial port settings.
'
' Parameters:
'   intPortID   - Port ID used when port was opened.
'   strSettings - Communication settings.
'                 Example: "baud=9600 parity=N data=8 stop=1"
'
' Returns:
'   Error Code  - 0 = No Error.
'-------------------------------------------------------------------------------
Private Function CommSet(IntportID As Integer, strSettings As String) As Long

    Dim lngStatus As Long

    On Error GoTo Routine_Error

    lngStatus = GetCommState(udtPorts(IntportID).lngHandle, _
                             udtPorts(IntportID).udtDCB)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommSet (GetCommState)")
        GoTo Routine_Exit
    End If

    lngStatus = BuildCommDCB(strSettings, udtPorts(IntportID).udtDCB)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommSet (BuildCommDCB)")
        GoTo Routine_Exit
    End If

    lngStatus = SetCommState(udtPorts(IntportID).lngHandle, _
                             udtPorts(IntportID).udtDCB)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommSet (SetCommState)")
        GoTo Routine_Exit
    End If

    lngStatus = 0

Routine_Exit:
    CommSet = lngStatus
    Exit Function

Routine_Error:
    lngStatus = Err.Number
    With udtCommError
        .lngErrorCode = lngStatus
        .strFunction = "CommSet"
        .strErrorMessage = Err.Description
    End With
    Resume Routine_Exit
End Function

'-------------------------------------------------------------------------------
' CommClose - Close the serial port.
'
' Parameters:
'   intPortID   - Port ID used when port was opened.
'
' Returns:
'   Error Code  - 0 = No Error.
'-------------------------------------------------------------------------------
Private Function CommClose(IntportID As Integer) As Long

    Dim lngStatus As Long

    On Error GoTo Routine_Error

    If udtPorts(IntportID).blnPortOpen Then
        lngStatus = CloseHandle(udtPorts(IntportID).lngHandle)

        If lngStatus = 0 Then
            lngStatus = SetCommError("CommClose (CloseHandle)")
            GoTo Routine_Exit
        End If

        udtPorts(IntportID).blnPortOpen = False
    End If

    lngStatus = 0

Routine_Exit:
    CommClose = lngStatus
    Exit Function

Routine_Error:
    lngStatus = Err.Number
    With udtCommError
        .lngErrorCode = lngStatus
        .strFunction = "CommClose"
        .strErrorMessage = Err.Description
    End With
    Resume Routine_Exit
End Function

'-------------------------------------------------------------------------------
' CommFlush - Flush the send and receive serial port buffers.
'
' Parameters:
'   intPortID   - Port ID used when port was opened.
'
' Returns:
'   Error Code  - 0 = No Error.
'-------------------------------------------------------------------------------
Private Function CommFlush(IntportID As Integer) As Long

    Dim lngStatus As Long

    On Error GoTo Routine_Error

    lngStatus = PurgeComm(udtPorts(IntportID).lngHandle, PURGE_TXABORT Or _
                                                         PURGE_RXABORT Or PURGE_TXCLEAR Or PURGE_RXCLEAR)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommFlush (PurgeComm)")
        GoTo Routine_Exit
    End If

    lngStatus = 0

Routine_Exit:
    CommFlush = lngStatus
    Exit Function

Routine_Error:
    lngStatus = Err.Number
    With udtCommError
        .lngErrorCode = lngStatus
        .strFunction = "CommFlush"
        .strErrorMessage = Err.Description
    End With
    Resume Routine_Exit
End Function


'-------------------------------------------------------------------------------
' CommRead - Read serial port input buffer.
'
' Parameters:
'   intPortID   - Port ID used when port was opened.
'   strData     - Data buffer.
'   lngSize     - Maximum number of bytes to be read.
'
' Returns:
'   Error Code  - 0 = No Error.
'-------------------------------------------------------------------------------
Private Function CommRead(IntportID As Integer, strData As String, _
                          lngsize As Long) As Long

    Dim lngStatus As Long
    Dim lngRdSize As Long, lngBytesRead As Long
    Dim lngRdStatus As Long, strRdBuffer As String * 1024
    Dim lngErrorFlags As Long, udtCommStat As COMSTAT

    On Error GoTo Routine_Error

    strData = ""
    lngBytesRead = 0
    DoEvents

    ' Clear any previous errors and get current status.
    lngStatus = ClearCommError(udtPorts(IntportID).lngHandle, lngErrorFlags, _
                               udtCommStat)

    If lngStatus = 0 Then
        lngBytesRead = -1
        lngStatus = SetCommError("CommRead (ClearCommError)")
        GoTo Routine_Exit
    End If

    If udtCommStat.cbInQue > 0 Then
        If udtCommStat.cbInQue > lngsize Then
            lngRdSize = udtCommStat.cbInQue
        Else
            lngRdSize = lngsize
        End If
    Else
        lngRdSize = 0
    End If

    If lngRdSize Then
        lngRdStatus = ReadFile(udtPorts(IntportID).lngHandle, strRdBuffer, _
                               lngRdSize, lngBytesRead, udtCommOverlap)

        If lngRdStatus = 0 Then
            lngStatus = GetLastError
            If lngStatus = ERROR_IO_PENDING Then
                ' Wait for read to complete.
                ' This function will timeout according to the
                ' COMMTIMEOUTS.ReadTotalTimeoutConstant variable.
                ' Every time it times out, check for port errors.

                ' Loop until operation is complete.
                While GetOverlappedResult(udtPorts(IntportID).lngHandle, _
                                          udtCommOverlap, lngBytesRead, True) = 0

                    lngStatus = GetLastError

                    If lngStatus <> ERROR_IO_INCOMPLETE Then
                        lngBytesRead = -1
                        lngStatus = SetCommErrorEx( _
                                    "CommRead (GetOverlappedResult)", _
                                    udtPorts(IntportID).lngHandle)
                        GoTo Routine_Exit
                    End If
                Wend
            Else
                ' Some other error occurred.
                lngBytesRead = -1
                lngStatus = SetCommErrorEx("CommRead (ReadFile)", _
                                           udtPorts(IntportID).lngHandle)
                GoTo Routine_Exit

            End If
        End If

        strData = Left$(strRdBuffer, lngBytesRead)
    End If

Routine_Exit:
    CommRead = lngBytesRead
    Exit Function

Routine_Error:
    lngBytesRead = -1
    lngStatus = Err.Number
    With udtCommError
        .lngErrorCode = lngStatus
        .strFunction = "CommRead"
        .strErrorMessage = Err.Description
    End With
    Resume Routine_Exit
End Function

'-------------------------------------------------------------------------------
' CommWrite - Output data to the serial port.
'
' Parameters:
'   intPortID   - Port ID used when port was opened.
'   strData     - Data to be transmitted.
'
' Returns:
'   Error Code  - 0 = No Error.
'-------------------------------------------------------------------------------
Private Function CommWrite(IntportID As Integer, strData As String) As Long

    Dim I      As Integer
    Dim lngStatus As Long, lngsize As Long
    Dim lngWrSize As Long, lngWrStatus As Long

    On Error GoTo Routine_Error

    ' Get the length of the data.
    lngsize = Len(strData)

    ' Output the data.
    lngWrStatus = WriteFile(udtPorts(IntportID).lngHandle, strData, lngsize, _
                            lngWrSize, udtCommOverlap)

    ' Note that normally the following code will not execute because the driver
    ' caches write operations. Small I/O requests (up to several thousand bytes)
    ' will normally be accepted immediately and WriteFile will return true even
    ' though an overlapped operation was specified.

    DoEvents

    If lngWrStatus = 0 Then
        lngStatus = GetLastError
        If lngStatus = 0 Then
            GoTo Routine_Exit
        ElseIf lngStatus = ERROR_IO_PENDING Then
            ' We should wait for the completion of the write operation so we know
            ' if it worked or not.
            '
            ' This is only one way to do this. It might be beneficial to place the
            ' writing operation in a separate thread so that blocking on completion
            ' will not negatively affect the responsiveness of the UI.
            '
            ' If the write takes long enough to complete, this function will timeout
            ' according to the CommTimeOuts.WriteTotalTimeoutConstant variable.
            ' At that time we can check for errors and then wait some more.

            ' Loop until operation is complete.
            While GetOverlappedResult(udtPorts(IntportID).lngHandle, _
                                      udtCommOverlap, lngWrSize, True) = 0

                lngStatus = GetLastError

                If lngStatus <> ERROR_IO_INCOMPLETE Then
                    lngStatus = SetCommErrorEx( _
                                "CommWrite (GetOverlappedResult)", _
                                udtPorts(IntportID).lngHandle)
                    GoTo Routine_Exit
                End If
            Wend
        Else
            ' Some other error occurred.
            lngWrSize = -1

            lngStatus = SetCommErrorEx("CommWrite (WriteFile)", _
                                       udtPorts(IntportID).lngHandle)
            GoTo Routine_Exit

        End If
    End If

    For I = 1 To 10
        DoEvents
    Next

Routine_Exit:
    CommWrite = lngWrSize
    Exit Function

Routine_Error:
    lngStatus = Err.Number
    With udtCommError
        .lngErrorCode = lngStatus
        .strFunction = "CommWrite"
        .strErrorMessage = Err.Description
    End With
    Resume Routine_Exit
End Function


'-------------------------------------------------------------------------------
' CommGetLine - Get the state of selected serial port control lines.
'
' Parameters:
'   intPortID   - Port ID used when port was opened.
'   intLine     - Serial port line. CTS, DSR, RING, RLSD (CD)
'   blnState    - Returns state of line (Cleared or Set).
'
' Returns:
'   Error Code  - 0 = No Error.
'-------------------------------------------------------------------------------
Private Function CommGetLine(IntportID As Integer, intLine As Integer, _
                             blnState As Boolean) As Long

    Dim lngStatus As Long
    Dim lngComStatus As Long, lngModemStatus As Long

    On Error GoTo Routine_Error

    lngStatus = GetCommModemStatus(udtPorts(IntportID).lngHandle, lngModemStatus)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommReadCD (GetCommModemStatus)")
        GoTo Routine_Exit
    End If

    If (lngModemStatus And intLine) Then
        blnState = True
    Else
        blnState = False
    End If

    lngStatus = 0

Routine_Exit:
    CommGetLine = lngStatus
    Exit Function

Routine_Error:
    lngStatus = Err.Number
    With udtCommError
        .lngErrorCode = lngStatus
        .strFunction = "CommReadCD"
        .strErrorMessage = Err.Description
    End With
    Resume Routine_Exit
End Function


'-------------------------------------------------------------------------------
' CommSetLine - Set the state of selected serial port control lines.
'
' Parameters:
'   intPortID   - Port ID used when port was opened.
'   intLine     - Serial port line. BREAK, DTR, RTS
'                 Note: BREAK actually sets or clears a "break" condition on
'                 the transmit data line.
'   blnState    - Sets the state of line (Cleared or Set).
'
' Returns:
'   Error Code  - 0 = No Error.
'-------------------------------------------------------------------------------
Private Function CommSetLine(IntportID As Integer, intLine As Integer, _
                             blnState As Boolean) As Long

    Dim lngStatus As Long
    Dim lngNewState As Long

    On Error GoTo Routine_Error

    If intLine = LINE_BREAK Then
        If blnState Then
            lngNewState = SETBREAK
        Else
            lngNewState = CLRBREAK
        End If

    ElseIf intLine = LINE_DTR Then
        If blnState Then
            lngNewState = SETDTR
        Else
            lngNewState = CLRDTR
        End If

    ElseIf intLine = LINE_RTS Then
        If blnState Then
            lngNewState = SETRTS
        Else
            lngNewState = CLRRTS
        End If
    End If

    lngStatus = EscapeCommFunction(udtPorts(IntportID).lngHandle, lngNewState)

    If lngStatus = 0 Then
        lngStatus = SetCommError("CommSetLine (EscapeCommFunction)")
        GoTo Routine_Exit
    End If

    lngStatus = 0

Routine_Exit:
    CommSetLine = lngStatus
    Exit Function

Routine_Error:
    lngStatus = Err.Number
    With udtCommError
        .lngErrorCode = lngStatus
        .strFunction = "CommSetLine"
        .strErrorMessage = Err.Description
    End With
    Resume Routine_Exit
End Function


'-------------------------------------------------------------------------------
' CommGetError - Get the last serial port error message.
'
' Parameters:
'   strMessage  - Error message from last serial port error.
'
' Returns:
'   Error Code  - Last serial port error code.
'-------------------------------------------------------------------------------
Private Function CommGetError(strMessage As String) As Long

    With udtCommError
        CommGetError = .lngErrorCode
        strMessage = "Error (" & CStr(.lngErrorCode) & "): " & .strFunction & _
                     " - " & .strErrorMessage
    End With

End Function

Private Sub Delay(T As Single)

    Dim TempSNG As Single

    TempSNG = Timer

    Do While Timer < TempSNG + T
        DoEvents                                      ' Yield to other processes.
    Loop

End Sub

Property Let BaudRate(T As Long)
    clBaud = T
End Property

Property Get BaudRate() As Long
    BaudRate = clBaud
End Property

Property Let Parity(T As String)
    clParity = T
End Property

Property Get Parity() As String
    Parity = clParity
End Property

Property Let Databits(T As Integer)
    clDatabits = T
End Property

Property Get Databits() As Integer
    Databits = clDatabits
End Property

Property Let StopBits(T As Integer)
    clStopbits = T
End Property

Property Get StopBits() As Integer
    StopBits = clStopbits
End Property

Property Let ComPort(T As Integer)
    clComport = T
End Property

Property Get ComPort() As Integer
    ComPort = clComport
End Property

Property Let LineDTR(T As Boolean)
    clLineDTR = T
End Property

Property Get LineDTR() As Boolean
    LineDTR = clLineDTR
End Property

Property Let LineRTS(T As Boolean)
    clLineRTS = T
End Property

Property Get LineRTS() As Boolean
    LineRTS = clLineRTS
End Property

Property Get Status() As Long
    Status = clStatus
End Property

Property Get Data() As String
    Data = clData
End Property

Property Let PostCommDelay(T As Single)
    clPostCommDelay = T
End Property

Property Get ErrorMsg() As String
    ErrorMsg = clErrorMsg
End Property

Private Sub Class_Initialize()

    clBaud = 9600
    clParity = "N"
    clDatabits = 8
    clStopbits = 1
    clComport = 1
    clStatus = 0
    clData = ""
    clPostCommDelay = 0
    clErrorMsg = ""
    clLineRTS = True
    clLineDTR = True
    lngStatus = 0
    strError = ""

End Sub



                                              ā? >           :           :                  ?                  ?  ?  ?  ?ĸĸĸĸ  ēB  ļA                                                  $? >           :           :                  ?                  ?  ?  ?  ?ĸĸĸĸ  B  B                                                 >  R=           :           :                  ?                  ?  ?  ?  ?ĸĸĸĸ  B  B                                                  +>  R=           :           :   