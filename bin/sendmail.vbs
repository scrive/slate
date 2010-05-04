'Public Class clsSendMail
Class clsSendMail
 
    Private oMessage    'CDO.Message Object
    Private strFrom     'Sender's Email ID: XX@YY.COM
    Public Body         'Body Text from Text File

    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�  
    ' Name: Sub Email (Public)
    ' 
    ' Purpose: Send Email Using CDO
    ' 
    ' Parameters:
    '    sEmailID: Sender's Mail ID String
    '    sPassword: Sender's Password String
    '    sTo: Recipient's Mail ID String (Primary)
    '    sCC: Recipient's Mail ID String (CC)
    '    sSubject: Subject String
    '    sBody: Body Message String
    ' 
    ' Return: -
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧� 
    Public Sub Send( sEMailID, sPassword, sTo, sCC, sSubject, sBody )
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧� 
        Dim oRegExp     'RegEx Object
        Dim sDetails    'Report Details
        Dim intStatus   'Report Status
        Dim sStepName   'Report Step
        
        'Sender ID has Class scope
        Me.From = sEmailID
        'Message Body
        If sBody <> "" Then Me.Body = sBody
 
        intStatus = micPass
        sStepName = " Sent"
 
        Set oRegExp = New RegExp
        oRegExp.Global = True
        oRegExp.Pattern = "<\w>|<\w\w>|<\w\d>"
        Set oMatches = oRegExp.Execute( Me.Body )
 
        'Build Message
        With oMessage
            .Subject = sSubject
            .From = sEmailID
            .To = sTo
            .CC = sCC
            'BCC Property can be added as well:
            '.BCC = sBCC
            'If HTML Tags found, use .HTMLBody
            If oMatches.Count > 0 Then
                .HTMLBody = Me.Body
            Else
                .TextBody = Me.Body
            End If
        End With
 
        Set oMatches = Nothing
        Set oRegExp = Nothing
 
        With oMessage.Configuration.Fields
            'Sender's Mail ID
            .Item("http://schemas.microsoft.com/cdo/configuration/" &_
            "sendusername") = sEmailID
            'Sender's Password
            .Item("http://schemas.microsoft.com/cdo/configuration/" &_
            "sendpassword") = sPassword
            'Name/IP of SMTP Server
            .Item("http://schemas.microsoft.com/cdo/configuration/" &_
            "smtpserver") = cdoSMTPServer
            'Server Port
            .Item("http://schemas.microsoft.com/cdo/configuration/" &_
            "smtpserverport") = cdoOutgoingMailSMTP
            'Send Using: (1) Local SMTP Pickup Service (2) Use SMTP Over Network
            .Item("http://schemas.microsoft.com/cdo/configuration/" &_
            "sendusing") = cdoSendUsing
            'Authentication Used: (1) None (2) Basic (3) NTLM
            .Item("http://schemas.microsoft.com/cdo/configuration/" &_
            "smtpauthenticate") = cdoAuthenticationType
            'SMTP Server Requires SSL/STARTTLS: Boolean
            .Item("http://schemas.microsoft.com/cdo/configuration/" &_
            "smtpusessl") = cdoUseSSL
            'Maximum Time in Seconds CDO will try to Establish Connection
            .Item("http://schemas.microsoft.com/cdo/configuration/" &_
            "smtpconnectiontimeout") = cdoTimeout
            'Update Configuration Entries
            .Update
        End With
 
        'Report Details
        sDetails = "SMTP Server: " & cdoSMTPServer & vbLf
        sDetails = sDetails & "Sender: " & sEMailID & vbLf
        sDetails = sDetails & "Recipient: " & sTo & vbLf
        sDetails = sDetails & "Server Port: " & cdoOutgoingMailSMTP & vbLf
        sDetails = sDetails & "SSL Used: " & cdoUseSSL & vbLf
        sDetails = sDetails & "Authentication Type: " & cdoAuthenticationType & vbLf
        sDetails = sDetails & "SMTP Service Type: " & cdoSendUsing & vbLf & vbLf
        sDetails = sDetails & "Subject: " & sSubject & vbLf & vbLf
        sDetails = sDetails & "Body: " & sBody
 
        On Error Resume Next
            'Send Message
            oMessage.Send
            If Err.Number <> 0 Then
                intStatus = micWarning
                sStepName = " Not Sent"
                sDetails = sDetails & vbLf & "Error Description: " & Err.Description
            End If
        On Error Goto 0
 
        'If you're not using QTP, please disable the statement below:
        ' Reporter.ReportEvent intStatus, "EMail" & sStepName, sDetails
    End Sub
 
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�  
    ' Name: Sub LoadBodyMessage (Public)
    ' 
    ' Purpose: Loads BodyText from a Text File
    ' 
    ' Parameters:
    '    sCompleteFilePath: Complete Path to the Text File (Eg: "C:\MyDocs\MyMail.txt")
    ' 
    ' Return: -
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    Public Sub LoadBodyMessage( sCompleteFilePath )
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧� 
        CONST ForReading = 1 
        Dim oFSO, oFile
 
        Set oFSO = CreateObject( "Scripting.FileSystemObject" )
        Set oFile = oFSO.OpenTextFile( sCompleteFilePath, ForReading )
        Me.Body = oFile.ReadAll
        oFile.Close: Set oFile = Nothing
 
        Set oFSO = Nothing
    End Sub
 
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�  
    ' Name: Class_Initialize (Private)
    ' 
    ' Purpose: Binds to the CDO Object
    ' 
    ' Parameters: -
    ' 
    ' Return: -
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�  
    Private Sub Class_Initialize
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�  
        Set oMessage = CreateObject( "CDO.Message" )
    End Sub
 
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�  
    ' Name: Class_Initialize (Private)
    ' 
    ' Purpose: Release the CDO Object
    ' 
    ' Parameters: -
    ' 
    ' Return: -
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�     
    Private Sub Class_Terminate
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧� 
        Set oMessage = Nothing
    End Sub
 
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    ' Name: Property cdoSendUsing (Private)
    ' 
    ' Purpose: Readonly property configuration for SMTP Service
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    Private Property Get cdoSendUsing  'As Integer
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�    
        cdoSendUsing = 2    'Use SMTP Over The Network
        'cdoSendUsing = 1    'Use Local SMTP Service Pickup Directory
    End Property
 
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    ' Name: Property cdoTimeout (Private)
    ' 
    ' Purpose: Maximum time in seconds CDO will try to establish a connection
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    Private Property Get cdoTimeout  'As Integer
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�    
        'cdoTimeout = 15    'Seconds
        cdoTimeout = 45    'Seconds
        'cdoTimeout = 75    'Seconds
    End Property
 
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    ' Name: Property cdoAuthenticationType (Private)
    ' 
    ' Purpose: Type of Authentication to be used
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�    
    Private Property Get cdoAuthenticationType  'As Integer
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�    
        'cdoAuthenticationType = 0    'No Authentication
        cdoAuthenticationType = 1    'Basic Authentication
        'cdoAuthenticationType = 2    'NTML Authentication
    End Property
 
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    ' Name: Property cdoOutgoingMailSMTP (Private)
    '
    ' Purpose: Server Port
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    Private Property Get cdoOutgoingMailSMTP  'As Integer
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
        If InStr(1, Lcase(Me.From), "@gmail") <> 0 Then
            cdoOutgoingMailSMTP = 465
        ElseIf InStr(1, Lcase(Me.From), "@skrivapa") <> 0 Then
            cdoOutgoingMailSMTP = 465
        ElseIf InStr(1, LCase(Me.From), "@aol") <> 0 Then
            cdoOutgoingMailSMTP = 587
        Else
            cdoOutgoingMailSMTP = 25
        End If
    End Property

    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    ' Name: Property cdoSMTPServer (Private)
    '
    ' Purpose: Name/IP of SMTP Server
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    Private Property Get cdoSMTPServer  'As String
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
        If InStr(1, LCase(Me.From), "@yahoo") <> 0 Then
            cdoSMTPServer = "smtp.mail.yahoo.com"
        ElseIf InStr(1, LCase(Me.From), "@gmail") <> 0 Then
            cdoSMTPServer = "smtp.gmail.com"
        ElseIf InStr(1, LCase(Me.From), "@skrivapa") <> 0 Then
            cdoSMTPServer = "smtp.gmail.com"
        ElseIf InStr(1, LCase(Me.From), "@hotmail") <> 0 Or _
               InStr(1, LCase(Me.From), "@live") <> 0 Then
            cdoSMTPServer = "smtp.live.com"
        ElseIf InStr(1, LCase(Me.From), "@aol") <> 0 Then
            cdoSMTPServer = "smtp.aol.com"
        End If
    End Property

    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    ' Name: Property cdoUseSSL (Private)
    '
    ' Purpose: Setting for SMTP Server's use of SSL (Boolean)
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    Private Property Get cdoUseSSL  'As Boolean
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
        cdoUseSSL = True
        If InStr(1, LCase(Me.From), "@aol") <> 0 Then
            cdoUseSSL = False
        End If
    End Property

    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    ' Name: Property From (Public)
    '
    ' Purpose: Sender's Email ID
    '覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�
    Public Property Let From( ByVal Val )
           strFrom = Val
    End Property
    Public Property Get From 'As String
           From = strFrom
    End Property
 
