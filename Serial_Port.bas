Attribute VB_Name = "Serial_Port"
Option Explicit
Dim blnStop    As Boolean
Sub StartCom()
    Dim TotalStation As New CLRS232
    Dim dataArray, stopArray
    Dim blnStart As Boolean, blnFlag As Boolean
    Dim lngComPort As Long, lngBaudRate As Long, lngDataBits As Long, lngStopBits As Long
    Dim lngCol As Long
    Dim strParity As String
    
    blnStart = False
    blnFlag = False
    blnStop = False
    
    With Sheets("Serial Port")
        lngComPort = .Range("P2").Value
        lngBaudRate = .Range("P3").Value
        strParity = .Range("P4").Value
        lngDataBits = .Range("P5").Value
        lngStopBits = .Range("P6").Value
    End With
    
    lngCol = 1
    With TotalStation
        .ComPort = lngComPort
        .BaudRate = lngBaudRate
        .Parity = strParity
        .Databits = lngDataBits
        .StopBits = lngStopBits
        .PostCommDelay = 0.1
        .OpenComms
        
        Do While blnStop = False
            .ReadComm
            DoEvents
            Sheets("Serial Port").Range("L7").Value = "Open"
            If Not blnStart Then
                If Not .Data = vbNullString Then
                    blnStart = True
                    blnFlag = True
                End If
            End If
            'Debug.Print .Data
            If blnFlag Then
                If (Not .Data = vbNullString) Then Debug.Print .Data
                If (Not .Data = vbNullString) And (.Data Like "*From NodeID 3*") Then
                    lngCol = lngCol + 1
                    Sheets("���������").Cells(lngCol, 1) = CStr(Time)
                    Sheets("���������").Cells(lngCol, 2) = CStr(Time - Sheets("���������").Cells(2, 1))
                    Sheets("���������").Cells(lngCol, 3) = Replace(Replace(Replace(Replace(Replace(Replace(Split(.Data, ":")(1), " ", ""), vbLf, ""), Chr(160), ""), ".", ","), Chr(13), ""), Chr(10), "")

                End If
            End If
        Loop
        .CloseComms
    End With
    Sheets("Serial Port").Range("L7").Value = "Closed"
End Sub
Sub StopCom()
    blnStop = True
    Sheets("Serial Port").Range("L7").Value = "Closed"
End Sub


	
			
	

      `�         �                                ��K ����K�                                                ������������������������