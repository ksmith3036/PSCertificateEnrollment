﻿<#
    .SYNOPSIS
    Requests a Certificate from an NDES Server via the SCEP Protocol.
    This works on Windows 8.1 and newer Operating Systems.

    .PARAMETER ComputerName
    Specifies the Host Name or IP Address of the NDES Server.
    If using SSL, this must match the NDES Server's identity as specified in its SSL Server Certificate.

    .PARAMETER MachineContext
    By default, the Key for Certificate Request gets created in the current User's Context.
    By specifying this Parameter, it will be created as a Machine Key.
    You must execute the Command with Elevation (Run as Administrator) then.

    .PARAMETER Subject
    Specifies the Subject DN for the Certificate.
    May be left empty if you specify a DnsName, Upn or IP instead.

    .PARAMETER Dns
    Specifies one or more DNS Names to be written into the Subject Alternative Name (SAN) Extension of the Certificate Request.
    May be left Empty if you specify a Subject, Upn or IP instead.

    .PARAMETER Upn
    Specifies one or more User Principal Names to be written into the Subject Alternative Name (SAN) Extension of the Certificate Request.
    May be left Empty if you specify a Subject, DnsName or IP instead.

    .PARAMETER Email
    Specifies one or more E-Mail addresses (RFC 822) to be written into the Subject Alternative Name (SAN) Extension of the Certificate Request.
    May be left Empty if you specify a Subject, DnsName, Upn or IP instead.

    .PARAMETER IP
    Specifies or more IP Addresses to be written into the Subject Alternative Name (SAN) Extension of the Certificate Request.
    May be left Empty if you specify a Subject, DnsName or Upn instead.

    .PARAMETER ChallengePassword
    Specifies the Challenge Password used to authenticate to the NDES Server.
    Not necessary if the NDES Server doesn't require a Password, or if you specify a SigningCert.

    .PARAMETER SigningCert
    Specifies the Signing Certificate used to sign the SCEP Certificate Request.
    Can be passed to the Command via the Pipeline.
    Use this when you already have a Certificate issued by the NDES Server and just want to renew it.
    Subject Information will be taken from this Certificate as otherwise NDES would deny the Request if there is a mismatch.

    .PARAMETER Ksp
    Specifies the Cryptographic Service Provider (CSP) or Key Storage Provider (KSP) to be used for the Private Key of the Certificate.
    You can specify any CSP or KSP that is installed on the System.
    Defaults to the Microsoft Software Key Storage Provider.

    .PARAMETER KeyAlgorithm
    Specifies the Algorithm to be used when creating the Key Pair.
    Defaults to "RSA".

    .PARAMETER KeyLength
    Specifies the Key Length for the Key pair of the Certificate.
    Gets applied only when KeyAlgorithm is "RSA".
    Defaults to 3072 Bits.

    .PARAMETER PrivateKeyExportable
    Specifies if the Private Key of the Certificate shall be marked as exportable.
    Defaults to the Key being not marked as exportable.

    .PARAMETER UseSSL
    Forces the connection to use SSL Encryption. Not necessary from a security perspective,
    as the SCEP Message's confidential partsd are encrypted with the NDES RA Certificates anyway.

    .PARAMETER Port
    Specifies the Network Port of the NDES Server to be used.
    Only necessary if your NDES Server is running on a non-default Port for some reason.
    Defaults to Port 80 without SSL and 443 with SSL.

    .PARAMETER Method
    Specifies if the Certificate Submission shall be done with HTTP "GET" or "POST".
    Defaults to "POST".

    .PARAMETER NoPolling
    Turn of polling for a certificate request that initially returned ScepDispositionPending.

    .PARAMETER MaxPolling
    Specifies the maximum time in seconds to wait for getting a certificate request that initially returned ScepDispositionPending.
    Defaults to 28800

    .PARAMETER PollingInterval
    Specifies the interval in seconds between polling for a certificate where the request initially returned ScepDispositionPending.
    Defaults to 300

    .OUTPUTS
    System.Security.Cryptography.X509Certificates.X509Certificate. Returns the issued Certificate returned by the NDES Server.