End Class
 
'覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�  
' Name: Sub Email (Public)
' 
' Purpose: Sends an Email Using CDO to a recipient
' 
' Parameters:
'    sEmailID: Sender's Mail ID String
'    sPassword: Sender's Password String
'    sTo: Recipient's Mail ID String
'    sSubject: Subject String
'    sBody: Body Message String
' 
' Return: -
'覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧� 
Public Function Email( EmailID, Password, Recipient, CC, Subject, Body )
'覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧� 
    Set Email = New clsSendMail
    With Email
        .Send EmailID, Password, Recipient, CC, Subject, Body
    End with 
End Function
 
'覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧�  
' Name: Sub EmailFromFile (Public)
' 
' Purpose: Sends an Email Using CDO to a recipient
'
' Parameters:
'    sEmailID: Sender's Mail ID String
'    sPassword: Sender's Password String
'    sTo: Recipient's Mail ID String
'    sSubject: Subject String
'    sCompleteFilePath: Text File containing the Body Message
' 
' Return: -
'覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧� 
Public Function EmailFromFile( EmailID, Password, Recipient, CC, Subject, sCompleteFilePath )
'覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧覧� 
    Set EmailFromFile = New clsSendMail
    With EmailFromFile
        .LoadBodyMessage sCompleteFilePath
        .Send EmailID, Password, Recipient, CC, Subject, ""
    End with
End Function

'Email "gracjanpolak@gmail.com", "wirnxnjf", "gracjanpolak@gmail.com", _
'    "", "Test email from skrivaPa", "skrivaPa welcomes"
Email "noreply@skrivapa.se", "kontrakcja", "lukas@skrivapa.se", _
    "", "Test email from skrivaPa", "skrivaPa welcomes"