#>
Function Get-NDESCertificate {

    [cmdletbinding()]
    param(
        [Parameter(Mandatory=$True)]
        [String]
        $ComputerName,

        [Alias("Machine")]
        [Parameter(
            ParameterSetName="NewRequest",
            Mandatory=$False
            )]
        [Switch]
        $MachineContext = $False,

        [Parameter(
            ParameterSetName="NewRequest",
            Mandatory=$False
            )]
        [ValidateNotNullOrEmpty()]
        [String]
        $Subject,

        [Parameter(
            ParameterSetName="NewRequest",
            Mandatory=$False
            )]
        [Alias("DnsName")]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
            $_ | ForEach-Object -Process {
            [System.Uri]::CheckHostName($_) -eq [System.UriHostnameType]::Dns
            }
        })]
        [String[]]
        $Dns,

        [Parameter(
            ParameterSetName="NewRequest",
            Mandatory=$False
            )]
        [Alias("UserPrincipalName")]
        [ValidateNotNullOrEmpty()]
        [mailaddress[]]
        $Upn,

        [Parameter(
            ParameterSetName="NewRequest",
            Mandatory=$False
            )]
        [Alias("RFC822Name")]
        [Alias("E-Mail")]
        [ValidateNotNullOrEmpty()]
        [mailaddress[]]
        $Email,

        [Alias("IPAddress")]
        [Parameter(Mandatory=$False)]
        [ValidateNotNullOrEmpty()]
        [System.Net.IPAddress[]]
        $IP,

        [Parameter(
            ParameterSetName="NewRequest",
            Mandatory=$False
            )]
        [ValidateNotNullOrEmpty()]
        [String]
        $ChallengePassword,

        [Parameter(
            ParameterSetName="RenewalRequest",
            ValuefromPipeline = $True,
            Mandatory=$False
            )]
        [ValidateScript({($_.HasPrivateKey) -and ($null -ne $_.PSParentPath)})]
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $SigningCert,

        [Alias("KeyStorageProvider")]
        [Parameter(Mandatory=$False)]
        [ValidateScript({
            $Ksp = $_
            [bool](Get-KeyStorageProvider | Where-Object { $_.Name -eq $Ksp })}
        )]
        [String]
        $Ksp = "Microsoft Software Key Storage Provider",

        [Parameter(Mandatory=$False)]
        [ValidateSet(
            "RSA",
            "ECDSA_P256",
            "ECDSA_P384",
            "ECDSA_P521",
            "ECDH_P256",
            "ECDH_P384",
            "ECDH_P521"
            )]
        [String]
        $KeyAlgorithm = "RSA",

        [Alias("KeySize")]
        [Parameter(Mandatory=$False)]
        [ValidateSet(512,1024,2048,3072,4096,8192)]
        [Int]
        $KeyLength = 3072,

        [Alias("Exportable")]
        [Parameter(Mandatory=$False)]
        [Switch]
        $PrivateKeyExportable = $False,

        [Alias("SSL")]
        [Parameter(Mandatory=$False)]
        [Switch]
        $UseSSL = $False,

        [Parameter(Mandatory=$False)]
        [ValidateRange(1,65535)]
        [Int]
        $Port,

        [Parameter(Mandatory=$False)]
        [ValidateSet("GET","POST")]
        [String]
        $Method = "POST",

        [Parameter(Mandatory=$False)]
        [ValidateNotNullOrEmpty()]
        [String]
        $Suffix = "certsrv/mscep/mscep.dll",

        [Parameter(Mandatory=$False)]
        [Switch]
        $NoPolling = $False,

        [Parameter(Mandatory=$False)]
        [ValidateRange(1,57600)]
        [Int]
        $MaxPolling = 28800,

        [Parameter(Mandatory=$False)]
        [ValidateRange(60,600)]
        [Int]
        $PollingInterval = 300

    )

    begin  {

        Add-Type -AssemblyName System.Security

        # This hides the Status Indicators of the Invoke-WebRequest Calls later on
        $ProgressPreference = 'SilentlyContinue'

        # Assembling the Configuration String, which is the SCEP URL in this Case
        If ($UseSSL)
            { $Protocol = "https" }
        Else 
            { $Protocol = "http" }

        If ($Port)
            { $PortString = ":$($Port)" }
        Else
            { $PortString = [String]::Empty }

        $ConfigString = "$($Protocol)://$($ComputerName)$($PortString)/$($Suffix)/pkiclient.exe"

        Write-Verbose -Message "Configuration String: $ConfigString"

        # SCEP GetCACaps Operation
        Try {
            $GetCACaps = (Invoke-WebRequest -uri "$($ConfigString)?operation=GetCACaps" -UseBasicParsing).Content
        }
        Catch {
            Write-Error -Message $PSItem.Exception.Message
            return
        }

        # SCEP GetCACert Operation
        Try {
            $GetCACert = (Invoke-WebRequest -uri "$($ConfigString)?operation=GetCACert" -UseBasicParsing).Content

            # Decoding the CMS (PKCS#7 Message that was returned from the NDES Server)
            $Pkcs7CaCert = New-Object System.Security.Cryptography.Pkcs.SignedCms
            $Pkcs7CaCert.Decode($GetCACert)
        }
        Catch {
            Write-Error -Message $PSItem.Exception.Message
            return
        }

    }

    process {

        # Skip pipeline processing if the preparation steps failed
        If (-not $GetCACaps) { return }
        If (-not $Pkcs7CaCert.Certificates) { return }

        # Ensuring the Code will be executed on a supported Operating System
        # Operating Systems prior to Windows 8.1 don't contain the IX509SCEPEnrollment Interface
        If ([int32](Get-WmiObject Win32_OperatingSystem).BuildNumber -lt $BUILD_NUMBER_WINDOWS_8_1) {
            Write-Error -Message "This must be executed on Windows 8.1/Windows Server 2012 R2 or newer!"
            return 
        }

        # Ensuring we work with Elevation when messing with the Computer Certificate Store
        # As we want to inherit Key Settings from the Signing Certificate, we must also check its Certificate Store
        If ($MachineContext.IsPresent -or ($SigningCert -and ($SigningCert.PSParentPath -match "Machine"))) {

            If (-not (
                [Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
                ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
                Write-Error -Message "This must be run with Elevation (Run as Administrator) when using the Machine Context!" 
                return
            }
        }

        $CertificateRequestPkcs10 = New-Object -ComObject "X509Enrollment.CX509CertificateRequestPkcs10"

        # Determining if we create an entirely new Certificate Request or inherit Settings from an old one
        If ($SigningCert) {

            # Certificate Renewal Request

            If ($GetCACaps -match "Renewal") {

                $InheritOptions =  $X509RequestInheritOptions.InheritDefault
                $InheritOptions += $X509RequestInheritOptions.InheritSubjectAltNameFlag
                $InheritOptions += $X509RequestInheritOptions.InheritExtensionsFlag
                $InheritOptions += $X509RequestInheritOptions.InheritSubjectFlag

                $CertificateRequestPkcs10.InitializeFromCertificate(
                    [int]($SigningCert.PSParentPath -match "Machine")+1,
                    [Convert]::ToBase64String($SigningCert.RawData),
                    $EncodingType.XCN_CRYPT_STRING_BASE64,
                    $InheritOptions
                )

                
                # Configuring the private Key of the Certificate
                $CertificateRequestPkcs10.PrivateKey.Length = $KeyLength
                $CertificateRequestPkcs10.PrivateKey.ExportPolicy = [int]($PrivateKeyExportable.IsPresent)
                $CertificateRequestPkcs10.PrivateKey.ProviderName = $Ksp

                <#
                    https://tools.ietf.org/html/draft-nourse-scep-23#section-2.3
                    A client that is performing certificate renewal as per Appendix D
                    SHOULD send an empty challenge password (i.e. use the empty string as
                    the challenge password) but MAY send the originally distributed
                    challenge password in the challengePassword attribute.
                #>
                $CertificateRequestPkcs10.ChallengePassword = [String]::Empty

            }
            Else {
                Write-Error -Message "The Server does not support Renewal!"
                return
            }

        }
        Else {

            # New Certificate Request

            If ((-not $Dns) -and (-not $Upn) -and (-not $Email) -and (-not $IP) -and (-not $Subject)) {
                Write-Error -Message "You must provide an Identity, either in Form ob a Subject or Subject Alternative Name!"
                return
            }


            # We first create the Private Key
            # https://docs.microsoft.com/en-us/windows/win32/api/certenroll/nn-certenroll-ix509privatekey
            # Setting the Provider Attribute on the CertRequest Object afterwards seems not to work with Key Storage Providers...why?
            $PrivateKey = New-Object -ComObject 'X509Enrollment.CX509PrivateKey'
            
            $PrivateKey.ProviderName = $Ksp

            $PrivateKey.MachineContext = [int]($MachineContext.IsPresent)
            $PrivateKey.ExportPolicy = [int]($PrivateKeyExportable.IsPresent)

            If ($KeyAlgorithm -ne "RSA") {

                $Algorithm = New-Object -ComObject 'X509Enrollment.CObjectId'
    
                # https://docs.microsoft.com/en-us/windows/win32/api/certenroll/nf-certenroll-iobjectid-initializefromalgorithmname
                $Algorithm.InitializeFromAlgorithmName(
                    $ObjectIdGroupId.XCN_CRYPT_PUBKEY_ALG_OID_GROUP_ID,
                    $ObjectIdPublicKeyFlags.XCN_CRYPT_OID_INFO_PUBKEY_ANY,
                    $AlgorithmFlags.AlgorithmFlagsNone,
                    $KeyAlgorithm
                )
    
                # https://docs.microsoft.com/en-us/windows/win32/api/certenroll/nf-certenroll-ix509privatekey-put_algorithm
                $PrivateKey.Algorithm = $Algorithm
    
                [void]([System.Runtime.Interopservices.Marshal]::ReleaseComObject($Algorithm))
            }
    
            # Key Length is only relevant when Key Type is "RSA"
            If ($KeyAlgorithm -eq "RSA") {
    
                $PrivateKey.Length = $KeyLength
            }
    
            Try {
                $PrivateKey.Create()
            }
            Catch {
                [void]([System.Runtime.Interopservices.Marshal]::ReleaseComObject($PrivateKey))
                Write-Error -Message $PSItem.Exception.Message
                return
            }

            $CertificateRequestPkcs10.InitializeFromPrivateKey(
                [int]($MachineContext.IsPresent)+1,
                $PrivateKey, 
                [String]::Empty
            )

            Try {
                # To Do: implement Validation of the Subject RDN
                $SubjectDnObject = New-Object -ComObject "X509Enrollment.CX500DistinguishedName"
                $SubjectDnObject.Encode($Subject)
                $CertificateRequestPkcs10.Subject = $SubjectDnObject
            }
            Catch {
                Write-Error -Message "Invalid Subject DN supplied!"
                return
            }

            # Set the Subject Alternative Names Extension if specified as Argument
            If ($Upn -or $Email -or $Dns -or $IP) {

                $SubjectAlternativeNamesExtension = New-Object -ComObject X509Enrollment.CX509ExtensionAlternativeNames
                $Sans = New-Object -ComObject X509Enrollment.CAlternativeNames
        
                # https://msdn.microsoft.com/en-us/library/aa374981(VS.85).aspx

                Foreach ($Entry in $Upn) {

                    $AlternativeNameObject = New-Object -ComObject X509Enrollment.CAlternativeName
                    $AlternativeNameObject.InitializeFromString(
                        $AlternativeNameType.XCN_CERT_ALT_NAME_USER_PRINCIPLE_NAME, 
                        $Entry
                    )
                    $Sans.Add($AlternativeNameObject)
                    [void]([System.Runtime.Interopservices.Marshal]::ReleaseComObject($AlternativeNameObject))
    
                }

                Foreach ($Entry in $Email) {
            
                    $AlternativeNameObject = New-Object -ComObject X509Enrollment.CAlternativeName
                    $AlternativeNameObject.InitializeFromString(
                        $AlternativeNameType.XCN_CERT_ALT_NAME_RFC822_NAME, 
                        $Entry
                    )
                    $Sans.Add($AlternativeNameObject)
                    [void]([System.Runtime.Interopservices.Marshal]::ReleaseComObject($AlternativeNameObject))
    
                }
    
                Foreach ($Entry in $Dns) {

                    $AlternativeNameObject = New-Object -ComObject X509Enrollment.CAlternativeName
                    $AlternativeNameObject.InitializeFromString(
                        $AlternativeNameType.XCN_CERT_ALT_NAME_DNS_NAME,
                        $Entry
                    )
                    $Sans.Add($AlternativeNameObject)
                    [void]([System.Runtime.Interopservices.Marshal]::ReleaseComObject($AlternativeNameObject))
    
                }

                Foreach ($Entry in $IP) {

                    $AlternativeNameObject = New-Object -ComObject X509Enrollment.CAlternativeName
                    $AlternativeNameObject.InitializeFromRawData(
                        $AlternativeNameType.XCN_CERT_ALT_NAME_IP_ADDRESS,
                        $EncodingType.XCN_CRYPT_STRING_BASE64,
                        [Convert]::ToBase64String($Entry.GetAddressBytes())
                    )
                    $Sans.Add($AlternativeNameObject)
                    [void]([System.Runtime.Interopservices.Marshal]::ReleaseComObject($AlternativeNameObject))
    
                }
                
                $SubjectAlternativeNamesExtension.Critical = $True
                $SubjectAlternativeNamesExtension.InitializeEncode($Sans)
        
                # Adding the Extension to the Certificate
                $CertificateRequestPkcs10.X509Extensions.Add($SubjectAlternativeNamesExtension)
        
            }

            If ($ChallengePassword) {
                <#
                    https://tools.ietf.org/html/draft-nourse-scep-23#section-2.2
                    PKCS#10 [RFC2986] specifies a PKCS#9 [RFC2985] challengePassword
                    attribute to be sent as part of the enrollment request.  Inclusion of
                    the challengePassword by the SCEP client is OPTIONAL and allows for
                    unauthenticated authorization of enrollment requests.
                #>
                $CertificateRequestPkcs10.ChallengePassword = $ChallengePassword
            }

        }

        <#
            Identify the Root CA Certificate that was delivered with the Chain
            https://tools.ietf.org/html/rfc5280#section-6.1
            A certificate is self-issued if the same DN appears in the subject and issuer fields 
        #>
        $RootCaCert = $Pkcs7CaCert.Certificates | Where-Object { $_.Subject -eq $_.Issuer }

        # Initialize the IX509SCEPEnrollment Interface
        # https://docs.microsoft.com/en-us/windows/win32/api/certenroll/nn-certenroll-ix509scepenrollment
        $SCEPEnrollmentInterface = New-Object -ComObject "X509Enrollment.CX509SCEPEnrollment"

        # Let's try to build a SCEP Enrollment Message now...

        Try {

            # https://docs.microsoft.com/en-us/windows/win32/api/certenroll/nf-certenroll-ix509scepenrollment-initialize
            $SCEPEnrollmentInterface.Initialize(
                $CertificateRequestPkcs10,
                (Get-CertificateHash -Bytes $RootCaCert.RawData -HashAlgorithm "MD5"),
                $EncodingType.XCN_CRYPT_STRING_HEX,
                [Convert]::ToBase64String($GetCACert),
                $EncodingType.XCN_CRYPT_STRING_BASE64
            )

        }
        Catch {
            Write-Error -Message $PSItem.Exception.Message
            return
        }

        # Sets the preferred hash and encryption algorithms for the request.
        # If you do not set this property, then the default hash and encryption algorithms will be used.
        # https://docs.microsoft.com/en-us/windows/win32/api/certenroll/nf-certenroll-ix509scepenrollment-put_servercapabilities
        $SCEPEnrollmentInterface.ServerCapabilities = $GetCACaps

        <#
            https://tools.ietf.org/html/draft-nourse-scep-23#section-2.2
            If the requester does not have an appropriate existing
            certificate, then a locally generated self-signed certificate
            MUST be used instead.  The self-signed certificate MUST use the
            same subject name as in the PKCS#10 request.

            https://docs.microsoft.com/en-us/windows/win32/api/certenroll/nf-certenroll-ix509scepenrollment-put_signercertificate
            To create a renewal request, you must set this property prior to calling the CreateRequestMessage method. 
            Otherwise, the CreateRequestMessage method will create a new request and generate a self-signed certificate 
            using the same private key as the inner PKCSV10 reqeust.
        #>
        If ($SigningCert) {

            $SignerCertificate = New-Object -ComObject 'X509Enrollment.CSignerCertificate'

            # https://docs.microsoft.com/en-us/windows/win32/api/certenroll/nf-certenroll-isignercertificate-initialize
            $SignerCertificate.Initialize(
                [int]($SigningCert.PSParentPath -match "Machine"),
                $X509PrivateKeyVerify.VerifyNone, # We did this already during Parameter Validation
                $EncodingType.XCN_CRYPT_STRING_BASE64,
                [Convert]::ToBase64String($SigningCert.RawData)
            )
            $SCEPEnrollmentInterface.SignerCertificate = $SignerCertificate
        }

        # Building the PKCS7 Message for the SCEP Enrollment
        # https://docs.microsoft.com/en-us/windows/win32/api/certenroll/nf-certenroll-ix509scepenrollment-createrequestmessage
        $SCEPRequestMessage = $SCEPEnrollmentInterface.CreateRequestMessage(
            $EncodingType.XCN_CRYPT_STRING_BASE64
            )
        
        $TransactionId = $SCEPEnrollmentInterface.TransactionId($EncodingType.XCN_CRYPT_STRING_HEX)
        $TransactionIdText = $TransactionId -replace '\s',''
        Write-Information -MessageData "Transaction Id: $TransactionIdText" -Tags "TransactionId" -InformationAction Continue

        $DoOperation = $True
        $FirstPendingMessage = $True

        While ($DoOperation) {
            $DoOperation = $False

            # Submission to the NDES Server
            Try {

                If ($Method -eq "POST") {

                    If ($GetCACaps -match "POSTPKIOperation") {
                        $SCEPResponse = Invoke-WebRequest `
                            -Body ([Convert]::FromBase64String($SCEPRequestMessage)) `
                            -Method 'POST' `
                            -Uri "$($ConfigString)?operation=PKIOperation" `
                            -Headers @{'Content-Type' = 'application/x-pki-message'} `
                            -UseBasicParsing
                    }
                    Else {
                        Write-Warning -Message "The Server indicates that it doesnt support the 'POST' Method. Falling back to 'GET'."
                        $Method = "GET"
                    }
                }

                If ($Method -eq "GET") {
                    $SCEPResponse = Invoke-WebRequest `
                        -Method 'GET' `
                        -Uri "$($ConfigString)?operation=PKIOperation&message=$([uri]::EscapeDataString($SCEPRequestMessage))" `
                        -Headers @{'Content-Type' = 'application/x-pki-message'} `
                        -UseBasicParsing
                }

                $SCEPResponse = [Convert]::ToBase64String($ScepResponse.Content)

            }
            Catch {
                Write-Error -Message $PSItem.Exception.Message
                return
            }
        
            Try {

                # Process a response message and return the disposition of the message.
                # https://docs.microsoft.com/en-us/windows/win32/api/certenroll/nf-certenroll-ix509scepenrollment-processresponsemessage
                $Disposition = $SCEPEnrollmentInterface.ProcessResponseMessage(
                    $SCEPResponse,
                    $EncodingType.XCN_CRYPT_STRING_BASE64
                    )

                # https://docs.microsoft.com/en-us/windows/win32/api/certpol/ne-certpol-x509scepdisposition
                Switch ($Disposition) {

                    $X509SCEPDisposition.SCEPDispositionFailure {

                        # Delete private key, to avoid dangling keys in the system
                        Try {
                            $PrivateKey.Delete()
                        }
                        Catch {
                            [void]([System.Runtime.Interopservices.Marshal]::ReleaseComObject($PrivateKey))
                            Write-Warning -Message $PSItem.Exception.Message
                        }

                        $ErrorMessage = ''
                        $ErrorMessage += "The NDES Server rejected the Certificate Request!`n"

                        # The Failinfo Method is only present in Windows 10
                        # Windows 8.1 / 2012 R2 Users therefore won't get any fancy error message, sadly
                        If ([int32](Get-WmiObject Win32_OperatingSystem).BuildNumber -ge $BUILD_NUMBER_WINDOWS_10) {

                            $FailInfo = ($SCEPFailInfo | Where-Object { $_.Code -eq $SCEPEnrollmentInterface.FailInfo() })

                            $ErrorMessage += "SCEP Failure Information: $($FailInfo.Message) ($($FailInfo.Code)) $($FailInfo.Description)`n"
                            $ErrorMessage += "Additional Information returned by the Server: $($SCEPEnrollmentInterface.Status().Text)`n"

                            If ($SCEPEnrollmentInterface.Status().Text -match $NDESErrorCode.CERT_E_WRONG_USAGE) {
                                $ErrorMessage += "Possible reason(s): The Challenge Password has been used already."
                            }

                            If ($SCEPEnrollmentInterface.Status().Text -match $NDESErrorCode.TRUST_E_CERT_SIGNATURE) {
                                $ErrorMessage += "Possible reason(s): The NDES Server requires a Challenge Password but none was supplied."
                            }

                            If ($SCEPEnrollmentInterface.Status().Text -match $NDESErrorCode.ERROR_NOT_FOUND) {
                                $ErrorMessage += "Possible reason(s): The Challenge Password supplied is unknown to the NDES Server, or it has been used already."
                            }

                            If ($SCEPEnrollmentInterface.Status().Text -match $NDESErrorCode.CERTSRV_E_BAD_REQUESTSUBJECT) {
                                $ErrorMessage += "Possible reason(s): The CA denied your request because an invalid Subject was requested."
                            }

                            If ($SCEPEnrollmentInterface.Status().Text -match $NDESErrorCode.RPC_S_SERVER_UNAVAILABLE) {
                                $ErrorMessage += "Possible reason(s): The NDES Server was unable to contact the Certification Authority."
                            }
                        }

                        Write-Error -Message $ErrorMessage

                    }

                    $X509SCEPDisposition.SCEPDispositionPending {
                        if ($NoPolling) {
                            Write-Warning -Message @"
The certificate submit was successful with status ScepDispositionPending, but polling for the issued certificate is disabled!
The enrollment may be continued after the CA admin has issued the certificate by using the following commands:
  certreq -f -v -config $($ComputerName)$($PortString) -retrieve $TransactionIdText thecertificate.crt
  certreq -v -accept thecertificate.crt
"@
                        }
                        Else {
                            If ($FirstPendingMessage) {
                                Write-Host "Certificate request pending administrator approval at Certificate Authority"
                                $EndPollingTime = (Get-Date).AddSeconds($MaxPolling)
                                Write-Information -MessageData "Will wait for approval until $($EndPollingTime.ToString('HH:mm'))" -Tags "EndPollTime" -InformationAction Continue
                                $FirstPendingMessage = $False
                            }
                            If ((Get-Date) -gt $EndPollingTime) {
                                Write-Error -Message "Aborts waiting for certificate approval at CA"
                            }
                            Else {
                                $Context = $X509CertificateEnrollmentContext.ContextUser
                                if ($MachineContext.IsPresent) {
                                    $Context = $X509CertificateEnrollmentContext.ContextMachine # eller ContextAdministratorForceMachine
                                }
                                $SCEPEnrollmentInterface = New-Object -ComObject "X509Enrollment.CX509SCEPEnrollment"
                                $SCEPEnrollmentInterface.InitializeForPending($Context)
                                $SCEPEnrollmentInterface.TransactionId($EncodingType.XCN_CRYPT_STRING_HEX) = $TransactionId
                                $SCEPRequestMessage = $SCEPEnrollmentInterface.CreateRetrievePendingMessage($EncodingType.XCN_CRYPT_STRING_BASE64)
                            
                                $WhenRetry = (Get-Date).AddSeconds($PollingInterval).ToString("HH:mm:ss")
                                Write-Host "Will retry to retrieve certficate at time $($WhenRetry)"
                                Start-Sleep -s $PollingInterval
                                Write-Host "Retries retrieving certificate"

                                $DoOperation = $True
                            }
                        }
                    }

                    $X509SCEPDisposition.SCEPDispositionPendingChallenge {
                        Write-Warning -Message  "The Enrollment was successful with Status ScepDispositionPendingChallenge, which is not yet implemented!"
                    }

                    $X509SCEPDisposition.SCEPDispositionUnknown {
                        Write-Error -Message "The Enrollment failed for an unknown Reason."
                    }

                    $X509SCEPDisposition.SCEPDispositionSuccess {

                        # We load the Certificate into an X509Certificate2 Object
                        # https://docs.microsoft.com/en-us/windows/win32/api/certenroll/nf-certenroll-ix509scepenrollment-get_certificate
                        Write-Host "Certificate imported successfully"
                        $CertificateObject = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2
                        $CertificateObject.Import(
                            [Convert]::FromBase64String(
                                $SCEPEnrollmentInterface.Certificate($EncodingType.XCN_CRYPT_STRING_BASE64)
                                )
                            )

                        # Return the resulting Certificate
                        If ($MachineContext.IsPresent -or ($SigningCert -and ($SigningCert.PSParentPath -match "Machine"))) {
                            Get-ChildItem -Path "Cert:\LocalMachine\My\$($CertificateObject.Thumbprint)"
                        }
                        Else {
                            Get-ChildItem -Path "Cert:\CurrentUser\My\$($CertificateObject.Thumbprint)"
                        }
                    }

                }

            }
            Catch {
                Write-Error -Message $PSItem.Exception.Message
                return  
            }
            
        } # end While

        # Cleaning up the COM Objects, avoiding any User Errors to be reported
        $CertificateRequestPkcs10,
        $SubjectDnObject,
        $SubjectAlternativeNamesExtension,
        $Sans,
        $SCEPEnrollmentInterface,
        $SignerCertificate | ForEach-Object -Process {

            Try {
                [void]([System.Runtime.Interopservices.Marshal]::ReleaseComObject($_))
            }
            Catch {
                # we don't want to return anything here
            }
        }
    }

    end {}
}