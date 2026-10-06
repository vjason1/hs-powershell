<#
.SYNOPSIS
    Hammerspace PowerShell Module — auto-generated from Swagger v1.2

.DESCRIPTION
    Provides PowerShell cmdlets for every endpoint in the Hammerspace
    sys-mgmt REST API (v1.2).  All cmdlets require an active session
    established with Connect-HammerspaceSession.
    Body parameters are exposed as individual named parameters.

.NOTES
    Authors  : Peter Learnmoth, Jason Ventresco, Google Gemini
    Version  : 1.2.0
    Generated: from swagger.json (Hammerspace API v1.2)
    Help text: HS3004-USEN-17 Hammerspace 5.2 Admin CLI Reference Rev-2
    Help text: from HS3004-USEN-17 Hammerspace 5.2 Admin CLI Reference Rev-2
#>

#Requires -Version 5.1
Set-StrictMode -Version 2

# ---------------------------------------------------------------------------
# Module-level session state
# ---------------------------------------------------------------------------
$script:HsSession = $null

# ---------------------------------------------------------------------------
# SECTION: Session Management
# ---------------------------------------------------------------------------

function Connect-HammerspaceSession {
    <#
    .SYNOPSIS
        Establish a session to the Hammerspace API.
    .DESCRIPTION
        Authenticates using HTTP Basic Auth and stores the session for all
        subsequent cmdlets. Validates the connection by calling POST /login.
    .PARAMETER HsHost
        Hostname or IP of the Hammerspace management interface.
    .PARAMETER Port
        Management port. Defaults to 8443.
    .PARAMETER Credential
        PSCredential. If omitted, Get-Credential is called interactively.
    .PARAMETER SkipCertificateCheck
        Skip TLS certificate validation (useful for self-signed certs).
    .EXAMPLE
        Connect-HammerspaceSession -HsHost 10.0.0.1 -SkipCertificateCheck
    .EXAMPLE
        $cred = Get-Credential
        Connect-HammerspaceSession -HsHost 10.0.0.1 -Credential $cred
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$HsHost,
        [Parameter()][int]$Port = 8443,
        [Parameter()][PSCredential]$Credential,
        [Parameter()][switch]$SkipCertificateCheck
    )

    if (-not $Credential) {
        $Credential = Get-Credential -Message "Enter Hammerspace API credentials for $HsHost"
    }

    $script:HsSession = [PSCustomObject]@{
        BaseUrl              = "https://${HsHost}:${Port}/mgmt/v1.2/rest"
        Credential           = $Credential
        SkipCertificateCheck = $SkipCertificateCheck.IsPresent
    }

    # Validate connectivity and credentials using GET /system/ping.
    # The Hammerspace API uses HTTP Basic Auth on every endpoint — there is no
    # separate login call. /system/ping requires auth and returns an empty 200
    # on success, making it a clean credential check.
    try {
        $null = Invoke-HsRequest -Method GET -Endpoint "/system/ping"
        Write-Host "Connected to Hammerspace at ${HsHost}:${Port}" -ForegroundColor Green
    } catch {
        $script:HsSession = $null
        throw "Failed to connect to Hammerspace at ${HsHost}:${Port}: $_"
    }
}

function Disconnect-HammerspaceSession {
    <#
    .SYNOPSIS
        Clear the stored Hammerspace session.
    #>
    [CmdletBinding()]
    param()
    $script:HsSession = $null
    Write-Host "Hammerspace session cleared." -ForegroundColor Yellow
}

function Get-HammerspaceSession {
    <#
    .SYNOPSIS
        Return the current session object, or throw if not connected.
    #>
    [CmdletBinding()]
    param()
    if (-not $script:HsSession) {
        throw "No active Hammerspace session. Call Connect-HammerspaceSession first."
    }
    return $script:HsSession
}

# ---------------------------------------------------------------------------
# SECTION: Internal HTTP helper
# ---------------------------------------------------------------------------

function Invoke-HsRequest {
    <#
    .SYNOPSIS
        Internal helper — authenticated REST calls to the Hammerspace API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][string]$Endpoint,
        [Parameter()][hashtable]$QueryParams,
        [Parameter()][hashtable]$Body
    )

    $session = Get-HammerspaceSession
    $uri     = "$($session.BaseUrl)$Endpoint"

    if ($QueryParams -and $QueryParams.Count -gt 0) {
        $qs = ($QueryParams.GetEnumerator() |
               Where-Object { $null -ne $_.Value -and $_.Value -ne '' } |
               ForEach-Object { "$([System.Uri]::EscapeDataString($_.Key))=$([System.Uri]::EscapeDataString([string]$_.Value))" }) -join "&"
        if ($qs) { $uri = "${uri}?${qs}" }
    }

    $plainUser = $session.Credential.UserName
    $plainPass = $session.Credential.GetNetworkCredential().Password
    $encoded   = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${plainUser}:${plainPass}"))
    $headers = @{ Authorization = "Basic $encoded" }

    $invokeParams = @{
        Method          = $Method
        Uri             = $uri
        Headers         = $headers
        UseBasicParsing = $true
    }

    if ($Body -and $Body.Count -gt 0) {
        $invokeParams["Body"]    = ($Body | ConvertTo-Json -Depth 20)
        $headers["Content-Type"] = "application/json"
    } elseif ($Method -in @('POST','PUT','PATCH')) {
        # Set Content-Type without a body to prevent PowerShell from
        # auto-setting application/x-www-form-urlencoded on bodyless POSTs.
        $headers["Content-Type"] = "application/json"
    }

    if ($session.SkipCertificateCheck) {
        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $invokeParams["SkipCertificateCheck"] = $true
        } else {
            [Net.ServicePointManager]::ServerCertificateValidationCallback = { $true }
        }
    }

    try {
        $response = Invoke-WebRequest @invokeParams -ErrorAction Stop
        if ($response.Content) { return $response.Content | ConvertFrom-Json }
        return $null
    } catch [System.Net.WebException] {
        $statusCode = [int]$_.Exception.Response.StatusCode
        $msg = $_.Exception.Message
        try {
            $stream = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream)
            $msg    = $reader.ReadToEnd()
        } catch {}
        throw "Hammerspace API error $statusCode : $msg"
    }
}

# ---------------------------------------------------------------------------
# SECTION: ad
# ---------------------------------------------------------------------------

function Get-HsAd {
    <#
    .SYNOPSIS
        Get AD configuration
    .DESCRIPTION
        GET /ad
    .PARAMETER Includediscoveryinfo
        (Query) includeDiscoveryInfo
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Includediscoveryinfo,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "includeDiscoveryInfo" = $Includediscoveryinfo
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/ad" -QueryParams $qp
}

function Get-HsAd2 {
    <#
    .SYNOPSIS
        Get discovered realm information
    .DESCRIPTION
        GET /ad/discover/{domain}
    .PARAMETER Domain
        (Path) domain
    .PARAMETER Includeservertime
        (Query) includeServerTime
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Domain,
        [Parameter()][string]$Includeservertime
    )

        $qp = @{
            "includeServerTime" = $Includeservertime
        }

        Invoke-HsRequest -Method GET -Endpoint "/ad/discover/${Domain}" -QueryParams $qp
}

function Invoke-HsAd {
    <#
    .SYNOPSIS
        Flush AD cache
    .DESCRIPTION
        POST /ad/flush_cache
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method POST -Endpoint "/ad/flush_cache"
}

function Get-HsAd3 {
    <#
    .SYNOPSIS
        Get an AD by ID
    .DESCRIPTION
        GET /ad/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Includediscoveryinfo
        (Query) includeDiscoveryInfo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Includediscoveryinfo
    )

        $qp = @{
            "includeDiscoveryInfo" = $Includediscoveryinfo
        }

        Invoke-HsRequest -Method GET -Endpoint "/ad/${Identifier}" -QueryParams $qp
}

function Set-HsAd {
    <#
    .SYNOPSIS
        View and modify Active Directory configuration
    .DESCRIPTION
        View and modify Active Directory configuration. Configure and view SMB parameters
    .NOTES
    CLI equivalent: ad-config, smb-config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$RecreateNfsSpns,
        [Parameter()][string]$Comment,
        [Parameter()][hashtable]$Ipv4,
        [Parameter()][hashtable]$Ipv6,
        [Parameter()][string]$Nodename,
        [Parameter()][switch]$Joined,
        [Parameter()][string]$Domain,
        [Parameter()][string]$Smbservername,
        [Parameter()][string]$Anvildnsname,
        [Parameter()][object[]]$Adservers,
        [Parameter()][string]$Username,
        [Parameter()][string]$Password,
        [Parameter()][string]$Computerou,
        [ValidateSet('SMB1', 'SMB2', 'SMB2_10', 'SMB3', 'SMB3_11')]
        [Parameter()][string]$Minsmbclient,
        [ValidateSet('RFC2307', 'RFC2307BIS', 'AD')]
        [Parameter()][string]$Ldapschema,
        [Parameter()][switch]$Distributedlockmanagerenabled,
        [Parameter()][switch]$Multichannelenabled,
        [Parameter()][switch]$Smbautohomeenabled,
        [Parameter()][object[]]$Dnsconfiguredips,
        [Parameter()][switch]$Registerallfloatingips,
        [Parameter()][hashtable]$Discoveryinfo,
        [Parameter()][switch]$Removecomputer,
        [Parameter()][object[]]$Dnsregisteredips,
        [Parameter()][object[]]$Dnsavailableips,
        [Parameter()][object[]]$Providedidmappingdomains,
        [Parameter()][object[]]$Effectiveidmappingdomains,
        [Parameter()][object[]]$Registerednfsspns,
        [Parameter()][object[]]$Smbautohomes,
        [Parameter()][object[]]$Missingrequirednfsspns,
        [Parameter()][string]$Portaldnshostname,
        [Parameter()][string]$Anvildnshostname
    )

        $qp = @{
            "recreate-nfs-spns" = $RecreateNfsSpns
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Ipv4")) { $body["ipv4"] = $Ipv4 }
        if ($PSBoundParameters.ContainsKey("Ipv6")) { $body["ipv6"] = $Ipv6 }
        if ($PSBoundParameters.ContainsKey("Nodename")) { $body["nodeName"] = $Nodename }
        $body["joined"] = $Joined.IsPresent
        if ($PSBoundParameters.ContainsKey("Domain")) { $body["domain"] = $Domain }
        if ($PSBoundParameters.ContainsKey("Smbservername")) { $body["smbServerName"] = $Smbservername }
        if ($PSBoundParameters.ContainsKey("Anvildnsname")) { $body["anvilDnsName"] = $Anvildnsname }
        if ($PSBoundParameters.ContainsKey("Adservers")) { $body["adServers"] = $Adservers }
        if ($PSBoundParameters.ContainsKey("Username")) { $body["username"] = $Username }
        if ($PSBoundParameters.ContainsKey("Password")) { $body["password"] = $Password }
        if ($PSBoundParameters.ContainsKey("Computerou")) { $body["computerOu"] = $Computerou }
        if ($PSBoundParameters.ContainsKey("Minsmbclient")) { $body["minSmbClient"] = $Minsmbclient }
        if ($PSBoundParameters.ContainsKey("Ldapschema")) { $body["ldapSchema"] = $Ldapschema }
        $body["distributedLockManagerEnabled"] = $Distributedlockmanagerenabled.IsPresent
        $body["multiChannelEnabled"] = $Multichannelenabled.IsPresent
        $body["smbAutohomeEnabled"] = $Smbautohomeenabled.IsPresent
        if ($PSBoundParameters.ContainsKey("Dnsconfiguredips")) { $body["dnsConfiguredIps"] = $Dnsconfiguredips }
        $body["registerAllFloatingIps"] = $Registerallfloatingips.IsPresent
        if ($PSBoundParameters.ContainsKey("Discoveryinfo")) { $body["discoveryInfo"] = $Discoveryinfo }
        $body["removeComputer"] = $Removecomputer.IsPresent
        if ($PSBoundParameters.ContainsKey("Dnsregisteredips")) { $body["dnsRegisteredIps"] = $Dnsregisteredips }
        if ($PSBoundParameters.ContainsKey("Dnsavailableips")) { $body["dnsAvailableIps"] = $Dnsavailableips }
        if ($PSBoundParameters.ContainsKey("Providedidmappingdomains")) { $body["providedIdMappingDomains"] = $Providedidmappingdomains }
        if ($PSBoundParameters.ContainsKey("Effectiveidmappingdomains")) { $body["effectiveIdMappingDomains"] = $Effectiveidmappingdomains }
        if ($PSBoundParameters.ContainsKey("Registerednfsspns")) { $body["registeredNfsSpns"] = $Registerednfsspns }
        if ($PSBoundParameters.ContainsKey("Smbautohomes")) { $body["smbAutohomes"] = $Smbautohomes }
        if ($PSBoundParameters.ContainsKey("Missingrequirednfsspns")) { $body["missingRequiredNfsSpns"] = $Missingrequirednfsspns }
        if ($PSBoundParameters.ContainsKey("Portaldnshostname")) { $body["portalDnsHostname"] = $Portaldnshostname }
        if ($PSBoundParameters.ContainsKey("Anvildnshostname")) { $body["anvilDnsHostname"] = $Anvildnshostname }

        Invoke-HsRequest -Method PUT -Endpoint "/ad/${Identifier}" -QueryParams $qp -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: antivirus
# ---------------------------------------------------------------------------

function Get-HsAntivirus {
    <#
    .SYNOPSIS
        List the antivirus services
    .DESCRIPTION
        List the antivirus services
    .NOTES
    CLI equivalent: antivirus-list
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/antivirus"
}

function New-HsAntivirus {
    <#
    .SYNOPSIS
        Add an antivirus service
    .DESCRIPTION
        Add an antivirus service
    .NOTES
    CLI equivalent: antivirus-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Createplacementobjectives,
        [Parameter()][string]$Comment,
        [Parameter()][int]$Modificationcount,
        [Parameter()][hashtable]$Node,
        [Parameter()][string]$Operstatereason,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][string]$Name,
        [ValidateSet('ADDED', 'OK', 'DECOMMISSIONING', 'DECOMMISSIONED', 'FAILED', 'UNAVAILABLE')]
        [Parameter()][string]$Storagevolumestate,
        [Parameter()][switch]$Realignonprotectiondrop,
        [Parameter()][int]$Lastregradeinitiated,
        [Parameter()][int]$Lastvolumerealigned,
        [Parameter()][hashtable]$Regradeinfo,
        [ValidateSet('NONE', 'DECOM_QUIESCE_DME', 'DECOM_QUIESCE_ENVOY', 'DECOM_QUIESCE_PDFS', 'DECOM_REGRADE', 'DECOM_INSTANCE_REMOVAL', 'DECOM_CLEANING')]
        [Parameter()][string]$Workflowstage,
        [Parameter()][hashtable]$Location,
        [Parameter()][hashtable]$Storagecapabilities,
        [Parameter()][int]$Suspectedsince,
        [Parameter()][int]$Maxsuspectedseconds,
        [Parameter()][string]$Rootfilehandle,
        [Parameter()][object[]]$Associatedlocations,
        [Parameter()][int]$Effectivetotalcapacity,
        [Parameter()][hashtable]$Objectstorelogicalvolume,
        [Parameter()][string]$Accesskey,
        [Parameter()][string]$Secretkey,
        [Parameter()][int]$Totalcapacity,
        [Parameter()][int]$Logicalused,
        [Parameter()][object[]]$Sites,
        [ValidateSet('HASH_NAMED', 'PATH_NAMED')]
        [Parameter()][string]$Osvnamingtype,
        [ValidateSet('HIGH_COMPRESSION', 'FAST_COMPRESSION', 'NO_COMPRESSION')]
        [Parameter()][string]$Compressiontype,
        [ValidateSet('CONTENT_BASED_CHUNKING', 'FIXED_CHUNKING', 'NO_CHUNKING')]
        [Parameter()][string]$Chunkingtype,
        [ValidateSet('STANDARD', 'AWS_GLACIER_INSTANT_RETRIEVAL')]
        [Parameter()][string]$Storageclass,
        [Parameter()][int]$Kmsinternalid,
        [Parameter()][hashtable]$Kms,
        [Parameter()][object[]]$Otversions,
        [Parameter()][switch]$Shared,
        [Parameter()][hashtable]$Gcinfo,
        [Parameter()][switch]$Gcenabled,
        [Parameter()][switch]$Noupload,
        [Parameter()][string]$Region
    )

        $qp = @{
            "createPlacementObjectives" = $Createplacementobjectives
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Modificationcount")) { $body["modificationCount"] = $Modificationcount }
        if ($PSBoundParameters.ContainsKey("Node")) { $body["node"] = $Node }
        if ($PSBoundParameters.ContainsKey("Operstatereason")) { $body["operStateReason"] = $Operstatereason }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Storagevolumestate")) { $body["storageVolumeState"] = $Storagevolumestate }
        $body["realignOnProtectionDrop"] = $Realignonprotectiondrop.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastregradeinitiated")) { $body["lastRegradeInitiated"] = $Lastregradeinitiated }
        if ($PSBoundParameters.ContainsKey("Lastvolumerealigned")) { $body["lastVolumeRealigned"] = $Lastvolumerealigned }
        if ($PSBoundParameters.ContainsKey("Regradeinfo")) { $body["regradeInfo"] = $Regradeinfo }
        if ($PSBoundParameters.ContainsKey("Workflowstage")) { $body["workflowStage"] = $Workflowstage }
        if ($PSBoundParameters.ContainsKey("Location")) { $body["location"] = $Location }
        if ($PSBoundParameters.ContainsKey("Storagecapabilities")) { $body["storageCapabilities"] = $Storagecapabilities }
        if ($PSBoundParameters.ContainsKey("Suspectedsince")) { $body["suspectedSince"] = $Suspectedsince }
        if ($PSBoundParameters.ContainsKey("Maxsuspectedseconds")) { $body["maxSuspectedSeconds"] = $Maxsuspectedseconds }
        if ($PSBoundParameters.ContainsKey("Rootfilehandle")) { $body["rootFileHandle"] = $Rootfilehandle }
        if ($PSBoundParameters.ContainsKey("Associatedlocations")) { $body["associatedLocations"] = $Associatedlocations }
        if ($PSBoundParameters.ContainsKey("Effectivetotalcapacity")) { $body["effectiveTotalCapacity"] = $Effectivetotalcapacity }
        if ($PSBoundParameters.ContainsKey("Objectstorelogicalvolume")) { $body["objectStoreLogicalVolume"] = $Objectstorelogicalvolume }
        if ($PSBoundParameters.ContainsKey("Accesskey")) { $body["accessKey"] = $Accesskey }
        if ($PSBoundParameters.ContainsKey("Secretkey")) { $body["secretKey"] = $Secretkey }
        if ($PSBoundParameters.ContainsKey("Totalcapacity")) { $body["totalCapacity"] = $Totalcapacity }
        if ($PSBoundParameters.ContainsKey("Logicalused")) { $body["logicalUsed"] = $Logicalused }
        if ($PSBoundParameters.ContainsKey("Sites")) { $body["sites"] = $Sites }
        if ($PSBoundParameters.ContainsKey("Osvnamingtype")) { $body["osvNamingType"] = $Osvnamingtype }
        if ($PSBoundParameters.ContainsKey("Compressiontype")) { $body["compressionType"] = $Compressiontype }
        if ($PSBoundParameters.ContainsKey("Chunkingtype")) { $body["chunkingType"] = $Chunkingtype }
        if ($PSBoundParameters.ContainsKey("Storageclass")) { $body["storageClass"] = $Storageclass }
        if ($PSBoundParameters.ContainsKey("Kmsinternalid")) { $body["kmsInternalId"] = $Kmsinternalid }
        if ($PSBoundParameters.ContainsKey("Kms")) { $body["kms"] = $Kms }
        if ($PSBoundParameters.ContainsKey("Otversions")) { $body["otVersions"] = $Otversions }
        $body["shared"] = $Shared.IsPresent
        if ($PSBoundParameters.ContainsKey("Gcinfo")) { $body["gcInfo"] = $Gcinfo }
        $body["gcEnabled"] = $Gcenabled.IsPresent
        $body["noUpload"] = $Noupload.IsPresent
        if ($PSBoundParameters.ContainsKey("Region")) { $body["region"] = $Region }

        Invoke-HsRequest -Method POST -Endpoint "/antivirus" -QueryParams $qp -Body $body
}

function Get-HsAntivirus2 {
    <#
    .SYNOPSIS
        Get an antivirus service by identifier
    .DESCRIPTION
        GET /antivirus/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/antivirus/${Identifier}"
}

function Set-HsAntivirus {
    <#
    .SYNOPSIS
        Update an antivirus service
    .DESCRIPTION
        Update an antivirus service
    .NOTES
    CLI equivalent: antivirus-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][int]$Modificationcount,
        [Parameter()][hashtable]$Node,
        [Parameter()][string]$Operstatereason,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][string]$Name,
        [ValidateSet('ADDED', 'OK', 'DECOMMISSIONING', 'DECOMMISSIONED', 'FAILED', 'UNAVAILABLE')]
        [Parameter()][string]$Storagevolumestate,
        [Parameter()][switch]$Realignonprotectiondrop,
        [Parameter()][int]$Lastregradeinitiated,
        [Parameter()][int]$Lastvolumerealigned,
        [Parameter()][hashtable]$Regradeinfo,
        [ValidateSet('NONE', 'DECOM_QUIESCE_DME', 'DECOM_QUIESCE_ENVOY', 'DECOM_QUIESCE_PDFS', 'DECOM_REGRADE', 'DECOM_INSTANCE_REMOVAL', 'DECOM_CLEANING')]
        [Parameter()][string]$Workflowstage,
        [Parameter()][hashtable]$Location,
        [Parameter()][hashtable]$Storagecapabilities,
        [Parameter()][int]$Suspectedsince,
        [Parameter()][int]$Maxsuspectedseconds,
        [Parameter()][string]$Rootfilehandle,
        [Parameter()][object[]]$Associatedlocations,
        [Parameter()][int]$Effectivetotalcapacity,
        [Parameter()][hashtable]$Objectstorelogicalvolume,
        [Parameter()][string]$Accesskey,
        [Parameter()][string]$Secretkey,
        [Parameter()][int]$Totalcapacity,
        [Parameter()][int]$Logicalused,
        [Parameter()][object[]]$Sites,
        [ValidateSet('HASH_NAMED', 'PATH_NAMED')]
        [Parameter()][string]$Osvnamingtype,
        [ValidateSet('HIGH_COMPRESSION', 'FAST_COMPRESSION', 'NO_COMPRESSION')]
        [Parameter()][string]$Compressiontype,
        [ValidateSet('CONTENT_BASED_CHUNKING', 'FIXED_CHUNKING', 'NO_CHUNKING')]
        [Parameter()][string]$Chunkingtype,
        [ValidateSet('STANDARD', 'AWS_GLACIER_INSTANT_RETRIEVAL')]
        [Parameter()][string]$Storageclass,
        [Parameter()][int]$Kmsinternalid,
        [Parameter()][hashtable]$Kms,
        [Parameter()][object[]]$Otversions,
        [Parameter()][switch]$Shared,
        [Parameter()][hashtable]$Gcinfo,
        [Parameter()][switch]$Gcenabled,
        [Parameter()][switch]$Noupload,
        [Parameter()][string]$Region
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Modificationcount")) { $body["modificationCount"] = $Modificationcount }
        if ($PSBoundParameters.ContainsKey("Node")) { $body["node"] = $Node }
        if ($PSBoundParameters.ContainsKey("Operstatereason")) { $body["operStateReason"] = $Operstatereason }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Storagevolumestate")) { $body["storageVolumeState"] = $Storagevolumestate }
        $body["realignOnProtectionDrop"] = $Realignonprotectiondrop.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastregradeinitiated")) { $body["lastRegradeInitiated"] = $Lastregradeinitiated }
        if ($PSBoundParameters.ContainsKey("Lastvolumerealigned")) { $body["lastVolumeRealigned"] = $Lastvolumerealigned }
        if ($PSBoundParameters.ContainsKey("Regradeinfo")) { $body["regradeInfo"] = $Regradeinfo }
        if ($PSBoundParameters.ContainsKey("Workflowstage")) { $body["workflowStage"] = $Workflowstage }
        if ($PSBoundParameters.ContainsKey("Location")) { $body["location"] = $Location }
        if ($PSBoundParameters.ContainsKey("Storagecapabilities")) { $body["storageCapabilities"] = $Storagecapabilities }
        if ($PSBoundParameters.ContainsKey("Suspectedsince")) { $body["suspectedSince"] = $Suspectedsince }
        if ($PSBoundParameters.ContainsKey("Maxsuspectedseconds")) { $body["maxSuspectedSeconds"] = $Maxsuspectedseconds }
        if ($PSBoundParameters.ContainsKey("Rootfilehandle")) { $body["rootFileHandle"] = $Rootfilehandle }
        if ($PSBoundParameters.ContainsKey("Associatedlocations")) { $body["associatedLocations"] = $Associatedlocations }
        if ($PSBoundParameters.ContainsKey("Effectivetotalcapacity")) { $body["effectiveTotalCapacity"] = $Effectivetotalcapacity }
        if ($PSBoundParameters.ContainsKey("Objectstorelogicalvolume")) { $body["objectStoreLogicalVolume"] = $Objectstorelogicalvolume }
        if ($PSBoundParameters.ContainsKey("Accesskey")) { $body["accessKey"] = $Accesskey }
        if ($PSBoundParameters.ContainsKey("Secretkey")) { $body["secretKey"] = $Secretkey }
        if ($PSBoundParameters.ContainsKey("Totalcapacity")) { $body["totalCapacity"] = $Totalcapacity }
        if ($PSBoundParameters.ContainsKey("Logicalused")) { $body["logicalUsed"] = $Logicalused }
        if ($PSBoundParameters.ContainsKey("Sites")) { $body["sites"] = $Sites }
        if ($PSBoundParameters.ContainsKey("Osvnamingtype")) { $body["osvNamingType"] = $Osvnamingtype }
        if ($PSBoundParameters.ContainsKey("Compressiontype")) { $body["compressionType"] = $Compressiontype }
        if ($PSBoundParameters.ContainsKey("Chunkingtype")) { $body["chunkingType"] = $Chunkingtype }
        if ($PSBoundParameters.ContainsKey("Storageclass")) { $body["storageClass"] = $Storageclass }
        if ($PSBoundParameters.ContainsKey("Kmsinternalid")) { $body["kmsInternalId"] = $Kmsinternalid }
        if ($PSBoundParameters.ContainsKey("Kms")) { $body["kms"] = $Kms }
        if ($PSBoundParameters.ContainsKey("Otversions")) { $body["otVersions"] = $Otversions }
        $body["shared"] = $Shared.IsPresent
        if ($PSBoundParameters.ContainsKey("Gcinfo")) { $body["gcInfo"] = $Gcinfo }
        $body["gcEnabled"] = $Gcenabled.IsPresent
        $body["noUpload"] = $Noupload.IsPresent
        if ($PSBoundParameters.ContainsKey("Region")) { $body["region"] = $Region }

        Invoke-HsRequest -Method PUT -Endpoint "/antivirus/${Identifier}" -Body $body
}

function Remove-HsAntivirus {
    <#
    .SYNOPSIS
        Remove an antivirus service
    .DESCRIPTION
        Remove an antivirus service
    .NOTES
    CLI equivalent: antivirus-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/antivirus/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: backup
# ---------------------------------------------------------------------------

function Get-HsBackup {
    <#
    .SYNOPSIS
        Get Backup configuration
    .DESCRIPTION
        GET /backup
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/backup" -QueryParams $qp
}

function New-HsBackup {
    <#
    .SYNOPSIS
        Configure product configuration and metadata backups. Optionally create a backup now
    .DESCRIPTION
        Configure product configuration and metadata backups. Optionally create a backup now
    .NOTES
    CLI equivalent: system-backup-config
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][hashtable]$Ipv4,
        [Parameter()][hashtable]$Ipv6,
        [Parameter()][string]$Nodename,
        [Parameter()][hashtable]$Backupstoragevolume,
        [Parameter()][string]$Clusteruuid,
        [Parameter()][object[]]$Availablebackups
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Ipv4")) { $body["ipv4"] = $Ipv4 }
        if ($PSBoundParameters.ContainsKey("Ipv6")) { $body["ipv6"] = $Ipv6 }
        if ($PSBoundParameters.ContainsKey("Nodename")) { $body["nodeName"] = $Nodename }
        if ($PSBoundParameters.ContainsKey("Backupstoragevolume")) { $body["backupStorageVolume"] = $Backupstoragevolume }
        if ($PSBoundParameters.ContainsKey("Clusteruuid")) { $body["clusterUuid"] = $Clusteruuid }
        if ($PSBoundParameters.ContainsKey("Availablebackups")) { $body["availableBackups"] = $Availablebackups }

        Invoke-HsRequest -Method POST -Endpoint "/backup" -Body $body
}

function Invoke-HsBackupCreate {
    <#
    .SYNOPSIS
        Create immediate backup
    .DESCRIPTION
        POST /backup/backup-create/{volume-ip}/{export-path}
    .PARAMETER VolumeIp
        (Path) volume-ip
    .PARAMETER ExportPath
        (Path) export-path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VolumeIp,
        [Parameter(Mandatory)][string]$ExportPath
    )

        Invoke-HsRequest -Method POST -Endpoint "/backup/backup-create/${VolumeIp}/${ExportPath}"
}

function Get-HsBackupList {
    <#
    .SYNOPSIS
        List the names of the product configuration and metadata backups in the backup volume
    .DESCRIPTION
        List the names of the product configuration and metadata backups in the backup volume
    .NOTES
    CLI equivalent: system-backup-list
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VolumeIp,
        [Parameter(Mandatory)][string]$ExportPath
    )

        Invoke-HsRequest -Method GET -Endpoint "/backup/backup-list/${VolumeIp}/${ExportPath}"
}

function Invoke-HsBackupRestore {
    <#
    .SYNOPSIS
        Restore product configuration and metadata backup
    .DESCRIPTION
        Restore product configuration and metadata backup
    .NOTES
    CLI equivalent: system-backup-restore
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VolumeIp,
        [Parameter(Mandatory)][string]$ExportPath,
        [Parameter()][string]$ClusterUuid
    )

        $qp = @{
            "cluster-uuid" = $ClusterUuid
        }

        Invoke-HsRequest -Method POST -Endpoint "/backup/backup-restore/${VolumeIp}/${ExportPath}" -QueryParams $qp
}

function Invoke-HsBackupRestore2 {
    <#
    .SYNOPSIS
        Restore backup from storage volume
    .DESCRIPTION
        POST /backup/backup-restore/{volume-ip}/{export-path}/{backup-name}
    .PARAMETER VolumeIp
        (Path) volume-ip
    .PARAMETER ExportPath
        (Path) export-path
    .PARAMETER BackupName
        (Path) backup-name
    .PARAMETER ClusterUuid
        (Query) cluster-uuid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$VolumeIp,
        [Parameter(Mandatory)][string]$ExportPath,
        [Parameter(Mandatory)][string]$BackupName,
        [Parameter()][string]$ClusterUuid
    )

        $qp = @{
            "cluster-uuid" = $ClusterUuid
        }

        Invoke-HsRequest -Method POST -Endpoint "/backup/backup-restore/${VolumeIp}/${ExportPath}/${BackupName}" -QueryParams $qp
}

function Set-HsBackup {
    <#
    .SYNOPSIS
        Update a backup schedule
    .DESCRIPTION
        PUT /backup/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Ipv4
        (Body) ipv4
    .PARAMETER Ipv6
        (Body) ipv6
    .PARAMETER Nodename
        (Body) nodeName
    .PARAMETER Backupstoragevolume
        (Body) backupStorageVolume
    .PARAMETER Clusteruuid
        (Body) clusterUuid
    .PARAMETER Availablebackups
        (Body) availableBackups
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][hashtable]$Ipv4,
        [Parameter()][hashtable]$Ipv6,
        [Parameter()][string]$Nodename,
        [Parameter()][hashtable]$Backupstoragevolume,
        [Parameter()][string]$Clusteruuid,
        [Parameter()][object[]]$Availablebackups
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Ipv4")) { $body["ipv4"] = $Ipv4 }
        if ($PSBoundParameters.ContainsKey("Ipv6")) { $body["ipv6"] = $Ipv6 }
        if ($PSBoundParameters.ContainsKey("Nodename")) { $body["nodeName"] = $Nodename }
        if ($PSBoundParameters.ContainsKey("Backupstoragevolume")) { $body["backupStorageVolume"] = $Backupstoragevolume }
        if ($PSBoundParameters.ContainsKey("Clusteruuid")) { $body["clusterUuid"] = $Clusteruuid }
        if ($PSBoundParameters.ContainsKey("Availablebackups")) { $body["availableBackups"] = $Availablebackups }

        Invoke-HsRequest -Method PUT -Endpoint "/backup/${Identifier}" -Body $body
}

function Remove-HsBackup {
    <#
    .SYNOPSIS
        Delete backup schedule
    .DESCRIPTION
        DELETE /backup/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/backup/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: base-storage-volumes
# ---------------------------------------------------------------------------

function Get-HsStorageVolume {
    <#
    .SYNOPSIS
        Get all volumes (File and Object)
    .DESCRIPTION
        GET /base-storage-volumes
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/base-storage-volumes" -QueryParams $qp
}

function Get-HsStorageVolume2 {
    <#
    .SYNOPSIS
        Get a volume by ID
    .DESCRIPTION
        GET /base-storage-volumes/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/base-storage-volumes/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: cntl
# ---------------------------------------------------------------------------

function Get-HsCntl {
    <#
    .SYNOPSIS
        Show an overview of the system
    .DESCRIPTION
        Show an overview of the system
    .NOTES
    CLI equivalent: system-view
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Viewtype,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "viewType" = $Viewtype
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/cntl" -QueryParams $qp
}

function Invoke-HsCntlAcceptEula {
    <#
    .SYNOPSIS
        Accept the EULA at https://hammerspace.com/company/EULA/
    .DESCRIPTION
        POST /cntl/accept-eula
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method POST -Endpoint "/cntl/accept-eula"
}

function Invoke-HsCntlShutdown {
    <#
    .SYNOPSIS
        Use this command to perform a clean system shutdown of the Anvil system that recalls all layouts
    .DESCRIPTION
        Use this command to perform a clean system shutdown of the Anvil system that recalls all layouts
    .NOTES
    CLI equivalent: system-shutdown
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Poweroff,
        [Parameter()][string]$Reboot,
        [Parameter()][string]$Reason
    )

        $qp = @{
            "poweroff" = $Poweroff
            "reboot" = $Reboot
            "reason" = $Reason
        }

        Invoke-HsRequest -Method POST -Endpoint "/cntl/shutdown" -QueryParams $qp
}

function Get-HsCntl2 {
    <#
    .SYNOPSIS
        Get cluster info
    .DESCRIPTION
        GET /cntl/state
    .PARAMETER Withunclearedeventseverity
        (Query) withUnclearedEventSeverity
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Withunclearedeventseverity
    )

        $qp = @{
            "withUnclearedEventSeverity" = $Withunclearedeventseverity
        }

        Invoke-HsRequest -Method GET -Endpoint "/cntl/state" -QueryParams $qp
}

function Get-HsCntl3 {
    <#
    .SYNOPSIS
        Get cluster info
    .DESCRIPTION
        GET /cntl/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Viewtype
        (Query) viewType
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Viewtype
    )

        $qp = @{
            "viewType" = $Viewtype
        }

        Invoke-HsRequest -Method GET -Endpoint "/cntl/${Identifier}" -QueryParams $qp
}

function Set-HsCntl {
    <#
    .SYNOPSIS
        Update cluster configuration
    .DESCRIPTION
        Update cluster configuration
    .NOTES
    CLI equivalent: cluster-config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/cntl/${Identifier}" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: data-analytics
# ---------------------------------------------------------------------------

function Get-HsDataAnalytic {
    <#
    .SYNOPSIS
        Query data-analytics
    .DESCRIPTION
        GET /data-analytics
    .PARAMETER Start
        (Query) start
    .PARAMETER End
        (Query) end
    .PARAMETER Path
        (Query) path
    .PARAMETER Field
        (Query) field
    .PARAMETER Func
        (Query) func
    .PARAMETER Groupby
        (Query) groupBy
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Start,
        [Parameter()][string]$End,
        [Parameter()][string]$Path,
        [Parameter()][string]$Field,
        [Parameter()][string]$Func,
        [Parameter()][string]$Groupby
    )

        $qp = @{
            "start" = $Start
            "end" = $End
            "path" = $Path
            "field" = $Field
            "func" = $Func
            "groupBy" = $Groupby
        }

        Invoke-HsRequest -Method GET -Endpoint "/data-analytics" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: data-copy-to-object
# ---------------------------------------------------------------------------

function Start-HsDataCopyToObject {
    <#
    .SYNOPSIS
        Start a data copy to object task
    .DESCRIPTION
        POST /data-copy-to-object
    .PARAMETER Bucket
        (Query) bucket
    .PARAMETER Share
        (Query) share
    .PARAMETER Sourcepath
        (Query) sourcePath
    .PARAMETER Destpath
        (Query) destPath
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Hwcomponentstate
        (Body) hwComponentState
    .PARAMETER Vpd
        (Body) vpd
    .PARAMETER Hwcomponents
        (Body) hwComponents
    .PARAMETER Systemservices
        (Body) systemServices
    .PARAMETER Platformservices
        (Body) platformServices
    .PARAMETER Nodestate
        (Body) nodeState
    .PARAMETER Nodetype
        (Body) nodeType
    .PARAMETER Nodemode
        (Body) nodeMode
    .PARAMETER Nodemodereason
        (Body) nodeModeReason
    .PARAMETER Mgmtipaddress
        (Body) mgmtIpAddress
    .PARAMETER Mgmtnodecredentials
        (Body) mgmtNodeCredentials
    .PARAMETER Endpoint
        (Body) endpoint
    .PARAMETER Trustcertificate
        (Body) trustCertificate
    .PARAMETER Usevirtualhostnaming
        (Body) useVirtualHostNaming
    .PARAMETER S3signingtype
        (Body) s3SigningType
    .PARAMETER Projectname
        (Body) projectName
    .PARAMETER Proxyinfo
        (Body) proxyInfo
    .PARAMETER Physicallocation
        (Body) physicalLocation
    .PARAMETER Swversion
        (Body) swVersion
    .PARAMETER Applicableversions
        (Body) applicableVersions
    .PARAMETER Orchestrationsystemtype
        (Body) orchestrationSystemType
    .PARAMETER Gateway
        (Body) gateway
    .PARAMETER Boottime
        (Body) bootTime
    .PARAMETER Conditions
        (Body) conditions
    .PARAMETER Driverselector
        (Body) driverSelector
    .PARAMETER Productnodetype
        (Body) productNodeType
    .PARAMETER Managedcertificates
        (Body) managedCertificates
    .PARAMETER Blockdeviceinfo
        (Body) blockDeviceInfo
    .PARAMETER Nvmeofhostnqn
        (Body) nvmeOfHostNqn
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Bucket,
        [Parameter()][string]$Share,
        [Parameter()][string]$Sourcepath,
        [Parameter()][string]$Destpath,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [ValidateSet('UNKNOWN', 'OK', 'WARN', 'CRITICAL', 'FAILED')]
        [Parameter()][string]$Hwcomponentstate,
        [Parameter()][hashtable]$Vpd,
        [Parameter()][object[]]$Hwcomponents,
        [Parameter()][object[]]$Systemservices,
        [Parameter()][object[]]$Platformservices,
        [ValidateSet('UNAUTHENTICATED', 'AUTHENTICATED', 'FAILED_AUTHENTICATION', 'FAILED_SETUP', 'MANAGED', 'FAILED_DISCOVERY', 'MOUNTED', 'FAILED_ACCESS', 'CONFIGURED')]
        [Parameter()][string]$Nodestate,
        [ValidateSet('PD', 'NETAPP_CMODE', 'NETAPP_7MODE', 'NETAPP_CLOUD', 'EMC_ISILON', 'EMC_VNX', 'EMC_UNITY', 'GOOGLE_CLOUD_FILESTORE', 'QUMULO', 'RCLONE', 'HNAS', 'ROZOFS', 'ROZOFS_HS', 'SOFTNAS_CLOUD', 'WINDOWS_FILE_SERVER', 'DELL_ENAS', 'PURE_FB', 'VAST', 'WEKA', 'NETAPP_FSX', 'AMAZON_S3', 'ACTIVE_SCALE_S3', 'IBM_S3', 'CLOUDIAN_S3', 'ECS_S3', 'GENERIC_S3', 'GOOGLE_S3', 'SCALITY_S3', 'STORAGE_GRID_S3', 'SWIFT', 'AZURE', 'GOOGLE_CLOUD', 'HCP_S3', 'ATMOS', 'WASABI_S3', 'NETAPP_S3', 'MCAFEE_AV', 'CLAM_AV', 'SNOWFLAKE', 'INTERNAL_S3', 'PURE_FB_S3', 'SEAGATE_LYVE_S3', 'CARINGO_SWARM_S3', 'ISILON_S3', 'BACKBLAZE_S3', 'HAMMERSPACE_S3', 'STORJ_S3', 'OTHER', 'MOVER_EXT')]
        [Parameter()][string]$Nodetype,
        [ValidateSet('ONLINE', 'OFFLINE', 'MAINTENANCE', 'DISABLED', 'UPDATE')]
        [Parameter()][string]$Nodemode,
        [Parameter()][string]$Nodemodereason,
        [Parameter()][hashtable]$Mgmtipaddress,
        [Parameter()][hashtable]$Mgmtnodecredentials,
        [Parameter()][string]$Endpoint,
        [Parameter()][switch]$Trustcertificate,
        [Parameter()][switch]$Usevirtualhostnaming,
        [ValidateSet('S3_DEFAULT_SIGNING', 'S3_V4_SIGNING')]
        [Parameter()][string]$S3signingtype,
        [Parameter()][string]$Projectname,
        [Parameter()][hashtable]$Proxyinfo,
        [Parameter()][hashtable]$Physicallocation,
        [Parameter()][hashtable]$Swversion,
        [Parameter()][object[]]$Applicableversions,
        [ValidateSet('NONE', 'OBJECT', 'FILE', 'ANTIVIRUS')]
        [Parameter()][string]$Orchestrationsystemtype,
        [Parameter()][hashtable]$Gateway,
        [Parameter()][int]$Boottime,
        [Parameter()][string]$Conditions,
        [Parameter()][string]$Driverselector,
        [ValidateSet('ANVIL', 'DSX', 'MDSI_CONTAINER')]
        [Parameter()][string]$Productnodetype,
        [Parameter()][object[]]$Managedcertificates,
        [Parameter()][string]$Blockdeviceinfo,
        [Parameter()][string]$Nvmeofhostnqn
    )

        $qp = @{
            "bucket" = $Bucket
            "share" = $Share
            "sourcePath" = $Sourcepath
            "destPath" = $Destpath
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Hwcomponentstate")) { $body["hwComponentState"] = $Hwcomponentstate }
        if ($PSBoundParameters.ContainsKey("Vpd")) { $body["vpd"] = $Vpd }
        if ($PSBoundParameters.ContainsKey("Hwcomponents")) { $body["hwComponents"] = $Hwcomponents }
        if ($PSBoundParameters.ContainsKey("Systemservices")) { $body["systemServices"] = $Systemservices }
        if ($PSBoundParameters.ContainsKey("Platformservices")) { $body["platformServices"] = $Platformservices }
        if ($PSBoundParameters.ContainsKey("Nodestate")) { $body["nodeState"] = $Nodestate }
        if ($PSBoundParameters.ContainsKey("Nodetype")) { $body["nodeType"] = $Nodetype }
        if ($PSBoundParameters.ContainsKey("Nodemode")) { $body["nodeMode"] = $Nodemode }
        if ($PSBoundParameters.ContainsKey("Nodemodereason")) { $body["nodeModeReason"] = $Nodemodereason }
        if ($PSBoundParameters.ContainsKey("Mgmtipaddress")) { $body["mgmtIpAddress"] = $Mgmtipaddress }
        if ($PSBoundParameters.ContainsKey("Mgmtnodecredentials")) { $body["mgmtNodeCredentials"] = $Mgmtnodecredentials }
        if ($PSBoundParameters.ContainsKey("Endpoint")) { $body["endpoint"] = $Endpoint }
        $body["trustCertificate"] = $Trustcertificate.IsPresent
        $body["useVirtualHostNaming"] = $Usevirtualhostnaming.IsPresent
        if ($PSBoundParameters.ContainsKey("S3signingtype")) { $body["s3SigningType"] = $S3signingtype }
        if ($PSBoundParameters.ContainsKey("Projectname")) { $body["projectName"] = $Projectname }
        if ($PSBoundParameters.ContainsKey("Proxyinfo")) { $body["proxyInfo"] = $Proxyinfo }
        if ($PSBoundParameters.ContainsKey("Physicallocation")) { $body["physicalLocation"] = $Physicallocation }
        if ($PSBoundParameters.ContainsKey("Swversion")) { $body["swVersion"] = $Swversion }
        if ($PSBoundParameters.ContainsKey("Applicableversions")) { $body["applicableVersions"] = $Applicableversions }
        if ($PSBoundParameters.ContainsKey("Orchestrationsystemtype")) { $body["orchestrationSystemType"] = $Orchestrationsystemtype }
        if ($PSBoundParameters.ContainsKey("Gateway")) { $body["gateway"] = $Gateway }
        if ($PSBoundParameters.ContainsKey("Boottime")) { $body["bootTime"] = $Boottime }
        if ($PSBoundParameters.ContainsKey("Conditions")) { $body["conditions"] = $Conditions }
        if ($PSBoundParameters.ContainsKey("Driverselector")) { $body["driverSelector"] = $Driverselector }
        if ($PSBoundParameters.ContainsKey("Productnodetype")) { $body["productNodeType"] = $Productnodetype }
        if ($PSBoundParameters.ContainsKey("Managedcertificates")) { $body["managedCertificates"] = $Managedcertificates }
        if ($PSBoundParameters.ContainsKey("Blockdeviceinfo")) { $body["blockDeviceInfo"] = $Blockdeviceinfo }
        if ($PSBoundParameters.ContainsKey("Nvmeofhostnqn")) { $body["nvmeOfHostNqn"] = $Nvmeofhostnqn }

        Invoke-HsRequest -Method POST -Endpoint "/data-copy-to-object" -QueryParams $qp -Body $body
}

function Get-HsDataCopyToObjectListBucket {
    <#
    .SYNOPSIS
        Return a listing of buckets from the specified object storage
    .DESCRIPTION
        POST /data-copy-to-object/list-buckets
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Hwcomponentstate
        (Body) hwComponentState
    .PARAMETER Vpd
        (Body) vpd
    .PARAMETER Hwcomponents
        (Body) hwComponents
    .PARAMETER Systemservices
        (Body) systemServices
    .PARAMETER Platformservices
        (Body) platformServices
    .PARAMETER Nodestate
        (Body) nodeState
    .PARAMETER Nodetype
        (Body) nodeType
    .PARAMETER Nodemode
        (Body) nodeMode
    .PARAMETER Nodemodereason
        (Body) nodeModeReason
    .PARAMETER Mgmtipaddress
        (Body) mgmtIpAddress
    .PARAMETER Mgmtnodecredentials
        (Body) mgmtNodeCredentials
    .PARAMETER Endpoint
        (Body) endpoint
    .PARAMETER Trustcertificate
        (Body) trustCertificate
    .PARAMETER Usevirtualhostnaming
        (Body) useVirtualHostNaming
    .PARAMETER S3signingtype
        (Body) s3SigningType
    .PARAMETER Projectname
        (Body) projectName
    .PARAMETER Proxyinfo
        (Body) proxyInfo
    .PARAMETER Physicallocation
        (Body) physicalLocation
    .PARAMETER Swversion
        (Body) swVersion
    .PARAMETER Applicableversions
        (Body) applicableVersions
    .PARAMETER Orchestrationsystemtype
        (Body) orchestrationSystemType
    .PARAMETER Gateway
        (Body) gateway
    .PARAMETER Boottime
        (Body) bootTime
    .PARAMETER Conditions
        (Body) conditions
    .PARAMETER Driverselector
        (Body) driverSelector
    .PARAMETER Productnodetype
        (Body) productNodeType
    .PARAMETER Managedcertificates
        (Body) managedCertificates
    .PARAMETER Blockdeviceinfo
        (Body) blockDeviceInfo
    .PARAMETER Nvmeofhostnqn
        (Body) nvmeOfHostNqn
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [ValidateSet('UNKNOWN', 'OK', 'WARN', 'CRITICAL', 'FAILED')]
        [Parameter()][string]$Hwcomponentstate,
        [Parameter()][hashtable]$Vpd,
        [Parameter()][object[]]$Hwcomponents,
        [Parameter()][object[]]$Systemservices,
        [Parameter()][object[]]$Platformservices,
        [ValidateSet('UNAUTHENTICATED', 'AUTHENTICATED', 'FAILED_AUTHENTICATION', 'FAILED_SETUP', 'MANAGED', 'FAILED_DISCOVERY', 'MOUNTED', 'FAILED_ACCESS', 'CONFIGURED')]
        [Parameter()][string]$Nodestate,
        [ValidateSet('PD', 'NETAPP_CMODE', 'NETAPP_7MODE', 'NETAPP_CLOUD', 'EMC_ISILON', 'EMC_VNX', 'EMC_UNITY', 'GOOGLE_CLOUD_FILESTORE', 'QUMULO', 'RCLONE', 'HNAS', 'ROZOFS', 'ROZOFS_HS', 'SOFTNAS_CLOUD', 'WINDOWS_FILE_SERVER', 'DELL_ENAS', 'PURE_FB', 'VAST', 'WEKA', 'NETAPP_FSX', 'AMAZON_S3', 'ACTIVE_SCALE_S3', 'IBM_S3', 'CLOUDIAN_S3', 'ECS_S3', 'GENERIC_S3', 'GOOGLE_S3', 'SCALITY_S3', 'STORAGE_GRID_S3', 'SWIFT', 'AZURE', 'GOOGLE_CLOUD', 'HCP_S3', 'ATMOS', 'WASABI_S3', 'NETAPP_S3', 'MCAFEE_AV', 'CLAM_AV', 'SNOWFLAKE', 'INTERNAL_S3', 'PURE_FB_S3', 'SEAGATE_LYVE_S3', 'CARINGO_SWARM_S3', 'ISILON_S3', 'BACKBLAZE_S3', 'HAMMERSPACE_S3', 'STORJ_S3', 'OTHER', 'MOVER_EXT')]
        [Parameter()][string]$Nodetype,
        [ValidateSet('ONLINE', 'OFFLINE', 'MAINTENANCE', 'DISABLED', 'UPDATE')]
        [Parameter()][string]$Nodemode,
        [Parameter()][string]$Nodemodereason,
        [Parameter()][hashtable]$Mgmtipaddress,
        [Parameter()][hashtable]$Mgmtnodecredentials,
        [Parameter()][string]$Endpoint,
        [Parameter()][switch]$Trustcertificate,
        [Parameter()][switch]$Usevirtualhostnaming,
        [ValidateSet('S3_DEFAULT_SIGNING', 'S3_V4_SIGNING')]
        [Parameter()][string]$S3signingtype,
        [Parameter()][string]$Projectname,
        [Parameter()][hashtable]$Proxyinfo,
        [Parameter()][hashtable]$Physicallocation,
        [Parameter()][hashtable]$Swversion,
        [Parameter()][object[]]$Applicableversions,
        [ValidateSet('NONE', 'OBJECT', 'FILE', 'ANTIVIRUS')]
        [Parameter()][string]$Orchestrationsystemtype,
        [Parameter()][hashtable]$Gateway,
        [Parameter()][int]$Boottime,
        [Parameter()][string]$Conditions,
        [Parameter()][string]$Driverselector,
        [ValidateSet('ANVIL', 'DSX', 'MDSI_CONTAINER')]
        [Parameter()][string]$Productnodetype,
        [Parameter()][object[]]$Managedcertificates,
        [Parameter()][string]$Blockdeviceinfo,
        [Parameter()][string]$Nvmeofhostnqn
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Hwcomponentstate")) { $body["hwComponentState"] = $Hwcomponentstate }
        if ($PSBoundParameters.ContainsKey("Vpd")) { $body["vpd"] = $Vpd }
        if ($PSBoundParameters.ContainsKey("Hwcomponents")) { $body["hwComponents"] = $Hwcomponents }
        if ($PSBoundParameters.ContainsKey("Systemservices")) { $body["systemServices"] = $Systemservices }
        if ($PSBoundParameters.ContainsKey("Platformservices")) { $body["platformServices"] = $Platformservices }
        if ($PSBoundParameters.ContainsKey("Nodestate")) { $body["nodeState"] = $Nodestate }
        if ($PSBoundParameters.ContainsKey("Nodetype")) { $body["nodeType"] = $Nodetype }
        if ($PSBoundParameters.ContainsKey("Nodemode")) { $body["nodeMode"] = $Nodemode }
        if ($PSBoundParameters.ContainsKey("Nodemodereason")) { $body["nodeModeReason"] = $Nodemodereason }
        if ($PSBoundParameters.ContainsKey("Mgmtipaddress")) { $body["mgmtIpAddress"] = $Mgmtipaddress }
        if ($PSBoundParameters.ContainsKey("Mgmtnodecredentials")) { $body["mgmtNodeCredentials"] = $Mgmtnodecredentials }
        if ($PSBoundParameters.ContainsKey("Endpoint")) { $body["endpoint"] = $Endpoint }
        $body["trustCertificate"] = $Trustcertificate.IsPresent
        $body["useVirtualHostNaming"] = $Usevirtualhostnaming.IsPresent
        if ($PSBoundParameters.ContainsKey("S3signingtype")) { $body["s3SigningType"] = $S3signingtype }
        if ($PSBoundParameters.ContainsKey("Projectname")) { $body["projectName"] = $Projectname }
        if ($PSBoundParameters.ContainsKey("Proxyinfo")) { $body["proxyInfo"] = $Proxyinfo }
        if ($PSBoundParameters.ContainsKey("Physicallocation")) { $body["physicalLocation"] = $Physicallocation }
        if ($PSBoundParameters.ContainsKey("Swversion")) { $body["swVersion"] = $Swversion }
        if ($PSBoundParameters.ContainsKey("Applicableversions")) { $body["applicableVersions"] = $Applicableversions }
        if ($PSBoundParameters.ContainsKey("Orchestrationsystemtype")) { $body["orchestrationSystemType"] = $Orchestrationsystemtype }
        if ($PSBoundParameters.ContainsKey("Gateway")) { $body["gateway"] = $Gateway }
        if ($PSBoundParameters.ContainsKey("Boottime")) { $body["bootTime"] = $Boottime }
        if ($PSBoundParameters.ContainsKey("Conditions")) { $body["conditions"] = $Conditions }
        if ($PSBoundParameters.ContainsKey("Driverselector")) { $body["driverSelector"] = $Driverselector }
        if ($PSBoundParameters.ContainsKey("Productnodetype")) { $body["productNodeType"] = $Productnodetype }
        if ($PSBoundParameters.ContainsKey("Managedcertificates")) { $body["managedCertificates"] = $Managedcertificates }
        if ($PSBoundParameters.ContainsKey("Blockdeviceinfo")) { $body["blockDeviceInfo"] = $Blockdeviceinfo }
        if ($PSBoundParameters.ContainsKey("Nvmeofhostnqn")) { $body["nvmeOfHostNqn"] = $Nvmeofhostnqn }

        Invoke-HsRequest -Method POST -Endpoint "/data-copy-to-object/list-buckets" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: data-portals
# ---------------------------------------------------------------------------

function Get-HsDataPortal {
    <#
    .SYNOPSIS
        List the processor services
    .DESCRIPTION
        List the processor services
    .NOTES
    CLI equivalent: processor-list
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/data-portals"
}

function Get-HsDataPortal2 {
    <#
    .SYNOPSIS
        Get a Data Portal
    .DESCRIPTION
        GET /data-portals/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/data-portals/${Identifier}"
}

function Set-HsDataPortal {
    <#
    .SYNOPSIS
        Add a processor service
    .DESCRIPTION
        Add a processor service. Update a processor service. Remove a processor service. Update data portal
    .NOTES
    CLI equivalent: processor-add, processor-update, processor-remove, dp-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/data-portals/${Identifier}" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: disk-drives
# ---------------------------------------------------------------------------

function Get-HsDiskDrive {
    <#
    .SYNOPSIS
        List disk drives
    .DESCRIPTION
        List disk drives
    .NOTES
    CLI equivalent: drive-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/disk-drives" -QueryParams $qp
}

function Get-HsDiskDrive2 {
    <#
    .SYNOPSIS
        Get disk drive by ID
    .DESCRIPTION
        GET /disk-drives/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/disk-drives/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: dnss
# ---------------------------------------------------------------------------

function Get-HsDns {
    <#
    .SYNOPSIS
        Get DNS
    .DESCRIPTION
        GET /dnss
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/dnss" -QueryParams $qp
}

function Get-HsDns2 {
    <#
    .SYNOPSIS
        Get DNS
    .DESCRIPTION
        GET /dnss/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/dnss/${Identifier}"
}

function Set-HsDns {
    <#
    .SYNOPSIS
        Configure DNS
    .DESCRIPTION
        Configure DNS
    .NOTES
    CLI equivalent: dns-config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Force,
        [Parameter()][string]$Comment,
        [Parameter()][hashtable]$Ipv4,
        [Parameter()][hashtable]$Ipv6,
        [Parameter()][string]$Nodename,
        [Parameter()][string]$Domainname,
        [Parameter()][object[]]$Servers
    )

        $qp = @{
            "force" = $Force
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Ipv4")) { $body["ipv4"] = $Ipv4 }
        if ($PSBoundParameters.ContainsKey("Ipv6")) { $body["ipv6"] = $Ipv6 }
        if ($PSBoundParameters.ContainsKey("Nodename")) { $body["nodeName"] = $Nodename }
        if ($PSBoundParameters.ContainsKey("Domainname")) { $body["domainName"] = $Domainname }
        if ($PSBoundParameters.ContainsKey("Servers")) { $body["servers"] = $Servers }

        Invoke-HsRequest -Method PUT -Endpoint "/dnss/${Identifier}" -QueryParams $qp -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: domain-idmaps
# ---------------------------------------------------------------------------

function Get-HsDomainIdmap {
    <#
    .SYNOPSIS
        List domain ID mapping rules
    .DESCRIPTION
        List domain ID mapping rules
    .NOTES
    CLI equivalent: domain-idmap-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/domain-idmaps" -QueryParams $qp
}

function New-HsDomainIdmap {
    <#
    .SYNOPSIS
        Create domain ID mapping rule
    .DESCRIPTION
        Create domain ID mapping rule
    .NOTES
    CLI equivalent: domain-idmap-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Mapfrom,
        [Parameter()][switch]$Inheritfrom,
        [Parameter()][string]$Mapto,
        [Parameter()][switch]$Inheritto,
        [Parameter()][string]$Attribute,
        [Parameter()][switch]$Bidirectional,
        [Parameter()][int]$Priority
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Mapfrom")) { $body["mapFrom"] = $Mapfrom }
        $body["inheritFrom"] = $Inheritfrom.IsPresent
        if ($PSBoundParameters.ContainsKey("Mapto")) { $body["mapTo"] = $Mapto }
        $body["inheritTo"] = $Inheritto.IsPresent
        if ($PSBoundParameters.ContainsKey("Attribute")) { $body["attribute"] = $Attribute }
        $body["bidirectional"] = $Bidirectional.IsPresent
        if ($PSBoundParameters.ContainsKey("Priority")) { $body["priority"] = $Priority }

        Invoke-HsRequest -Method POST -Endpoint "/domain-idmaps" -Body $body
}

function Invoke-HsDomainIdmapReload {
    <#
    .SYNOPSIS
        Reload domain ID mapping rules
    .DESCRIPTION
        Reload domain ID mapping rules
    .NOTES
    CLI equivalent: domain-idmap-reload
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method POST -Endpoint "/domain-idmaps/reload"
}

function Get-HsDomainIdmap2 {
    <#
    .SYNOPSIS
        Get LDAP ID map by ID
    .DESCRIPTION
        GET /domain-idmaps/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/domain-idmaps/${Identifier}"
}

function Set-HsDomainIdmap {
    <#
    .SYNOPSIS
        Update LDAP ID map
    .DESCRIPTION
        PUT /domain-idmaps/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Mapfrom
        (Body) mapFrom
    .PARAMETER Inheritfrom
        (Body) inheritFrom
    .PARAMETER Mapto
        (Body) mapTo
    .PARAMETER Inheritto
        (Body) inheritTo
    .PARAMETER Attribute
        (Body) attribute
    .PARAMETER Bidirectional
        (Body) bidirectional
    .PARAMETER Priority
        (Body) priority
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Mapfrom,
        [Parameter()][switch]$Inheritfrom,
        [Parameter()][string]$Mapto,
        [Parameter()][switch]$Inheritto,
        [Parameter()][string]$Attribute,
        [Parameter()][switch]$Bidirectional,
        [Parameter()][int]$Priority
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Mapfrom")) { $body["mapFrom"] = $Mapfrom }
        $body["inheritFrom"] = $Inheritfrom.IsPresent
        if ($PSBoundParameters.ContainsKey("Mapto")) { $body["mapTo"] = $Mapto }
        $body["inheritTo"] = $Inheritto.IsPresent
        if ($PSBoundParameters.ContainsKey("Attribute")) { $body["attribute"] = $Attribute }
        $body["bidirectional"] = $Bidirectional.IsPresent
        if ($PSBoundParameters.ContainsKey("Priority")) { $body["priority"] = $Priority }

        Invoke-HsRequest -Method PUT -Endpoint "/domain-idmaps/${Identifier}" -Body $body
}

function Remove-HsDomainIdmap {
    <#
    .SYNOPSIS
        Delete domain ID mapping rule
    .DESCRIPTION
        Delete domain ID mapping rule
    .NOTES
    CLI equivalent: domain-idmap-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/domain-idmaps/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: events
# ---------------------------------------------------------------------------

function Get-HsEvent {
    <#
    .SYNOPSIS
        List events generated by the system
    .DESCRIPTION
        List events generated by the system
    .NOTES
    CLI equivalent: event-list
    WARNING: Possible values: DEBUG | INFORMATIONAL | NOTICE | WARNING | ERROR |
    WARNING: DISK_USAGE_LIMIT_EXCEEDED | DISK_USAGE_LIMIT_WARNING | DNS_ISSUE |
    WARNING: SHARE_QUOTA_EXCEEDED | SHARE_QUOTA_WARNING | SHARE_RESTORED |
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/events" -QueryParams $qp
}

function Clear-HsEventClear {
    <#
    .SYNOPSIS
        Clears events
    .DESCRIPTION
        PUT /events/clear
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method PUT -Endpoint "/events/clear"
}

function Get-HsEvent2 {
    <#
    .SYNOPSIS
        Get event counts grouped by given field
    .DESCRIPTION
        GET /events/summary
    .PARAMETER Groupby
        (Query) groupBy
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Groupby,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "groupBy" = $Groupby
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/events/summary" -QueryParams $qp
}

function Get-HsEvent3 {
    <#
    .SYNOPSIS
        Get an event
    .DESCRIPTION
        GET /events/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/events/${Identifier}"
}

function Set-HsEvent {
    <#
    .SYNOPSIS
        Clear events generated by the system
    .DESCRIPTION
        Clear events generated by the system
    .NOTES
    CLI equivalent: event-update
    WARNING: DISK_USAGE_LIMIT_EXCEEDED | DISK_USAGE_LIMIT_WARNING | DNS_ISSUE |
    WARNING: SHARE_QUOTA_EXCEEDED | SHARE_QUOTA_WARNING | SHARE_RESTORED |
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][int]$Sequence,
        [ValidateSet('NONE', 'CREATED', 'ADDED', 'CANCELLED', 'UPDATED', 'DELETED', 'REMOVED', 'CREATE_FAILED', 'ADD_FAILED', 'UPDATE_FAILED', 'DELETE_FAILED', 'REMOVE_FAILED', 'COMPONENT_MISSING', 'SOFTWARE_VERSION_CHANGED', 'SOFTWARE_UPDATE_STARTED', 'SOFTWARE_UPDATE_SUCCESS', 'SOFTWARE_UPDATE_FAILED', 'ACTUAL_ALLOCATED_CAPACITY_EXCEEDED', 'ALLOCATED_CAPACITY_EXCEEDED', 'ALLOCATED_CAPACITY_APPROACHING_LIMIT', 'LICENSE_STATE_CHANGED', 'LICENSE_ACTIVATED', 'LICENSE_ACTIVATION_FAILED', 'EVAL_ABOUT_TO_EXPIRE', 'EVAL_EXPIRED', 'LICENSING_MISCONFIGURED', 'LICENSE_ABOUT_TO_EXPIRE', 'LICENSE_EXPIRED', 'LICENSE_IN_GRACE_ABOUT_TO_EXPIRE', 'BORROWING_LICENSE_EXPIRED', 'BORROWING_LICENSE_ABOUT_TO_EXPIRE', 'OVER_CAPACITY_GRACE_ABOUT_TO_EXPIRE', 'OVER_CAPACITY_LICENSE_VIOLATION', 'EXPIRED_LICENSE_IN_GRACE', 'LICENSE_ABOUT_TO_ENTER_GRACE', 'USER_PASSWORD_CHANGED', 'MGMT_STARTED', 'MGMT_STARTED_FROM_RESTORE', 'MGMT_GENERIC_EVENT', 'NODE_MODE_ISSUE', 'CLUSTER_FAILOVER', 'CLUSTER_SPLIT_BRAIN', 'CLUSTER_REPLICATION_EVENT', 'DD_CLUSTER_PLANNED_SHUTDOWN', 'DD_CLUSTER_PLANNED_SHUTDOWN_FAILED', 'NETWORK_LDAP_UNREACHABLE', 'NETWORK_NTP_UNREACHABLE', 'VOLUME_STATE_CHANGED', 'VOLUME_DECOMMISSION_EVENT', 'VOLUME_ASSIMILATION_EVENT', 'VOLUME_CONFIG_TEST_FAILED', 'VOLUME_CONFIG_TEST_ALL_FAILED', 'VOLUME_CLONE_TEST_FAILED', 'HW_NIC_LINK_EVENT', 'HW_DRIVE_FAILED', 'HW_RAID_EVENT', 'HW_FAN_FAILED', 'HW_PSU_FAILED', 'HW_FRU_EVENT', 'VASA_VAAI_PROVIDER_EVENT', 'PORTAL_EXPORT_FAILED', 'PORTAL_UNEXPORT_FAILED', 'SUPPORT_CALL_HOME_EVENT', 'SHARE_QUOTA_WARNING', 'SHARE_QUOTA_EXCEEDED', 'SHARE_RESTORED', 'SHARE_RESTORE_FAILED', 'SHARE_SNAPSHOT_CREATED', 'SHARE_SNAPSHOT_CREATE_FAILED', 'SHARE_SNAPSHOT_DELETED', 'SHARE_SNAPSHOT_DELETE_FAILED', 'SHARE_CLONED', 'SHARE_CLONE_FAILED', 'CLUSTER_MISCONFIGURED', 'READ_LATENCY_THRESHOLD_CROSSED', 'WRITE_LATENCY_THRESHOLD_CROSSED', 'ASSIMILATION_SUCCESS', 'ASSIMILATION_FAILED', 'ASSIMILATION_STOPPED', 'ASSIMILATION_CANCELLED', 'SHARE_PRUNING', 'SHARE_PRUNING_BLOCKED', 'VOLUME_EVICTION_FAILED', 'INVALID_COMB_STRUCTURE', 'NO_REGISTERED_MOVER', 'NO_REGISTERED_STORAGE_VOLUME', 'PDDM_EXITED', 'PDDM_KILLED_DI', 'MODELER_SHARE_SWEEP_COMPLETED', 'PDDM_RESTART', 'COLLECTIONS_ENTER', 'COLLECTIONS_LEAVE', 'DISK_USAGE_LIMIT_WARNING', 'DISK_USAGE_LIMIT_EXCEEDED', 'SALT_NOT_FUNCTIONAL', 'MISSING_DATA_MOVER', 'MISSING_CLOUD_MOVER', 'MISSING_STORAGE_VOLUME', 'BACKUP_FAILED', 'BACKUP_COMPLETED', 'BACKUP_CREATION_FAILED', 'DATA_COPY_TO_OBJECT_SUCCESS', 'DATA_COPY_TO_OBJECT_FAILED', 'BACKUP_NOT_SCHEDULED', 'CTDB_NODE_FAILURE', 'CTDB_NOT_RESPONDING', 'CTDB_IN_RECOVERY', 'KMS_OPERATION_CHECK_FAILED', 'GFS_PARTICIPANT_ADDED', 'GFS_PARTICIPANT_ADD_FAILED', 'GFS_PARTICIPANT_REMOVED', 'GFS_PARTICIPANT_REMOVE_FAILED', 'REPLICATION_PORT_CHECK_FAILED', 'GFS_PARTICIPANT_OPER_STATE_CHANGED', 'DATA_REPLICATION_ISSUE', 'METADATA_REPLICATION_ISSUE', 'MISSING_SHARED_OBJECT_STORAGE_VOLUME', 'CAPACITY_HEARTBEAT_DISABLED', 'REPLICATION_LATENCY_THRESHOLD_EXCEEDED', 'MOVER_CONNECTED', 'MOVER_UNKNOWN', 'MOVER_BAD_IP', 'MOVER_DROPPED', 'MOVER_AT_CAPACITY', 'CAPACITY_THRESHOLD_PASSED', 'SHARE_EVENTS_PROCESSING', 'SHARE_EVENTS_PROCESSED', 'SHARE_EVENT_PROCESSING_BLOCKED', 'FAILURE_REPORTING_LICENSED_USAGE', 'METERED_LICENSE_IN_GRACE', 'INVALID_ADDITIONAL_ADDRESS', 'KEYTAB_MISMATCH', 'AD_WITHOUT_NTP', 'NTP_NOT_SYNCHRONIZED', 'AD_DC_OUT_OF_TIME_SYNC', 'AD_COMPUTER_ISSUE', 'IDMAPD_SYNC_ISSUE', 'REPLICATION_WITHOUT_NTP', 'REPLICATION_CLOCK_OUT_OF_SYNC', 'AD_SERVER_ISSUE', 'SERVICE_OPER_STATE_ISSUE', 'OBJECT_VOLUME_IO_TEST_FAILED', 'OBJECT_VOLUME_IO_TEST_ALL_FAILED', 'OBJECT_VOLUME_RESERVATION_OLD', 'DNS_ISSUE', 'CLUSTER_DEGRADED', 'OBJECT_VOLUME_GC_COMPLETED', 'OBJECT_VOLUME_GC_FAILED', 'OBJECT_VOLUME_GC_CANCELLED', 'OBJECT_VOLUME_GC_BLOCKED', 'ECGROUP_ARRAY', 'ECGROUP_MOUNTPOINT', 'ECGROUP_STORAGE', 'OSV_QUORUM_IN_FLUX', 'OSV_HMDB_REPLICATION_OUT_OF_SYNC', 'OSV_HMDB_INSUFFICIENT_GC_MEMORY', 'OSV_HMDB_DEGRADED_BLOOM_FILTER_ALLOCATED', 'OSV_SITE_TO_SITE_CONN_FAILED', 'OSV_CSP_CONN_FAILED', 'PROMETHEUS_DEGRADED', 'AD_CACHE_FLUSH_SUCCESS', 'AD_CACHE_FLUSH_FAILED', 'NO_AVAILABLE_STORAGE_ON_NODE', 'QUORUM_DEVICE_CONFIGURED', 'QUORUM_DEVICE_UNCONFIGURED', 'QUORUM_DEVICE_UNHEALTHY', 'MISSING_COMB_STRUCTURE', 'COMB_MIGRATION_INCOMPLETE', 'KERBEROS_SYNC_FAILURE', 'KERBEROS_CLUSTER_UNHEALTHY', 'KERBEROS_SHARE_WITH_UNJOINED_AD', 'NFS_LAYOUT_ERROR_STALE', 'NFS_LAYOUT_ERROR_NXIO', 'NFS_LAYOUT_ERROR_IO', 'NFS_LAYOUT_ERROR_ACCESS', 'S3_MULTIPART_UPLOAD_ABORTED', 'KERBEROS_SHARE_WITH_NO_NFS_SPNS', 'AUDIT', 'SYSTEM', 'S3_SERVICE_RELOADED', 'S3_SERVICE_RELOAD_ERROR', 'INDEXING_SENT', 'NAME_SERVICE_UNHEALTHY', 'SSSD_CONFIG_SYNC_FAILED', 'KERBEROS_USER_MAPPING_NONFUNCTIONAL', 'KERBEROS_REQUIRED_NFS_SPNS_MISSING', 'NFS_TLS_CONFIGURATION_UNHEALTHY', 'PKI_CA_CREATION_FAILED', 'PKI_TRUST_SYNC_FAILED', 'PKI_NODE_CERT_CREATION_FAILED', 'PKI_NODE_CERT_SYNC_FAILED', 'PKI_NODE_CHECK_FAILED', 'METRIC_COLLECTION_DEGRADED')]
        [Parameter()][string]$Type,
        [Parameter()][hashtable]$Sourceid,
        [Parameter()][string]$Sourcename,
        [ValidateSet('DEBUG', 'INFORMATIONAL', 'NOTICE', 'WARNING', 'ERROR', 'CRITICAL', 'ALERT', 'EMERGENCY')]
        [Parameter()][string]$Severity,
        [Parameter()][object[]]$Params,
        [Parameter()][int]$Cleartime,
        [Parameter()][hashtable]$Createdbyid,
        [Parameter()][string]$Createdbyname,
        [Parameter()][switch]$Activity,
        [Parameter()][switch]$Cleared,
        [ValidateSet('USER', 'CONDITION')]
        [Parameter()][string]$Clearreason,
        [Parameter()][int]$Count
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Sequence")) { $body["sequence"] = $Sequence }
        if ($PSBoundParameters.ContainsKey("Type")) { $body["type"] = $Type }
        if ($PSBoundParameters.ContainsKey("Sourceid")) { $body["sourceId"] = $Sourceid }
        if ($PSBoundParameters.ContainsKey("Sourcename")) { $body["sourceName"] = $Sourcename }
        if ($PSBoundParameters.ContainsKey("Severity")) { $body["severity"] = $Severity }
        if ($PSBoundParameters.ContainsKey("Params")) { $body["params"] = $Params }
        if ($PSBoundParameters.ContainsKey("Cleartime")) { $body["clearTime"] = $Cleartime }
        if ($PSBoundParameters.ContainsKey("Createdbyid")) { $body["createdById"] = $Createdbyid }
        if ($PSBoundParameters.ContainsKey("Createdbyname")) { $body["createdByName"] = $Createdbyname }
        $body["activity"] = $Activity.IsPresent
        $body["cleared"] = $Cleared.IsPresent
        if ($PSBoundParameters.ContainsKey("Clearreason")) { $body["clearReason"] = $Clearreason }
        if ($PSBoundParameters.ContainsKey("Count")) { $body["count"] = $Count }

        Invoke-HsRequest -Method PUT -Endpoint "/events/${Identifier}" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: file-snapshots
# ---------------------------------------------------------------------------

function Get-HsFileSnapshot {
    <#
    .SYNOPSIS
        List file snapshots
    .DESCRIPTION
        List file snapshots. List scheduled file snapshots
    .NOTES
    CLI equivalent: file-snapshot-list, file-snapshot-schedule-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/file-snapshots" -QueryParams $qp
}

function New-HsFileSnapshot {
    <#
    .SYNOPSIS
        Create file snapshot
    .DESCRIPTION
        Create file snapshot

    .EXAMPLE
        file-snapshot-create --filename /test/VM2/*.vmdk --now
    .NOTES
    CLI equivalent: file-snapshot-create
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method POST -Endpoint "/file-snapshots" -Body $body
}

function New-HsFileSnapshotCreate {
    <#
    .SYNOPSIS
        Create file snapshot
    .DESCRIPTION
        POST /file-snapshots/create
    .PARAMETER FilenameExpression
        (Query) filename-expression
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$FilenameExpression
    )

        $qp = @{
            "filename-expression" = $FilenameExpression
        }

        Invoke-HsRequest -Method POST -Endpoint "/file-snapshots/create" -QueryParams $qp
}

function Remove-HsFileSnapshotDelete {
    <#
    .SYNOPSIS
        Delete file snapshot
    .DESCRIPTION
        POST /file-snapshots/delete
    .PARAMETER FilenameExpression
        (Query) filename-expression
    .PARAMETER DateTimeExpression
        (Query) date-time-expression
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$FilenameExpression,
        [Parameter()][string]$DateTimeExpression
    )

        $qp = @{
            "filename-expression" = $FilenameExpression
            "date-time-expression" = $DateTimeExpression
        }

        Invoke-HsRequest -Method POST -Endpoint "/file-snapshots/delete" -QueryParams $qp
}

function Get-HsFileSnapshot2 {
    <#
    .SYNOPSIS
        Get all file snapshots
    .DESCRIPTION
        GET /file-snapshots/list
    .PARAMETER FilenameExpression
        (Query) filename-expression
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$FilenameExpression
    )

        $qp = @{
            "filename-expression" = $FilenameExpression
        }

        Invoke-HsRequest -Method GET -Endpoint "/file-snapshots/list" -QueryParams $qp
}

function Invoke-HsFileSnapshotRestore {
    <#
    .SYNOPSIS
        Restore files from snapshots
    .DESCRIPTION
        Restore files from snapshots
    .NOTES
    CLI equivalent: file-snapshot-restore
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$FilenameExpression,
        [Parameter()][string]$DateTimeExpression
    )

        $qp = @{
            "filename-expression" = $FilenameExpression
            "date-time-expression" = $DateTimeExpression
        }

        Invoke-HsRequest -Method POST -Endpoint "/file-snapshots/restore" -QueryParams $qp
}

function New-HsFileSnapshot2 {
    <#
    .SYNOPSIS
        Clone file
    .DESCRIPTION
        POST /file-snapshots/{file-source}/{file-destination}
    .PARAMETER FileSource
        (Path) file-source
    .PARAMETER FileDestination
        (Path) file-destination
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FileSource,
        [Parameter(Mandatory)][string]$FileDestination
    )

        Invoke-HsRequest -Method POST -Endpoint "/file-snapshots/${FileSource}/${FileDestination}"
}

function Get-HsFileSnapshot3 {
    <#
    .SYNOPSIS
        Get file snapshot by ID
    .DESCRIPTION
        GET /file-snapshots/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/file-snapshots/${Identifier}"
}

function Set-HsFileSnapshot {
    <#
    .SYNOPSIS
        Update file snapshot schedule
    .DESCRIPTION
        Update file snapshot schedule
    .NOTES
    CLI equivalent: file-snapshot-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/file-snapshots/${Identifier}" -Body $body
}

function Remove-HsFileSnapshot {
    <#
    .SYNOPSIS
        Delete file snapshots
    .DESCRIPTION
        Delete file snapshots
    .NOTES
    CLI equivalent: file-snapshot-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/file-snapshots/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: files
# ---------------------------------------------------------------------------

function Get-HsFile {
    <#
    .SYNOPSIS
        Get file details
    .DESCRIPTION
        GET /files
    .PARAMETER Path
        (Query) path
    .PARAMETER Includereplicationdetails
        (Query) includeReplicationDetails
    .PARAMETER Getparentdirsize
        (Query) getParentDirSize
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Path,
        [Parameter()][string]$Includereplicationdetails,
        [Parameter()][string]$Getparentdirsize,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "path" = $Path
            "includeReplicationDetails" = $Includereplicationdetails
            "getParentDirSize" = $Getparentdirsize
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/files" -QueryParams $qp
}

function Get-HsFileExistDp {
    <#
    .SYNOPSIS
        Query a DP for file info (prepends '/mnt/data-portal' to provided path)
    .DESCRIPTION
        GET /files/file_exists_dp
    .PARAMETER Path
        (Query) path
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Path
    )

        $qp = @{
            "path" = $Path
        }

        Invoke-HsRequest -Method GET -Endpoint "/files/file_exists_dp" -QueryParams $qp
}

function Get-HsFileUsedCapacity {
    <#
    .SYNOPSIS
        Get used capacity
    .DESCRIPTION
        GET /files/used_capacity
    .PARAMETER Path
        (Query) path
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Path
    )

        $qp = @{
            "path" = $Path
        }

        Invoke-HsRequest -Method GET -Endpoint "/files/used_capacity" -QueryParams $qp
}

function Remove-HsFileWorm {
    <#
    .SYNOPSIS
        Perform a privileged delete on a WORM file or empty dir
    .DESCRIPTION
        DELETE /files/worm/{share-identifier}/{path}
    .PARAMETER ShareIdentifier
        (Path) share-identifier
    .PARAMETER Path
        (Path) path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShareIdentifier,
        [Parameter(Mandatory)][string]$Path
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/files/worm/${ShareIdentifier}/${Path}"
}

function Get-HsFile2 {
    <#
    .SYNOPSIS
        Get file details
    .DESCRIPTION
        GET /files/{path}
    .PARAMETER Path
        (Path) path
    .PARAMETER Pattern
        (Query) pattern
    .PARAMETER Dalil
        (Query) dalil
    .PARAMETER Itself
        (Query) itself
    .PARAMETER Includereplicationdetails
        (Query) includeReplicationDetails
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string]$Pattern,
        [Parameter()][string]$Dalil,
        [Parameter()][string]$Itself,
        [Parameter()][string]$Includereplicationdetails,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "pattern" = $Pattern
            "dalil" = $Dalil
            "itself" = $Itself
            "includeReplicationDetails" = $Includereplicationdetails
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/files/${Path}" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: gateways
# ---------------------------------------------------------------------------

function Get-HsGateway {
    <#
    .SYNOPSIS
        List gateway configuration
    .DESCRIPTION
        List gateway configuration
    .NOTES
    CLI equivalent: gateway-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/gateways" -QueryParams $qp
}

function Set-HsGateway {
    <#
    .SYNOPSIS
        Update gateway configuration
    .DESCRIPTION
        Update gateway configuration
    .NOTES
    CLI equivalent: gateway-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/gateways/${Identifier}" -Body $body
}

function Get-HsGateway2 {
    <#
    .SYNOPSIS
        Get gateway configuration by node
    .DESCRIPTION
        GET /gateways/{node}
    .PARAMETER Node
        (Path) node
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Node
    )

        Invoke-HsRequest -Method GET -Endpoint "/gateways/${Node}"
}

# ---------------------------------------------------------------------------
# SECTION: heartbeat
# ---------------------------------------------------------------------------

function Get-HsHeartbeat {
    <#
    .SYNOPSIS
        List the configured heartbeats
    .DESCRIPTION
        List the configured heartbeats
    .NOTES
    CLI equivalent: heartbeat-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/heartbeat" -QueryParams $qp
}

function Send-HsHeartbeatSend {
    <#
    .SYNOPSIS
        Sends the specified heartbeat type to support
    .DESCRIPTION
        Sends the specified heartbeat type to support
    .NOTES
    CLI equivalent: heartbeat-send
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method POST -Endpoint "/heartbeat/send/${Identifier}"
}

function Set-HsHeartbeat {
    <#
    .SYNOPSIS
        Update the heartbeat configuration
    .DESCRIPTION
        Update the heartbeat configuration
    .NOTES
    CLI equivalent: heartbeat-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [ValidateSet('PDSUPPORT', 'HEALTH', 'CAPACITY')]
        [Parameter()][string]$Payloadtype,
        [Parameter()][switch]$Enabled,
        [Parameter()][string]$Name,
        [Parameter()][int]$Startdelaysecs,
        [Parameter()][int]$Intervalsecs,
        [Parameter()][int]$Nextsendtime,
        [Parameter()][int]$Previoussendtime
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Payloadtype")) { $body["payloadType"] = $Payloadtype }
        $body["enabled"] = $Enabled.IsPresent
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Startdelaysecs")) { $body["startDelaySecs"] = $Startdelaysecs }
        if ($PSBoundParameters.ContainsKey("Intervalsecs")) { $body["intervalSecs"] = $Intervalsecs }
        if ($PSBoundParameters.ContainsKey("Nextsendtime")) { $body["nextSendTime"] = $Nextsendtime }
        if ($PSBoundParameters.ContainsKey("Previoussendtime")) { $body["previousSendTime"] = $Previoussendtime }

        Invoke-HsRequest -Method PUT -Endpoint "/heartbeat/${Identifier}" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: i18n
# ---------------------------------------------------------------------------

function Get-HsI18n {
    <#
    .SYNOPSIS
        List messages in resource bundle
    .DESCRIPTION
        GET /i18n
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/i18n"
}

function Get-HsI18n2 {
    <#
    .SYNOPSIS
        List messages in resource bundle by locale
    .DESCRIPTION
        GET /i18n/{localeName}
    .PARAMETER Localename
        (Path) localeName
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Localename
    )

        Invoke-HsRequest -Method GET -Endpoint "/i18n/${Localename}"
}

# ---------------------------------------------------------------------------
# SECTION: identity-group-mappings
# ---------------------------------------------------------------------------

function Get-HsIdentityGroupMapping {
    <#
    .SYNOPSIS
        List the identity group mappings
    .DESCRIPTION
        List the identity group mappings
    .NOTES
    CLI equivalent: identity-group-mapping-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/identity-group-mappings" -QueryParams $qp
}

function New-HsIdentityGroupMapping {
    <#
    .SYNOPSIS
        Map a federated user’s group to an internal Role. For example, map the members of a particular
    .DESCRIPTION
        Map a federated user’s group to an internal Role. For example, map the members of a particular
    .NOTES
    CLI equivalent: identity-group-mapping-create
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][string]$Group,
        [Parameter()][hashtable]$Managementrole
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Group")) { $body["group"] = $Group }
        if ($PSBoundParameters.ContainsKey("Managementrole")) { $body["managementRole"] = $Managementrole }

        Invoke-HsRequest -Method POST -Endpoint "/identity-group-mappings" -Body $body
}

function Get-HsIdentityGroupMapping2 {
    <#
    .SYNOPSIS
        Get an identity group mapping by name or ID
    .DESCRIPTION
        GET /identity-group-mappings/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/identity-group-mappings/${Identifier}"
}

function Set-HsIdentityGroupMapping {
    <#
    .SYNOPSIS
        Update an identity group mapping
    .DESCRIPTION
        Update an identity group mapping
    .NOTES
    CLI equivalent: identity-group-mapping-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][string]$Group,
        [Parameter()][hashtable]$Managementrole
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Group")) { $body["group"] = $Group }
        if ($PSBoundParameters.ContainsKey("Managementrole")) { $body["managementRole"] = $Managementrole }

        Invoke-HsRequest -Method PUT -Endpoint "/identity-group-mappings/${Identifier}" -Body $body
}

function Remove-HsIdentityGroupMapping {
    <#
    .SYNOPSIS
        Delete an identity group mapping
    .DESCRIPTION
        Delete an identity group mapping
    .NOTES
    CLI equivalent: identity-group-mapping-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/identity-group-mappings/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: identity
# ---------------------------------------------------------------------------

function Get-HsIdentity {
    <#
    .SYNOPSIS
        Get identity
    .DESCRIPTION
        GET /identity/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/identity/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: idp
# ---------------------------------------------------------------------------

function Get-HsIdp {
    <#
    .SYNOPSIS
        List the federated Identity Providers (IdPs)
    .DESCRIPTION
        List the federated Identity Providers (IdPs)
    .NOTES
    CLI equivalent: idp-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/idp" -QueryParams $qp
}

function New-HsIdp {
    <#
    .SYNOPSIS
        Add an Identity Provider (IdP) such as Active Directory for purposes of federated authentication and
    .DESCRIPTION
        Add an Identity Provider (IdP) such as Active Directory for purposes of federated authentication and
    .NOTES
    CLI equivalent: idp-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Servers,
        [ValidateSet('AD')]
        [Parameter()][string]$Type,
        [Parameter()][string]$Name,
        [Parameter()][string]$Domain,
        [Parameter()][switch]$Followreferrals,
        [Parameter()][int]$Connecttimeoutseconds,
        [Parameter()][int]$Readtimeoutseconds,
        [ValidateSet('NONE', 'TLS', 'STARTTLS')]
        [Parameter()][string]$Connectionsecuritytype,
        [Parameter()][switch]$Validateservercert
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Servers")) { $body["servers"] = $Servers }
        if ($PSBoundParameters.ContainsKey("Type")) { $body["type"] = $Type }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Domain")) { $body["domain"] = $Domain }
        $body["followReferrals"] = $Followreferrals.IsPresent
        if ($PSBoundParameters.ContainsKey("Connecttimeoutseconds")) { $body["connectTimeoutSeconds"] = $Connecttimeoutseconds }
        if ($PSBoundParameters.ContainsKey("Readtimeoutseconds")) { $body["readTimeoutSeconds"] = $Readtimeoutseconds }
        if ($PSBoundParameters.ContainsKey("Connectionsecuritytype")) { $body["connectionSecurityType"] = $Connectionsecuritytype }
        $body["validateServerCert"] = $Validateservercert.IsPresent

        Invoke-HsRequest -Method POST -Endpoint "/idp" -Body $body
}

function Get-HsIdp2 {
    <#
    .SYNOPSIS
        Get a federated Identity Provider (IdP) by name or ID
    .DESCRIPTION
        GET /idp/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/idp/${Identifier}"
}

function Set-HsIdp {
    <#
    .SYNOPSIS
        Update a federated Identity Provider (IdP)
    .DESCRIPTION
        Update a federated Identity Provider (IdP)
    .NOTES
    CLI equivalent: idp-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Servers,
        [ValidateSet('AD')]
        [Parameter()][string]$Type,
        [Parameter()][string]$Name,
        [Parameter()][string]$Domain,
        [Parameter()][switch]$Followreferrals,
        [Parameter()][int]$Connecttimeoutseconds,
        [Parameter()][int]$Readtimeoutseconds,
        [ValidateSet('NONE', 'TLS', 'STARTTLS')]
        [Parameter()][string]$Connectionsecuritytype,
        [Parameter()][switch]$Validateservercert
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Servers")) { $body["servers"] = $Servers }
        if ($PSBoundParameters.ContainsKey("Type")) { $body["type"] = $Type }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Domain")) { $body["domain"] = $Domain }
        $body["followReferrals"] = $Followreferrals.IsPresent
        if ($PSBoundParameters.ContainsKey("Connecttimeoutseconds")) { $body["connectTimeoutSeconds"] = $Connecttimeoutseconds }
        if ($PSBoundParameters.ContainsKey("Readtimeoutseconds")) { $body["readTimeoutSeconds"] = $Readtimeoutseconds }
        if ($PSBoundParameters.ContainsKey("Connectionsecuritytype")) { $body["connectionSecurityType"] = $Connectionsecuritytype }
        $body["validateServerCert"] = $Validateservercert.IsPresent

        Invoke-HsRequest -Method PUT -Endpoint "/idp/${Identifier}" -Body $body
}

function Remove-HsIdp {
    <#
    .SYNOPSIS
        Remove a federated Identity Provider (IdP)
    .DESCRIPTION
        Remove a federated Identity Provider (IdP)
    .NOTES
    CLI equivalent: idp-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/idp/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: kmses
# ---------------------------------------------------------------------------

function Get-HsKms {
    <#
    .SYNOPSIS
        List the key management systems (KMS)s
    .DESCRIPTION
        List the key management systems (KMS)s
    .NOTES
    CLI equivalent: kms-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/kmses" -QueryParams $qp
}

function New-HsKms {
    <#
    .SYNOPSIS
        Add a key management system (KMS)
    .DESCRIPTION
        Add a key management system (KMS)
    .NOTES
    CLI equivalent: kms-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [ValidateSet('NCIPHER_WSOP', 'AWS_KMS', 'PASSPHRASE')]
        [Parameter()][string]$Type,
        [Parameter()][string]$Endpoint,
        [Parameter()][hashtable]$Credentials,
        [Parameter()][string]$Keyid,
        [Parameter()][int]$Passphrasecount,
        [Parameter()][string]$Accessid
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Type")) { $body["type"] = $Type }
        if ($PSBoundParameters.ContainsKey("Endpoint")) { $body["endpoint"] = $Endpoint }
        if ($PSBoundParameters.ContainsKey("Credentials")) { $body["credentials"] = $Credentials }
        if ($PSBoundParameters.ContainsKey("Keyid")) { $body["keyId"] = $Keyid }
        if ($PSBoundParameters.ContainsKey("Passphrasecount")) { $body["passphraseCount"] = $Passphrasecount }
        if ($PSBoundParameters.ContainsKey("Accessid")) { $body["accessId"] = $Accessid }

        Invoke-HsRequest -Method POST -Endpoint "/kmses" -Body $body
}

function Get-HsKms2 {
    <#
    .SYNOPSIS
        Get a key management system by ID
    .DESCRIPTION
        GET /kmses/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/kmses/${Identifier}"
}

function Set-HsKms {
    <#
    .SYNOPSIS
        Update a key management system (KMS)
    .DESCRIPTION
        Update a key management system (KMS)
    .NOTES
    CLI equivalent: kms-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [ValidateSet('NCIPHER_WSOP', 'AWS_KMS', 'PASSPHRASE')]
        [Parameter()][string]$Type,
        [Parameter()][string]$Endpoint,
        [Parameter()][hashtable]$Credentials,
        [Parameter()][string]$Keyid,
        [Parameter()][int]$Passphrasecount,
        [Parameter()][string]$Accessid
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Type")) { $body["type"] = $Type }
        if ($PSBoundParameters.ContainsKey("Endpoint")) { $body["endpoint"] = $Endpoint }
        if ($PSBoundParameters.ContainsKey("Credentials")) { $body["credentials"] = $Credentials }
        if ($PSBoundParameters.ContainsKey("Keyid")) { $body["keyId"] = $Keyid }
        if ($PSBoundParameters.ContainsKey("Passphrasecount")) { $body["passphraseCount"] = $Passphrasecount }
        if ($PSBoundParameters.ContainsKey("Accessid")) { $body["accessId"] = $Accessid }

        Invoke-HsRequest -Method PUT -Endpoint "/kmses/${Identifier}" -Body $body
}

function Remove-HsKms {
    <#
    .SYNOPSIS
        Remove a key management system
    .DESCRIPTION
        Remove a key management system
    .NOTES
    CLI equivalent: kms-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Force
    )

        $qp = @{
            "force" = $Force
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/kmses/${Identifier}" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: labels
# ---------------------------------------------------------------------------

function Get-HsLabel {
    <#
    .SYNOPSIS
        Get all labels
    .DESCRIPTION
        GET /labels
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/labels" -QueryParams $qp
}

function New-HsLabel {
    <#
    .SYNOPSIS
        Create a label
    .DESCRIPTION
        POST /labels
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Zombie
        (Body) zombie
    .PARAMETER Impliedlabels
        (Body) impliedLabels
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][switch]$Zombie,
        [Parameter()][object[]]$Impliedlabels
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        $body["zombie"] = $Zombie.IsPresent
        if ($PSBoundParameters.ContainsKey("Impliedlabels")) { $body["impliedLabels"] = $Impliedlabels }

        Invoke-HsRequest -Method POST -Endpoint "/labels" -Body $body
}

function Get-HsLabel2 {
    <#
    .SYNOPSIS
        Get a label by ID
    .DESCRIPTION
        GET /labels/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/labels/${Identifier}"
}

function Set-HsLabel {
    <#
    .SYNOPSIS
        Update a label
    .DESCRIPTION
        PUT /labels/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Zombie
        (Body) zombie
    .PARAMETER Impliedlabels
        (Body) impliedLabels
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][switch]$Zombie,
        [Parameter()][object[]]$Impliedlabels
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        $body["zombie"] = $Zombie.IsPresent
        if ($PSBoundParameters.ContainsKey("Impliedlabels")) { $body["impliedLabels"] = $Impliedlabels }

        Invoke-HsRequest -Method PUT -Endpoint "/labels/${Identifier}" -Body $body
}

function Remove-HsLabel {
    <#
    .SYNOPSIS
        Remove a label
    .DESCRIPTION
        DELETE /labels/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/labels/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: ldaps
# ---------------------------------------------------------------------------

function Get-HsLdap {
    <#
    .SYNOPSIS
        Get LDAP
    .DESCRIPTION
        GET /ldaps
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/ldaps" -QueryParams $qp
}

function New-HsLdap {
    <#
    .SYNOPSIS
        Configure LDAP
    .DESCRIPTION
        POST /ldaps
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Ipv4
        (Body) ipv4
    .PARAMETER Ipv6
        (Body) ipv6
    .PARAMETER Nodename
        (Body) nodeName
    .PARAMETER Url
        (Body) url
    .PARAMETER Base
        (Body) base
    .PARAMETER Tlscacert
        (Body) tlsCaCert
    .PARAMETER Uri
        (Body) uri
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][hashtable]$Ipv4,
        [Parameter()][hashtable]$Ipv6,
        [Parameter()][string]$Nodename,
        [Parameter()][string]$Url,
        [Parameter()][string]$Base,
        [Parameter()][string]$Tlscacert,
        [Parameter()][string]$Uri
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Ipv4")) { $body["ipv4"] = $Ipv4 }
        if ($PSBoundParameters.ContainsKey("Ipv6")) { $body["ipv6"] = $Ipv6 }
        if ($PSBoundParameters.ContainsKey("Nodename")) { $body["nodeName"] = $Nodename }
        if ($PSBoundParameters.ContainsKey("Url")) { $body["url"] = $Url }
        if ($PSBoundParameters.ContainsKey("Base")) { $body["base"] = $Base }
        if ($PSBoundParameters.ContainsKey("Tlscacert")) { $body["tlsCaCert"] = $Tlscacert }
        if ($PSBoundParameters.ContainsKey("Uri")) { $body["uri"] = $Uri }

        Invoke-HsRequest -Method POST -Endpoint "/ldaps" -Body $body
}

function Get-HsLdap2 {
    <#
    .SYNOPSIS
        Get LDAP
    .DESCRIPTION
        GET /ldaps/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/ldaps/${Identifier}"
}

function Set-HsLdap {
    <#
    .SYNOPSIS
        Update LDAP
    .DESCRIPTION
        PUT /ldaps/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Ipv4
        (Body) ipv4
    .PARAMETER Ipv6
        (Body) ipv6
    .PARAMETER Nodename
        (Body) nodeName
    .PARAMETER Url
        (Body) url
    .PARAMETER Base
        (Body) base
    .PARAMETER Tlscacert
        (Body) tlsCaCert
    .PARAMETER Uri
        (Body) uri
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][hashtable]$Ipv4,
        [Parameter()][hashtable]$Ipv6,
        [Parameter()][string]$Nodename,
        [Parameter()][string]$Url,
        [Parameter()][string]$Base,
        [Parameter()][string]$Tlscacert,
        [Parameter()][string]$Uri
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Ipv4")) { $body["ipv4"] = $Ipv4 }
        if ($PSBoundParameters.ContainsKey("Ipv6")) { $body["ipv6"] = $Ipv6 }
        if ($PSBoundParameters.ContainsKey("Nodename")) { $body["nodeName"] = $Nodename }
        if ($PSBoundParameters.ContainsKey("Url")) { $body["url"] = $Url }
        if ($PSBoundParameters.ContainsKey("Base")) { $body["base"] = $Base }
        if ($PSBoundParameters.ContainsKey("Tlscacert")) { $body["tlsCaCert"] = $Tlscacert }
        if ($PSBoundParameters.ContainsKey("Uri")) { $body["uri"] = $Uri }

        Invoke-HsRequest -Method PUT -Endpoint "/ldaps/${Identifier}" -Body $body
}

function Remove-HsLdap {
    <#
    .SYNOPSIS
        Delete LDAP
    .DESCRIPTION
        DELETE /ldaps/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/ldaps/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: license-server
# ---------------------------------------------------------------------------

function Get-HsLicenseServer {
    <#
    .SYNOPSIS
        Get all metered licenses
    .DESCRIPTION
        GET /license-server
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/license-server" -QueryParams $qp
}

function Submit-HsLicenseServerReportUsage {
    <#
    .SYNOPSIS
        Report license usage.
    .DESCRIPTION
        PUT /license-server/report-usage/{uuid}
    .PARAMETER Uuid
        (Path) uuid
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Activationid
        (Body) activationId
    .PARAMETER Licensetype
        (Body) licenseType
    .PARAMETER Expirationurgency
        (Body) expirationUrgency
    .PARAMETER Capacitypercentused
        (Body) capacityPercentUsed
    .PARAMETER Offlineresponsepending
        (Body) offlineResponsePending
    .PARAMETER Requestedlicensecount
        (Body) requestedLicenseCount
    .PARAMETER Licensecount
        (Body) licenseCount
    .PARAMETER Featurecount
        (Body) featureCount
    .PARAMETER Validationfailurecount
        (Body) validationFailureCount
    .PARAMETER Supportsgrace
        (Body) supportsGrace
    .PARAMETER Sharingwith
        (Body) sharingWith
    .PARAMETER Borrowingfrom
        (Body) borrowingFrom
    .PARAMETER Activationtime
        (Body) activationTime
    .PARAMETER Expirationtime
        (Body) expirationTime
    .PARAMETER Startofgraceperiod
        (Body) startOfGracePeriod
    .PARAMETER Graceinitiator
        (Body) graceInitiator
    .PARAMETER Daysremainingingraceperiod
        (Body) daysRemainingInGracePeriod
    .PARAMETER Activelyreporting
        (Body) activelyReporting
    .PARAMETER Lastvalidatedtimemillis
        (Body) lastValidatedTimeMillis
    .PARAMETER Proxylicense
        (Body) proxyLicense
    .PARAMETER Clientcert
        (Body) clientCert
    .PARAMETER Site
        (Body) site
    .PARAMETER Licensedclientsite
        (Body) licensedClientSite
    .PARAMETER Licenseserversite
        (Body) licenseServerSite
    .PARAMETER Feature
        (Body) feature
    .PARAMETER Allocatedcapacity
        (Body) allocatedCapacity
    .PARAMETER Usagestat
        (Body) usageStat
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uuid,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Activationid,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Licensetype,
        [ValidateSet('DEBUG', 'INFORMATIONAL', 'NOTICE', 'WARNING', 'ERROR', 'CRITICAL', 'ALERT', 'EMERGENCY')]
        [Parameter()][string]$Expirationurgency,
        [Parameter()][int]$Capacitypercentused,
        [ValidateSet('ADD', 'UPDATE', 'REMOVE')]
        [Parameter()][string]$Offlineresponsepending,
        [Parameter()][int]$Requestedlicensecount,
        [Parameter()][int]$Licensecount,
        [Parameter()][int]$Featurecount,
        [Parameter()][int]$Validationfailurecount,
        [Parameter()][switch]$Supportsgrace,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Sharingwith,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Borrowingfrom,
        [Parameter()][int]$Activationtime,
        [Parameter()][int]$Expirationtime,
        [Parameter()][int]$Startofgraceperiod,
        [Parameter()][string]$Graceinitiator,
        [Parameter()][int]$Daysremainingingraceperiod,
        [Parameter()][switch]$Activelyreporting,
        [Parameter()][int]$Lastvalidatedtimemillis,
        [Parameter()][switch]$Proxylicense,
        [Parameter()][string]$Clientcert,
        [Parameter()][hashtable]$Site,
        [Parameter()][hashtable]$Licensedclientsite,
        [Parameter()][hashtable]$Licenseserversite,
        [Parameter()][hashtable]$Feature,
        [Parameter()][int]$Allocatedcapacity,
        [Parameter()][hashtable]$Usagestat
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Activationid")) { $body["activationId"] = $Activationid }
        if ($PSBoundParameters.ContainsKey("Licensetype")) { $body["licenseType"] = $Licensetype }
        if ($PSBoundParameters.ContainsKey("Expirationurgency")) { $body["expirationUrgency"] = $Expirationurgency }
        if ($PSBoundParameters.ContainsKey("Capacitypercentused")) { $body["capacityPercentUsed"] = $Capacitypercentused }
        if ($PSBoundParameters.ContainsKey("Offlineresponsepending")) { $body["offlineResponsePending"] = $Offlineresponsepending }
        if ($PSBoundParameters.ContainsKey("Requestedlicensecount")) { $body["requestedLicenseCount"] = $Requestedlicensecount }
        if ($PSBoundParameters.ContainsKey("Licensecount")) { $body["licenseCount"] = $Licensecount }
        if ($PSBoundParameters.ContainsKey("Featurecount")) { $body["featureCount"] = $Featurecount }
        if ($PSBoundParameters.ContainsKey("Validationfailurecount")) { $body["validationFailureCount"] = $Validationfailurecount }
        $body["supportsGrace"] = $Supportsgrace.IsPresent
        if ($PSBoundParameters.ContainsKey("Sharingwith")) { $body["sharingWith"] = $Sharingwith }
        if ($PSBoundParameters.ContainsKey("Borrowingfrom")) { $body["borrowingFrom"] = $Borrowingfrom }
        if ($PSBoundParameters.ContainsKey("Activationtime")) { $body["activationTime"] = $Activationtime }
        if ($PSBoundParameters.ContainsKey("Expirationtime")) { $body["expirationTime"] = $Expirationtime }
        if ($PSBoundParameters.ContainsKey("Startofgraceperiod")) { $body["startOfGracePeriod"] = $Startofgraceperiod }
        if ($PSBoundParameters.ContainsKey("Graceinitiator")) { $body["graceInitiator"] = $Graceinitiator }
        if ($PSBoundParameters.ContainsKey("Daysremainingingraceperiod")) { $body["daysRemainingInGracePeriod"] = $Daysremainingingraceperiod }
        $body["activelyReporting"] = $Activelyreporting.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastvalidatedtimemillis")) { $body["lastValidatedTimeMillis"] = $Lastvalidatedtimemillis }
        $body["proxyLicense"] = $Proxylicense.IsPresent
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        if ($PSBoundParameters.ContainsKey("Site")) { $body["site"] = $Site }
        if ($PSBoundParameters.ContainsKey("Licensedclientsite")) { $body["licensedClientSite"] = $Licensedclientsite }
        if ($PSBoundParameters.ContainsKey("Licenseserversite")) { $body["licenseServerSite"] = $Licenseserversite }
        if ($PSBoundParameters.ContainsKey("Feature")) { $body["feature"] = $Feature }
        if ($PSBoundParameters.ContainsKey("Allocatedcapacity")) { $body["allocatedCapacity"] = $Allocatedcapacity }
        if ($PSBoundParameters.ContainsKey("Usagestat")) { $body["usageStat"] = $Usagestat }

        Invoke-HsRequest -Method PUT -Endpoint "/license-server/report-usage/${Uuid}" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: licenses
# ---------------------------------------------------------------------------

function Get-HsLicense {
    <#
    .SYNOPSIS
        List all licenses
    .DESCRIPTION
        List all licenses
    .NOTES
    CLI equivalent: license-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/licenses" -QueryParams $qp
}

function New-HsLicense {
    <#
    .SYNOPSIS
        Add and activate a license
    .DESCRIPTION
        Add and activate a license
    .NOTES
    CLI equivalent: license-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$LicenseServerUsername,
        [Parameter()][string]$LicenseServerPassword,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Activationid,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Licensetype,
        [ValidateSet('DEBUG', 'INFORMATIONAL', 'NOTICE', 'WARNING', 'ERROR', 'CRITICAL', 'ALERT', 'EMERGENCY')]
        [Parameter()][string]$Expirationurgency,
        [Parameter()][int]$Capacitypercentused,
        [ValidateSet('ADD', 'UPDATE', 'REMOVE')]
        [Parameter()][string]$Offlineresponsepending,
        [Parameter()][int]$Requestedlicensecount,
        [Parameter()][int]$Licensecount,
        [Parameter()][int]$Featurecount,
        [Parameter()][int]$Validationfailurecount,
        [Parameter()][switch]$Supportsgrace,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Sharingwith,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Borrowingfrom,
        [Parameter()][int]$Activationtime,
        [Parameter()][int]$Expirationtime,
        [Parameter()][int]$Startofgraceperiod,
        [Parameter()][string]$Graceinitiator,
        [Parameter()][int]$Daysremainingingraceperiod,
        [Parameter()][switch]$Activelyreporting,
        [Parameter()][int]$Lastvalidatedtimemillis,
        [Parameter()][switch]$Proxylicense,
        [Parameter()][string]$Clientcert,
        [Parameter()][hashtable]$Site,
        [Parameter()][hashtable]$Licensedclientsite,
        [Parameter()][hashtable]$Licenseserversite,
        [Parameter()][hashtable]$Feature,
        [Parameter()][int]$Allocatedcapacity,
        [Parameter()][hashtable]$Usagestat
    )

        $qp = @{
            "license-server-username" = $LicenseServerUsername
            "license-server-password" = $LicenseServerPassword
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Activationid")) { $body["activationId"] = $Activationid }
        if ($PSBoundParameters.ContainsKey("Licensetype")) { $body["licenseType"] = $Licensetype }
        if ($PSBoundParameters.ContainsKey("Expirationurgency")) { $body["expirationUrgency"] = $Expirationurgency }
        if ($PSBoundParameters.ContainsKey("Capacitypercentused")) { $body["capacityPercentUsed"] = $Capacitypercentused }
        if ($PSBoundParameters.ContainsKey("Offlineresponsepending")) { $body["offlineResponsePending"] = $Offlineresponsepending }
        if ($PSBoundParameters.ContainsKey("Requestedlicensecount")) { $body["requestedLicenseCount"] = $Requestedlicensecount }
        if ($PSBoundParameters.ContainsKey("Licensecount")) { $body["licenseCount"] = $Licensecount }
        if ($PSBoundParameters.ContainsKey("Featurecount")) { $body["featureCount"] = $Featurecount }
        if ($PSBoundParameters.ContainsKey("Validationfailurecount")) { $body["validationFailureCount"] = $Validationfailurecount }
        $body["supportsGrace"] = $Supportsgrace.IsPresent
        if ($PSBoundParameters.ContainsKey("Sharingwith")) { $body["sharingWith"] = $Sharingwith }
        if ($PSBoundParameters.ContainsKey("Borrowingfrom")) { $body["borrowingFrom"] = $Borrowingfrom }
        if ($PSBoundParameters.ContainsKey("Activationtime")) { $body["activationTime"] = $Activationtime }
        if ($PSBoundParameters.ContainsKey("Expirationtime")) { $body["expirationTime"] = $Expirationtime }
        if ($PSBoundParameters.ContainsKey("Startofgraceperiod")) { $body["startOfGracePeriod"] = $Startofgraceperiod }
        if ($PSBoundParameters.ContainsKey("Graceinitiator")) { $body["graceInitiator"] = $Graceinitiator }
        if ($PSBoundParameters.ContainsKey("Daysremainingingraceperiod")) { $body["daysRemainingInGracePeriod"] = $Daysremainingingraceperiod }
        $body["activelyReporting"] = $Activelyreporting.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastvalidatedtimemillis")) { $body["lastValidatedTimeMillis"] = $Lastvalidatedtimemillis }
        $body["proxyLicense"] = $Proxylicense.IsPresent
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        if ($PSBoundParameters.ContainsKey("Site")) { $body["site"] = $Site }
        if ($PSBoundParameters.ContainsKey("Licensedclientsite")) { $body["licensedClientSite"] = $Licensedclientsite }
        if ($PSBoundParameters.ContainsKey("Licenseserversite")) { $body["licenseServerSite"] = $Licenseserversite }
        if ($PSBoundParameters.ContainsKey("Feature")) { $body["feature"] = $Feature }
        if ($PSBoundParameters.ContainsKey("Allocatedcapacity")) { $body["allocatedCapacity"] = $Allocatedcapacity }
        if ($PSBoundParameters.ContainsKey("Usagestat")) { $body["usageStat"] = $Usagestat }

        Invoke-HsRequest -Method POST -Endpoint "/licenses" -QueryParams $qp -Body $body
}

function Get-HsLicenseOfflineAddRequestDownload {
    <#
    .SYNOPSIS
        Add and activate a license via an offline process. A request file is generated and obtained via one of
    .DESCRIPTION
        Add and activate a license via an offline process. A request file is generated and obtained via one of
    .NOTES
    CLI equivalent: license-offline-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Activationid,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Licensetype,
        [ValidateSet('DEBUG', 'INFORMATIONAL', 'NOTICE', 'WARNING', 'ERROR', 'CRITICAL', 'ALERT', 'EMERGENCY')]
        [Parameter()][string]$Expirationurgency,
        [Parameter()][int]$Capacitypercentused,
        [ValidateSet('ADD', 'UPDATE', 'REMOVE')]
        [Parameter()][string]$Offlineresponsepending,
        [Parameter()][int]$Requestedlicensecount,
        [Parameter()][int]$Licensecount,
        [Parameter()][int]$Featurecount,
        [Parameter()][int]$Validationfailurecount,
        [Parameter()][switch]$Supportsgrace,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Sharingwith,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Borrowingfrom,
        [Parameter()][int]$Activationtime,
        [Parameter()][int]$Expirationtime,
        [Parameter()][int]$Startofgraceperiod,
        [Parameter()][string]$Graceinitiator,
        [Parameter()][int]$Daysremainingingraceperiod,
        [Parameter()][switch]$Activelyreporting,
        [Parameter()][int]$Lastvalidatedtimemillis,
        [Parameter()][switch]$Proxylicense,
        [Parameter()][string]$Clientcert,
        [Parameter()][hashtable]$Site,
        [Parameter()][hashtable]$Licensedclientsite,
        [Parameter()][hashtable]$Licenseserversite,
        [Parameter()][hashtable]$Feature,
        [Parameter()][int]$Allocatedcapacity,
        [Parameter()][hashtable]$Usagestat
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Activationid")) { $body["activationId"] = $Activationid }
        if ($PSBoundParameters.ContainsKey("Licensetype")) { $body["licenseType"] = $Licensetype }
        if ($PSBoundParameters.ContainsKey("Expirationurgency")) { $body["expirationUrgency"] = $Expirationurgency }
        if ($PSBoundParameters.ContainsKey("Capacitypercentused")) { $body["capacityPercentUsed"] = $Capacitypercentused }
        if ($PSBoundParameters.ContainsKey("Offlineresponsepending")) { $body["offlineResponsePending"] = $Offlineresponsepending }
        if ($PSBoundParameters.ContainsKey("Requestedlicensecount")) { $body["requestedLicenseCount"] = $Requestedlicensecount }
        if ($PSBoundParameters.ContainsKey("Licensecount")) { $body["licenseCount"] = $Licensecount }
        if ($PSBoundParameters.ContainsKey("Featurecount")) { $body["featureCount"] = $Featurecount }
        if ($PSBoundParameters.ContainsKey("Validationfailurecount")) { $body["validationFailureCount"] = $Validationfailurecount }
        $body["supportsGrace"] = $Supportsgrace.IsPresent
        if ($PSBoundParameters.ContainsKey("Sharingwith")) { $body["sharingWith"] = $Sharingwith }
        if ($PSBoundParameters.ContainsKey("Borrowingfrom")) { $body["borrowingFrom"] = $Borrowingfrom }
        if ($PSBoundParameters.ContainsKey("Activationtime")) { $body["activationTime"] = $Activationtime }
        if ($PSBoundParameters.ContainsKey("Expirationtime")) { $body["expirationTime"] = $Expirationtime }
        if ($PSBoundParameters.ContainsKey("Startofgraceperiod")) { $body["startOfGracePeriod"] = $Startofgraceperiod }
        if ($PSBoundParameters.ContainsKey("Graceinitiator")) { $body["graceInitiator"] = $Graceinitiator }
        if ($PSBoundParameters.ContainsKey("Daysremainingingraceperiod")) { $body["daysRemainingInGracePeriod"] = $Daysremainingingraceperiod }
        $body["activelyReporting"] = $Activelyreporting.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastvalidatedtimemillis")) { $body["lastValidatedTimeMillis"] = $Lastvalidatedtimemillis }
        $body["proxyLicense"] = $Proxylicense.IsPresent
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        if ($PSBoundParameters.ContainsKey("Site")) { $body["site"] = $Site }
        if ($PSBoundParameters.ContainsKey("Licensedclientsite")) { $body["licensedClientSite"] = $Licensedclientsite }
        if ($PSBoundParameters.ContainsKey("Licenseserversite")) { $body["licenseServerSite"] = $Licenseserversite }
        if ($PSBoundParameters.ContainsKey("Feature")) { $body["feature"] = $Feature }
        if ($PSBoundParameters.ContainsKey("Allocatedcapacity")) { $body["allocatedCapacity"] = $Allocatedcapacity }
        if ($PSBoundParameters.ContainsKey("Usagestat")) { $body["usageStat"] = $Usagestat }

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-add-request-download" -Body $body
}

function Export-HsLicenseOfflineAddRequestExport {
    <#
    .SYNOPSIS
        Add and activate a license via an offline process. A request file is generated and obtained via one of
    .DESCRIPTION
        Add and activate a license via an offline process. A request file is generated and obtained via one of
    .NOTES
    CLI equivalent: license-offline-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$ExportUri,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Activationid,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Licensetype,
        [ValidateSet('DEBUG', 'INFORMATIONAL', 'NOTICE', 'WARNING', 'ERROR', 'CRITICAL', 'ALERT', 'EMERGENCY')]
        [Parameter()][string]$Expirationurgency,
        [Parameter()][int]$Capacitypercentused,
        [ValidateSet('ADD', 'UPDATE', 'REMOVE')]
        [Parameter()][string]$Offlineresponsepending,
        [Parameter()][int]$Requestedlicensecount,
        [Parameter()][int]$Licensecount,
        [Parameter()][int]$Featurecount,
        [Parameter()][int]$Validationfailurecount,
        [Parameter()][switch]$Supportsgrace,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Sharingwith,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Borrowingfrom,
        [Parameter()][int]$Activationtime,
        [Parameter()][int]$Expirationtime,
        [Parameter()][int]$Startofgraceperiod,
        [Parameter()][string]$Graceinitiator,
        [Parameter()][int]$Daysremainingingraceperiod,
        [Parameter()][switch]$Activelyreporting,
        [Parameter()][int]$Lastvalidatedtimemillis,
        [Parameter()][switch]$Proxylicense,
        [Parameter()][string]$Clientcert,
        [Parameter()][hashtable]$Site,
        [Parameter()][hashtable]$Licensedclientsite,
        [Parameter()][hashtable]$Licenseserversite,
        [Parameter()][hashtable]$Feature,
        [Parameter()][int]$Allocatedcapacity,
        [Parameter()][hashtable]$Usagestat
    )

        $qp = @{
            "export-uri" = $ExportUri
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Activationid")) { $body["activationId"] = $Activationid }
        if ($PSBoundParameters.ContainsKey("Licensetype")) { $body["licenseType"] = $Licensetype }
        if ($PSBoundParameters.ContainsKey("Expirationurgency")) { $body["expirationUrgency"] = $Expirationurgency }
        if ($PSBoundParameters.ContainsKey("Capacitypercentused")) { $body["capacityPercentUsed"] = $Capacitypercentused }
        if ($PSBoundParameters.ContainsKey("Offlineresponsepending")) { $body["offlineResponsePending"] = $Offlineresponsepending }
        if ($PSBoundParameters.ContainsKey("Requestedlicensecount")) { $body["requestedLicenseCount"] = $Requestedlicensecount }
        if ($PSBoundParameters.ContainsKey("Licensecount")) { $body["licenseCount"] = $Licensecount }
        if ($PSBoundParameters.ContainsKey("Featurecount")) { $body["featureCount"] = $Featurecount }
        if ($PSBoundParameters.ContainsKey("Validationfailurecount")) { $body["validationFailureCount"] = $Validationfailurecount }
        $body["supportsGrace"] = $Supportsgrace.IsPresent
        if ($PSBoundParameters.ContainsKey("Sharingwith")) { $body["sharingWith"] = $Sharingwith }
        if ($PSBoundParameters.ContainsKey("Borrowingfrom")) { $body["borrowingFrom"] = $Borrowingfrom }
        if ($PSBoundParameters.ContainsKey("Activationtime")) { $body["activationTime"] = $Activationtime }
        if ($PSBoundParameters.ContainsKey("Expirationtime")) { $body["expirationTime"] = $Expirationtime }
        if ($PSBoundParameters.ContainsKey("Startofgraceperiod")) { $body["startOfGracePeriod"] = $Startofgraceperiod }
        if ($PSBoundParameters.ContainsKey("Graceinitiator")) { $body["graceInitiator"] = $Graceinitiator }
        if ($PSBoundParameters.ContainsKey("Daysremainingingraceperiod")) { $body["daysRemainingInGracePeriod"] = $Daysremainingingraceperiod }
        $body["activelyReporting"] = $Activelyreporting.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastvalidatedtimemillis")) { $body["lastValidatedTimeMillis"] = $Lastvalidatedtimemillis }
        $body["proxyLicense"] = $Proxylicense.IsPresent
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        if ($PSBoundParameters.ContainsKey("Site")) { $body["site"] = $Site }
        if ($PSBoundParameters.ContainsKey("Licensedclientsite")) { $body["licensedClientSite"] = $Licensedclientsite }
        if ($PSBoundParameters.ContainsKey("Licenseserversite")) { $body["licenseServerSite"] = $Licenseserversite }
        if ($PSBoundParameters.ContainsKey("Feature")) { $body["feature"] = $Feature }
        if ($PSBoundParameters.ContainsKey("Allocatedcapacity")) { $body["allocatedCapacity"] = $Allocatedcapacity }
        if ($PSBoundParameters.ContainsKey("Usagestat")) { $body["usageStat"] = $Usagestat }

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-add-request-export" -QueryParams $qp -Body $body
}

function Import-HsLicenseOfflineAddResponseImport {
    <#
    .SYNOPSIS
        Import and process an offline license add response file
    .DESCRIPTION
        POST /licenses/offline-add-response-import/{activation-id}/{import-uri}
    .PARAMETER ActivationId
        (Path) activation-id
    .PARAMETER ImportUri
        (Path) import-uri
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId,
        [Parameter(Mandatory)][string]$ImportUri
    )

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-add-response-import/${ActivationId}/${ImportUri}"
}

function Import-HsLicenseOfflineAddResponseUpload {
    <#
    .SYNOPSIS
        Upload and process an offline license add response file
    .DESCRIPTION
        POST /licenses/offline-add-response-upload/{activation-id}
    .PARAMETER ActivationId
        (Path) activation-id
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId
    )

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-add-response-upload/${ActivationId}"
}

function Stop-HsLicenseOfflineCancelPending {
    <#
    .SYNOPSIS
        Cancel a pending offline license operation for a given activation ID. If the initial request has already
    .DESCRIPTION
        Cancel a pending offline license operation for a given activation ID. If the initial request has already
    .NOTES
    CLI equivalent: license-offline-cancel
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId
    )

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-cancel-pending/${ActivationId}"
}

function Get-HsLicenseOfflineRemoveRequestDownload {
    <#
    .SYNOPSIS
        Deactivate and remove a license via an offline process. A request file is generated and obtained via
    .DESCRIPTION
        Deactivate and remove a license via an offline process. A request file is generated and obtained via
    .NOTES
    CLI equivalent: license-offline-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId
    )

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-remove-request-download/${ActivationId}"
}

function Export-HsLicenseOfflineRemoveRequestExport {
    <#
    .SYNOPSIS
        Create a request file for removing a license offline and export it to a location
    .DESCRIPTION
        POST /licenses/offline-remove-request-export/{activation-id}
    .PARAMETER ActivationId
        (Path) activation-id
    .PARAMETER ExportUri
        (Query) export-uri
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId,
        [Parameter()][string]$ExportUri
    )

        $qp = @{
            "export-uri" = $ExportUri
        }

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-remove-request-export/${ActivationId}" -QueryParams $qp
}

function Import-HsLicenseOfflineRemoveResponseImport {
    <#
    .SYNOPSIS
        Import and process an offline license remove response file
    .DESCRIPTION
        POST /licenses/offline-remove-response-import/{activation-id}/{import-uri}
    .PARAMETER ActivationId
        (Path) activation-id
    .PARAMETER ImportUri
        (Path) import-uri
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId,
        [Parameter(Mandatory)][string]$ImportUri
    )

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-remove-response-import/${ActivationId}/${ImportUri}"
}

function Import-HsLicenseOfflineRemoveResponseUpload {
    <#
    .SYNOPSIS
        Upload and process an offline license remove response file
    .DESCRIPTION
        POST /licenses/offline-remove-response-upload/{activation-id}
    .PARAMETER ActivationId
        (Path) activation-id
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId
    )

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-remove-response-upload/${ActivationId}"
}

function Get-HsLicenseOfflineUpdateRequestDownload {
    <#
    .SYNOPSIS
        Update the allocated capacity for a capacity-based license via an offline process. A request file is
    .DESCRIPTION
        Update the allocated capacity for a capacity-based license via an offline process. A request file is
    .NOTES
    CLI equivalent: license-offline-update
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Activationid,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Licensetype,
        [ValidateSet('DEBUG', 'INFORMATIONAL', 'NOTICE', 'WARNING', 'ERROR', 'CRITICAL', 'ALERT', 'EMERGENCY')]
        [Parameter()][string]$Expirationurgency,
        [Parameter()][int]$Capacitypercentused,
        [ValidateSet('ADD', 'UPDATE', 'REMOVE')]
        [Parameter()][string]$Offlineresponsepending,
        [Parameter()][int]$Requestedlicensecount,
        [Parameter()][int]$Licensecount,
        [Parameter()][int]$Featurecount,
        [Parameter()][int]$Validationfailurecount,
        [Parameter()][switch]$Supportsgrace,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Sharingwith,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Borrowingfrom,
        [Parameter()][int]$Activationtime,
        [Parameter()][int]$Expirationtime,
        [Parameter()][int]$Startofgraceperiod,
        [Parameter()][string]$Graceinitiator,
        [Parameter()][int]$Daysremainingingraceperiod,
        [Parameter()][switch]$Activelyreporting,
        [Parameter()][int]$Lastvalidatedtimemillis,
        [Parameter()][switch]$Proxylicense,
        [Parameter()][string]$Clientcert,
        [Parameter()][hashtable]$Site,
        [Parameter()][hashtable]$Licensedclientsite,
        [Parameter()][hashtable]$Licenseserversite,
        [Parameter()][hashtable]$Feature,
        [Parameter()][int]$Allocatedcapacity,
        [Parameter()][hashtable]$Usagestat
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Activationid")) { $body["activationId"] = $Activationid }
        if ($PSBoundParameters.ContainsKey("Licensetype")) { $body["licenseType"] = $Licensetype }
        if ($PSBoundParameters.ContainsKey("Expirationurgency")) { $body["expirationUrgency"] = $Expirationurgency }
        if ($PSBoundParameters.ContainsKey("Capacitypercentused")) { $body["capacityPercentUsed"] = $Capacitypercentused }
        if ($PSBoundParameters.ContainsKey("Offlineresponsepending")) { $body["offlineResponsePending"] = $Offlineresponsepending }
        if ($PSBoundParameters.ContainsKey("Requestedlicensecount")) { $body["requestedLicenseCount"] = $Requestedlicensecount }
        if ($PSBoundParameters.ContainsKey("Licensecount")) { $body["licenseCount"] = $Licensecount }
        if ($PSBoundParameters.ContainsKey("Featurecount")) { $body["featureCount"] = $Featurecount }
        if ($PSBoundParameters.ContainsKey("Validationfailurecount")) { $body["validationFailureCount"] = $Validationfailurecount }
        $body["supportsGrace"] = $Supportsgrace.IsPresent
        if ($PSBoundParameters.ContainsKey("Sharingwith")) { $body["sharingWith"] = $Sharingwith }
        if ($PSBoundParameters.ContainsKey("Borrowingfrom")) { $body["borrowingFrom"] = $Borrowingfrom }
        if ($PSBoundParameters.ContainsKey("Activationtime")) { $body["activationTime"] = $Activationtime }
        if ($PSBoundParameters.ContainsKey("Expirationtime")) { $body["expirationTime"] = $Expirationtime }
        if ($PSBoundParameters.ContainsKey("Startofgraceperiod")) { $body["startOfGracePeriod"] = $Startofgraceperiod }
        if ($PSBoundParameters.ContainsKey("Graceinitiator")) { $body["graceInitiator"] = $Graceinitiator }
        if ($PSBoundParameters.ContainsKey("Daysremainingingraceperiod")) { $body["daysRemainingInGracePeriod"] = $Daysremainingingraceperiod }
        $body["activelyReporting"] = $Activelyreporting.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastvalidatedtimemillis")) { $body["lastValidatedTimeMillis"] = $Lastvalidatedtimemillis }
        $body["proxyLicense"] = $Proxylicense.IsPresent
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        if ($PSBoundParameters.ContainsKey("Site")) { $body["site"] = $Site }
        if ($PSBoundParameters.ContainsKey("Licensedclientsite")) { $body["licensedClientSite"] = $Licensedclientsite }
        if ($PSBoundParameters.ContainsKey("Licenseserversite")) { $body["licenseServerSite"] = $Licenseserversite }
        if ($PSBoundParameters.ContainsKey("Feature")) { $body["feature"] = $Feature }
        if ($PSBoundParameters.ContainsKey("Allocatedcapacity")) { $body["allocatedCapacity"] = $Allocatedcapacity }
        if ($PSBoundParameters.ContainsKey("Usagestat")) { $body["usageStat"] = $Usagestat }

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-update-request-download" -Body $body
}

function Export-HsLicenseOfflineUpdateRequestExport {
    <#
    .SYNOPSIS
        Create a request file for updating a license offline and export it to a location
    .DESCRIPTION
        POST /licenses/offline-update-request-export
    .PARAMETER ExportUri
        (Query) export-uri
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Activationid
        (Body) activationId
    .PARAMETER Licensetype
        (Body) licenseType
    .PARAMETER Expirationurgency
        (Body) expirationUrgency
    .PARAMETER Capacitypercentused
        (Body) capacityPercentUsed
    .PARAMETER Offlineresponsepending
        (Body) offlineResponsePending
    .PARAMETER Requestedlicensecount
        (Body) requestedLicenseCount
    .PARAMETER Licensecount
        (Body) licenseCount
    .PARAMETER Featurecount
        (Body) featureCount
    .PARAMETER Validationfailurecount
        (Body) validationFailureCount
    .PARAMETER Supportsgrace
        (Body) supportsGrace
    .PARAMETER Sharingwith
        (Body) sharingWith
    .PARAMETER Borrowingfrom
        (Body) borrowingFrom
    .PARAMETER Activationtime
        (Body) activationTime
    .PARAMETER Expirationtime
        (Body) expirationTime
    .PARAMETER Startofgraceperiod
        (Body) startOfGracePeriod
    .PARAMETER Graceinitiator
        (Body) graceInitiator
    .PARAMETER Daysremainingingraceperiod
        (Body) daysRemainingInGracePeriod
    .PARAMETER Activelyreporting
        (Body) activelyReporting
    .PARAMETER Lastvalidatedtimemillis
        (Body) lastValidatedTimeMillis
    .PARAMETER Proxylicense
        (Body) proxyLicense
    .PARAMETER Clientcert
        (Body) clientCert
    .PARAMETER Site
        (Body) site
    .PARAMETER Licensedclientsite
        (Body) licensedClientSite
    .PARAMETER Licenseserversite
        (Body) licenseServerSite
    .PARAMETER Feature
        (Body) feature
    .PARAMETER Allocatedcapacity
        (Body) allocatedCapacity
    .PARAMETER Usagestat
        (Body) usageStat
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$ExportUri,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Activationid,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Licensetype,
        [ValidateSet('DEBUG', 'INFORMATIONAL', 'NOTICE', 'WARNING', 'ERROR', 'CRITICAL', 'ALERT', 'EMERGENCY')]
        [Parameter()][string]$Expirationurgency,
        [Parameter()][int]$Capacitypercentused,
        [ValidateSet('ADD', 'UPDATE', 'REMOVE')]
        [Parameter()][string]$Offlineresponsepending,
        [Parameter()][int]$Requestedlicensecount,
        [Parameter()][int]$Licensecount,
        [Parameter()][int]$Featurecount,
        [Parameter()][int]$Validationfailurecount,
        [Parameter()][switch]$Supportsgrace,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Sharingwith,
        [ValidateSet('NODE', 'FILE_CAPACITY', 'OBJECT_CAPACITY', 'METERED', 'SHARING')]
        [Parameter()][string]$Borrowingfrom,
        [Parameter()][int]$Activationtime,
        [Parameter()][int]$Expirationtime,
        [Parameter()][int]$Startofgraceperiod,
        [Parameter()][string]$Graceinitiator,
        [Parameter()][int]$Daysremainingingraceperiod,
        [Parameter()][switch]$Activelyreporting,
        [Parameter()][int]$Lastvalidatedtimemillis,
        [Parameter()][switch]$Proxylicense,
        [Parameter()][string]$Clientcert,
        [Parameter()][hashtable]$Site,
        [Parameter()][hashtable]$Licensedclientsite,
        [Parameter()][hashtable]$Licenseserversite,
        [Parameter()][hashtable]$Feature,
        [Parameter()][int]$Allocatedcapacity,
        [Parameter()][hashtable]$Usagestat
    )

        $qp = @{
            "export-uri" = $ExportUri
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Activationid")) { $body["activationId"] = $Activationid }
        if ($PSBoundParameters.ContainsKey("Licensetype")) { $body["licenseType"] = $Licensetype }
        if ($PSBoundParameters.ContainsKey("Expirationurgency")) { $body["expirationUrgency"] = $Expirationurgency }
        if ($PSBoundParameters.ContainsKey("Capacitypercentused")) { $body["capacityPercentUsed"] = $Capacitypercentused }
        if ($PSBoundParameters.ContainsKey("Offlineresponsepending")) { $body["offlineResponsePending"] = $Offlineresponsepending }
        if ($PSBoundParameters.ContainsKey("Requestedlicensecount")) { $body["requestedLicenseCount"] = $Requestedlicensecount }
        if ($PSBoundParameters.ContainsKey("Licensecount")) { $body["licenseCount"] = $Licensecount }
        if ($PSBoundParameters.ContainsKey("Featurecount")) { $body["featureCount"] = $Featurecount }
        if ($PSBoundParameters.ContainsKey("Validationfailurecount")) { $body["validationFailureCount"] = $Validationfailurecount }
        $body["supportsGrace"] = $Supportsgrace.IsPresent
        if ($PSBoundParameters.ContainsKey("Sharingwith")) { $body["sharingWith"] = $Sharingwith }
        if ($PSBoundParameters.ContainsKey("Borrowingfrom")) { $body["borrowingFrom"] = $Borrowingfrom }
        if ($PSBoundParameters.ContainsKey("Activationtime")) { $body["activationTime"] = $Activationtime }
        if ($PSBoundParameters.ContainsKey("Expirationtime")) { $body["expirationTime"] = $Expirationtime }
        if ($PSBoundParameters.ContainsKey("Startofgraceperiod")) { $body["startOfGracePeriod"] = $Startofgraceperiod }
        if ($PSBoundParameters.ContainsKey("Graceinitiator")) { $body["graceInitiator"] = $Graceinitiator }
        if ($PSBoundParameters.ContainsKey("Daysremainingingraceperiod")) { $body["daysRemainingInGracePeriod"] = $Daysremainingingraceperiod }
        $body["activelyReporting"] = $Activelyreporting.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastvalidatedtimemillis")) { $body["lastValidatedTimeMillis"] = $Lastvalidatedtimemillis }
        $body["proxyLicense"] = $Proxylicense.IsPresent
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        if ($PSBoundParameters.ContainsKey("Site")) { $body["site"] = $Site }
        if ($PSBoundParameters.ContainsKey("Licensedclientsite")) { $body["licensedClientSite"] = $Licensedclientsite }
        if ($PSBoundParameters.ContainsKey("Licenseserversite")) { $body["licenseServerSite"] = $Licenseserversite }
        if ($PSBoundParameters.ContainsKey("Feature")) { $body["feature"] = $Feature }
        if ($PSBoundParameters.ContainsKey("Allocatedcapacity")) { $body["allocatedCapacity"] = $Allocatedcapacity }
        if ($PSBoundParameters.ContainsKey("Usagestat")) { $body["usageStat"] = $Usagestat }

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-update-request-export" -QueryParams $qp -Body $body
}

function Import-HsLicenseOfflineUpdateResponseImport {
    <#
    .SYNOPSIS
        Import and process an offline license update response file
    .DESCRIPTION
        POST /licenses/offline-update-response-import/{activation-id}/{import-uri}
    .PARAMETER ActivationId
        (Path) activation-id
    .PARAMETER ImportUri
        (Path) import-uri
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId,
        [Parameter(Mandatory)][string]$ImportUri
    )

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-update-response-import/${ActivationId}/${ImportUri}"
}

function Import-HsLicenseOfflineUpdateResponseUpload {
    <#
    .SYNOPSIS
        Upload and process an offline license update response file
    .DESCRIPTION
        POST /licenses/offline-update-response-upload/{activation-id}
    .PARAMETER ActivationId
        (Path) activation-id
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId
    )

        Invoke-HsRequest -Method POST -Endpoint "/licenses/offline-update-response-upload/${ActivationId}"
}

function Get-HsLicense2 {
    <#
    .SYNOPSIS
        Get a license by activation ID
    .DESCRIPTION
        GET /licenses/{activation-id}
    .PARAMETER ActivationId
        (Path) activation-id
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId
    )

        Invoke-HsRequest -Method GET -Endpoint "/licenses/${ActivationId}"
}

function Set-HsLicense {
    <#
    .SYNOPSIS
        Update the allocated capacity for a capacity-based license
    .DESCRIPTION
        Update the allocated capacity for a capacity-based license
    .NOTES
    CLI equivalent: license-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/licenses/${ActivationId}" -Body $body
}

function Remove-HsLicense {
    <#
    .SYNOPSIS
        Deactivate and remove a license
    .DESCRIPTION
        Deactivate and remove a license
    .NOTES
    CLI equivalent: license-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ActivationId,
        [Parameter()][string]$Force
    )

        $qp = @{
            "force" = $Force
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/licenses/${ActivationId}" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: logical-volumes
# ---------------------------------------------------------------------------

function Get-HsLogicalVolume {
    <#
    .SYNOPSIS
        List logical volumes
    .DESCRIPTION
        List logical volumes
    .NOTES
    CLI equivalent: logical-volume-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/logical-volumes" -QueryParams $qp
}

function New-HsLogicalVolume {
    <#
    .SYNOPSIS
        Create logical volume
    .DESCRIPTION
        Create logical volume
    .NOTES
    CLI equivalent: logical-volume-create
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Nodename,
        [Parameter()][string]$Devicepath,
        [Parameter()][string]$Force
    )

        $qp = @{
            "nodeName" = $Nodename
            "devicePath" = $Devicepath
            "force" = $Force
        }

        Invoke-HsRequest -Method POST -Endpoint "/logical-volumes" -QueryParams $qp
}

function Get-HsLogicalVolume2 {
    <#
    .SYNOPSIS
        Get logical volume by ID
    .DESCRIPTION
        GET /logical-volumes/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/logical-volumes/${Identifier}"
}

function Remove-HsLogicalVolume {
    <#
    .SYNOPSIS
        Delete logical volume
    .DESCRIPTION
        Delete logical volume
    .NOTES
    CLI equivalent: logical-volume-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/logical-volumes/${Identifier}"
}

function Get-HsLogicalVolume3 {
    <#
    .SYNOPSIS
        Discover a logical volume
    .DESCRIPTION
        GET /logical-volumes/{identifier}/discover
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/logical-volumes/${Identifier}/discover"
}

# ---------------------------------------------------------------------------
# SECTION: login
# ---------------------------------------------------------------------------

function Connect-HsLogin {
    <#
    .SYNOPSIS
        Login
    .DESCRIPTION
        POST /login
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method POST -Endpoint "/login"
}

# ---------------------------------------------------------------------------
# SECTION: login-policy
# ---------------------------------------------------------------------------

function Get-HsLoginPolicy {
    <#
    .SYNOPSIS
        Get all login policies
    .DESCRIPTION
        GET /login-policy
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/login-policy" -QueryParams $qp
}

function New-HsLoginPolicy {
    <#
    .SYNOPSIS
        Configure the system login policies
    .DESCRIPTION
        Configure the system login policies
    .NOTES
    CLI equivalent: login-policy-config
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method POST -Endpoint "/login-policy" -Body $body
}

function Get-HsLoginPolicy2 {
    <#
    .SYNOPSIS
        Get a login policy
    .DESCRIPTION
        GET /login-policy/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/login-policy/${Identifier}"
}

function Set-HsLoginPolicy {
    <#
    .SYNOPSIS
        Configure the system login policies
    .DESCRIPTION
        Configure the system login policies
    .NOTES
    CLI equivalent: login-policy-config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Allowednetworks,
        [Parameter()][int]$Lockafterfailures,
        [Parameter()][int]$Lockfailureinterval,
        [Parameter()][int]$Lockouttime
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Allowednetworks")) { $body["allowedNetworks"] = $Allowednetworks }
        if ($PSBoundParameters.ContainsKey("Lockafterfailures")) { $body["lockAfterFailures"] = $Lockafterfailures }
        if ($PSBoundParameters.ContainsKey("Lockfailureinterval")) { $body["lockFailureInterval"] = $Lockfailureinterval }
        if ($PSBoundParameters.ContainsKey("Lockouttime")) { $body["lockoutTime"] = $Lockouttime }

        Invoke-HsRequest -Method PUT -Endpoint "/login-policy/${Identifier}" -Body $body
}

function Remove-HsLoginPolicy {
    <#
    .SYNOPSIS
        Delete a login policy
    .DESCRIPTION
        DELETE /login-policy/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/login-policy/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: mailsmtp
# ---------------------------------------------------------------------------

function Get-HsMailsmtp {
    <#
    .SYNOPSIS
        Get SMTP
    .DESCRIPTION
        GET /mail/smtp
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/mail/smtp" -QueryParams $qp
}

function New-HsMailsmtp {
    <#
    .SYNOPSIS
        Add an SMTP gateway which will be used for events and call home through a mail server
    .DESCRIPTION
        Add an SMTP gateway which will be used for events and call home through a mail server
    .NOTES
    CLI equivalent: email-config
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method POST -Endpoint "/mail/smtp" -Body $body
}

function Send-HsMailsmtpTest {
    <#
    .SYNOPSIS
        Test notification
    .DESCRIPTION
        POST /mail/smtp/test/{email}
    .PARAMETER Email
        (Path) email
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Email
    )

        Invoke-HsRequest -Method POST -Endpoint "/mail/smtp/test/${Email}"
}

function Get-HsMailsmtp2 {
    <#
    .SYNOPSIS
        Get SMTP
    .DESCRIPTION
        GET /mail/smtp/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/mail/smtp/${Identifier}"
}

function Set-HsMailsmtp {
    <#
    .SYNOPSIS
        Add an SMTP gateway which will be used for events and call home through a mail server
    .DESCRIPTION
        Add an SMTP gateway which will be used for events and call home through a mail server
    .NOTES
    CLI equivalent: email-config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/mail/smtp/${Identifier}" -Body $body
}

function Remove-HsMailsmtp {
    <#
    .SYNOPSIS
        Delete SMTP
    .DESCRIPTION
        DELETE /mail/smtp/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/mail/smtp/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: mdsis
# ---------------------------------------------------------------------------

function Get-HsMdsi {
    <#
    .SYNOPSIS
        Get all MDSIs
    .DESCRIPTION
        GET /mdsis
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/mdsis" -QueryParams $qp
}

function New-HsMdsi {
    <#
    .SYNOPSIS
        Add MDSI and related MDSI container node
    .DESCRIPTION
        POST /mdsis
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Shares
        (Body) shares
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][hashtable]$Shares
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Shares")) { $body["shares"] = $Shares }

        Invoke-HsRequest -Method POST -Endpoint "/mdsis" -Body $body
}

function Get-HsMdsi2 {
    <#
    .SYNOPSIS
        Get MDSI by ID
    .DESCRIPTION
        GET /mdsis/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/mdsis/${Identifier}"
}

function Remove-HsMdsi {
    <#
    .SYNOPSIS
        Remove MDSI and related MDSI container node if there is one
    .DESCRIPTION
        DELETE /mdsis/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Force
        (Query) force
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Force
    )

        $qp = @{
            "force" = $Force
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/mdsis/${Identifier}" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: metrics
# ---------------------------------------------------------------------------

function Get-HsMetric {
    <#
    .SYNOPSIS
        List metrics
    .DESCRIPTION
        List metrics
    .NOTES
    CLI equivalent: metric-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Start,
        [Parameter()][string]$End,
        [Parameter()][string]$Func,
        [Parameter()][string]$Limit,
        [Parameter()][string]$Groupby,
        [Parameter()][string]$Objecttype,
        [Parameter()][string]$Name,
        [Parameter()][string]$Uuid,
        [Parameter()][string]$Field
    )

        $qp = @{
            "start" = $Start
            "end" = $End
            "func" = $Func
            "limit" = $Limit
            "groupBy" = $Groupby
            "objectType" = $Objecttype
            "name" = $Name
            "uuid" = $Uuid
            "field" = $Field
        }

        Invoke-HsRequest -Method GET -Endpoint "/metrics" -QueryParams $qp
}

function Get-HsMetricCapacity {
    <#
    .SYNOPSIS
        Query influxDB for capacity metrics data
    .DESCRIPTION
        GET /metrics/capacity/{objectType}/{objectUuid}
    .PARAMETER Objecttype
        (Path) objectType
    .PARAMETER Objectuuid
        (Path) objectUuid
    .PARAMETER Precedingduration
        (Query) precedingDuration
    .PARAMETER Intervalduration
        (Query) intervalDuration
    .PARAMETER Includemanageddatausage
        (Query) includeManagedDataUsage
    .PARAMETER Filltype
        (Query) fillType
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Objecttype,
        [Parameter(Mandatory)][string]$Objectuuid,
        [Parameter()][string]$Precedingduration,
        [Parameter()][string]$Intervalduration,
        [Parameter()][string]$Includemanageddatausage,
        [Parameter()][string]$Filltype
    )

        $qp = @{
            "precedingDuration" = $Precedingduration
            "intervalDuration" = $Intervalduration
            "includeManagedDataUsage" = $Includemanageddatausage
            "fillType" = $Filltype
        }

        Invoke-HsRequest -Method GET -Endpoint "/metrics/capacity/${Objecttype}/${Objectuuid}" -QueryParams $qp
}

function Get-HsMetric2 {
    <#
    .SYNOPSIS
        Query metrics through native InfluxDB API
    .DESCRIPTION
        GET /metrics/native
    .PARAMETER Q
        (Query) q
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Q
    )

        $qp = @{
            "q" = $Q
        }

        Invoke-HsRequest -Method GET -Endpoint "/metrics/native" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: modeler
# ---------------------------------------------------------------------------

function Invoke-HsModelerTriggerSweep {
    <#
    .SYNOPSIS
        Query pdfs for tree stats
    .DESCRIPTION
        POST /modeler/tree-stats/trigger-sweep/{share}
    .PARAMETER Share
        (Path) share
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Share
    )

        Invoke-HsRequest -Method POST -Endpoint "/modeler/tree-stats/trigger-sweep/${Share}"
}

function Get-HsModelerTreeStat {
    <#
    .SYNOPSIS
        Get latest tree stats of share
    .DESCRIPTION
        GET /modeler/tree-stats/{share}
    .PARAMETER Share
        (Path) share
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Share
    )

        Invoke-HsRequest -Method GET -Endpoint "/modeler/tree-stats/${Share}"
}

# ---------------------------------------------------------------------------
# SECTION: name-services
# ---------------------------------------------------------------------------

function Get-HsNameService {
    <#
    .SYNOPSIS
        Get all domains configured for use as Name Services
    .DESCRIPTION
        GET /name-services
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/name-services" -QueryParams $qp
}

function New-HsNameService {
    <#
    .SYNOPSIS
        Configure an LDAP domain for use as a Name Service
    .DESCRIPTION
        POST /name-services
    .PARAMETER Skipconnectiontest
        (Query) skipConnectionTest
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Nameservicetype
        (Body) nameServiceType
    .PARAMETER Ordinal
        (Body) ordinal
    .PARAMETER Domain
        (Body) domain
    .PARAMETER Networkendpoints
        (Body) networkEndpoints
    .PARAMETER Ldaptransport
        (Body) ldapTransport
    .PARAMETER Ldapschema
        (Body) ldapSchema
    .PARAMETER Searchbase
        (Body) searchBase
    .PARAMETER Binddn
        (Body) bindDn
    .PARAMETER Bindsecret
        (Body) bindSecret
    .PARAMETER Deobfuscatedsecret
        (Body) deobfuscatedSecret
    .PARAMETER Sssdqueryresult
        (Body) sssdQueryResult
    .PARAMETER Successmessage
        (Body) successMessage
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Skipconnectiontest,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [ValidateSet('AD_JOINED', 'AD_TRUSTED', 'NIS', 'LDAP')]
        [Parameter()][string]$Nameservicetype,
        [Parameter()][int]$Ordinal,
        [Parameter()][string]$Domain,
        [Parameter()][object[]]$Networkendpoints,
        [ValidateSet('STARTTLS', 'LDAPS', 'LDAP')]
        [Parameter()][string]$Ldaptransport,
        [ValidateSet('RFC2307', 'RFC2307BIS', 'AD')]
        [Parameter()][string]$Ldapschema,
        [Parameter()][string]$Searchbase,
        [Parameter()][string]$Binddn,
        [Parameter()][string]$Bindsecret,
        [Parameter()][string]$Deobfuscatedsecret,
        [Parameter()][hashtable]$Sssdqueryresult,
        [Parameter()][string]$Successmessage
    )

        $qp = @{
            "skipConnectionTest" = $Skipconnectiontest
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Nameservicetype")) { $body["nameServiceType"] = $Nameservicetype }
        if ($PSBoundParameters.ContainsKey("Ordinal")) { $body["ordinal"] = $Ordinal }
        if ($PSBoundParameters.ContainsKey("Domain")) { $body["domain"] = $Domain }
        if ($PSBoundParameters.ContainsKey("Networkendpoints")) { $body["networkEndpoints"] = $Networkendpoints }
        if ($PSBoundParameters.ContainsKey("Ldaptransport")) { $body["ldapTransport"] = $Ldaptransport }
        if ($PSBoundParameters.ContainsKey("Ldapschema")) { $body["ldapSchema"] = $Ldapschema }
        if ($PSBoundParameters.ContainsKey("Searchbase")) { $body["searchBase"] = $Searchbase }
        if ($PSBoundParameters.ContainsKey("Binddn")) { $body["bindDn"] = $Binddn }
        if ($PSBoundParameters.ContainsKey("Bindsecret")) { $body["bindSecret"] = $Bindsecret }
        if ($PSBoundParameters.ContainsKey("Deobfuscatedsecret")) { $body["deobfuscatedSecret"] = $Deobfuscatedsecret }
        if ($PSBoundParameters.ContainsKey("Sssdqueryresult")) { $body["sssdQueryResult"] = $Sssdqueryresult }
        if ($PSBoundParameters.ContainsKey("Successmessage")) { $body["successMessage"] = $Successmessage }

        Invoke-HsRequest -Method POST -Endpoint "/name-services" -QueryParams $qp -Body $body
}

function Test-HsNameServiceConnectiontest {
    <#
    .SYNOPSIS
        Test connectivity to a Name Service (does not need to be configured, can be a pre-add check)
    .DESCRIPTION
        POST /name-services/connectionTest
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method POST -Endpoint "/name-services/connectionTest"
}

function Set-HsNameServiceReorder {
    <#
    .SYNOPSIS
        Change the resolution order of configured Name Services
    .DESCRIPTION
        PUT /name-services/reorder
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method PUT -Endpoint "/name-services/reorder"
}

function Get-HsNameServiceResolvegroup {
    <#
    .SYNOPSIS
        Attempt to resolve a group name against configured Name Services
    .DESCRIPTION
        GET /name-services/resolveGroup
    .PARAMETER GroupIdentifier
        (Query) group-identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$GroupIdentifier
    )

        $qp = @{
            "group-identifier" = $GroupIdentifier
        }

        Invoke-HsRequest -Method GET -Endpoint "/name-services/resolveGroup" -QueryParams $qp
}

function Get-HsNameServiceResolveuser {
    <#
    .SYNOPSIS
        Attempt to resolve a user name against configured Name Services
    .DESCRIPTION
        GET /name-services/resolveUser
    .PARAMETER UserIdentifier
        (Query) user-identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$UserIdentifier
    )

        $qp = @{
            "user-identifier" = $UserIdentifier
        }

        Invoke-HsRequest -Method GET -Endpoint "/name-services/resolveUser" -QueryParams $qp
}

function Get-HsNameServiceResolveusergroup {
    <#
    .SYNOPSIS
        Attempt to resolve a user's groups against configured Name Services
    .DESCRIPTION
        GET /name-services/resolveUserGroups
    .PARAMETER UserGroupsIdentifier
        (Query) user-groups-identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$UserGroupsIdentifier
    )

        $qp = @{
            "user-groups-identifier" = $UserGroupsIdentifier
        }

        Invoke-HsRequest -Method GET -Endpoint "/name-services/resolveUserGroups" -QueryParams $qp
}

function Get-HsNameService2 {
    <#
    .SYNOPSIS
        Get a domain configured for use as a Name Service by identifier
    .DESCRIPTION
        GET /name-services/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/name-services/${Identifier}"
}

function Set-HsNameService {
    <#
    .SYNOPSIS
        Update an LDAP domain configured for Name Services
    .DESCRIPTION
        PUT /name-services/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Skipconnectiontest
        (Query) skipConnectionTest
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Nameservicetype
        (Body) nameServiceType
    .PARAMETER Ordinal
        (Body) ordinal
    .PARAMETER Domain
        (Body) domain
    .PARAMETER Networkendpoints
        (Body) networkEndpoints
    .PARAMETER Ldaptransport
        (Body) ldapTransport
    .PARAMETER Ldapschema
        (Body) ldapSchema
    .PARAMETER Searchbase
        (Body) searchBase
    .PARAMETER Binddn
        (Body) bindDn
    .PARAMETER Bindsecret
        (Body) bindSecret
    .PARAMETER Deobfuscatedsecret
        (Body) deobfuscatedSecret
    .PARAMETER Sssdqueryresult
        (Body) sssdQueryResult
    .PARAMETER Successmessage
        (Body) successMessage
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Skipconnectiontest,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [ValidateSet('AD_JOINED', 'AD_TRUSTED', 'NIS', 'LDAP')]
        [Parameter()][string]$Nameservicetype,
        [Parameter()][int]$Ordinal,
        [Parameter()][string]$Domain,
        [Parameter()][object[]]$Networkendpoints,
        [ValidateSet('STARTTLS', 'LDAPS', 'LDAP')]
        [Parameter()][string]$Ldaptransport,
        [ValidateSet('RFC2307', 'RFC2307BIS', 'AD')]
        [Parameter()][string]$Ldapschema,
        [Parameter()][string]$Searchbase,
        [Parameter()][string]$Binddn,
        [Parameter()][string]$Bindsecret,
        [Parameter()][string]$Deobfuscatedsecret,
        [Parameter()][hashtable]$Sssdqueryresult,
        [Parameter()][string]$Successmessage
    )

        $qp = @{
            "skipConnectionTest" = $Skipconnectiontest
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Nameservicetype")) { $body["nameServiceType"] = $Nameservicetype }
        if ($PSBoundParameters.ContainsKey("Ordinal")) { $body["ordinal"] = $Ordinal }
        if ($PSBoundParameters.ContainsKey("Domain")) { $body["domain"] = $Domain }
        if ($PSBoundParameters.ContainsKey("Networkendpoints")) { $body["networkEndpoints"] = $Networkendpoints }
        if ($PSBoundParameters.ContainsKey("Ldaptransport")) { $body["ldapTransport"] = $Ldaptransport }
        if ($PSBoundParameters.ContainsKey("Ldapschema")) { $body["ldapSchema"] = $Ldapschema }
        if ($PSBoundParameters.ContainsKey("Searchbase")) { $body["searchBase"] = $Searchbase }
        if ($PSBoundParameters.ContainsKey("Binddn")) { $body["bindDn"] = $Binddn }
        if ($PSBoundParameters.ContainsKey("Bindsecret")) { $body["bindSecret"] = $Bindsecret }
        if ($PSBoundParameters.ContainsKey("Deobfuscatedsecret")) { $body["deobfuscatedSecret"] = $Deobfuscatedsecret }
        if ($PSBoundParameters.ContainsKey("Sssdqueryresult")) { $body["sssdQueryResult"] = $Sssdqueryresult }
        if ($PSBoundParameters.ContainsKey("Successmessage")) { $body["successMessage"] = $Successmessage }

        Invoke-HsRequest -Method PUT -Endpoint "/name-services/${Identifier}" -QueryParams $qp -Body $body
}

function Remove-HsNameService {
    <#
    .SYNOPSIS
        Remove an LDAP domain from the Name Services configuration
    .DESCRIPTION
        DELETE /name-services/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/name-services/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: network-interfaces
# ---------------------------------------------------------------------------

function Get-HsNetworkInterface {
    <#
    .SYNOPSIS
        List network interfaces
    .DESCRIPTION
        List network interfaces
    .NOTES
    CLI equivalent: interface-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/network-interfaces" -QueryParams $qp
}

function Get-HsNetworkInterface2 {
    <#
    .SYNOPSIS
        Get network interface by node and name
    .DESCRIPTION
        GET /network-interfaces/resolve
    .PARAMETER Node
        (Query) node
    .PARAMETER Ifname
        (Query) ifName
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Node,
        [Parameter()][string]$Ifname
    )

        $qp = @{
            "node" = $Node
            "ifName" = $Ifname
        }

        Invoke-HsRequest -Method GET -Endpoint "/network-interfaces/resolve" -QueryParams $qp
}

function Get-HsNetworkInterface3 {
    <#
    .SYNOPSIS
        Get network interface by ID
    .DESCRIPTION
        GET /network-interfaces/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/network-interfaces/${Identifier}"
}

function New-HsNetworkInterface {
    <#
    .SYNOPSIS
        Create virtual network interface
    .DESCRIPTION
        Create virtual network interface. Add new floating IP address (cluster or portal)
    .NOTES
    CLI equivalent: interface-create, floating-ip-add
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][hashtable]$Supportedbyhw,
        [Parameter()][hashtable]$Supportedbyservices,
        [ValidateSet('UNKNOWN', 'INITIALIZING', 'RUNNING', 'FAILED', 'STOPPED')]
        [Parameter()][string]$Servicestate,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][hashtable]$Capacity,
        [Parameter()][switch]$Reserved,
        [Parameter()][string]$Clientcert,
        [Parameter()][switch]$Shared,
        [Parameter()][hashtable]$Discoveryinfo,
        [Parameter()][int]$Vlanid,
        [Parameter()][object[]]$Ipaddresses,
        [Parameter()][string]$Macaddress,
        [Parameter()][switch]$Dhcp,
        [Parameter()][int]$Linkspeed,
        [Parameter()][switch]$Rdmaavailable,
        [Parameter()][int]$Flags,
        [Parameter()][int]$Mtu,
        [Parameter()][object[]]$Roles,
        [ValidateSet('HALF', 'FULL')]
        [Parameter()][string]$Duplex
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Supportedbyhw")) { $body["supportedByHw"] = $Supportedbyhw }
        if ($PSBoundParameters.ContainsKey("Supportedbyservices")) { $body["supportedByServices"] = $Supportedbyservices }
        if ($PSBoundParameters.ContainsKey("Servicestate")) { $body["serviceState"] = $Servicestate }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Capacity")) { $body["capacity"] = $Capacity }
        $body["reserved"] = $Reserved.IsPresent
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        $body["shared"] = $Shared.IsPresent
        if ($PSBoundParameters.ContainsKey("Discoveryinfo")) { $body["discoveryInfo"] = $Discoveryinfo }
        if ($PSBoundParameters.ContainsKey("Vlanid")) { $body["vlanId"] = $Vlanid }
        if ($PSBoundParameters.ContainsKey("Ipaddresses")) { $body["ipAddresses"] = $Ipaddresses }
        if ($PSBoundParameters.ContainsKey("Macaddress")) { $body["macAddress"] = $Macaddress }
        $body["dhcp"] = $Dhcp.IsPresent
        if ($PSBoundParameters.ContainsKey("Linkspeed")) { $body["linkSpeed"] = $Linkspeed }
        $body["rdmaAvailable"] = $Rdmaavailable.IsPresent
        if ($PSBoundParameters.ContainsKey("Flags")) { $body["flags"] = $Flags }
        if ($PSBoundParameters.ContainsKey("Mtu")) { $body["mtu"] = $Mtu }
        if ($PSBoundParameters.ContainsKey("Roles")) { $body["roles"] = $Roles }
        if ($PSBoundParameters.ContainsKey("Duplex")) { $body["duplex"] = $Duplex }

        Invoke-HsRequest -Method POST -Endpoint "/network-interfaces/${Identifier}" -Body $body
}

function Set-HsNetworkInterface {
    <#
    .SYNOPSIS
        Update physical/virtual network interface
    .DESCRIPTION
        Update physical/virtual network interface
    .NOTES
    CLI equivalent: interface-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Overridedatacheck,
        [Parameter()][string]$Overrideipcheck,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][hashtable]$Supportedbyhw,
        [Parameter()][hashtable]$Supportedbyservices,
        [ValidateSet('UNKNOWN', 'INITIALIZING', 'RUNNING', 'FAILED', 'STOPPED')]
        [Parameter()][string]$Servicestate,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][hashtable]$Capacity,
        [Parameter()][switch]$Reserved,
        [Parameter()][string]$Clientcert,
        [Parameter()][switch]$Shared,
        [Parameter()][hashtable]$Discoveryinfo,
        [Parameter()][int]$Vlanid,
        [Parameter()][object[]]$Ipaddresses,
        [Parameter()][string]$Macaddress,
        [Parameter()][switch]$Dhcp,
        [Parameter()][int]$Linkspeed,
        [Parameter()][switch]$Rdmaavailable,
        [Parameter()][int]$Flags,
        [Parameter()][int]$Mtu,
        [Parameter()][object[]]$Roles,
        [ValidateSet('HALF', 'FULL')]
        [Parameter()][string]$Duplex
    )

        $qp = @{
            "overrideDataCheck" = $Overridedatacheck
            "overrideIpCheck" = $Overrideipcheck
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Supportedbyhw")) { $body["supportedByHw"] = $Supportedbyhw }
        if ($PSBoundParameters.ContainsKey("Supportedbyservices")) { $body["supportedByServices"] = $Supportedbyservices }
        if ($PSBoundParameters.ContainsKey("Servicestate")) { $body["serviceState"] = $Servicestate }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Capacity")) { $body["capacity"] = $Capacity }
        $body["reserved"] = $Reserved.IsPresent
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        $body["shared"] = $Shared.IsPresent
        if ($PSBoundParameters.ContainsKey("Discoveryinfo")) { $body["discoveryInfo"] = $Discoveryinfo }
        if ($PSBoundParameters.ContainsKey("Vlanid")) { $body["vlanId"] = $Vlanid }
        if ($PSBoundParameters.ContainsKey("Ipaddresses")) { $body["ipAddresses"] = $Ipaddresses }
        if ($PSBoundParameters.ContainsKey("Macaddress")) { $body["macAddress"] = $Macaddress }
        $body["dhcp"] = $Dhcp.IsPresent
        if ($PSBoundParameters.ContainsKey("Linkspeed")) { $body["linkSpeed"] = $Linkspeed }
        $body["rdmaAvailable"] = $Rdmaavailable.IsPresent
        if ($PSBoundParameters.ContainsKey("Flags")) { $body["flags"] = $Flags }
        if ($PSBoundParameters.ContainsKey("Mtu")) { $body["mtu"] = $Mtu }
        if ($PSBoundParameters.ContainsKey("Roles")) { $body["roles"] = $Roles }
        if ($PSBoundParameters.ContainsKey("Duplex")) { $body["duplex"] = $Duplex }

        Invoke-HsRequest -Method PUT -Endpoint "/network-interfaces/${Identifier}" -QueryParams $qp -Body $body
}

function Remove-HsNetworkInterface {
    <#
    .SYNOPSIS
        Delete virtual network interface
    .DESCRIPTION
        Delete virtual network interface. Remove existing floating IP address (cluster or portal)
    .NOTES
    CLI equivalent: interface-delete, floating-ip-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/network-interfaces/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: nfs-clients
# ---------------------------------------------------------------------------

function Get-HsNfsClient {
    <#
    .SYNOPSIS
        List all NFS clients
    .DESCRIPTION
        GET /nfs-clients
    .PARAMETER Protocol
        (Query) protocol
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Protocol
    )

        $qp = @{
            "protocol" = $Protocol
        }

        Invoke-HsRequest -Method GET -Endpoint "/nfs-clients" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: nis
# ---------------------------------------------------------------------------

function Get-HsNis {
    <#
    .SYNOPSIS
        Get NIS configuration
    .DESCRIPTION
        GET /nis
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/nis" -QueryParams $qp
}

function Get-HsNis2 {
    <#
    .SYNOPSIS
        Get NIS configuration by ID
    .DESCRIPTION
        GET /nis/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/nis/${Identifier}"
}

function Set-HsNis {
    <#
    .SYNOPSIS
        Configure NIS servers
    .DESCRIPTION
        Configure NIS servers
    .NOTES
    CLI equivalent: nis-config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/nis/${Identifier}" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: nodes
# ---------------------------------------------------------------------------

function Get-HsNode {
    <#
    .SYNOPSIS
        List all nodes in the system
    .DESCRIPTION
        List all nodes in the system
    .NOTES
    CLI equivalent: node-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/nodes" -QueryParams $qp
}

function New-HsNode {
    <#
    .SYNOPSIS
        Create a node in the system
    .DESCRIPTION
        Create a node in the system
    .NOTES
    CLI equivalent: node-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Createplacementobjectives,
        [Parameter()][string]$Ignoreipconflicts,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [ValidateSet('UNKNOWN', 'OK', 'WARN', 'CRITICAL', 'FAILED')]
        [Parameter()][string]$Hwcomponentstate,
        [Parameter()][hashtable]$Vpd,
        [Parameter()][object[]]$Hwcomponents,
        [Parameter()][object[]]$Systemservices,
        [Parameter()][object[]]$Platformservices,
        [ValidateSet('UNAUTHENTICATED', 'AUTHENTICATED', 'FAILED_AUTHENTICATION', 'FAILED_SETUP', 'MANAGED', 'FAILED_DISCOVERY', 'MOUNTED', 'FAILED_ACCESS', 'CONFIGURED')]
        [Parameter()][string]$Nodestate,
        [ValidateSet('PD', 'NETAPP_CMODE', 'NETAPP_7MODE', 'NETAPP_CLOUD', 'EMC_ISILON', 'EMC_VNX', 'EMC_UNITY', 'GOOGLE_CLOUD_FILESTORE', 'QUMULO', 'RCLONE', 'HNAS', 'ROZOFS', 'ROZOFS_HS', 'SOFTNAS_CLOUD', 'WINDOWS_FILE_SERVER', 'DELL_ENAS', 'PURE_FB', 'VAST', 'WEKA', 'NETAPP_FSX', 'AMAZON_S3', 'ACTIVE_SCALE_S3', 'IBM_S3', 'CLOUDIAN_S3', 'ECS_S3', 'GENERIC_S3', 'GOOGLE_S3', 'SCALITY_S3', 'STORAGE_GRID_S3', 'SWIFT', 'AZURE', 'GOOGLE_CLOUD', 'HCP_S3', 'ATMOS', 'WASABI_S3', 'NETAPP_S3', 'MCAFEE_AV', 'CLAM_AV', 'SNOWFLAKE', 'INTERNAL_S3', 'PURE_FB_S3', 'SEAGATE_LYVE_S3', 'CARINGO_SWARM_S3', 'ISILON_S3', 'BACKBLAZE_S3', 'HAMMERSPACE_S3', 'STORJ_S3', 'OTHER', 'MOVER_EXT')]
        [Parameter()][string]$Nodetype,
        [ValidateSet('ONLINE', 'OFFLINE', 'MAINTENANCE', 'DISABLED', 'UPDATE')]
        [Parameter()][string]$Nodemode,
        [Parameter()][string]$Nodemodereason,
        [Parameter()][hashtable]$Mgmtipaddress,
        [Parameter()][hashtable]$Mgmtnodecredentials,
        [Parameter()][string]$Endpoint,
        [Parameter()][switch]$Trustcertificate,
        [Parameter()][switch]$Usevirtualhostnaming,
        [ValidateSet('S3_DEFAULT_SIGNING', 'S3_V4_SIGNING')]
        [Parameter()][string]$S3signingtype,
        [Parameter()][string]$Projectname,
        [Parameter()][hashtable]$Proxyinfo,
        [Parameter()][hashtable]$Physicallocation,
        [Parameter()][hashtable]$Swversion,
        [Parameter()][object[]]$Applicableversions,
        [ValidateSet('NONE', 'OBJECT', 'FILE', 'ANTIVIRUS')]
        [Parameter()][string]$Orchestrationsystemtype,
        [Parameter()][hashtable]$Gateway,
        [Parameter()][int]$Boottime,
        [Parameter()][string]$Conditions,
        [Parameter()][string]$Driverselector,
        [ValidateSet('ANVIL', 'DSX', 'MDSI_CONTAINER')]
        [Parameter()][string]$Productnodetype,
        [Parameter()][object[]]$Managedcertificates,
        [Parameter()][string]$Blockdeviceinfo,
        [Parameter()][string]$Nvmeofhostnqn
    )

        $qp = @{
            "createPlacementObjectives" = $Createplacementobjectives
            "ignoreIpConflicts" = $Ignoreipconflicts
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Hwcomponentstate")) { $body["hwComponentState"] = $Hwcomponentstate }
        if ($PSBoundParameters.ContainsKey("Vpd")) { $body["vpd"] = $Vpd }
        if ($PSBoundParameters.ContainsKey("Hwcomponents")) { $body["hwComponents"] = $Hwcomponents }
        if ($PSBoundParameters.ContainsKey("Systemservices")) { $body["systemServices"] = $Systemservices }
        if ($PSBoundParameters.ContainsKey("Platformservices")) { $body["platformServices"] = $Platformservices }
        if ($PSBoundParameters.ContainsKey("Nodestate")) { $body["nodeState"] = $Nodestate }
        if ($PSBoundParameters.ContainsKey("Nodetype")) { $body["nodeType"] = $Nodetype }
        if ($PSBoundParameters.ContainsKey("Nodemode")) { $body["nodeMode"] = $Nodemode }
        if ($PSBoundParameters.ContainsKey("Nodemodereason")) { $body["nodeModeReason"] = $Nodemodereason }
        if ($PSBoundParameters.ContainsKey("Mgmtipaddress")) { $body["mgmtIpAddress"] = $Mgmtipaddress }
        if ($PSBoundParameters.ContainsKey("Mgmtnodecredentials")) { $body["mgmtNodeCredentials"] = $Mgmtnodecredentials }
        if ($PSBoundParameters.ContainsKey("Endpoint")) { $body["endpoint"] = $Endpoint }
        $body["trustCertificate"] = $Trustcertificate.IsPresent
        $body["useVirtualHostNaming"] = $Usevirtualhostnaming.IsPresent
        if ($PSBoundParameters.ContainsKey("S3signingtype")) { $body["s3SigningType"] = $S3signingtype }
        if ($PSBoundParameters.ContainsKey("Projectname")) { $body["projectName"] = $Projectname }
        if ($PSBoundParameters.ContainsKey("Proxyinfo")) { $body["proxyInfo"] = $Proxyinfo }
        if ($PSBoundParameters.ContainsKey("Physicallocation")) { $body["physicalLocation"] = $Physicallocation }
        if ($PSBoundParameters.ContainsKey("Swversion")) { $body["swVersion"] = $Swversion }
        if ($PSBoundParameters.ContainsKey("Applicableversions")) { $body["applicableVersions"] = $Applicableversions }
        if ($PSBoundParameters.ContainsKey("Orchestrationsystemtype")) { $body["orchestrationSystemType"] = $Orchestrationsystemtype }
        if ($PSBoundParameters.ContainsKey("Gateway")) { $body["gateway"] = $Gateway }
        if ($PSBoundParameters.ContainsKey("Boottime")) { $body["bootTime"] = $Boottime }
        if ($PSBoundParameters.ContainsKey("Conditions")) { $body["conditions"] = $Conditions }
        if ($PSBoundParameters.ContainsKey("Driverselector")) { $body["driverSelector"] = $Driverselector }
        if ($PSBoundParameters.ContainsKey("Productnodetype")) { $body["productNodeType"] = $Productnodetype }
        if ($PSBoundParameters.ContainsKey("Managedcertificates")) { $body["managedCertificates"] = $Managedcertificates }
        if ($PSBoundParameters.ContainsKey("Blockdeviceinfo")) { $body["blockDeviceInfo"] = $Blockdeviceinfo }
        if ($PSBoundParameters.ContainsKey("Nvmeofhostnqn")) { $body["nvmeOfHostNqn"] = $Nvmeofhostnqn }

        Invoke-HsRequest -Method POST -Endpoint "/nodes" -QueryParams $qp -Body $body
}

function Get-HsNode2 {
    <#
    .SYNOPSIS
        Get all nodes filtered by relation to other entity
    .DESCRIPTION
        GET /nodes/related-list
    .PARAMETER Filteruuid
        (Query) filterUuid
    .PARAMETER Filterobjecttype
        (Query) filterObjectType
    .PARAMETER Sort
        (Query) sort
    .PARAMETER Terse
        (Query) terse
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Filteruuid,
        [Parameter()][string]$Filterobjecttype,
        [Parameter()][string]$Sort,
        [Parameter()][string]$Terse,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "filterUuid" = $Filteruuid
            "filterObjectType" = $Filterobjecttype
            "sort" = $Sort
            "terse" = $Terse
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/nodes/related-list" -QueryParams $qp
}

function Get-HsNodeUnauthenticated {
    <#
    .SYNOPSIS
        Get unauthenticated nodes
    .DESCRIPTION
        GET /nodes/unauthenticated
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/nodes/unauthenticated"
}

function Get-HsNode3 {
    <#
    .SYNOPSIS
        Get node by ID
    .DESCRIPTION
        GET /nodes/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Blockdeviceinfo
        (Query) blockDeviceInfo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Blockdeviceinfo
    )

        $qp = @{
            "blockDeviceInfo" = $Blockdeviceinfo
        }

        Invoke-HsRequest -Method GET -Endpoint "/nodes/${Identifier}" -QueryParams $qp
}

function Set-HsNode {
    <#
    .SYNOPSIS
        Update a node in the system
    .DESCRIPTION
        Update a node in the system
    .NOTES
    CLI equivalent: node-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Skipobjectvolumevalidations,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [ValidateSet('UNKNOWN', 'OK', 'WARN', 'CRITICAL', 'FAILED')]
        [Parameter()][string]$Hwcomponentstate,
        [Parameter()][hashtable]$Vpd,
        [Parameter()][object[]]$Hwcomponents,
        [Parameter()][object[]]$Systemservices,
        [Parameter()][object[]]$Platformservices,
        [ValidateSet('UNAUTHENTICATED', 'AUTHENTICATED', 'FAILED_AUTHENTICATION', 'FAILED_SETUP', 'MANAGED', 'FAILED_DISCOVERY', 'MOUNTED', 'FAILED_ACCESS', 'CONFIGURED')]
        [Parameter()][string]$Nodestate,
        [ValidateSet('PD', 'NETAPP_CMODE', 'NETAPP_7MODE', 'NETAPP_CLOUD', 'EMC_ISILON', 'EMC_VNX', 'EMC_UNITY', 'GOOGLE_CLOUD_FILESTORE', 'QUMULO', 'RCLONE', 'HNAS', 'ROZOFS', 'ROZOFS_HS', 'SOFTNAS_CLOUD', 'WINDOWS_FILE_SERVER', 'DELL_ENAS', 'PURE_FB', 'VAST', 'WEKA', 'NETAPP_FSX', 'AMAZON_S3', 'ACTIVE_SCALE_S3', 'IBM_S3', 'CLOUDIAN_S3', 'ECS_S3', 'GENERIC_S3', 'GOOGLE_S3', 'SCALITY_S3', 'STORAGE_GRID_S3', 'SWIFT', 'AZURE', 'GOOGLE_CLOUD', 'HCP_S3', 'ATMOS', 'WASABI_S3', 'NETAPP_S3', 'MCAFEE_AV', 'CLAM_AV', 'SNOWFLAKE', 'INTERNAL_S3', 'PURE_FB_S3', 'SEAGATE_LYVE_S3', 'CARINGO_SWARM_S3', 'ISILON_S3', 'BACKBLAZE_S3', 'HAMMERSPACE_S3', 'STORJ_S3', 'OTHER', 'MOVER_EXT')]
        [Parameter()][string]$Nodetype,
        [ValidateSet('ONLINE', 'OFFLINE', 'MAINTENANCE', 'DISABLED', 'UPDATE')]
        [Parameter()][string]$Nodemode,
        [Parameter()][string]$Nodemodereason,
        [Parameter()][hashtable]$Mgmtipaddress,
        [Parameter()][hashtable]$Mgmtnodecredentials,
        [Parameter()][string]$Endpoint,
        [Parameter()][switch]$Trustcertificate,
        [Parameter()][switch]$Usevirtualhostnaming,
        [ValidateSet('S3_DEFAULT_SIGNING', 'S3_V4_SIGNING')]
        [Parameter()][string]$S3signingtype,
        [Parameter()][string]$Projectname,
        [Parameter()][hashtable]$Proxyinfo,
        [Parameter()][hashtable]$Physicallocation,
        [Parameter()][hashtable]$Swversion,
        [Parameter()][object[]]$Applicableversions,
        [ValidateSet('NONE', 'OBJECT', 'FILE', 'ANTIVIRUS')]
        [Parameter()][string]$Orchestrationsystemtype,
        [Parameter()][hashtable]$Gateway,
        [Parameter()][int]$Boottime,
        [Parameter()][string]$Conditions,
        [Parameter()][string]$Driverselector,
        [ValidateSet('ANVIL', 'DSX', 'MDSI_CONTAINER')]
        [Parameter()][string]$Productnodetype,
        [Parameter()][object[]]$Managedcertificates,
        [Parameter()][string]$Blockdeviceinfo,
        [Parameter()][string]$Nvmeofhostnqn
    )

        $qp = @{
            "skipObjectVolumeValidations" = $Skipobjectvolumevalidations
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Hwcomponentstate")) { $body["hwComponentState"] = $Hwcomponentstate }
        if ($PSBoundParameters.ContainsKey("Vpd")) { $body["vpd"] = $Vpd }
        if ($PSBoundParameters.ContainsKey("Hwcomponents")) { $body["hwComponents"] = $Hwcomponents }
        if ($PSBoundParameters.ContainsKey("Systemservices")) { $body["systemServices"] = $Systemservices }
        if ($PSBoundParameters.ContainsKey("Platformservices")) { $body["platformServices"] = $Platformservices }
        if ($PSBoundParameters.ContainsKey("Nodestate")) { $body["nodeState"] = $Nodestate }
        if ($PSBoundParameters.ContainsKey("Nodetype")) { $body["nodeType"] = $Nodetype }
        if ($PSBoundParameters.ContainsKey("Nodemode")) { $body["nodeMode"] = $Nodemode }
        if ($PSBoundParameters.ContainsKey("Nodemodereason")) { $body["nodeModeReason"] = $Nodemodereason }
        if ($PSBoundParameters.ContainsKey("Mgmtipaddress")) { $body["mgmtIpAddress"] = $Mgmtipaddress }
        if ($PSBoundParameters.ContainsKey("Mgmtnodecredentials")) { $body["mgmtNodeCredentials"] = $Mgmtnodecredentials }
        if ($PSBoundParameters.ContainsKey("Endpoint")) { $body["endpoint"] = $Endpoint }
        $body["trustCertificate"] = $Trustcertificate.IsPresent
        $body["useVirtualHostNaming"] = $Usevirtualhostnaming.IsPresent
        if ($PSBoundParameters.ContainsKey("S3signingtype")) { $body["s3SigningType"] = $S3signingtype }
        if ($PSBoundParameters.ContainsKey("Projectname")) { $body["projectName"] = $Projectname }
        if ($PSBoundParameters.ContainsKey("Proxyinfo")) { $body["proxyInfo"] = $Proxyinfo }
        if ($PSBoundParameters.ContainsKey("Physicallocation")) { $body["physicalLocation"] = $Physicallocation }
        if ($PSBoundParameters.ContainsKey("Swversion")) { $body["swVersion"] = $Swversion }
        if ($PSBoundParameters.ContainsKey("Applicableversions")) { $body["applicableVersions"] = $Applicableversions }
        if ($PSBoundParameters.ContainsKey("Orchestrationsystemtype")) { $body["orchestrationSystemType"] = $Orchestrationsystemtype }
        if ($PSBoundParameters.ContainsKey("Gateway")) { $body["gateway"] = $Gateway }
        if ($PSBoundParameters.ContainsKey("Boottime")) { $body["bootTime"] = $Boottime }
        if ($PSBoundParameters.ContainsKey("Conditions")) { $body["conditions"] = $Conditions }
        if ($PSBoundParameters.ContainsKey("Driverselector")) { $body["driverSelector"] = $Driverselector }
        if ($PSBoundParameters.ContainsKey("Productnodetype")) { $body["productNodeType"] = $Productnodetype }
        if ($PSBoundParameters.ContainsKey("Managedcertificates")) { $body["managedCertificates"] = $Managedcertificates }
        if ($PSBoundParameters.ContainsKey("Blockdeviceinfo")) { $body["blockDeviceInfo"] = $Blockdeviceinfo }
        if ($PSBoundParameters.ContainsKey("Nvmeofhostnqn")) { $body["nvmeOfHostNqn"] = $Nvmeofhostnqn }

        Invoke-HsRequest -Method PUT -Endpoint "/nodes/${Identifier}" -QueryParams $qp -Body $body
}

function Remove-HsNode {
    <#
    .SYNOPSIS
        Remove a node from the system. A node that contains system services cannot be removed
    .DESCRIPTION
        Remove a node from the system. A node that contains system services cannot be removed
    .NOTES
    CLI equivalent: node-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Force
    )

        $qp = @{
            "force" = $Force
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/nodes/${Identifier}" -QueryParams $qp
}

function Invoke-HsNode {
    <#
    .SYNOPSIS
        Refresh node
    .DESCRIPTION
        POST /nodes/{identifier}/refresh
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Rescan
        (Query) rescan
    .PARAMETER Reconcilecomponents
        (Query) reconcileComponents
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Rescan,
        [Parameter()][string]$Reconcilecomponents
    )

        $qp = @{
            "rescan" = $Rescan
            "reconcileComponents" = $Reconcilecomponents
        }

        Invoke-HsRequest -Method POST -Endpoint "/nodes/${Identifier}/refresh" -QueryParams $qp
}

function Set-HsNodeSetMode {
    <#
    .SYNOPSIS
        Modify node’s mode
    .DESCRIPTION
        Modify node’s mode
    .NOTES
    CLI equivalent: node-mode-change
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter(Mandatory)][string]$Mode
    )

        Invoke-HsRequest -Method POST -Endpoint "/nodes/${Identifier}/set-mode/${Mode}"
}

# ---------------------------------------------------------------------------
# SECTION: notification-rules
# ---------------------------------------------------------------------------

function Get-HsNotificationRule {
    <#
    .SYNOPSIS
        List notification rules
    .DESCRIPTION
        List notification rules
    .NOTES
    CLI equivalent: notification-rule-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/notification-rules" -QueryParams $qp
}

function New-HsNotificationRule {
    <#
    .SYNOPSIS
        Create a notification rule
    .DESCRIPTION
        Create a notification rule
    .NOTES
    CLI equivalent: notification-rule-create
    WARNING: Possible values: DEBUG | INFORMATIONAL | NOTICE | WARNING | ERROR |
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [ValidateSet('DEBUG', 'INFORMATIONAL', 'NOTICE', 'WARNING', 'ERROR', 'CRITICAL', 'ALERT', 'EMERGENCY')]
        [Parameter()][string]$Threshold,
        [Parameter()][hashtable]$Users,
        [ValidateSet('PLAIN', 'XML')]
        [Parameter()][string]$Format,
        [Parameter()][switch]$Collectlogs,
        [Parameter()][string]$Uri
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Threshold")) { $body["threshold"] = $Threshold }
        if ($PSBoundParameters.ContainsKey("Users")) { $body["users"] = $Users }
        if ($PSBoundParameters.ContainsKey("Format")) { $body["format"] = $Format }
        $body["collectLogs"] = $Collectlogs.IsPresent
        if ($PSBoundParameters.ContainsKey("Uri")) { $body["uri"] = $Uri }

        Invoke-HsRequest -Method POST -Endpoint "/notification-rules" -Body $body
}

function Get-HsNotificationRule2 {
    <#
    .SYNOPSIS
        Get notification rule
    .DESCRIPTION
        GET /notification-rules/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/notification-rules/${Identifier}"
}

function Set-HsNotificationRule {
    <#
    .SYNOPSIS
        Update a notification rule
    .DESCRIPTION
        Update a notification rule
    .NOTES
    CLI equivalent: notification-rule-update
    WARNING: Possible values: DEBUG | INFORMATIONAL | NOTICE | WARNING | ERROR |
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [ValidateSet('DEBUG', 'INFORMATIONAL', 'NOTICE', 'WARNING', 'ERROR', 'CRITICAL', 'ALERT', 'EMERGENCY')]
        [Parameter()][string]$Threshold,
        [Parameter()][hashtable]$Users,
        [ValidateSet('PLAIN', 'XML')]
        [Parameter()][string]$Format,
        [Parameter()][switch]$Collectlogs,
        [Parameter()][string]$Uri
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Threshold")) { $body["threshold"] = $Threshold }
        if ($PSBoundParameters.ContainsKey("Users")) { $body["users"] = $Users }
        if ($PSBoundParameters.ContainsKey("Format")) { $body["format"] = $Format }
        $body["collectLogs"] = $Collectlogs.IsPresent
        if ($PSBoundParameters.ContainsKey("Uri")) { $body["uri"] = $Uri }

        Invoke-HsRequest -Method PUT -Endpoint "/notification-rules/${Identifier}" -Body $body
}

function Remove-HsNotificationRule {
    <#
    .SYNOPSIS
        Remove a notification rule
    .DESCRIPTION
        Remove a notification rule
    .NOTES
    CLI equivalent: notification-rule-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/notification-rules/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: ntps
# ---------------------------------------------------------------------------

function Get-HsNtp {
    <#
    .SYNOPSIS
        Get NTP
    .DESCRIPTION
        GET /ntps
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/ntps" -QueryParams $qp
}

function Get-HsNtp2 {
    <#
    .SYNOPSIS
        Get NTP
    .DESCRIPTION
        GET /ntps/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/ntps/${Identifier}"
}

function Set-HsNtp {
    <#
    .SYNOPSIS
        Configure NTP
    .DESCRIPTION
        Configure NTP
    .NOTES
    CLI equivalent: ntp-config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][hashtable]$Ipv4,
        [Parameter()][hashtable]$Ipv6,
        [Parameter()][string]$Nodename,
        [Parameter()][object[]]$Servers
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Ipv4")) { $body["ipv4"] = $Ipv4 }
        if ($PSBoundParameters.ContainsKey("Ipv6")) { $body["ipv6"] = $Ipv6 }
        if ($PSBoundParameters.ContainsKey("Nodename")) { $body["nodeName"] = $Nodename }
        if ($PSBoundParameters.ContainsKey("Servers")) { $body["servers"] = $Servers }

        Invoke-HsRequest -Method PUT -Endpoint "/ntps/${Identifier}" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: nvmeof-enclosures
# ---------------------------------------------------------------------------

function Get-HsNvmeofEnclosure {
    <#
    .SYNOPSIS
        List all NVMe-oF enclosures
    .DESCRIPTION
        GET /nvmeof-enclosures
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/nvmeof-enclosures"
}

function New-HsNvmeofEnclosure {
    <#
    .SYNOPSIS
        nvmeof-config [option]
    .DESCRIPTION
        nvmeof-config [option]
    .NOTES
    CLI equivalent: nvmeof-config
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Dryrun,
        [Parameter()][string]$Connectall,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][hashtable]$Supportedbyhw,
        [Parameter()][hashtable]$Supportedbyservices,
        [ValidateSet('UNKNOWN', 'INITIALIZING', 'RUNNING', 'FAILED', 'STOPPED')]
        [Parameter()][string]$Servicestate,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][hashtable]$Capacity,
        [Parameter()][switch]$Reserved,
        [Parameter()][string]$Clientcert,
        [Parameter()][switch]$Shared,
        [Parameter()][hashtable]$Discoveryinfo,
        [Parameter()][hashtable]$Nvmeofconfig,
        [Parameter()][object[]]$Subsystems,
        [Parameter()][object[]]$Nvmeoftargets
    )

        $qp = @{
            "dryRun" = $Dryrun
            "connectAll" = $Connectall
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Supportedbyhw")) { $body["supportedByHw"] = $Supportedbyhw }
        if ($PSBoundParameters.ContainsKey("Supportedbyservices")) { $body["supportedByServices"] = $Supportedbyservices }
        if ($PSBoundParameters.ContainsKey("Servicestate")) { $body["serviceState"] = $Servicestate }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Capacity")) { $body["capacity"] = $Capacity }
        $body["reserved"] = $Reserved.IsPresent
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        $body["shared"] = $Shared.IsPresent
        if ($PSBoundParameters.ContainsKey("Discoveryinfo")) { $body["discoveryInfo"] = $Discoveryinfo }
        if ($PSBoundParameters.ContainsKey("Nvmeofconfig")) { $body["nvmeOfConfig"] = $Nvmeofconfig }
        if ($PSBoundParameters.ContainsKey("Subsystems")) { $body["subsystems"] = $Subsystems }
        if ($PSBoundParameters.ContainsKey("Nvmeoftargets")) { $body["nvmeOfTargets"] = $Nvmeoftargets }

        Invoke-HsRequest -Method POST -Endpoint "/nvmeof-enclosures" -QueryParams $qp -Body $body
}

function Set-HsNvmeofEnclosure {
    <#
    .SYNOPSIS
        nvmeof-config [option]
    .DESCRIPTION
        nvmeof-config [option]
    .NOTES
    CLI equivalent: nvmeof-config
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][hashtable]$Supportedbyhw,
        [Parameter()][hashtable]$Supportedbyservices,
        [ValidateSet('UNKNOWN', 'INITIALIZING', 'RUNNING', 'FAILED', 'STOPPED')]
        [Parameter()][string]$Servicestate,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][hashtable]$Capacity,
        [Parameter()][switch]$Reserved,
        [Parameter()][string]$Clientcert,
        [Parameter()][switch]$Shared,
        [Parameter()][hashtable]$Discoveryinfo,
        [Parameter()][hashtable]$Nvmeofconfig,
        [Parameter()][object[]]$Subsystems,
        [Parameter()][object[]]$Nvmeoftargets
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Supportedbyhw")) { $body["supportedByHw"] = $Supportedbyhw }
        if ($PSBoundParameters.ContainsKey("Supportedbyservices")) { $body["supportedByServices"] = $Supportedbyservices }
        if ($PSBoundParameters.ContainsKey("Servicestate")) { $body["serviceState"] = $Servicestate }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Capacity")) { $body["capacity"] = $Capacity }
        $body["reserved"] = $Reserved.IsPresent
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        $body["shared"] = $Shared.IsPresent
        if ($PSBoundParameters.ContainsKey("Discoveryinfo")) { $body["discoveryInfo"] = $Discoveryinfo }
        if ($PSBoundParameters.ContainsKey("Nvmeofconfig")) { $body["nvmeOfConfig"] = $Nvmeofconfig }
        if ($PSBoundParameters.ContainsKey("Subsystems")) { $body["subsystems"] = $Subsystems }
        if ($PSBoundParameters.ContainsKey("Nvmeoftargets")) { $body["nvmeOfTargets"] = $Nvmeoftargets }

        Invoke-HsRequest -Method PUT -Endpoint "/nvmeof-enclosures/discover" -Body $body
}

function Get-HsNvmeofEnclosure2 {
    <#
    .SYNOPSIS
        Get NVMe-oF enclosure by identifier
    .DESCRIPTION
        GET /nvmeof-enclosures/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/nvmeof-enclosures/${Identifier}"
}

function Set-HsNvmeofEnclosure2 {
    <#
    .SYNOPSIS
        Update NvmeOf Enclosure. At least one nvmeOfTarget must be specified
    .DESCRIPTION
        PUT /nvmeof-enclosures/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Dryrun
        (Query) dryRun
    .PARAMETER Connectall
        (Query) connectAll
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Supportedbyhw
        (Body) supportedByHw
    .PARAMETER Supportedbyservices
        (Body) supportedByServices
    .PARAMETER Servicestate
        (Body) serviceState
    .PARAMETER Adminstate
        (Body) adminState
    .PARAMETER Capacity
        (Body) capacity
    .PARAMETER Reserved
        (Body) reserved
    .PARAMETER Clientcert
        (Body) clientCert
    .PARAMETER Shared
        (Body) shared
    .PARAMETER Discoveryinfo
        (Body) discoveryInfo
    .PARAMETER Nvmeofconfig
        (Body) nvmeOfConfig
    .PARAMETER Subsystems
        (Body) subsystems
    .PARAMETER Nvmeoftargets
        (Body) nvmeOfTargets
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Dryrun,
        [Parameter()][string]$Connectall,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][hashtable]$Supportedbyhw,
        [Parameter()][hashtable]$Supportedbyservices,
        [ValidateSet('UNKNOWN', 'INITIALIZING', 'RUNNING', 'FAILED', 'STOPPED')]
        [Parameter()][string]$Servicestate,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][hashtable]$Capacity,
        [Parameter()][switch]$Reserved,
        [Parameter()][string]$Clientcert,
        [Parameter()][switch]$Shared,
        [Parameter()][hashtable]$Discoveryinfo,
        [Parameter()][hashtable]$Nvmeofconfig,
        [Parameter()][object[]]$Subsystems,
        [Parameter()][object[]]$Nvmeoftargets
    )

        $qp = @{
            "dryRun" = $Dryrun
            "connectAll" = $Connectall
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Supportedbyhw")) { $body["supportedByHw"] = $Supportedbyhw }
        if ($PSBoundParameters.ContainsKey("Supportedbyservices")) { $body["supportedByServices"] = $Supportedbyservices }
        if ($PSBoundParameters.ContainsKey("Servicestate")) { $body["serviceState"] = $Servicestate }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Capacity")) { $body["capacity"] = $Capacity }
        $body["reserved"] = $Reserved.IsPresent
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        $body["shared"] = $Shared.IsPresent
        if ($PSBoundParameters.ContainsKey("Discoveryinfo")) { $body["discoveryInfo"] = $Discoveryinfo }
        if ($PSBoundParameters.ContainsKey("Nvmeofconfig")) { $body["nvmeOfConfig"] = $Nvmeofconfig }
        if ($PSBoundParameters.ContainsKey("Subsystems")) { $body["subsystems"] = $Subsystems }
        if ($PSBoundParameters.ContainsKey("Nvmeoftargets")) { $body["nvmeOfTargets"] = $Nvmeoftargets }

        Invoke-HsRequest -Method PUT -Endpoint "/nvmeof-enclosures/${Identifier}" -QueryParams $qp -Body $body
}

function Remove-HsNvmeofEnclosure {
    <#
    .SYNOPSIS
        Delete NVMe-oF enclosure by ID
    .DESCRIPTION
        DELETE /nvmeof-enclosures/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/nvmeof-enclosures/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: object-storage-volumes
# ---------------------------------------------------------------------------

function Get-HsObjectStorageVolume {
    <#
    .SYNOPSIS
        List object volumes
    .DESCRIPTION
        List object volumes
    .NOTES
    CLI equivalent: object-volume-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/object-storage-volumes" -QueryParams $qp
}

function New-HsObjectStorageVolume {
    <#
    .SYNOPSIS
        Add an object storage volume to the product
    .DESCRIPTION
        Add an object storage volume to the product. Add an object storage node to the product. Technology Preview: Add a zero durability object storage volume to the product. This feature is NOT
    .NOTES
    CLI equivalent: object-volume-add, object-storage-add, preview-no-upload-object-volume-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Createplacementobjectives,
        [Parameter()][string]$Skipregioncheck,
        [Parameter()][string]$Comment,
        [Parameter()][int]$Modificationcount,
        [Parameter()][string]$Operstatereason,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][string]$Name,
        [ValidateSet('ADDED', 'OK', 'DECOMMISSIONING', 'DECOMMISSIONED', 'FAILED', 'UNAVAILABLE')]
        [Parameter()][string]$Storagevolumestate,
        [Parameter()][switch]$Realignonprotectiondrop,
        [Parameter()][int]$Lastregradeinitiated,
        [Parameter()][int]$Lastvolumerealigned,
        [Parameter()][hashtable]$Regradeinfo,
        [ValidateSet('NONE', 'DECOM_QUIESCE_DME', 'DECOM_QUIESCE_ENVOY', 'DECOM_QUIESCE_PDFS', 'DECOM_REGRADE', 'DECOM_INSTANCE_REMOVAL', 'DECOM_CLEANING')]
        [Parameter()][string]$Workflowstage,
        [Parameter()][hashtable]$Location,
        [Parameter()][hashtable]$Storagecapabilities,
        [Parameter()][int]$Suspectedsince,
        [Parameter()][int]$Maxsuspectedseconds,
        [Parameter()][string]$Rootfilehandle,
        [Parameter()][object[]]$Associatedlocations,
        [Parameter()][int]$Effectivetotalcapacity,
        [Parameter()][hashtable]$Objectstorelogicalvolume,
        [Parameter()][string]$Accesskey,
        [Parameter()][string]$Secretkey,
        [Parameter()][int]$Totalcapacity,
        [Parameter()][int]$Logicalused,
        [Parameter()][object[]]$Sites,
        [ValidateSet('HASH_NAMED', 'PATH_NAMED')]
        [Parameter()][string]$Osvnamingtype,
        [ValidateSet('HIGH_COMPRESSION', 'FAST_COMPRESSION', 'NO_COMPRESSION')]
        [Parameter()][string]$Compressiontype,
        [ValidateSet('CONTENT_BASED_CHUNKING', 'FIXED_CHUNKING', 'NO_CHUNKING')]
        [Parameter()][string]$Chunkingtype,
        [ValidateSet('STANDARD', 'AWS_GLACIER_INSTANT_RETRIEVAL')]
        [Parameter()][string]$Storageclass,
        [Parameter()][int]$Kmsinternalid,
        [Parameter()][hashtable]$Kms,
        [Parameter()][object[]]$Otversions,
        [Parameter()][switch]$Shared,
        [Parameter()][hashtable]$Gcinfo,
        [Parameter()][switch]$Gcenabled,
        [Parameter()][switch]$Noupload,
        [Parameter()][string]$Region
    )

        $qp = @{
            "createPlacementObjectives" = $Createplacementobjectives
            "skipRegionCheck" = $Skipregioncheck
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Modificationcount")) { $body["modificationCount"] = $Modificationcount }
        if ($PSBoundParameters.ContainsKey("Operstatereason")) { $body["operStateReason"] = $Operstatereason }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Storagevolumestate")) { $body["storageVolumeState"] = $Storagevolumestate }
        $body["realignOnProtectionDrop"] = $Realignonprotectiondrop.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastregradeinitiated")) { $body["lastRegradeInitiated"] = $Lastregradeinitiated }
        if ($PSBoundParameters.ContainsKey("Lastvolumerealigned")) { $body["lastVolumeRealigned"] = $Lastvolumerealigned }
        if ($PSBoundParameters.ContainsKey("Regradeinfo")) { $body["regradeInfo"] = $Regradeinfo }
        if ($PSBoundParameters.ContainsKey("Workflowstage")) { $body["workflowStage"] = $Workflowstage }
        if ($PSBoundParameters.ContainsKey("Location")) { $body["location"] = $Location }
        if ($PSBoundParameters.ContainsKey("Storagecapabilities")) { $body["storageCapabilities"] = $Storagecapabilities }
        if ($PSBoundParameters.ContainsKey("Suspectedsince")) { $body["suspectedSince"] = $Suspectedsince }
        if ($PSBoundParameters.ContainsKey("Maxsuspectedseconds")) { $body["maxSuspectedSeconds"] = $Maxsuspectedseconds }
        if ($PSBoundParameters.ContainsKey("Rootfilehandle")) { $body["rootFileHandle"] = $Rootfilehandle }
        if ($PSBoundParameters.ContainsKey("Associatedlocations")) { $body["associatedLocations"] = $Associatedlocations }
        if ($PSBoundParameters.ContainsKey("Effectivetotalcapacity")) { $body["effectiveTotalCapacity"] = $Effectivetotalcapacity }
        if ($PSBoundParameters.ContainsKey("Objectstorelogicalvolume")) { $body["objectStoreLogicalVolume"] = $Objectstorelogicalvolume }
        if ($PSBoundParameters.ContainsKey("Accesskey")) { $body["accessKey"] = $Accesskey }
        if ($PSBoundParameters.ContainsKey("Secretkey")) { $body["secretKey"] = $Secretkey }
        if ($PSBoundParameters.ContainsKey("Totalcapacity")) { $body["totalCapacity"] = $Totalcapacity }
        if ($PSBoundParameters.ContainsKey("Logicalused")) { $body["logicalUsed"] = $Logicalused }
        if ($PSBoundParameters.ContainsKey("Sites")) { $body["sites"] = $Sites }
        if ($PSBoundParameters.ContainsKey("Osvnamingtype")) { $body["osvNamingType"] = $Osvnamingtype }
        if ($PSBoundParameters.ContainsKey("Compressiontype")) { $body["compressionType"] = $Compressiontype }
        if ($PSBoundParameters.ContainsKey("Chunkingtype")) { $body["chunkingType"] = $Chunkingtype }
        if ($PSBoundParameters.ContainsKey("Storageclass")) { $body["storageClass"] = $Storageclass }
        if ($PSBoundParameters.ContainsKey("Kmsinternalid")) { $body["kmsInternalId"] = $Kmsinternalid }
        if ($PSBoundParameters.ContainsKey("Kms")) { $body["kms"] = $Kms }
        if ($PSBoundParameters.ContainsKey("Otversions")) { $body["otVersions"] = $Otversions }
        $body["shared"] = $Shared.IsPresent
        if ($PSBoundParameters.ContainsKey("Gcinfo")) { $body["gcInfo"] = $Gcinfo }
        $body["gcEnabled"] = $Gcenabled.IsPresent
        $body["noUpload"] = $Noupload.IsPresent
        if ($PSBoundParameters.ContainsKey("Region")) { $body["region"] = $Region }

        Invoke-HsRequest -Method POST -Endpoint "/object-storage-volumes" -QueryParams $qp -Body $body
}

function Get-HsObjectStorageVolume2 {
    <#
    .SYNOPSIS
        Get all object storage volumes filtered by relation to other entity
    .DESCRIPTION
        GET /object-storage-volumes/related-list
    .PARAMETER Filteruuid
        (Query) filterUuid
    .PARAMETER Filterobjecttype
        (Query) filterObjectType
    .PARAMETER Sort
        (Query) sort
    .PARAMETER Terse
        (Query) terse
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Filteruuid,
        [Parameter()][string]$Filterobjecttype,
        [Parameter()][string]$Sort,
        [Parameter()][string]$Terse,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "filterUuid" = $Filteruuid
            "filterObjectType" = $Filterobjecttype
            "sort" = $Sort
            "terse" = $Terse
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/object-storage-volumes/related-list" -QueryParams $qp
}

function Get-HsObjectStorageVolume3 {
    <#
    .SYNOPSIS
        Get object storage volume by ID
    .DESCRIPTION
        GET /object-storage-volumes/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/object-storage-volumes/${Identifier}"
}

function Set-HsObjectStorageVolume {
    <#
    .SYNOPSIS
        Update object volume
    .DESCRIPTION
        Update object volume. Update an object storage node. Set an object volume to the FAILED state. Typically used to allow the removal of an object volume. Mark an unavailable object volume as available. Mark an object volume as unavailable
    .NOTES
    CLI equivalent: object-volume-update, object-storage-update, object-volume-fail, object-volume-set-available, object-volume-set-unavailable
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Skipregioncheck,
        [Parameter()][string]$Comment,
        [Parameter()][int]$Modificationcount,
        [Parameter()][string]$Operstatereason,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][string]$Name,
        [ValidateSet('ADDED', 'OK', 'DECOMMISSIONING', 'DECOMMISSIONED', 'FAILED', 'UNAVAILABLE')]
        [Parameter()][string]$Storagevolumestate,
        [Parameter()][switch]$Realignonprotectiondrop,
        [Parameter()][int]$Lastregradeinitiated,
        [Parameter()][int]$Lastvolumerealigned,
        [Parameter()][hashtable]$Regradeinfo,
        [ValidateSet('NONE', 'DECOM_QUIESCE_DME', 'DECOM_QUIESCE_ENVOY', 'DECOM_QUIESCE_PDFS', 'DECOM_REGRADE', 'DECOM_INSTANCE_REMOVAL', 'DECOM_CLEANING')]
        [Parameter()][string]$Workflowstage,
        [Parameter()][hashtable]$Location,
        [Parameter()][hashtable]$Storagecapabilities,
        [Parameter()][int]$Suspectedsince,
        [Parameter()][int]$Maxsuspectedseconds,
        [Parameter()][string]$Rootfilehandle,
        [Parameter()][object[]]$Associatedlocations,
        [Parameter()][int]$Effectivetotalcapacity,
        [Parameter()][hashtable]$Objectstorelogicalvolume,
        [Parameter()][string]$Accesskey,
        [Parameter()][string]$Secretkey,
        [Parameter()][int]$Totalcapacity,
        [Parameter()][int]$Logicalused,
        [Parameter()][object[]]$Sites,
        [ValidateSet('HASH_NAMED', 'PATH_NAMED')]
        [Parameter()][string]$Osvnamingtype,
        [ValidateSet('HIGH_COMPRESSION', 'FAST_COMPRESSION', 'NO_COMPRESSION')]
        [Parameter()][string]$Compressiontype,
        [ValidateSet('CONTENT_BASED_CHUNKING', 'FIXED_CHUNKING', 'NO_CHUNKING')]
        [Parameter()][string]$Chunkingtype,
        [ValidateSet('STANDARD', 'AWS_GLACIER_INSTANT_RETRIEVAL')]
        [Parameter()][string]$Storageclass,
        [Parameter()][int]$Kmsinternalid,
        [Parameter()][hashtable]$Kms,
        [Parameter()][object[]]$Otversions,
        [Parameter()][switch]$Shared,
        [Parameter()][hashtable]$Gcinfo,
        [Parameter()][switch]$Gcenabled,
        [Parameter()][switch]$Noupload,
        [Parameter()][string]$Region
    )

        $qp = @{
            "skipRegionCheck" = $Skipregioncheck
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Modificationcount")) { $body["modificationCount"] = $Modificationcount }
        if ($PSBoundParameters.ContainsKey("Operstatereason")) { $body["operStateReason"] = $Operstatereason }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Storagevolumestate")) { $body["storageVolumeState"] = $Storagevolumestate }
        $body["realignOnProtectionDrop"] = $Realignonprotectiondrop.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastregradeinitiated")) { $body["lastRegradeInitiated"] = $Lastregradeinitiated }
        if ($PSBoundParameters.ContainsKey("Lastvolumerealigned")) { $body["lastVolumeRealigned"] = $Lastvolumerealigned }
        if ($PSBoundParameters.ContainsKey("Regradeinfo")) { $body["regradeInfo"] = $Regradeinfo }
        if ($PSBoundParameters.ContainsKey("Workflowstage")) { $body["workflowStage"] = $Workflowstage }
        if ($PSBoundParameters.ContainsKey("Location")) { $body["location"] = $Location }
        if ($PSBoundParameters.ContainsKey("Storagecapabilities")) { $body["storageCapabilities"] = $Storagecapabilities }
        if ($PSBoundParameters.ContainsKey("Suspectedsince")) { $body["suspectedSince"] = $Suspectedsince }
        if ($PSBoundParameters.ContainsKey("Maxsuspectedseconds")) { $body["maxSuspectedSeconds"] = $Maxsuspectedseconds }
        if ($PSBoundParameters.ContainsKey("Rootfilehandle")) { $body["rootFileHandle"] = $Rootfilehandle }
        if ($PSBoundParameters.ContainsKey("Associatedlocations")) { $body["associatedLocations"] = $Associatedlocations }
        if ($PSBoundParameters.ContainsKey("Effectivetotalcapacity")) { $body["effectiveTotalCapacity"] = $Effectivetotalcapacity }
        if ($PSBoundParameters.ContainsKey("Objectstorelogicalvolume")) { $body["objectStoreLogicalVolume"] = $Objectstorelogicalvolume }
        if ($PSBoundParameters.ContainsKey("Accesskey")) { $body["accessKey"] = $Accesskey }
        if ($PSBoundParameters.ContainsKey("Secretkey")) { $body["secretKey"] = $Secretkey }
        if ($PSBoundParameters.ContainsKey("Totalcapacity")) { $body["totalCapacity"] = $Totalcapacity }
        if ($PSBoundParameters.ContainsKey("Logicalused")) { $body["logicalUsed"] = $Logicalused }
        if ($PSBoundParameters.ContainsKey("Sites")) { $body["sites"] = $Sites }
        if ($PSBoundParameters.ContainsKey("Osvnamingtype")) { $body["osvNamingType"] = $Osvnamingtype }
        if ($PSBoundParameters.ContainsKey("Compressiontype")) { $body["compressionType"] = $Compressiontype }
        if ($PSBoundParameters.ContainsKey("Chunkingtype")) { $body["chunkingType"] = $Chunkingtype }
        if ($PSBoundParameters.ContainsKey("Storageclass")) { $body["storageClass"] = $Storageclass }
        if ($PSBoundParameters.ContainsKey("Kmsinternalid")) { $body["kmsInternalId"] = $Kmsinternalid }
        if ($PSBoundParameters.ContainsKey("Kms")) { $body["kms"] = $Kms }
        if ($PSBoundParameters.ContainsKey("Otversions")) { $body["otVersions"] = $Otversions }
        $body["shared"] = $Shared.IsPresent
        if ($PSBoundParameters.ContainsKey("Gcinfo")) { $body["gcInfo"] = $Gcinfo }
        $body["gcEnabled"] = $Gcenabled.IsPresent
        $body["noUpload"] = $Noupload.IsPresent
        if ($PSBoundParameters.ContainsKey("Region")) { $body["region"] = $Region }

        Invoke-HsRequest -Method PUT -Endpoint "/object-storage-volumes/${Identifier}" -QueryParams $qp -Body $body
}

function Remove-HsObjectStorageVolume {
    <#
    .SYNOPSIS
        Remove an object volume from the system
    .DESCRIPTION
        Remove an object volume from the system. Cancel the removal of an object volume. The volume must be in the DECOMMISSIONING state
    .NOTES
    CLI equivalent: object-volume-remove, object-volume-remove-cancel
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Skipgfsvalidation,
        [Parameter()][string]$Bypassdecommission
    )

        $qp = @{
            "skipGfsValidation" = $Skipgfsvalidation
            "bypassDecommission" = $Bypassdecommission
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/object-storage-volumes/${Identifier}" -QueryParams $qp
}

function Invoke-HsObjectStorageVolumeDecommission {
    <#
    .SYNOPSIS
        Start the object volume decommission process (DEPRECATED)
    .DESCRIPTION
        Start the object volume decommission process (DEPRECATED). Cancel the object storage volume decommission process (DEPRECATED)
    .NOTES
    CLI equivalent: object-volume-decommission, object-volume-decommission-cancel
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Skipgfsvalidation
    )

        $qp = @{
            "skipGfsValidation" = $Skipgfsvalidation
        }

        Invoke-HsRequest -Method POST -Endpoint "/object-storage-volumes/${Identifier}/decommission" -QueryParams $qp
}

function Start-HsObjectStorageVolumeGarbageCollect {
    <#
    .SYNOPSIS
        Start garbage collection on a given object volume
    .DESCRIPTION
        Start garbage collection on a given object volume
    .NOTES
    CLI equivalent: object-volume-gc-start
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method POST -Endpoint "/object-storage-volumes/${Identifier}/garbage-collect"
}

function Stop-HsObjectStorageVolumeGarbageCollect {
    <#
    .SYNOPSIS
        Stop garbage collection on a given object volume
    .DESCRIPTION
        Stop garbage collection on a given object volume
    .NOTES
    CLI equivalent: object-volume-gc-stop
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/object-storage-volumes/${Identifier}/garbage-collect"
}

function Remove-HsObjectStorageVolumeRemoteReservation {
    <#
    .SYNOPSIS
        Delete a site’s reservation from an object volume
    .DESCRIPTION
        Delete a site’s reservation from an object volume
    .NOTES
    CLI equivalent: object-volume-reservation-delete
    WARNING: failed or been removed without first removing the object volume. WARNING: deleting a site’s
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter(Mandatory)][string]$SiteIdentifier,
        [Parameter()][string]$Force
    )

        $qp = @{
            "force" = $Force
        }

        Invoke-HsRequest -Method PUT -Endpoint "/object-storage-volumes/${Identifier}/remote-reservation/${SiteIdentifier}" -QueryParams $qp
}

function Set-HsObjectStorageVolumeReplace {
    <#
    .SYNOPSIS
        Replace object storage volume
    .DESCRIPTION
        POST /object-storage-volumes/{identifier}/replace
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method POST -Endpoint "/object-storage-volumes/${Identifier}/replace"
}

# ---------------------------------------------------------------------------
# SECTION: object-store-logical-volumes
# ---------------------------------------------------------------------------

function Get-HsObjectStoreLogicalVolume {
    <#
    .SYNOPSIS
        Get the shared information for a shared object storage volume by the UUID which is in the hs_osv_details file in the OSVs bucket
    .DESCRIPTION
        GET /object-store-logical-volumes/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/object-store-logical-volumes/${Identifier}"
}

function Get-HsObjectStoreLogicalVolume2 {
    <#
    .SYNOPSIS
        Discover an object store logical volume (bucket)
    .DESCRIPTION
        GET /object-store-logical-volumes/{identifier}/discover
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/object-store-logical-volumes/${Identifier}/discover"
}

# ---------------------------------------------------------------------------
# SECTION: objectives
# ---------------------------------------------------------------------------

function Get-HsObjective {
    <#
    .SYNOPSIS
        Get all objectives
    .DESCRIPTION
        GET /objectives
    .PARAMETER Hidetechpreview
        (Query) hideTechPreview
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Hidetechpreview,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "hideTechPreview" = $Hidetechpreview
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/objectives" -QueryParams $qp
}

function New-HsObjective {
    <#
    .SYNOPSIS
        Create objective
    .DESCRIPTION
        POST /objectives
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Zombie
        (Body) zombie
    .PARAMETER Hidden
        (Body) hidden
    .PARAMETER Basic
        (Body) basic
    .PARAMETER Expression
        (Body) expression
    .PARAMETER Appliedobjectives
        (Body) appliedObjectives
    .PARAMETER Priority
        (Body) priority
    .PARAMETER Readperformance
        (Body) readPerformance
    .PARAMETER Writeperformance
        (Body) writePerformance
    .PARAMETER Protection
        (Body) protection
    .PARAMETER Placementobjective
        (Body) placementObjective
    .PARAMETER Techpreview
        (Body) techPreview
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][switch]$Zombie,
        [Parameter()][switch]$Hidden,
        [Parameter()][switch]$Basic,
        [Parameter()][string]$Expression,
        [Parameter()][object[]]$Appliedobjectives,
        [ValidateSet('LOW', 'MEDIUM_LOW', 'MEDIUM', 'MEDIUM_HIGH', 'HIGH')]
        [Parameter()][string]$Priority,
        [Parameter()][hashtable]$Readperformance,
        [Parameter()][hashtable]$Writeperformance,
        [Parameter()][hashtable]$Protection,
        [Parameter()][hashtable]$Placementobjective,
        [Parameter()][switch]$Techpreview
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        $body["zombie"] = $Zombie.IsPresent
        $body["hidden"] = $Hidden.IsPresent
        $body["basic"] = $Basic.IsPresent
        if ($PSBoundParameters.ContainsKey("Expression")) { $body["expression"] = $Expression }
        if ($PSBoundParameters.ContainsKey("Appliedobjectives")) { $body["appliedObjectives"] = $Appliedobjectives }
        if ($PSBoundParameters.ContainsKey("Priority")) { $body["priority"] = $Priority }
        if ($PSBoundParameters.ContainsKey("Readperformance")) { $body["readPerformance"] = $Readperformance }
        if ($PSBoundParameters.ContainsKey("Writeperformance")) { $body["writePerformance"] = $Writeperformance }
        if ($PSBoundParameters.ContainsKey("Protection")) { $body["protection"] = $Protection }
        if ($PSBoundParameters.ContainsKey("Placementobjective")) { $body["placementObjective"] = $Placementobjective }
        $body["techPreview"] = $Techpreview.IsPresent

        Invoke-HsRequest -Method POST -Endpoint "/objectives" -Body $body
}

function Export-HsObjectiveExport {
    <#
    .SYNOPSIS
        Export objectives
    .DESCRIPTION
        POST /objectives/export
    .PARAMETER Uuid
        (Query) uuid
    .PARAMETER Name
        (Query) name
    .PARAMETER Target
        (Query) target
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Uuid,
        [Parameter()][string]$Name,
        [Parameter()][string]$Target
    )

        $qp = @{
            "uuid" = $Uuid
            "name" = $Name
            "target" = $Target
        }

        Invoke-HsRequest -Method POST -Endpoint "/objectives/export" -QueryParams $qp
}

function Find-HsObjectiveFindmatchingvolume {
    <#
    .SYNOPSIS
        Find matching volumes
    .DESCRIPTION
        POST /objectives/findMatchingVolumes
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Zombie
        (Body) zombie
    .PARAMETER Hidden
        (Body) hidden
    .PARAMETER Basic
        (Body) basic
    .PARAMETER Expression
        (Body) expression
    .PARAMETER Appliedobjectives
        (Body) appliedObjectives
    .PARAMETER Priority
        (Body) priority
    .PARAMETER Readperformance
        (Body) readPerformance
    .PARAMETER Writeperformance
        (Body) writePerformance
    .PARAMETER Protection
        (Body) protection
    .PARAMETER Placementobjective
        (Body) placementObjective
    .PARAMETER Techpreview
        (Body) techPreview
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][switch]$Zombie,
        [Parameter()][switch]$Hidden,
        [Parameter()][switch]$Basic,
        [Parameter()][string]$Expression,
        [Parameter()][object[]]$Appliedobjectives,
        [ValidateSet('LOW', 'MEDIUM_LOW', 'MEDIUM', 'MEDIUM_HIGH', 'HIGH')]
        [Parameter()][string]$Priority,
        [Parameter()][hashtable]$Readperformance,
        [Parameter()][hashtable]$Writeperformance,
        [Parameter()][hashtable]$Protection,
        [Parameter()][hashtable]$Placementobjective,
        [Parameter()][switch]$Techpreview
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        $body["zombie"] = $Zombie.IsPresent
        $body["hidden"] = $Hidden.IsPresent
        $body["basic"] = $Basic.IsPresent
        if ($PSBoundParameters.ContainsKey("Expression")) { $body["expression"] = $Expression }
        if ($PSBoundParameters.ContainsKey("Appliedobjectives")) { $body["appliedObjectives"] = $Appliedobjectives }
        if ($PSBoundParameters.ContainsKey("Priority")) { $body["priority"] = $Priority }
        if ($PSBoundParameters.ContainsKey("Readperformance")) { $body["readPerformance"] = $Readperformance }
        if ($PSBoundParameters.ContainsKey("Writeperformance")) { $body["writePerformance"] = $Writeperformance }
        if ($PSBoundParameters.ContainsKey("Protection")) { $body["protection"] = $Protection }
        if ($PSBoundParameters.ContainsKey("Placementobjective")) { $body["placementObjective"] = $Placementobjective }
        $body["techPreview"] = $Techpreview.IsPresent

        Invoke-HsRequest -Method POST -Endpoint "/objectives/findMatchingVolumes" -Body $body
}

function Import-HsObjectiveImport {
    <#
    .SYNOPSIS
        Import objectives
    .DESCRIPTION
        POST /objectives/import
    .PARAMETER Source
        (Query) source
    .PARAMETER Name
        (Query) name
    .PARAMETER Prefix
        (Query) prefix
    .PARAMETER Merge
        (Query) merge
    .PARAMETER Insecure
        (Query) insecure
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Source,
        [Parameter()][string]$Name,
        [Parameter()][string]$Prefix,
        [Parameter()][string]$Merge,
        [Parameter()][string]$Insecure
    )

        $qp = @{
            "source" = $Source
            "name" = $Name
            "prefix" = $Prefix
            "merge" = $Merge
            "insecure" = $Insecure
        }

        Invoke-HsRequest -Method POST -Endpoint "/objectives/import" -QueryParams $qp
}

function Get-HsObjectiveValidate {
    <#
    .SYNOPSIS
        Validate expression
    .DESCRIPTION
        GET /objectives/validate/{exp}
    .PARAMETER Exp
        (Path) exp
    .PARAMETER Hidetechpreview
        (Query) hideTechPreview
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Exp,
        [Parameter()][string]$Hidetechpreview
    )

        $qp = @{
            "hideTechPreview" = $Hidetechpreview
        }

        Invoke-HsRequest -Method GET -Endpoint "/objectives/validate/${Exp}" -QueryParams $qp
}

function Get-HsObjective2 {
    <#
    .SYNOPSIS
        Get objective by ID
    .DESCRIPTION
        GET /objectives/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/objectives/${Identifier}"
}

function Set-HsObjective {
    <#
    .SYNOPSIS
        Update objective
    .DESCRIPTION
        PUT /objectives/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Zombie
        (Body) zombie
    .PARAMETER Hidden
        (Body) hidden
    .PARAMETER Basic
        (Body) basic
    .PARAMETER Expression
        (Body) expression
    .PARAMETER Appliedobjectives
        (Body) appliedObjectives
    .PARAMETER Priority
        (Body) priority
    .PARAMETER Readperformance
        (Body) readPerformance
    .PARAMETER Writeperformance
        (Body) writePerformance
    .PARAMETER Protection
        (Body) protection
    .PARAMETER Placementobjective
        (Body) placementObjective
    .PARAMETER Techpreview
        (Body) techPreview
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][switch]$Zombie,
        [Parameter()][switch]$Hidden,
        [Parameter()][switch]$Basic,
        [Parameter()][string]$Expression,
        [Parameter()][object[]]$Appliedobjectives,
        [ValidateSet('LOW', 'MEDIUM_LOW', 'MEDIUM', 'MEDIUM_HIGH', 'HIGH')]
        [Parameter()][string]$Priority,
        [Parameter()][hashtable]$Readperformance,
        [Parameter()][hashtable]$Writeperformance,
        [Parameter()][hashtable]$Protection,
        [Parameter()][hashtable]$Placementobjective,
        [Parameter()][switch]$Techpreview
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        $body["zombie"] = $Zombie.IsPresent
        $body["hidden"] = $Hidden.IsPresent
        $body["basic"] = $Basic.IsPresent
        if ($PSBoundParameters.ContainsKey("Expression")) { $body["expression"] = $Expression }
        if ($PSBoundParameters.ContainsKey("Appliedobjectives")) { $body["appliedObjectives"] = $Appliedobjectives }
        if ($PSBoundParameters.ContainsKey("Priority")) { $body["priority"] = $Priority }
        if ($PSBoundParameters.ContainsKey("Readperformance")) { $body["readPerformance"] = $Readperformance }
        if ($PSBoundParameters.ContainsKey("Writeperformance")) { $body["writePerformance"] = $Writeperformance }
        if ($PSBoundParameters.ContainsKey("Protection")) { $body["protection"] = $Protection }
        if ($PSBoundParameters.ContainsKey("Placementobjective")) { $body["placementObjective"] = $Placementobjective }
        $body["techPreview"] = $Techpreview.IsPresent

        Invoke-HsRequest -Method PUT -Endpoint "/objectives/${Identifier}" -Body $body
}

function Remove-HsObjective {
    <#
    .SYNOPSIS
        Delete objective
    .DESCRIPTION
        DELETE /objectives/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/objectives/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: pd-node-cntl
# ---------------------------------------------------------------------------

function Add-HsPdNodeCntl {
    <#
    .SYNOPSIS
        Add HA node
    .DESCRIPTION
        POST /pd-node-cntl/add
    .PARAMETER Ip
        (Query) ip
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Ip
    )

        $qp = @{
            "ip" = $Ip
        }

        Invoke-HsRequest -Method POST -Endpoint "/pd-node-cntl/add" -QueryParams $qp
}

function Repair-HsPdNodeCntl {
    <#
    .SYNOPSIS
        Repair node storage volumes
    .DESCRIPTION
        Repair node storage volumes
    .NOTES
    CLI equivalent: node-storage-repair
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Id
    )

        $qp = @{
            "id" = $Id
        }

        Invoke-HsRequest -Method POST -Endpoint "/pd-node-cntl/repair" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: pd-support
# ---------------------------------------------------------------------------

function Invoke-HsPdSupport {
    <#
    .SYNOPSIS
        Collect logs and information from all nodes
    .DESCRIPTION
        Collect logs and information from all nodes
    .NOTES
    CLI equivalent: support-bundle
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Node,
        [Parameter()][switch]$All,
        [Parameter()][object[]]$Extra,
        [Parameter()][string]$Outputurl,
        [Parameter()][switch]$Push,
        [Parameter()][switch]$Error,
        [Parameter()][string]$Message
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Node")) { $body["node"] = $Node }
        $body["all"] = $All.IsPresent
        if ($PSBoundParameters.ContainsKey("Extra")) { $body["extra"] = $Extra }
        if ($PSBoundParameters.ContainsKey("Outputurl")) { $body["outputUrl"] = $Outputurl }
        $body["push"] = $Push.IsPresent
        $body["error"] = $Error.IsPresent
        if ($PSBoundParameters.ContainsKey("Message")) { $body["message"] = $Message }

        Invoke-HsRequest -Method POST -Endpoint "/pd-support" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: pki-certificate-authorities
# ---------------------------------------------------------------------------

function Get-HsPkiCertificateAuthority {
    <#
    .SYNOPSIS
        List certificate authorities
    .DESCRIPTION
        GET /pki-certificate-authorities
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/pki-certificate-authorities"
}

function Get-HsPkiCertificateAuthoritiesSystem {
    <#
    .SYNOPSIS
        Get the current system certificate authority
    .DESCRIPTION
        GET /pki-certificate-authorities/system
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/pki-certificate-authorities/system"
}

function Get-HsPkiCertificateAuthority2 {
    <#
    .SYNOPSIS
        Get certificate authority by ID
    .DESCRIPTION
        GET /pki-certificate-authorities/{uuid}
    .PARAMETER Uuid
        (Path) uuid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uuid
    )

        Invoke-HsRequest -Method GET -Endpoint "/pki-certificate-authorities/${Uuid}"
}

# ---------------------------------------------------------------------------
# SECTION: pki-certificates
# ---------------------------------------------------------------------------

function Get-HsPkiCertificate {
    <#
    .SYNOPSIS
        List certificates
    .DESCRIPTION
        GET /pki-certificates
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/pki-certificates"
}

function New-HsPkiCertificate {
    <#
    .SYNOPSIS
        Add certificate(s) to be installed and trusted by the system
    .DESCRIPTION
        POST /pki-certificates
    .PARAMETER Trustintermediateca
        (Query) trustIntermediateCa
    .PARAMETER Trustselfsignedcertificate
        (Query) trustSelfSignedCertificate
    .PARAMETER Validateonly
        (Query) validateOnly
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Trustintermediateca,
        [Parameter()][string]$Trustselfsignedcertificate,
        [Parameter()][string]$Validateonly
    )

        $qp = @{
            "trustIntermediateCa" = $Trustintermediateca
            "trustSelfSignedCertificate" = $Trustselfsignedcertificate
            "validateOnly" = $Validateonly
        }

        Invoke-HsRequest -Method POST -Endpoint "/pki-certificates" -QueryParams $qp
}

function New-HsPkiCertificateSignCsr {
    <#
    .SYNOPSIS
        Sign a CSR from JSON metadata
    .DESCRIPTION
        POST /pki-certificates/sign-csr
    .PARAMETER Track
        (Query) track
    .PARAMETER Includechain
        (Query) includeChain
    .PARAMETER Csrpem
        (Body) csrPem
    .PARAMETER Trustpolicy
        (Body) trustPolicy
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Track,
        [Parameter()][string]$Includechain,
        [Parameter()][string]$Csrpem,
        [Parameter()][hashtable]$Trustpolicy
    )

        $qp = @{
            "track" = $Track
            "includeChain" = $Includechain
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Csrpem")) { $body["csrPem"] = $Csrpem }
        if ($PSBoundParameters.ContainsKey("Trustpolicy")) { $body["trustPolicy"] = $Trustpolicy }

        Invoke-HsRequest -Method POST -Endpoint "/pki-certificates/sign-csr" -QueryParams $qp -Body $body
}

function Remove-HsPkiCertificate {
    <#
    .SYNOPSIS
        Remove a previously uploaded certificate
    .DESCRIPTION
        DELETE /pki-certificates/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/pki-certificates/${Identifier}"
}

function Get-HsPkiCertificate2 {
    <#
    .SYNOPSIS
        Get certificate by ID
    .DESCRIPTION
        GET /pki-certificates/{uuid}
    .PARAMETER Uuid
        (Path) uuid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uuid
    )

        Invoke-HsRequest -Method GET -Endpoint "/pki-certificates/${Uuid}"
}

# ---------------------------------------------------------------------------
# SECTION: pki-managed-certificates
# ---------------------------------------------------------------------------

function Get-HsPkiManagedCertificate {
    <#
    .SYNOPSIS
        List managed certificates
    .DESCRIPTION
        GET /pki-managed-certificates
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/pki-managed-certificates"
}

function Get-HsPkiManagedCertificate2 {
    <#
    .SYNOPSIS
        Get managed certificate by ID
    .DESCRIPTION
        GET /pki-managed-certificates/{uuid}
    .PARAMETER Uuid
        (Path) uuid
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uuid
    )

        Invoke-HsRequest -Method GET -Endpoint "/pki-managed-certificates/${Uuid}"
}

# ---------------------------------------------------------------------------
# SECTION: reports
# ---------------------------------------------------------------------------

function Get-HsReportActiveFiles {
    <#
    .SYNOPSIS
        Query influxDB for active files reports
    .DESCRIPTION
        GET /reports/active-files
    .PARAMETER Startmillis
        (Query) startMillis
    .PARAMETER Endmillis
        (Query) endMillis
    .PARAMETER Precedingdurationmillis
        (Query) precedingDurationMillis
    .PARAMETER Share
        (Query) share
    .PARAMETER Sv
        (Query) sv
    .PARAMETER Limit
        (Query) limit
    .PARAMETER Offset
        (Query) offset
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Startmillis,
        [Parameter()][string]$Endmillis,
        [Parameter()][string]$Precedingdurationmillis,
        [Parameter()][string]$Share,
        [Parameter()][string]$Sv,
        [Parameter()][string]$Limit,
        [Parameter()][string]$Offset
    )

        $qp = @{
            "startMillis" = $Startmillis
            "endMillis" = $Endmillis
            "precedingDurationMillis" = $Precedingdurationmillis
            "share" = $Share
            "sv" = $Sv
            "limit" = $Limit
            "offset" = $Offset
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/active-files" -QueryParams $qp
}

function Get-HsReportActivityAnalytic {
    <#
    .SYNOPSIS
        Query influxDB for active clients reports
    .DESCRIPTION
        GET /reports/activity-analytics
    .PARAMETER Share
        (Query) share
    .PARAMETER Sv
        (Query) sv
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Share,
        [Parameter()][string]$Sv
    )

        $qp = @{
            "share" = $Share
            "sv" = $Sv
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/activity-analytics" -QueryParams $qp
}

function Get-HsReportStat {
    <#
    .SYNOPSIS
        Query influxDB for active clients reports
    .DESCRIPTION
        GET /reports/activity-analytics/stats
    .PARAMETER Startmillis
        (Query) startMillis
    .PARAMETER Endmillis
        (Query) endMillis
    .PARAMETER Precedingdurationmillis
        (Query) precedingDurationMillis
    .PARAMETER Share
        (Query) share
    .PARAMETER Sv
        (Query) sv
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Startmillis,
        [Parameter()][string]$Endmillis,
        [Parameter()][string]$Precedingdurationmillis,
        [Parameter()][string]$Share,
        [Parameter()][string]$Sv
    )

        $qp = @{
            "startMillis" = $Startmillis
            "endMillis" = $Endmillis
            "precedingDurationMillis" = $Precedingdurationmillis
            "share" = $Share
            "sv" = $Sv
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/activity-analytics/stats" -QueryParams $qp
}

function Get-HsReportLicensedUsage {
    <#
    .SYNOPSIS
        Get the usage associated with a metered client license
    .DESCRIPTION
        GET /reports/licensed-usage/{activationid}
    .PARAMETER Activationid
        (Path) activationid
    .PARAMETER Precedingdurationmillis
        (Query) precedingDurationMillis
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Activationid,
        [Parameter()][string]$Precedingdurationmillis
    )

        $qp = @{
            "precedingDurationMillis" = $Precedingdurationmillis
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/licensed-usage/${Activationid}" -QueryParams $qp
}

function Get-HsReportMobility {
    <#
    .SYNOPSIS
        Query influxDB for mobility reports
    .DESCRIPTION
        GET /reports/mobility
    .PARAMETER Startmillis
        (Query) startMillis
    .PARAMETER Endmillis
        (Query) endMillis
    .PARAMETER Precedingdurationmillis
        (Query) precedingDurationMillis
    .PARAMETER Share
        (Query) share
    .PARAMETER From
        (Query) from
    .PARAMETER To
        (Query) to
    .PARAMETER Volumegroupid
        (Query) volumeGroupId
    .PARAMETER Reasons
        (Query) reasons
    .PARAMETER Statuses
        (Query) statuses
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Startmillis,
        [Parameter()][string]$Endmillis,
        [Parameter()][string]$Precedingdurationmillis,
        [Parameter()][string]$Share,
        [Parameter()][string]$From,
        [Parameter()][string]$To,
        [Parameter()][string]$Volumegroupid,
        [Parameter()][string]$Reasons,
        [Parameter()][string]$Statuses,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize
    )

        $qp = @{
            "startMillis" = $Startmillis
            "endMillis" = $Endmillis
            "precedingDurationMillis" = $Precedingdurationmillis
            "share" = $Share
            "from" = $From
            "to" = $To
            "volumeGroupId" = $Volumegroupid
            "reasons" = $Reasons
            "statuses" = $Statuses
            "page" = $Page
            "page.size" = $PageSize
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/mobility" -QueryParams $qp
}

function Get-HsReportReplication {
    <#
    .SYNOPSIS
        Query influxDB for completed replication mobilities involving shared object storage grouped by time intervals in some period specified by a range
    .DESCRIPTION
        GET /reports/mobility/replications
    .PARAMETER Startmillis
        (Query) startMillis
    .PARAMETER Endmillis
        (Query) endMillis
    .PARAMETER Precedingdurationmillis
        (Query) precedingDurationMillis
    .PARAMETER Intervals
        (Query) intervals
    .PARAMETER Alignment
        (Query) alignment
    .PARAMETER Share
        (Query) share
    .PARAMETER Replicatingshares
        (Query) replicatingShares
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Startmillis,
        [Parameter()][string]$Endmillis,
        [Parameter()][string]$Precedingdurationmillis,
        [Parameter()][string]$Intervals,
        [Parameter()][string]$Alignment,
        [Parameter()][string]$Share,
        [Parameter()][string]$Replicatingshares
    )

        $qp = @{
            "startMillis" = $Startmillis
            "endMillis" = $Endmillis
            "precedingDurationMillis" = $Precedingdurationmillis
            "intervals" = $Intervals
            "alignment" = $Alignment
            "share" = $Share
            "replicatingShares" = $Replicatingshares
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/mobility/replications" -QueryParams $qp
}

function Get-HsReportReplication2 {
    <#
    .SYNOPSIS
        Query influxDB for completed replication mobilities involving shared object storage grouped by time intervals in some period preceding current time
    .DESCRIPTION
        GET /reports/mobility/replications/{precedingDurationMillis}/{intervals}
    .PARAMETER Precedingdurationmillis
        (Path) precedingDurationMillis
    .PARAMETER Intervals
        (Path) intervals
    .PARAMETER Share
        (Query) share
    .PARAMETER Replicatingshares
        (Query) replicatingShares
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Precedingdurationmillis,
        [Parameter(Mandatory)][string]$Intervals,
        [Parameter()][string]$Share,
        [Parameter()][string]$Replicatingshares
    )

        $qp = @{
            "share" = $Share
            "replicatingShares" = $Replicatingshares
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/mobility/replications/${Precedingdurationmillis}/${Intervals}" -QueryParams $qp
}

function Get-HsReportShare {
    <#
    .SYNOPSIS
        Query influxDB for completed mobilities for share grouped by time intervals in some period specified by a duration
    .DESCRIPTION
        GET /reports/mobility/share
    .PARAMETER Startmillis
        (Query) startMillis
    .PARAMETER Endmillis
        (Query) endMillis
    .PARAMETER Precedingdurationmillis
        (Query) precedingDurationMillis
    .PARAMETER Intervals
        (Query) intervals
    .PARAMETER Alignment
        (Query) alignment
    .PARAMETER Share
        (Query) share
    .PARAMETER Statuses
        (Query) statuses
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Startmillis,
        [Parameter()][string]$Endmillis,
        [Parameter()][string]$Precedingdurationmillis,
        [Parameter()][string]$Intervals,
        [Parameter()][string]$Alignment,
        [Parameter()][string]$Share,
        [Parameter()][string]$Statuses
    )

        $qp = @{
            "startMillis" = $Startmillis
            "endMillis" = $Endmillis
            "precedingDurationMillis" = $Precedingdurationmillis
            "intervals" = $Intervals
            "alignment" = $Alignment
            "share" = $Share
            "statuses" = $Statuses
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/mobility/share" -QueryParams $qp
}

function Get-HsReport {
    <#
    .SYNOPSIS
        Query influxDB for mobility reports summary. At least one of to, from or volumeGroupId must be omitted
    .DESCRIPTION
        GET /reports/mobility/summary
    .PARAMETER Startmillis
        (Query) startMillis
    .PARAMETER Endmillis
        (Query) endMillis
    .PARAMETER Precedingdurationmillis
        (Query) precedingDurationMillis
    .PARAMETER Share
        (Query) share
    .PARAMETER From
        (Query) from
    .PARAMETER To
        (Query) to
    .PARAMETER Volumegroupid
        (Query) volumeGroupId
    .PARAMETER Reasons
        (Query) reasons
    .PARAMETER Statuses
        (Query) statuses
    .PARAMETER FailedStatusesOnly
        (Query) failed-statuses-only
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Startmillis,
        [Parameter()][string]$Endmillis,
        [Parameter()][string]$Precedingdurationmillis,
        [Parameter()][string]$Share,
        [Parameter()][string]$From,
        [Parameter()][string]$To,
        [Parameter()][string]$Volumegroupid,
        [Parameter()][string]$Reasons,
        [Parameter()][string]$Statuses,
        [Parameter()][string]$FailedStatusesOnly
    )

        $qp = @{
            "startMillis" = $Startmillis
            "endMillis" = $Endmillis
            "precedingDurationMillis" = $Precedingdurationmillis
            "share" = $Share
            "from" = $From
            "to" = $To
            "volumeGroupId" = $Volumegroupid
            "reasons" = $Reasons
            "statuses" = $Statuses
            "failed-statuses-only" = $FailedStatusesOnly
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/mobility/summary" -QueryParams $qp
}

function Get-HsReportMobilityBandwidth {
    <#
    .SYNOPSIS
        Query influxDB for performance reports
    .DESCRIPTION
        GET /reports/moe/mobility-bandwidth
    .PARAMETER Startmillis
        (Query) startMillis
    .PARAMETER Endmillis
        (Query) endMillis
    .PARAMETER Fromstoragecontaineruuid
        (Query) fromStorageContainerUuid
    .PARAMETER Fromstoragecontainertype
        (Query) fromStorageContainerType
    .PARAMETER Tostoragecontaineruuid
        (Query) toStorageContainerUuid
    .PARAMETER Tostoragecontainertype
        (Query) toStorageContainerType
    .PARAMETER Precedingdurationmillis
        (Query) precedingDurationMillis
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Startmillis,
        [Parameter()][string]$Endmillis,
        [Parameter()][string]$Fromstoragecontaineruuid,
        [Parameter()][string]$Fromstoragecontainertype,
        [Parameter()][string]$Tostoragecontaineruuid,
        [Parameter()][string]$Tostoragecontainertype,
        [Parameter()][string]$Precedingdurationmillis
    )

        $qp = @{
            "startMillis" = $Startmillis
            "endMillis" = $Endmillis
            "fromStorageContainerUuid" = $Fromstoragecontaineruuid
            "fromStorageContainerType" = $Fromstoragecontainertype
            "toStorageContainerUuid" = $Tostoragecontaineruuid
            "toStorageContainerType" = $Tostoragecontainertype
            "precedingDurationMillis" = $Precedingdurationmillis
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/moe/mobility-bandwidth" -QueryParams $qp
}

function Get-HsReportProxyUsage {
    <#
    .SYNOPSIS
        Get the usage for all clusters known to be subject to metered usage
    .DESCRIPTION
        GET /reports/proxy-usage
    .PARAMETER Precedingdurationmillis
        (Query) precedingDurationMillis
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Precedingdurationmillis
    )

        $qp = @{
            "precedingDurationMillis" = $Precedingdurationmillis
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/proxy-usage" -QueryParams $qp
}

function Get-HsReportShareLatencies {
    <#
    .SYNOPSIS
        Query influxDB for replication latencies
    .DESCRIPTION
        GET /reports/replication/share-latencies/{uuid}
    .PARAMETER Uuid
        (Path) uuid
    .PARAMETER Participantid
        (Query) participantId
    .PARAMETER Startmillis
        (Query) startMillis
    .PARAMETER Endmillis
        (Query) endMillis
    .PARAMETER Precedingdurationmillis
        (Query) precedingDurationMillis
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uuid,
        [Parameter()][string]$Participantid,
        [Parameter()][string]$Startmillis,
        [Parameter()][string]$Endmillis,
        [Parameter()][string]$Precedingdurationmillis
    )

        $qp = @{
            "participantId" = $Participantid
            "startMillis" = $Startmillis
            "endMillis" = $Endmillis
            "precedingDurationMillis" = $Precedingdurationmillis
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/replication/share-latencies/${Uuid}" -QueryParams $qp
}

function Get-HsReportAlignment {
    <#
    .SYNOPSIS
        Query influxDB for alignment stats data
    .DESCRIPTION
        GET /reports/stats/alignment/{objectType}/{objectUuid}
    .PARAMETER Objecttype
        (Path) objectType
    .PARAMETER Objectuuid
        (Path) objectUuid
    .PARAMETER Precedingduration
        (Query) precedingDuration
    .PARAMETER Intervalduration
        (Query) intervalDuration
    .PARAMETER Breakdown
        (Query) breakdown
    .PARAMETER Shareuuid
        (Query) shareUuid
    .PARAMETER Volumeuuid
        (Query) volumeUuid
    .PARAMETER Filltype
        (Query) fillType
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Objecttype,
        [Parameter(Mandatory)][string]$Objectuuid,
        [Parameter()][string]$Precedingduration,
        [Parameter()][string]$Intervalduration,
        [Parameter()][string]$Breakdown,
        [Parameter()][string]$Shareuuid,
        [Parameter()][string]$Volumeuuid,
        [Parameter()][string]$Filltype
    )

        $qp = @{
            "precedingDuration" = $Precedingduration
            "intervalDuration" = $Intervalduration
            "breakdown" = $Breakdown
            "shareUuid" = $Shareuuid
            "volumeUuid" = $Volumeuuid
            "fillType" = $Filltype
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/stats/alignment/${Objecttype}/${Objectuuid}" -QueryParams $qp
}

function Get-HsReportCloud {
    <#
    .SYNOPSIS
        Query influxDB for cloud stats data
    .DESCRIPTION
        GET /reports/stats/cloud/{objectType}/{objectUuid}
    .PARAMETER Objecttype
        (Path) objectType
    .PARAMETER Objectuuid
        (Path) objectUuid
    .PARAMETER Precedingduration
        (Query) precedingDuration
    .PARAMETER Intervalduration
        (Query) intervalDuration
    .PARAMETER Filestat
        (Query) fileStat
    .PARAMETER Breakdown
        (Query) breakdown
    .PARAMETER Volumeuuid
        (Query) volumeUuid
    .PARAMETER Filltype
        (Query) fillType
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Objecttype,
        [Parameter(Mandatory)][string]$Objectuuid,
        [Parameter()][string]$Precedingduration,
        [Parameter()][string]$Intervalduration,
        [Parameter()][string]$Filestat,
        [Parameter()][string]$Breakdown,
        [Parameter()][string]$Volumeuuid,
        [Parameter()][string]$Filltype
    )

        $qp = @{
            "precedingDuration" = $Precedingduration
            "intervalDuration" = $Intervalduration
            "fileStat" = $Filestat
            "breakdown" = $Breakdown
            "volumeUuid" = $Volumeuuid
            "fillType" = $Filltype
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/stats/cloud/${Objecttype}/${Objectuuid}" -QueryParams $qp
}

function Get-HsReportMetadata {
    <#
    .SYNOPSIS
        Query influxDB for metadata stats data
    .DESCRIPTION
        GET /reports/stats/metadata/{objectType}/{objectUuid}
    .PARAMETER Objecttype
        (Path) objectType
    .PARAMETER Objectuuid
        (Path) objectUuid
    .PARAMETER Precedingduration
        (Query) precedingDuration
    .PARAMETER Intervalduration
        (Query) intervalDuration
    .PARAMETER Filltype
        (Query) fillType
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Objecttype,
        [Parameter(Mandatory)][string]$Objectuuid,
        [Parameter()][string]$Precedingduration,
        [Parameter()][string]$Intervalduration,
        [Parameter()][string]$Filltype
    )

        $qp = @{
            "precedingDuration" = $Precedingduration
            "intervalDuration" = $Intervalduration
            "fillType" = $Filltype
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/stats/metadata/${Objecttype}/${Objectuuid}" -QueryParams $qp
}

function Get-HsReportPerformance {
    <#
    .SYNOPSIS
        Query influxDB for performance stats data
    .DESCRIPTION
        GET /reports/stats/performance/{objectType}/{objectUuid}
    .PARAMETER Objecttype
        (Path) objectType
    .PARAMETER Objectuuid
        (Path) objectUuid
    .PARAMETER Precedingduration
        (Query) precedingDuration
    .PARAMETER Intervalduration
        (Query) intervalDuration
    .PARAMETER Breakdown
        (Query) breakdown
    .PARAMETER Shareuuid
        (Query) shareUuid
    .PARAMETER Volumeuuid
        (Query) volumeUuid
    .PARAMETER Filltype
        (Query) fillType
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Objecttype,
        [Parameter(Mandatory)][string]$Objectuuid,
        [Parameter()][string]$Precedingduration,
        [Parameter()][string]$Intervalduration,
        [Parameter()][string]$Breakdown,
        [Parameter()][string]$Shareuuid,
        [Parameter()][string]$Volumeuuid,
        [Parameter()][string]$Filltype
    )

        $qp = @{
            "precedingDuration" = $Precedingduration
            "intervalDuration" = $Intervalduration
            "breakdown" = $Breakdown
            "shareUuid" = $Shareuuid
            "volumeUuid" = $Volumeuuid
            "fillType" = $Filltype
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/stats/performance/${Objecttype}/${Objectuuid}" -QueryParams $qp
}

function Get-HsReportSpace {
    <#
    .SYNOPSIS
        Query influxDB for space stats data
    .DESCRIPTION
        GET /reports/stats/space/{objectType}/{objectUuid}
    .PARAMETER Objecttype
        (Path) objectType
    .PARAMETER Objectuuid
        (Path) objectUuid
    .PARAMETER Precedingduration
        (Query) precedingDuration
    .PARAMETER Intervalduration
        (Query) intervalDuration
    .PARAMETER Breakdown
        (Query) breakdown
    .PARAMETER Shareuuid
        (Query) shareUuid
    .PARAMETER Volumeuuid
        (Query) volumeUuid
    .PARAMETER Filltype
        (Query) fillType
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Objecttype,
        [Parameter(Mandatory)][string]$Objectuuid,
        [Parameter()][string]$Precedingduration,
        [Parameter()][string]$Intervalduration,
        [Parameter()][string]$Breakdown,
        [Parameter()][string]$Shareuuid,
        [Parameter()][string]$Volumeuuid,
        [Parameter()][string]$Filltype
    )

        $qp = @{
            "precedingDuration" = $Precedingduration
            "intervalDuration" = $Intervalduration
            "breakdown" = $Breakdown
            "shareUuid" = $Shareuuid
            "volumeUuid" = $Volumeuuid
            "fillType" = $Filltype
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/stats/space/${Objecttype}/${Objectuuid}" -QueryParams $qp
}

function Get-HsReportVolumesExceededThreshold {
    <#
    .SYNOPSIS
        Query the influxDB for performance reports
    .DESCRIPTION
        GET /reports/volumes-exceeded-threshold
    .PARAMETER Startmillis
        (Query) startMillis
    .PARAMETER Endmillis
        (Query) endMillis
    .PARAMETER Storagecontaineruuid
        (Query) storageContainerUuid
    .PARAMETER Storagecontainertype
        (Query) storageContainerType
    .PARAMETER Precedingdurationmillis
        (Query) precedingDurationMillis
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Startmillis,
        [Parameter()][string]$Endmillis,
        [Parameter()][string]$Storagecontaineruuid,
        [Parameter()][string]$Storagecontainertype,
        [Parameter()][string]$Precedingdurationmillis
    )

        $qp = @{
            "startMillis" = $Startmillis
            "endMillis" = $Endmillis
            "storageContainerUuid" = $Storagecontaineruuid
            "storageContainerType" = $Storagecontainertype
            "precedingDurationMillis" = $Precedingdurationmillis
        }

        Invoke-HsRequest -Method GET -Endpoint "/reports/volumes-exceeded-threshold" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: roles
# ---------------------------------------------------------------------------

function Get-HsRole {
    <#
    .SYNOPSIS
        List user roles
    .DESCRIPTION
        List user roles
    .NOTES
    CLI equivalent: role-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/roles" -QueryParams $qp
}

function New-HsRole {
    <#
    .SYNOPSIS
        Create a user role with access permissions
    .DESCRIPTION
        Create a user role with access permissions

    .EXAMPLE
        role-create --name graham --acl "ANY:+c+r+u+d"
    .NOTES
    CLI equivalent: role-create
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][hashtable]$Loginpolicy,
        [ValidateSet('SYSTEM', 'CUSTOMER')]
        [Parameter()][string]$Deftype,
        [Parameter()][object[]]$Acls,
        [Parameter()][int]$Idletimeoutseconds
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Loginpolicy")) { $body["loginPolicy"] = $Loginpolicy }
        if ($PSBoundParameters.ContainsKey("Deftype")) { $body["defType"] = $Deftype }
        if ($PSBoundParameters.ContainsKey("Acls")) { $body["acls"] = $Acls }
        if ($PSBoundParameters.ContainsKey("Idletimeoutseconds")) { $body["idleTimeoutSeconds"] = $Idletimeoutseconds }

        Invoke-HsRequest -Method POST -Endpoint "/roles" -Body $body
}

function Get-HsRole2 {
    <#
    .SYNOPSIS
        Get role
    .DESCRIPTION
        GET /roles/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/roles/${Identifier}"
}

function Set-HsRole {
    <#
    .SYNOPSIS
        Update an existing user role
    .DESCRIPTION
        Update an existing user role

    .EXAMPLE
        role-update --name graham --acl "ANY:+c+r+u-d"
    .NOTES
    CLI equivalent: role-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][hashtable]$Loginpolicy,
        [ValidateSet('SYSTEM', 'CUSTOMER')]
        [Parameter()][string]$Deftype,
        [Parameter()][object[]]$Acls,
        [Parameter()][int]$Idletimeoutseconds
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Loginpolicy")) { $body["loginPolicy"] = $Loginpolicy }
        if ($PSBoundParameters.ContainsKey("Deftype")) { $body["defType"] = $Deftype }
        if ($PSBoundParameters.ContainsKey("Acls")) { $body["acls"] = $Acls }
        if ($PSBoundParameters.ContainsKey("Idletimeoutseconds")) { $body["idleTimeoutSeconds"] = $Idletimeoutseconds }

        Invoke-HsRequest -Method PUT -Endpoint "/roles/${Identifier}" -Body $body
}

function Remove-HsRole {
    <#
    .SYNOPSIS
        Remove a user role
    .DESCRIPTION
        Remove a user role
    .NOTES
    CLI equivalent: role-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/roles/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: s3server
# ---------------------------------------------------------------------------

function Get-HsS3server {
    <#
    .SYNOPSIS
        List S3 servers
    .DESCRIPTION
        List S3 servers
    .NOTES
    CLI equivalent: s3-server-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Referenceview,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "referenceView" = $Referenceview
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/s3server" -QueryParams $qp
}

function New-HsS3server {
    <#
    .SYNOPSIS
        Create an S3 server
    .DESCRIPTION
        Create an S3 server
    .NOTES
    CLI equivalent: s3-server-create
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$ValidateOnly,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][object[]]$Endpoints,
        [Parameter()][object[]]$Users,
        [Parameter()][object[]]$Buckets,
        [Parameter()][object[]]$Bucketcontainers,
        [ValidateSet('LOCAL', 'AD')]
        [Parameter()][string]$Identityprovider,
        [Parameter()][object[]]$Ports,
        [Parameter()][string]$Umask,
        [ValidateSet('PUBLIC', 'GROUP', 'PRIVATE')]
        [Parameter()][string]$Acl,
        [Parameter()][int]$Maxkeys,
        [Parameter()][switch]$Strictbucketnaming,
        [Parameter()][switch]$Strictbucketlisting,
        [Parameter()][switch]$Defaultserver,
        [Parameter()][string]$Managementkey,
        [Parameter()][string]$Managementsecret,
        [Parameter()][string]$Region,
        [Parameter()][string]$Endpointprefix,
        [Parameter()][int]$Mpuabortthresholddays,
        [Parameter()][string]$Effectiveendpointprefix
    )

        $qp = @{
            "validate-only" = $ValidateOnly
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Endpoints")) { $body["endpoints"] = $Endpoints }
        if ($PSBoundParameters.ContainsKey("Users")) { $body["users"] = $Users }
        if ($PSBoundParameters.ContainsKey("Buckets")) { $body["buckets"] = $Buckets }
        if ($PSBoundParameters.ContainsKey("Bucketcontainers")) { $body["bucketContainers"] = $Bucketcontainers }
        if ($PSBoundParameters.ContainsKey("Identityprovider")) { $body["identityProvider"] = $Identityprovider }
        if ($PSBoundParameters.ContainsKey("Ports")) { $body["ports"] = $Ports }
        if ($PSBoundParameters.ContainsKey("Umask")) { $body["umask"] = $Umask }
        if ($PSBoundParameters.ContainsKey("Acl")) { $body["acl"] = $Acl }
        if ($PSBoundParameters.ContainsKey("Maxkeys")) { $body["maxKeys"] = $Maxkeys }
        $body["strictBucketNaming"] = $Strictbucketnaming.IsPresent
        $body["strictBucketListing"] = $Strictbucketlisting.IsPresent
        $body["defaultServer"] = $Defaultserver.IsPresent
        if ($PSBoundParameters.ContainsKey("Managementkey")) { $body["managementKey"] = $Managementkey }
        if ($PSBoundParameters.ContainsKey("Managementsecret")) { $body["managementSecret"] = $Managementsecret }
        if ($PSBoundParameters.ContainsKey("Region")) { $body["region"] = $Region }
        if ($PSBoundParameters.ContainsKey("Endpointprefix")) { $body["endpointPrefix"] = $Endpointprefix }
        if ($PSBoundParameters.ContainsKey("Mpuabortthresholddays")) { $body["mpuAbortThresholdDays"] = $Mpuabortthresholddays }
        if ($PSBoundParameters.ContainsKey("Effectiveendpointprefix")) { $body["effectiveEndpointPrefix"] = $Effectiveendpointprefix }

        Invoke-HsRequest -Method POST -Endpoint "/s3server" -QueryParams $qp -Body $body
}

function Get-HsS3server2 {
    <#
    .SYNOPSIS
        Get S3 server by ID
    .DESCRIPTION
        GET /s3server/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Withunclearedeventseverity
        (Query) withUnclearedEventSeverity
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Withunclearedeventseverity
    )

        $qp = @{
            "withUnclearedEventSeverity" = $Withunclearedeventseverity
        }

        Invoke-HsRequest -Method GET -Endpoint "/s3server/${Identifier}" -QueryParams $qp
}

function Set-HsS3server {
    <#
    .SYNOPSIS
        Update an S3 server
    .DESCRIPTION
        Update an S3 server
    .NOTES
    CLI equivalent: s3-server-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$ValidateOnly,
        [Parameter()][string]$Deletebucketcontent,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][object[]]$Endpoints,
        [Parameter()][object[]]$Users,
        [Parameter()][object[]]$Buckets,
        [Parameter()][object[]]$Bucketcontainers,
        [ValidateSet('LOCAL', 'AD')]
        [Parameter()][string]$Identityprovider,
        [Parameter()][object[]]$Ports,
        [Parameter()][string]$Umask,
        [ValidateSet('PUBLIC', 'GROUP', 'PRIVATE')]
        [Parameter()][string]$Acl,
        [Parameter()][int]$Maxkeys,
        [Parameter()][switch]$Strictbucketnaming,
        [Parameter()][switch]$Strictbucketlisting,
        [Parameter()][switch]$Defaultserver,
        [Parameter()][string]$Managementkey,
        [Parameter()][string]$Managementsecret,
        [Parameter()][string]$Region,
        [Parameter()][string]$Endpointprefix,
        [Parameter()][int]$Mpuabortthresholddays,
        [Parameter()][string]$Effectiveendpointprefix
    )

        $qp = @{
            "validate-only" = $ValidateOnly
            "deleteBucketContent" = $Deletebucketcontent
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Endpoints")) { $body["endpoints"] = $Endpoints }
        if ($PSBoundParameters.ContainsKey("Users")) { $body["users"] = $Users }
        if ($PSBoundParameters.ContainsKey("Buckets")) { $body["buckets"] = $Buckets }
        if ($PSBoundParameters.ContainsKey("Bucketcontainers")) { $body["bucketContainers"] = $Bucketcontainers }
        if ($PSBoundParameters.ContainsKey("Identityprovider")) { $body["identityProvider"] = $Identityprovider }
        if ($PSBoundParameters.ContainsKey("Ports")) { $body["ports"] = $Ports }
        if ($PSBoundParameters.ContainsKey("Umask")) { $body["umask"] = $Umask }
        if ($PSBoundParameters.ContainsKey("Acl")) { $body["acl"] = $Acl }
        if ($PSBoundParameters.ContainsKey("Maxkeys")) { $body["maxKeys"] = $Maxkeys }
        $body["strictBucketNaming"] = $Strictbucketnaming.IsPresent
        $body["strictBucketListing"] = $Strictbucketlisting.IsPresent
        $body["defaultServer"] = $Defaultserver.IsPresent
        if ($PSBoundParameters.ContainsKey("Managementkey")) { $body["managementKey"] = $Managementkey }
        if ($PSBoundParameters.ContainsKey("Managementsecret")) { $body["managementSecret"] = $Managementsecret }
        if ($PSBoundParameters.ContainsKey("Region")) { $body["region"] = $Region }
        if ($PSBoundParameters.ContainsKey("Endpointprefix")) { $body["endpointPrefix"] = $Endpointprefix }
        if ($PSBoundParameters.ContainsKey("Mpuabortthresholddays")) { $body["mpuAbortThresholdDays"] = $Mpuabortthresholddays }
        if ($PSBoundParameters.ContainsKey("Effectiveendpointprefix")) { $body["effectiveEndpointPrefix"] = $Effectiveendpointprefix }

        Invoke-HsRequest -Method PUT -Endpoint "/s3server/${Identifier}" -QueryParams $qp -Body $body
}

function Remove-HsS3server {
    <#
    .SYNOPSIS
        Delete an S3 server
    .DESCRIPTION
        Delete an S3 server
    .NOTES
    CLI equivalent: s3-server-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/s3server/${Identifier}"
}

function Add-HsS3serverBucket {
    <#
    .SYNOPSIS
        Add a new bucket or bucket container to an existing S3 server
    .DESCRIPTION
        Add a new bucket or bucket container to an existing S3 server
    .NOTES
    CLI equivalent: s3-server-bucket-create
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][hashtable]$Share,
        [Parameter()][string]$Path,
        [Parameter()][string]$Alias,
        [ValidateSet('PUBLIC', 'GROUP', 'PRIVATE')]
        [Parameter()][string]$Acl,
        [ValidateSet('PUBLIC', 'GROUP', 'PRIVATE')]
        [Parameter()][string]$Effectiveacl,
        [Parameter()][string]$Umask,
        [Parameter()][string]$Region
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Share")) { $body["share"] = $Share }
        if ($PSBoundParameters.ContainsKey("Path")) { $body["path"] = $Path }
        if ($PSBoundParameters.ContainsKey("Alias")) { $body["alias"] = $Alias }
        if ($PSBoundParameters.ContainsKey("Acl")) { $body["acl"] = $Acl }
        if ($PSBoundParameters.ContainsKey("Effectiveacl")) { $body["effectiveAcl"] = $Effectiveacl }
        if ($PSBoundParameters.ContainsKey("Umask")) { $body["umask"] = $Umask }
        if ($PSBoundParameters.ContainsKey("Region")) { $body["region"] = $Region }

        Invoke-HsRequest -Method POST -Endpoint "/s3server/${Identifier}/bucket" -Body $body
}

function Remove-HsS3serverBucket {
    <#
    .SYNOPSIS
        Remove a bucket or bucket container from an S3 server
    .DESCRIPTION
        Remove a bucket or bucket container from an S3 server
    .NOTES
    CLI equivalent: s3-server-bucket-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Bucketname,
        [Parameter()][string]$Deletebucketcontent
    )

        $qp = @{
            "bucketName" = $Bucketname
            "deleteBucketContent" = $Deletebucketcontent
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/s3server/${Identifier}/bucket" -QueryParams $qp
}

function Get-HsS3serverListbuckets {
    <#
    .SYNOPSIS
        GET /s3server/{identifier}/listBuckets
    .DESCRIPTION
        GET /s3server/{identifier}/listBuckets
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/s3server/${Identifier}/listBuckets"
}

function Add-HsS3serverUser {
    <#
    .SYNOPSIS
        Add an authorized users to an S3 server
    .DESCRIPTION
        Add an authorized users to an S3 server
    .NOTES
    CLI equivalent: s3-server-user-add
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][hashtable]$User,
        [Parameter()][string]$Accesskey,
        [Parameter()][string]$Secretkey,
        [Parameter()][switch]$Enabled
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("User")) { $body["user"] = $User }
        if ($PSBoundParameters.ContainsKey("Accesskey")) { $body["accessKey"] = $Accesskey }
        if ($PSBoundParameters.ContainsKey("Secretkey")) { $body["secretKey"] = $Secretkey }
        $body["enabled"] = $Enabled.IsPresent

        Invoke-HsRequest -Method POST -Endpoint "/s3server/${Identifier}/user" -Body $body
}

function Remove-HsS3serverUser {
    <#
    .SYNOPSIS
        Remove user from an S3 server
    .DESCRIPTION
        Remove user from an S3 server
    .NOTES
    CLI equivalent: s3-server-user-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Username
    )

        $qp = @{
            "userName" = $Username
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/s3server/${Identifier}/user" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: schedules
# ---------------------------------------------------------------------------

function Get-HsSchedule {
    <#
    .SYNOPSIS
        List schedules
    .DESCRIPTION
        List schedules
    .NOTES
    CLI equivalent: schedule-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/schedules" -QueryParams $qp
}

function New-HsSchedule {
    <#
    .SYNOPSIS
        Create a schedule
    .DESCRIPTION
        Create a schedule
    .NOTES
    CLI equivalent: schedule-create
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][object[]]$Snapshots,
        [Parameter()][hashtable]$Sharesnapshots,
        [Parameter()][object[]]$Backups,
        [Parameter()][string]$Cronexpression,
        [Parameter()][string]$Crondesc
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Snapshots")) { $body["snapshots"] = $Snapshots }
        if ($PSBoundParameters.ContainsKey("Sharesnapshots")) { $body["shareSnapshots"] = $Sharesnapshots }
        if ($PSBoundParameters.ContainsKey("Backups")) { $body["backups"] = $Backups }
        if ($PSBoundParameters.ContainsKey("Cronexpression")) { $body["cronExpression"] = $Cronexpression }
        if ($PSBoundParameters.ContainsKey("Crondesc")) { $body["cronDesc"] = $Crondesc }

        Invoke-HsRequest -Method POST -Endpoint "/schedules" -Body $body
}

function Get-HsSchedule2 {
    <#
    .SYNOPSIS
        Get snapshot schedule by ID
    .DESCRIPTION
        GET /schedules/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/schedules/${Identifier}"
}

function Set-HsSchedule {
    <#
    .SYNOPSIS
        Update a schedule
    .DESCRIPTION
        Update a schedule
    .NOTES
    CLI equivalent: schedule-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/schedules/${Identifier}" -Body $body
}

function Remove-HsSchedule {
    <#
    .SYNOPSIS
        Delete a schedule
    .DESCRIPTION
        Delete a schedule
    .NOTES
    CLI equivalent: schedule-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/schedules/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: share-participants
# ---------------------------------------------------------------------------

function Get-HsShareParticipant {
    <#
    .SYNOPSIS
        Display a list of all configured global file system participants, or a list filtered to a specific share
    .DESCRIPTION
        Display a list of all configured global file system participants, or a list filtered to a specific share
    .NOTES
    CLI equivalent: gfs-participant-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/share-participants" -QueryParams $qp
}

function New-HsShareParticipant {
    <#
    .SYNOPSIS
        Configure another site to participate in a global file system share by creating a share on the remote
    .DESCRIPTION
        Configure another site to participate in a global file system share by creating a share on the remote
    .NOTES
    CLI equivalent: gfs-participant-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][int]$Remoteshareinternalid,
        [Parameter()][int]$Participantid,
        [Parameter()][hashtable]$Share,
        [Parameter()][int]$Updateinterval,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][string]$Operstatereason,
        [Parameter()][string]$Objectstoragevolumescsv,
        [Parameter()][int]$Shareinternalid,
        [Parameter()][string]$Sharename,
        [Parameter()][hashtable]$Latency,
        [Parameter()][hashtable]$Addspec,
        [Parameter()][hashtable]$Removespec
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Remoteshareinternalid")) { $body["remoteShareInternalId"] = $Remoteshareinternalid }
        if ($PSBoundParameters.ContainsKey("Participantid")) { $body["participantId"] = $Participantid }
        if ($PSBoundParameters.ContainsKey("Share")) { $body["share"] = $Share }
        if ($PSBoundParameters.ContainsKey("Updateinterval")) { $body["updateInterval"] = $Updateinterval }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Operstatereason")) { $body["operStateReason"] = $Operstatereason }
        if ($PSBoundParameters.ContainsKey("Objectstoragevolumescsv")) { $body["objectStorageVolumesCsv"] = $Objectstoragevolumescsv }
        if ($PSBoundParameters.ContainsKey("Shareinternalid")) { $body["shareInternalId"] = $Shareinternalid }
        if ($PSBoundParameters.ContainsKey("Sharename")) { $body["shareName"] = $Sharename }
        if ($PSBoundParameters.ContainsKey("Latency")) { $body["latency"] = $Latency }
        if ($PSBoundParameters.ContainsKey("Addspec")) { $body["addSpec"] = $Addspec }
        if ($PSBoundParameters.ContainsKey("Removespec")) { $body["removeSpec"] = $Removespec }

        Invoke-HsRequest -Method POST -Endpoint "/share-participants" -Body $body
}

function Set-HsShareParticipantChangeAdminState {
    <#
    .SYNOPSIS
        Allow replication of data and metadata ‘to’ share participant(s). When one of id, internal-id, or name
    .DESCRIPTION
        Allow replication of data and metadata ‘to’ share participant(s). When one of id, internal-id, or name. Stop replication of data and metadata ‘to’ share participant(s). When one of id, internal-id, or name is
    .NOTES
    CLI equivalent: gfs-participant-enable, gfs-participant-disable
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$State,
        [Parameter()][string]$Site,
        [Parameter()][string]$Share
    )

        $qp = @{
            "state" = $State
            "site" = $Site
            "share" = $Share
        }

        Invoke-HsRequest -Method PUT -Endpoint "/share-participants/change-admin-state" -QueryParams $qp
}

function Get-HsShareParticipant2 {
    <#
    .SYNOPSIS
        Get a share participant by ID
    .DESCRIPTION
        GET /share-participants/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/share-participants/${Identifier}"
}

function Set-HsShareParticipant {
    <#
    .SYNOPSIS
        Update a share participant
    .DESCRIPTION
        PUT /share-participants/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Comment
        (Body) comment
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/share-participants/${Identifier}" -Body $body
}

function Remove-HsShareParticipant {
    <#
    .SYNOPSIS
        Remove a site from a share replication by removing the site as a participant of the share
    .DESCRIPTION
        Remove a site from a share replication by removing the site as a participant of the share
    .NOTES
    CLI equivalent: gfs-participant-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Ignoreremovefailures,
        [Parameter()][string]$Forcemasteracquisition
    )

        $qp = @{
            "ignoreRemoveFailures" = $Ignoreremovefailures
            "forceMasterAcquisition" = $Forcemasteracquisition
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/share-participants/${Identifier}" -QueryParams $qp
}

function Remove-HsShareParticipant2 {
    <#
    .SYNOPSIS
        Removes a GFS participant from a share. Regardless of which participant is specified, that participant's share will be stripped of all other participants, and the share at all other sites will be stripped of the specified participant.
    .DESCRIPTION
        DELETE /share-participants/{share-identifier}/{site-identifier}
    .PARAMETER ShareIdentifier
        (Path) share-identifier
    .PARAMETER SiteIdentifier
        (Path) site-identifier
    .PARAMETER Ignoreremovefailures
        (Query) ignoreRemoveFailures
    .PARAMETER Forcemasteracquisition
        (Query) forceMasterAcquisition
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShareIdentifier,
        [Parameter(Mandatory)][string]$SiteIdentifier,
        [Parameter()][string]$Ignoreremovefailures,
        [Parameter()][string]$Forcemasteracquisition
    )

        $qp = @{
            "ignoreRemoveFailures" = $Ignoreremovefailures
            "forceMasterAcquisition" = $Forcemasteracquisition
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/share-participants/${ShareIdentifier}/${SiteIdentifier}" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: share-replications
# ---------------------------------------------------------------------------

function Remove-HsShareReplication {
    <#
    .SYNOPSIS
        Cause the specified participant to no longer participant in the replicating share. regardless of which participant is specified, that participant's share will be stripped of all other participants, and the share at all other sites will be stripped of the specified participant.
    .DESCRIPTION
        PUT /share-replications/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER SiteId
        (Query) site-id
    .PARAMETER SiteName
        (Query) site-name
    .PARAMETER SiteInternalId
        (Query) site-internal-id
    .PARAMETER SiteAddress
        (Query) site-address
    .PARAMETER SiteParticipantId
        (Query) site-participant-id
    .PARAMETER Ignoreremotefailures
        (Query) ignoreRemoteFailures
    .PARAMETER ForceMasterAcquisition
        (Query) force-master-acquisition
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$SiteId,
        [Parameter()][string]$SiteName,
        [Parameter()][string]$SiteInternalId,
        [Parameter()][string]$SiteAddress,
        [Parameter()][string]$SiteParticipantId,
        [Parameter()][string]$Ignoreremotefailures,
        [Parameter()][string]$ForceMasterAcquisition
    )

        $qp = @{
            "site-id" = $SiteId
            "site-name" = $SiteName
            "site-internal-id" = $SiteInternalId
            "site-address" = $SiteAddress
            "site-participant-id" = $SiteParticipantId
            "ignoreRemoteFailures" = $Ignoreremotefailures
            "force-master-acquisition" = $ForceMasterAcquisition
        }

        Invoke-HsRequest -Method PUT -Endpoint "/share-replications/${Identifier}" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: share-snapshots
# ---------------------------------------------------------------------------

function Get-HsShareSnapshotSchedule {
    <#
    .SYNOPSIS
        List snapshots for share
    .DESCRIPTION
        List snapshots for share. List scheduled snapshots for share
    .NOTES
    CLI equivalent: share-snapshot-list, share-snapshot-schedule-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/share-snapshots" -QueryParams $qp
}

function New-HsShareSnapshotSchedule {
    <#
    .SYNOPSIS
        Create share snapshot schedule
    .DESCRIPTION
        POST /share-snapshots
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Schedule
        (Body) schedule
    .PARAMETER Retention
        (Body) retention
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][hashtable]$Schedule,
        [Parameter()][hashtable]$Retention
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Schedule")) { $body["schedule"] = $Schedule }
        if ($PSBoundParameters.ContainsKey("Retention")) { $body["retention"] = $Retention }

        Invoke-HsRequest -Method POST -Endpoint "/share-snapshots" -Body $body
}

function Copy-HsShareSnapshotCloneCreate {
    <#
    .SYNOPSIS
        Clone share snapshot
    .DESCRIPTION
        Clone share snapshot
    .NOTES
    CLI equivalent: share-clone-create
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShareIdentifier,
        [Parameter()][string]$SnapshotName,
        [Parameter()][string]$DestinationPath,
        [Parameter()][string]$OverwriteDestination
    )

        $qp = @{
            "snapshot-name" = $SnapshotName
            "destination-path" = $DestinationPath
            "overwrite-destination" = $OverwriteDestination
        }

        Invoke-HsRequest -Method POST -Endpoint "/share-snapshots/clone-create/${ShareIdentifier}" -QueryParams $qp
}

function New-HsShareSnapshotCreate {
    <#
    .SYNOPSIS
        Create share snapshot
    .DESCRIPTION
        Create share snapshot

    .EXAMPLE
        share-snapshot-create --share-name test --now
    .NOTES
    CLI equivalent: share-snapshot-create
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShareIdentifier,
        [Parameter()][string]$SnapshotName
    )

        $qp = @{
            "snapshot-name" = $SnapshotName
        }

        Invoke-HsRequest -Method POST -Endpoint "/share-snapshots/snapshot-create/${ShareIdentifier}" -QueryParams $qp
}

function Remove-HsShareSnapshotDelete {
    <#
    .SYNOPSIS
        Delete share snapshot
    .DESCRIPTION
        Delete share snapshot
    .NOTES
    CLI equivalent: share-snapshot-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShareIdentifier,
        [Parameter(Mandatory)][string]$SnapshotName
    )

        Invoke-HsRequest -Method POST -Endpoint "/share-snapshots/snapshot-delete/${ShareIdentifier}/${SnapshotName}"
}

function Get-HsShareSnapshotList {
    <#
    .SYNOPSIS
        List snapshots for share
    .DESCRIPTION
        List snapshots for share
    .NOTES
    CLI equivalent: share-snapshot-list
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShareIdentifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/share-snapshots/snapshot-list/${ShareIdentifier}"
}

function Restore-HsShareSnapshotRestoreFiles {
    <#
    .SYNOPSIS
        Restore files from share snapshot
    .DESCRIPTION
        POST /share-snapshots/snapshot-restore-files/{share-identifier}/{snapshot-name}
    .PARAMETER ShareIdentifier
        (Path) share-identifier
    .PARAMETER SnapshotName
        (Path) snapshot-name
    .PARAMETER Filename
        (Query) filename
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShareIdentifier,
        [Parameter(Mandatory)][string]$SnapshotName,
        [Parameter()][string]$Filename
    )

        $qp = @{
            "filename" = $Filename
        }

        Invoke-HsRequest -Method POST -Endpoint "/share-snapshots/snapshot-restore-files/${ShareIdentifier}/${SnapshotName}" -QueryParams $qp
}

function Restore-HsShareSnapshotRestore {
    <#
    .SYNOPSIS
        Restore files from a share snapshot (when used with –filename option) or a complete share
    .DESCRIPTION
        Restore files from a share snapshot (when used with –filename option) or a complete share
    .NOTES
    CLI equivalent: share-snapshot-restore
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ShareIdentifier,
        [Parameter(Mandatory)][string]$SnapshotName
    )

        Invoke-HsRequest -Method POST -Endpoint "/share-snapshots/snapshot-restore/${ShareIdentifier}/${SnapshotName}"
}

function Set-HsShareSnapshotSchedule {
    <#
    .SYNOPSIS
        Update share snapshot schedule
    .DESCRIPTION
        Update share snapshot schedule
    .NOTES
    CLI equivalent: share-snapshot-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/share-snapshots/${Identifier}" -Body $body
}

function Remove-HsShareSnapshotSchedule {
    <#
    .SYNOPSIS
        Delete share snapshot schedule
    .DESCRIPTION
        DELETE /share-snapshots/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER ClearSnapshots
        (Query) clear-snapshots
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$ClearSnapshots
    )

        $qp = @{
            "clear-snapshots" = $ClearSnapshots
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/share-snapshots/${Identifier}" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: shares
# ---------------------------------------------------------------------------

function Get-HsShare {
    <#
    .SYNOPSIS
        Display a list of all shares available in the system. Two types of lists can be displayed: a full list and
    .DESCRIPTION
        Display a list of all shares available in the system. Two types of lists can be displayed: a full list and
    .NOTES
    CLI equivalent: share-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/shares" -QueryParams $qp
}

function New-HsShare {
    <#
    .SYNOPSIS
        Create a share
    .DESCRIPTION
        Create a share

    .EXAMPLE
        share-create --name share2 --path /share2 --export-option *,rw,noroot-squash
    .NOTES
    CLI equivalent: share-create
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$CreatePath,
        [Parameter()][string]$OverrideMemCheck,
        [Parameter()][string]$ValidateOnly,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][string]$Path,
        [ValidateSet('OFFLINE', 'ONLINE', 'MOUNTED', 'PUBLISHED', 'CREATED', 'PRE_REMOVAL', 'REMOVING', 'REMOVED', 'RECLAIMING', 'REMOVE_FAILED')]
        [Parameter()][string]$Sharestate,
        [ValidateSet('CREATING', 'CREATED', 'PRE_DELETE', 'DELETE_SCHEDULED', 'DELETING', 'DELETE_FAILED')]
        [Parameter()][string]$Sharelifecycle,
        [Parameter()][object[]]$Exportoptions,
        [Parameter()][object[]]$Shareobjectives,
        [Parameter()][object[]]$Sharesnapshots,
        [Parameter()][hashtable]$Shareparticipants,
        [Parameter()][switch]$Isorwasreplicated,
        [Parameter()][object[]]$Smbaliases,
        [Parameter()][int]$Sharesizelimit,
        [Parameter()][int]$Warnutilizationpercentthreshold,
        [ValidateSet('NORMAL', 'WARNING', 'OVER_QUOTA')]
        [Parameter()][string]$Utilizationstate,
        [Parameter()][string]$Preferreddomain,
        [Parameter()][string]$Unmappeduser,
        [Parameter()][string]$Unmappedgroup,
        [Parameter()][int]$Participantid,
        [Parameter()][int]$Nextparticipantid,
        [Parameter()][int]$Replicationlatencyalertthreshold,
        [Parameter()][string]$Logicalshareuuid,
        [Parameter()][string]$Clientcert,
        [Parameter()][hashtable]$Owningmdsi,
        [Parameter()][string]$Defaultselinuxcontext,
        [Parameter()][hashtable]$Referral,
        [Parameter()][switch]$Isreferral,
        [Parameter()][string]$Privatekeycrc32fingerprint,
        [Parameter()][switch]$Smbbrowsable,
        [Parameter()][string]$Replicationclientcert,
        [Parameter()][string]$Replicationprivatekey,
        [Parameter()][object[]]$Stats,
        [Parameter()][int]$Totalnumberoffiles,
        [Parameter()][int]$Numberofopenfiles,
        [Parameter()][hashtable]$Space,
        [Parameter()][hashtable]$Inodes,
        [Parameter()][int]$Scheduledpurgetime,
        [Parameter()][hashtable]$Objectives,
        [Parameter()][object[]]$Attributes
    )

        $qp = @{
            "create-path" = $CreatePath
            "override-mem-check" = $OverrideMemCheck
            "validate-only" = $ValidateOnly
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Path")) { $body["path"] = $Path }
        if ($PSBoundParameters.ContainsKey("Sharestate")) { $body["shareState"] = $Sharestate }
        if ($PSBoundParameters.ContainsKey("Sharelifecycle")) { $body["shareLifecycle"] = $Sharelifecycle }
        if ($PSBoundParameters.ContainsKey("Exportoptions")) { $body["exportOptions"] = $Exportoptions }
        if ($PSBoundParameters.ContainsKey("Shareobjectives")) { $body["shareObjectives"] = $Shareobjectives }
        if ($PSBoundParameters.ContainsKey("Sharesnapshots")) { $body["shareSnapshots"] = $Sharesnapshots }
        if ($PSBoundParameters.ContainsKey("Shareparticipants")) { $body["shareParticipants"] = $Shareparticipants }
        $body["isOrWasReplicated"] = $Isorwasreplicated.IsPresent
        if ($PSBoundParameters.ContainsKey("Smbaliases")) { $body["smbAliases"] = $Smbaliases }
        if ($PSBoundParameters.ContainsKey("Sharesizelimit")) { $body["shareSizeLimit"] = $Sharesizelimit }
        if ($PSBoundParameters.ContainsKey("Warnutilizationpercentthreshold")) { $body["warnUtilizationPercentThreshold"] = $Warnutilizationpercentthreshold }
        if ($PSBoundParameters.ContainsKey("Utilizationstate")) { $body["utilizationState"] = $Utilizationstate }
        if ($PSBoundParameters.ContainsKey("Preferreddomain")) { $body["preferredDomain"] = $Preferreddomain }
        if ($PSBoundParameters.ContainsKey("Unmappeduser")) { $body["unmappedUser"] = $Unmappeduser }
        if ($PSBoundParameters.ContainsKey("Unmappedgroup")) { $body["unmappedGroup"] = $Unmappedgroup }
        if ($PSBoundParameters.ContainsKey("Participantid")) { $body["participantId"] = $Participantid }
        if ($PSBoundParameters.ContainsKey("Nextparticipantid")) { $body["nextParticipantId"] = $Nextparticipantid }
        if ($PSBoundParameters.ContainsKey("Replicationlatencyalertthreshold")) { $body["replicationLatencyAlertThreshold"] = $Replicationlatencyalertthreshold }
        if ($PSBoundParameters.ContainsKey("Logicalshareuuid")) { $body["logicalShareUuid"] = $Logicalshareuuid }
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        if ($PSBoundParameters.ContainsKey("Owningmdsi")) { $body["owningMdsi"] = $Owningmdsi }
        if ($PSBoundParameters.ContainsKey("Defaultselinuxcontext")) { $body["defaultSELinuxContext"] = $Defaultselinuxcontext }
        if ($PSBoundParameters.ContainsKey("Referral")) { $body["referral"] = $Referral }
        $body["isReferral"] = $Isreferral.IsPresent
        if ($PSBoundParameters.ContainsKey("Privatekeycrc32fingerprint")) { $body["privateKeyCrc32Fingerprint"] = $Privatekeycrc32fingerprint }
        $body["smbBrowsable"] = $Smbbrowsable.IsPresent
        if ($PSBoundParameters.ContainsKey("Replicationclientcert")) { $body["replicationClientCert"] = $Replicationclientcert }
        if ($PSBoundParameters.ContainsKey("Replicationprivatekey")) { $body["replicationPrivateKey"] = $Replicationprivatekey }
        if ($PSBoundParameters.ContainsKey("Stats")) { $body["stats"] = $Stats }
        if ($PSBoundParameters.ContainsKey("Totalnumberoffiles")) { $body["totalNumberOfFiles"] = $Totalnumberoffiles }
        if ($PSBoundParameters.ContainsKey("Numberofopenfiles")) { $body["numberOfOpenFiles"] = $Numberofopenfiles }
        if ($PSBoundParameters.ContainsKey("Space")) { $body["space"] = $Space }
        if ($PSBoundParameters.ContainsKey("Inodes")) { $body["inodes"] = $Inodes }
        if ($PSBoundParameters.ContainsKey("Scheduledpurgetime")) { $body["scheduledPurgeTime"] = $Scheduledpurgetime }
        if ($PSBoundParameters.ContainsKey("Objectives")) { $body["objectives"] = $Objectives }
        if ($PSBoundParameters.ContainsKey("Attributes")) { $body["attributes"] = $Attributes }

        Invoke-HsRequest -Method POST -Endpoint "/shares" -QueryParams $qp -Body $body
}

function Get-HsShare2 {
    <#
    .SYNOPSIS
        Provide share mounting details for all shares
    .DESCRIPTION
        GET /shares/mount-details
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/shares/mount-details"
}

function Get-HsShare3 {
    <#
    .SYNOPSIS
        Get all shares filtered by relation to other entity
    .DESCRIPTION
        GET /shares/related-list
    .PARAMETER Filteruuid
        (Query) filterUuid
    .PARAMETER Filterobjecttype
        (Query) filterObjectType
    .PARAMETER Sort
        (Query) sort
    .PARAMETER Terse
        (Query) terse
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Filteruuid,
        [Parameter()][string]$Filterobjecttype,
        [Parameter()][string]$Sort,
        [Parameter()][string]$Terse,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "filterUuid" = $Filteruuid
            "filterObjectType" = $Filterobjecttype
            "sort" = $Sort
            "terse" = $Terse
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/shares/related-list" -QueryParams $qp
}

function Get-HsShare4 {
    <#
    .SYNOPSIS
        List uuids for all shares
    .DESCRIPTION
        GET /shares/uuid-list
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/shares/uuid-list"
}

function Get-HsShare5 {
    <#
    .SYNOPSIS
        Get share by ID
    .DESCRIPTION
        GET /shares/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Withunclearedeventseverity
        (Query) withUnclearedEventSeverity
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Withunclearedeventseverity
    )

        $qp = @{
            "withUnclearedEventSeverity" = $Withunclearedeventseverity
        }

        Invoke-HsRequest -Method GET -Endpoint "/shares/${Identifier}" -QueryParams $qp
}

function Set-HsShare {
    <#
    .SYNOPSIS
        Update a share
    .DESCRIPTION
        Update a share
    .NOTES
    CLI equivalent: share-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$ValidateOnly,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][string]$Path,
        [ValidateSet('OFFLINE', 'ONLINE', 'MOUNTED', 'PUBLISHED', 'CREATED', 'PRE_REMOVAL', 'REMOVING', 'REMOVED', 'RECLAIMING', 'REMOVE_FAILED')]
        [Parameter()][string]$Sharestate,
        [ValidateSet('CREATING', 'CREATED', 'PRE_DELETE', 'DELETE_SCHEDULED', 'DELETING', 'DELETE_FAILED')]
        [Parameter()][string]$Sharelifecycle,
        [Parameter()][object[]]$Exportoptions,
        [Parameter()][object[]]$Shareobjectives,
        [Parameter()][object[]]$Sharesnapshots,
        [Parameter()][hashtable]$Shareparticipants,
        [Parameter()][switch]$Isorwasreplicated,
        [Parameter()][object[]]$Smbaliases,
        [Parameter()][int]$Sharesizelimit,
        [Parameter()][int]$Warnutilizationpercentthreshold,
        [ValidateSet('NORMAL', 'WARNING', 'OVER_QUOTA')]
        [Parameter()][string]$Utilizationstate,
        [Parameter()][string]$Preferreddomain,
        [Parameter()][string]$Unmappeduser,
        [Parameter()][string]$Unmappedgroup,
        [Parameter()][int]$Participantid,
        [Parameter()][int]$Nextparticipantid,
        [Parameter()][int]$Replicationlatencyalertthreshold,
        [Parameter()][string]$Logicalshareuuid,
        [Parameter()][string]$Clientcert,
        [Parameter()][hashtable]$Owningmdsi,
        [Parameter()][string]$Defaultselinuxcontext,
        [Parameter()][hashtable]$Referral,
        [Parameter()][switch]$Isreferral,
        [Parameter()][string]$Privatekeycrc32fingerprint,
        [Parameter()][switch]$Smbbrowsable,
        [Parameter()][string]$Replicationclientcert,
        [Parameter()][string]$Replicationprivatekey,
        [Parameter()][object[]]$Stats,
        [Parameter()][int]$Totalnumberoffiles,
        [Parameter()][int]$Numberofopenfiles,
        [Parameter()][hashtable]$Space,
        [Parameter()][hashtable]$Inodes,
        [Parameter()][int]$Scheduledpurgetime,
        [Parameter()][hashtable]$Objectives,
        [Parameter()][object[]]$Attributes
    )

        $qp = @{
            "validate-only" = $ValidateOnly
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Path")) { $body["path"] = $Path }
        if ($PSBoundParameters.ContainsKey("Sharestate")) { $body["shareState"] = $Sharestate }
        if ($PSBoundParameters.ContainsKey("Sharelifecycle")) { $body["shareLifecycle"] = $Sharelifecycle }
        if ($PSBoundParameters.ContainsKey("Exportoptions")) { $body["exportOptions"] = $Exportoptions }
        if ($PSBoundParameters.ContainsKey("Shareobjectives")) { $body["shareObjectives"] = $Shareobjectives }
        if ($PSBoundParameters.ContainsKey("Sharesnapshots")) { $body["shareSnapshots"] = $Sharesnapshots }
        if ($PSBoundParameters.ContainsKey("Shareparticipants")) { $body["shareParticipants"] = $Shareparticipants }
        $body["isOrWasReplicated"] = $Isorwasreplicated.IsPresent
        if ($PSBoundParameters.ContainsKey("Smbaliases")) { $body["smbAliases"] = $Smbaliases }
        if ($PSBoundParameters.ContainsKey("Sharesizelimit")) { $body["shareSizeLimit"] = $Sharesizelimit }
        if ($PSBoundParameters.ContainsKey("Warnutilizationpercentthreshold")) { $body["warnUtilizationPercentThreshold"] = $Warnutilizationpercentthreshold }
        if ($PSBoundParameters.ContainsKey("Utilizationstate")) { $body["utilizationState"] = $Utilizationstate }
        if ($PSBoundParameters.ContainsKey("Preferreddomain")) { $body["preferredDomain"] = $Preferreddomain }
        if ($PSBoundParameters.ContainsKey("Unmappeduser")) { $body["unmappedUser"] = $Unmappeduser }
        if ($PSBoundParameters.ContainsKey("Unmappedgroup")) { $body["unmappedGroup"] = $Unmappedgroup }
        if ($PSBoundParameters.ContainsKey("Participantid")) { $body["participantId"] = $Participantid }
        if ($PSBoundParameters.ContainsKey("Nextparticipantid")) { $body["nextParticipantId"] = $Nextparticipantid }
        if ($PSBoundParameters.ContainsKey("Replicationlatencyalertthreshold")) { $body["replicationLatencyAlertThreshold"] = $Replicationlatencyalertthreshold }
        if ($PSBoundParameters.ContainsKey("Logicalshareuuid")) { $body["logicalShareUuid"] = $Logicalshareuuid }
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        if ($PSBoundParameters.ContainsKey("Owningmdsi")) { $body["owningMdsi"] = $Owningmdsi }
        if ($PSBoundParameters.ContainsKey("Defaultselinuxcontext")) { $body["defaultSELinuxContext"] = $Defaultselinuxcontext }
        if ($PSBoundParameters.ContainsKey("Referral")) { $body["referral"] = $Referral }
        $body["isReferral"] = $Isreferral.IsPresent
        if ($PSBoundParameters.ContainsKey("Privatekeycrc32fingerprint")) { $body["privateKeyCrc32Fingerprint"] = $Privatekeycrc32fingerprint }
        $body["smbBrowsable"] = $Smbbrowsable.IsPresent
        if ($PSBoundParameters.ContainsKey("Replicationclientcert")) { $body["replicationClientCert"] = $Replicationclientcert }
        if ($PSBoundParameters.ContainsKey("Replicationprivatekey")) { $body["replicationPrivateKey"] = $Replicationprivatekey }
        if ($PSBoundParameters.ContainsKey("Stats")) { $body["stats"] = $Stats }
        if ($PSBoundParameters.ContainsKey("Totalnumberoffiles")) { $body["totalNumberOfFiles"] = $Totalnumberoffiles }
        if ($PSBoundParameters.ContainsKey("Numberofopenfiles")) { $body["numberOfOpenFiles"] = $Numberofopenfiles }
        if ($PSBoundParameters.ContainsKey("Space")) { $body["space"] = $Space }
        if ($PSBoundParameters.ContainsKey("Inodes")) { $body["inodes"] = $Inodes }
        if ($PSBoundParameters.ContainsKey("Scheduledpurgetime")) { $body["scheduledPurgeTime"] = $Scheduledpurgetime }
        if ($PSBoundParameters.ContainsKey("Objectives")) { $body["objectives"] = $Objectives }
        if ($PSBoundParameters.ContainsKey("Attributes")) { $body["attributes"] = $Attributes }

        Invoke-HsRequest -Method PUT -Endpoint "/shares/${Identifier}" -QueryParams $qp -Body $body
}

function Remove-HsShare {
    <#
    .SYNOPSIS
        Delete a share
    .DESCRIPTION
        Delete a share
    .NOTES
    CLI equivalent: share-delete
    WARNING: WARNING! Deleting a share also deletes all data on the share. This is destructive and
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$DeleteDelay,
        [Parameter()][string]$DeletePath
    )

        $qp = @{
            "delete-delay" = $DeleteDelay
            "delete-path" = $DeletePath
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/shares/${Identifier}" -QueryParams $qp
}

function Get-HsShareAttribute {
    <#
    .SYNOPSIS
        Get attributes of share root inode, or path within share
    .DESCRIPTION
        GET /shares/{identifier}/attribute
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Path
        (Query) path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Path
    )

        $qp = @{
            "path" = $Path
        }

        Invoke-HsRequest -Method GET -Endpoint "/shares/${Identifier}/attribute" -QueryParams $qp
}

function Set-HsShareAttribute {
    <#
    .SYNOPSIS
        Set attribute share root inode, or path within share
    .DESCRIPTION
        POST /shares/{identifier}/attribute
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Path
        (Query) path
    .PARAMETER Name
        (Body) name
    .PARAMETER Type
        (Body) type
    .PARAMETER Value
        (Body) value
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Path,
        [Parameter()][string]$Name,
        [Parameter()][string]$Type,
        [Parameter()][hashtable]$Value
    )

        $qp = @{
            "path" = $Path
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Type")) { $body["type"] = $Type }
        if ($PSBoundParameters.ContainsKey("Value")) { $body["value"] = $Value }

        Invoke-HsRequest -Method POST -Endpoint "/shares/${Identifier}/attribute" -QueryParams $qp -Body $body
}

function Remove-HsShareAttribute {
    <#
    .SYNOPSIS
        Remove attribute from share root inode, or path within share
    .DESCRIPTION
        DELETE /shares/{identifier}/attribute
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Path
        (Query) path
    .PARAMETER Name
        (Query) name
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Path,
        [Parameter()][string]$Name
    )

        $qp = @{
            "path" = $Path
            "name" = $Name
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/shares/${Identifier}/attribute" -QueryParams $qp
}

function Get-HsShareCollectionSum {
    <#
    .SYNOPSIS
        Get collection sums json for the share
    .DESCRIPTION
        GET /shares/{identifier}/collection-sum
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/shares/${Identifier}/collection-sum"
}

function Get-HsShare6 {
    <#
    .SYNOPSIS
        Provide share mounting details
    .DESCRIPTION
        GET /shares/{identifier}/mount-details
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/shares/${Identifier}/mount-details"
}

function Move-HsShareMove {
    <#
    .SYNOPSIS
        Move share to a different path. This command only changes the export map of the share while
    .DESCRIPTION
        Move share to a different path. This command only changes the export map of the share while
    .NOTES
    CLI equivalent: share-move
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter(Mandatory)][string]$Path,
        [Parameter()][string]$CreatePath,
        [Parameter()][string]$ValidateOnly
    )

        $qp = @{
            "create-path" = $CreatePath
            "validate-only" = $ValidateOnly
        }

        Invoke-HsRequest -Method POST -Endpoint "/shares/${Identifier}/move/${Path}" -QueryParams $qp
}

function Get-HsShareObjectiveList {
    <#
    .SYNOPSIS
        Read objective(s) set on share (and optionally a path within the share)
    .DESCRIPTION
        GET /shares/{identifier}/objective-list
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Path
        (Query) path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Path
    )

        $qp = @{
            "path" = $Path
        }

        Invoke-HsRequest -Method GET -Endpoint "/shares/${Identifier}/objective-list" -QueryParams $qp
}

function Reset-HsShareObjectiveReset {
    <#
    .SYNOPSIS
        Reset objectives on share (when path is omitted), or path within share to their defaults
    .DESCRIPTION
        POST /shares/{identifier}/objective-reset
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Path
        (Query) path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Path
    )

        $qp = @{
            "path" = $Path
        }

        Invoke-HsRequest -Method POST -Endpoint "/shares/${Identifier}/objective-reset" -QueryParams $qp
}

function Set-HsShareObjectiveSet {
    <#
    .SYNOPSIS
        Set objective on share (when path is omitted), or path within share
    .DESCRIPTION
        POST /shares/{identifier}/objective-set
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Path
        (Query) path
    .PARAMETER ObjectiveIdentifier
        (Query) objective-identifier
    .PARAMETER Applicability
        (Query) applicability
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Path,
        [Parameter()][string]$ObjectiveIdentifier,
        [Parameter()][string]$Applicability
    )

        $qp = @{
            "path" = $Path
            "objective-identifier" = $ObjectiveIdentifier
            "applicability" = $Applicability
        }

        Invoke-HsRequest -Method POST -Endpoint "/shares/${Identifier}/objective-set" -QueryParams $qp
}

function Clear-HsShareObjectiveUnset {
    <#
    .SYNOPSIS
        Unset objective on share (when path is omitted), or path within share. Note that when this is called with an objective which is inherited & not applied locally, the effect will be that the objective will be added locally with an applicability that negates the inherited applicability.
    .DESCRIPTION
        POST /shares/{identifier}/objective-unset
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Path
        (Query) path
    .PARAMETER ObjectiveIdentifier
        (Query) objective-identifier
    .PARAMETER Applicability
        (Query) applicability
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Path,
        [Parameter()][string]$ObjectiveIdentifier,
        [Parameter()][string]$Applicability
    )

        $qp = @{
            "path" = $Path
            "objective-identifier" = $ObjectiveIdentifier
            "applicability" = $Applicability
        }

        Invoke-HsRequest -Method POST -Endpoint "/shares/${Identifier}/objective-unset" -QueryParams $qp
}

function Update-HsShareObjective {
    <#
    .SYNOPSIS
        Update the applicability of an objective on share (when path is omitted), or path within share
    .DESCRIPTION
        POST /shares/{identifier}/objective-update
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Path
        (Query) path
    .PARAMETER ObjectiveIdentifier
        (Query) objective-identifier
    .PARAMETER Applicability
        (Query) applicability
    .PARAMETER NewApplicability
        (Query) new-applicability
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Path,
        [Parameter()][string]$ObjectiveIdentifier,
        [Parameter()][string]$Applicability,
        [Parameter()][string]$NewApplicability
    )

        $qp = @{
            "path" = $Path
            "objective-identifier" = $ObjectiveIdentifier
            "applicability" = $Applicability
            "new-applicability" = $NewApplicability
        }

        Invoke-HsRequest -Method POST -Endpoint "/shares/${Identifier}/objective-update" -QueryParams $qp
}

function Restore-HsShareUndelete {
    <#
    .SYNOPSIS
        Abort scheduled deletion a share
    .DESCRIPTION
        Abort scheduled deletion a share
    .NOTES
    CLI equivalent: share-undelete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method POST -Endpoint "/shares/${Identifier}/undelete"
}

# ---------------------------------------------------------------------------
# SECTION: sites
# ---------------------------------------------------------------------------

function Get-HsSite {
    <#
    .SYNOPSIS
        List known remote sites
    .DESCRIPTION
        List known remote sites
    .NOTES
    CLI equivalent: remote-site-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/sites" -QueryParams $qp
}

function New-HsSite {
    <#
    .SYNOPSIS
        Add a remote site
    .DESCRIPTION
        Add a remote site
    .NOTES
    CLI equivalent: remote-site-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Address,
        [Parameter()][switch]$Trustclientcert
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Address")) { $body["address"] = $Address }
        $body["trustClientCert"] = $Trustclientcert.IsPresent

        Invoke-HsRequest -Method POST -Endpoint "/sites" -Body $body
}

function Get-HsSite2 {
    <#
    .SYNOPSIS
        Discover a remote site and possibly update a matching existing one
    .DESCRIPTION
        GET /sites/discover/{address}
    .PARAMETER Address
        (Path) address
    .PARAMETER Sync
        (Query) sync
    .PARAMETER Validatereplicationports
        (Query) validateReplicationPorts
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Address,
        [Parameter()][string]$Sync,
        [Parameter()][string]$Validatereplicationports
    )

        $qp = @{
            "sync" = $Sync
            "validateReplicationPorts" = $Validatereplicationports
        }

        Invoke-HsRequest -Method GET -Endpoint "/sites/discover/${Address}" -QueryParams $qp
}

function Get-HsSite3 {
    <#
    .SYNOPSIS
        Get the local site
    .DESCRIPTION
        GET /sites/local
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/sites/local"
}

function Get-HsSite4 {
    <#
    .SYNOPSIS
        Get a site by ID
    .DESCRIPTION
        GET /sites/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Type
        (Query) type
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Type
    )

        $qp = @{
            "type" = $Type
        }

        Invoke-HsRequest -Method GET -Endpoint "/sites/${Identifier}" -QueryParams $qp
}

function Set-HsSite {
    <#
    .SYNOPSIS
        Update a remote site. Use this to override the management and data address when configuring a
    .DESCRIPTION
        Update a remote site. Use this to override the management and data address when configuring a. Update information for the local site
    .NOTES
    CLI equivalent: remote-site-update, local-site-config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][string]$Sitemgmtaddress,
        [Parameter()][string]$Sitedataaddress,
        [Parameter()][string]$Overridemgmtaddress,
        [Parameter()][string]$Overridedataaddress,
        [Parameter()][string]$Mgmtaddress,
        [Parameter()][string]$Dataaddress,
        [ValidateSet('LOCAL', 'REMOTE')]
        [Parameter()][string]$Type,
        [Parameter()][string]$Clientcert,
        [Parameter()][switch]$Trustclientcert,
        [Parameter()][hashtable]$Physicallocation,
        [Parameter()][hashtable]$Swversion,
        [Parameter()][object[]]$Objectstoragevolumes,
        [Parameter()][object[]]$Shareparticipants
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Sitemgmtaddress")) { $body["siteMgmtAddress"] = $Sitemgmtaddress }
        if ($PSBoundParameters.ContainsKey("Sitedataaddress")) { $body["siteDataAddress"] = $Sitedataaddress }
        if ($PSBoundParameters.ContainsKey("Overridemgmtaddress")) { $body["overrideMgmtAddress"] = $Overridemgmtaddress }
        if ($PSBoundParameters.ContainsKey("Overridedataaddress")) { $body["overrideDataAddress"] = $Overridedataaddress }
        if ($PSBoundParameters.ContainsKey("Mgmtaddress")) { $body["mgmtAddress"] = $Mgmtaddress }
        if ($PSBoundParameters.ContainsKey("Dataaddress")) { $body["dataAddress"] = $Dataaddress }
        if ($PSBoundParameters.ContainsKey("Type")) { $body["type"] = $Type }
        if ($PSBoundParameters.ContainsKey("Clientcert")) { $body["clientCert"] = $Clientcert }
        $body["trustClientCert"] = $Trustclientcert.IsPresent
        if ($PSBoundParameters.ContainsKey("Physicallocation")) { $body["physicalLocation"] = $Physicallocation }
        if ($PSBoundParameters.ContainsKey("Swversion")) { $body["swVersion"] = $Swversion }
        if ($PSBoundParameters.ContainsKey("Objectstoragevolumes")) { $body["objectStorageVolumes"] = $Objectstoragevolumes }
        if ($PSBoundParameters.ContainsKey("Shareparticipants")) { $body["shareParticipants"] = $Shareparticipants }

        Invoke-HsRequest -Method PUT -Endpoint "/sites/${Identifier}" -Body $body
}

function Remove-HsSite {
    <#
    .SYNOPSIS
        Remove a remote site
    .DESCRIPTION
        Remove a remote site
    .NOTES
    CLI equivalent: remote-site-remove
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/sites/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: smbautohomes
# ---------------------------------------------------------------------------

function Get-HsSmbautohome {
    <#
    .SYNOPSIS
        Get SMB autohome
    .DESCRIPTION
        GET /smbautohomes
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/smbautohomes" -QueryParams $qp
}

function New-HsSmbautohome {
    <#
    .SYNOPSIS
        Create a new SMB autohome
    .DESCRIPTION
        POST /smbautohomes
    .PARAMETER Comment
        (Body) comment
    .PARAMETER User
        (Body) user
    .PARAMETER Path
        (Body) path
    .PARAMETER Homesharename
        (Body) homeShareName
    .PARAMETER Acl
        (Body) acl
    .PARAMETER Createhomedir
        (Body) createHomeDir
    .PARAMETER Isdefault
        (Body) isDefault
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][hashtable]$User,
        [Parameter()][string]$Path,
        [Parameter()][string]$Homesharename,
        [ValidateSet('PUBLIC', 'GROUP', 'PRIVATE')]
        [Parameter()][string]$Acl,
        [Parameter()][switch]$Createhomedir,
        [Parameter()][switch]$Isdefault
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("User")) { $body["user"] = $User }
        if ($PSBoundParameters.ContainsKey("Path")) { $body["path"] = $Path }
        if ($PSBoundParameters.ContainsKey("Homesharename")) { $body["homeShareName"] = $Homesharename }
        if ($PSBoundParameters.ContainsKey("Acl")) { $body["acl"] = $Acl }
        $body["createHomeDir"] = $Createhomedir.IsPresent
        $body["isDefault"] = $Isdefault.IsPresent

        Invoke-HsRequest -Method POST -Endpoint "/smbautohomes" -Body $body
}

function Remove-HsSmbautohome {
    <#
    .SYNOPSIS
        Remove the default SMB autohome
    .DESCRIPTION
        DELETE /smbautohomes/default
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method DELETE -Endpoint "/smbautohomes/default"
}

function Get-HsSmbautohomeUsername {
    <#
    .SYNOPSIS
        Get SMB autohome by username
    .DESCRIPTION
        GET /smbautohomes/username/{username}
    .PARAMETER Username
        (Path) username
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Username
    )

        Invoke-HsRequest -Method GET -Endpoint "/smbautohomes/username/${Username}"
}

function Remove-HsSmbautohomeUsername {
    <#
    .SYNOPSIS
        Remove an SMB autohome by username
    .DESCRIPTION
        DELETE /smbautohomes/username/{username}
    .PARAMETER Username
        (Path) username
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Username
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/smbautohomes/username/${Username}"
}

function Get-HsSmbautohome2 {
    <#
    .SYNOPSIS
        Get SMB autohome
    .DESCRIPTION
        GET /smbautohomes/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/smbautohomes/${Identifier}"
}

function Set-HsSmbautohome {
    <#
    .SYNOPSIS
        Update SMB autohome
    .DESCRIPTION
        PUT /smbautohomes/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Force
        (Query) force
    .PARAMETER Comment
        (Body) comment
    .PARAMETER User
        (Body) user
    .PARAMETER Path
        (Body) path
    .PARAMETER Homesharename
        (Body) homeShareName
    .PARAMETER Acl
        (Body) acl
    .PARAMETER Createhomedir
        (Body) createHomeDir
    .PARAMETER Isdefault
        (Body) isDefault
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Force,
        [Parameter()][string]$Comment,
        [Parameter()][hashtable]$User,
        [Parameter()][string]$Path,
        [Parameter()][string]$Homesharename,
        [ValidateSet('PUBLIC', 'GROUP', 'PRIVATE')]
        [Parameter()][string]$Acl,
        [Parameter()][switch]$Createhomedir,
        [Parameter()][switch]$Isdefault
    )

        $qp = @{
            "force" = $Force
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("User")) { $body["user"] = $User }
        if ($PSBoundParameters.ContainsKey("Path")) { $body["path"] = $Path }
        if ($PSBoundParameters.ContainsKey("Homesharename")) { $body["homeShareName"] = $Homesharename }
        if ($PSBoundParameters.ContainsKey("Acl")) { $body["acl"] = $Acl }
        $body["createHomeDir"] = $Createhomedir.IsPresent
        $body["isDefault"] = $Isdefault.IsPresent

        Invoke-HsRequest -Method PUT -Endpoint "/smbautohomes/${Identifier}" -QueryParams $qp -Body $body
}

function Remove-HsSmbautohome2 {
    <#
    .SYNOPSIS
        Remove an SMB autohome
    .DESCRIPTION
        DELETE /smbautohomes/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/smbautohomes/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: snapshot-retentions
# ---------------------------------------------------------------------------

function Get-HsSnapshotRetention {
    <#
    .SYNOPSIS
        List snapshot retention policies
    .DESCRIPTION
        List snapshot retention policies
    .NOTES
    CLI equivalent: snapshot-retention-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/snapshot-retentions" -QueryParams $qp
}

function New-HsSnapshotRetention {
    <#
    .SYNOPSIS
        Create a snapshot retention policy
    .DESCRIPTION
        Create a snapshot retention policy
    .NOTES
    CLI equivalent: snapshot-retention-create
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][int]$Retentiontime,
        [Parameter()][int]$Numofcopies,
        [Parameter()][hashtable]$Snapshots,
        [Parameter()][hashtable]$Sharesnapshots
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Retentiontime")) { $body["retentionTime"] = $Retentiontime }
        if ($PSBoundParameters.ContainsKey("Numofcopies")) { $body["numOfCopies"] = $Numofcopies }
        if ($PSBoundParameters.ContainsKey("Snapshots")) { $body["snapshots"] = $Snapshots }
        if ($PSBoundParameters.ContainsKey("Sharesnapshots")) { $body["shareSnapshots"] = $Sharesnapshots }

        Invoke-HsRequest -Method POST -Endpoint "/snapshot-retentions" -Body $body
}

function Get-HsSnapshotRetention2 {
    <#
    .SYNOPSIS
        Get snapshot retention by ID
    .DESCRIPTION
        GET /snapshot-retentions/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/snapshot-retentions/${Identifier}"
}

function Set-HsSnapshotRetention {
    <#
    .SYNOPSIS
        Update snapshot retention policy
    .DESCRIPTION
        Update snapshot retention policy
    .NOTES
    CLI equivalent: snapshot-retention-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/snapshot-retentions/${Identifier}" -Body $body
}

function Remove-HsSnapshotRetention {
    <#
    .SYNOPSIS
        Delete snapshot retention policy
    .DESCRIPTION
        Delete snapshot retention policy
    .NOTES
    CLI equivalent: snapshot-retention-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/snapshot-retentions/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: snmp
# ---------------------------------------------------------------------------

function Get-HsSnmp {
    <#
    .SYNOPSIS
        Get SNMP configuration
    .DESCRIPTION
        GET /snmp
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/snmp" -QueryParams $qp
}

function Send-HsSnmpTrapTest {
    <#
    .SYNOPSIS
        Send test SNMP trap to desired receiver
    .DESCRIPTION
        POST /snmp/trap-test
    .PARAMETER Host
        (Body) host
    .PARAMETER Version
        (Body) version
    .PARAMETER Community
        (Body) community
    #>
    [CmdletBinding()]
    param(
        [Parameter()][hashtable]$HsHost,
        [ValidateSet('ANY', 'V1', 'V2C')]
        [Parameter()][string]$Version,
        [Parameter()][string]$Community
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Host")) { $body["host"] = $HsHost }
        if ($PSBoundParameters.ContainsKey("Version")) { $body["version"] = $Version }
        if ($PSBoundParameters.ContainsKey("Community")) { $body["community"] = $Community }

        Invoke-HsRequest -Method POST -Endpoint "/snmp/trap-test" -Body $body
}

function Get-HsSnmp2 {
    <#
    .SYNOPSIS
        Get SNMP configuration by ID
    .DESCRIPTION
        GET /snmp/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/snmp/${Identifier}"
}

function Set-HsSnmp {
    <#
    .SYNOPSIS
        Configure SNMP service
    .DESCRIPTION
        Configure SNMP service
    .NOTES
    CLI equivalent: snmp-config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/snmp/${Identifier}" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: static-routes
# ---------------------------------------------------------------------------

function Get-HsStaticRoute {
    <#
    .SYNOPSIS
        List static routes
    .DESCRIPTION
        List static routes
    .NOTES
    CLI equivalent: static-route-list
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/static-routes"
}

function New-HsStaticRoute {
    <#
    .SYNOPSIS
        Add a new static route
    .DESCRIPTION
        Add a new static route
    .NOTES
    CLI equivalent: static-route-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][hashtable]$Destination,
        [Parameter()][hashtable]$Nexthop
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Destination")) { $body["destination"] = $Destination }
        if ($PSBoundParameters.ContainsKey("Nexthop")) { $body["nextHop"] = $Nexthop }

        Invoke-HsRequest -Method POST -Endpoint "/static-routes" -Body $body
}

function Remove-HsStaticRoute {
    <#
    .SYNOPSIS
        Delete a static route
    .DESCRIPTION
        Delete a static route
    .NOTES
    CLI equivalent: static-route-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$NextHop
    )

        $qp = @{
            "next-hop" = $NextHop
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/static-routes/${Identifier}" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: storage-volumes
# ---------------------------------------------------------------------------

function Get-HsStorageVolume {
    <#
    .SYNOPSIS
        Display a detailed list of all storage volumes available in the system. Two types of lists can be
    .DESCRIPTION
        Display a detailed list of all storage volumes available in the system. Two types of lists can be
    .NOTES
    CLI equivalent: volume-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/storage-volumes" -QueryParams $qp
}

function New-HsStorageVolume {
    <#
    .SYNOPSIS
        Add a storage volume to the product
    .DESCRIPTION
        Add a storage volume to the product
    .NOTES
    CLI equivalent: volume-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Force,
        [Parameter()][string]$Stripealigntodefault,
        [Parameter()][string]$Skipperftest,
        [Parameter()][string]$Skipconfigtest,
        [Parameter()][string]$Createplacementobjectives,
        [Parameter()][string]$Comment,
        [Parameter()][int]$Modificationcount,
        [Parameter()][string]$Operstatereason,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][string]$Name,
        [ValidateSet('ADDED', 'OK', 'DECOMMISSIONING', 'DECOMMISSIONED', 'FAILED', 'UNAVAILABLE')]
        [Parameter()][string]$Storagevolumestate,
        [Parameter()][switch]$Realignonprotectiondrop,
        [Parameter()][int]$Lastregradeinitiated,
        [Parameter()][int]$Lastvolumerealigned,
        [Parameter()][hashtable]$Regradeinfo,
        [ValidateSet('NONE', 'DECOM_QUIESCE_DME', 'DECOM_QUIESCE_ENVOY', 'DECOM_QUIESCE_PDFS', 'DECOM_REGRADE', 'DECOM_INSTANCE_REMOVAL', 'DECOM_CLEANING')]
        [Parameter()][string]$Workflowstage,
        [Parameter()][hashtable]$Storagecapabilities,
        [Parameter()][int]$Suspectedsince,
        [Parameter()][int]$Maxsuspectedseconds,
        [Parameter()][string]$Rootfilehandle,
        [Parameter()][object[]]$Associatedlocations,
        [Parameter()][int]$Effectivetotalcapacity,
        [Parameter()][double]$Cost,
        [Parameter()][int]$Numoffiles,
        [Parameter()][int]$Spaceused,
        [Parameter()][hashtable]$Logicalvolume,
        [ValidateSet('READ_ONLY', 'READ_WRITE')]
        [Parameter()][string]$Accesstype,
        [Parameter()][object[]]$Excludedipaddresses,
        [Parameter()][object[]]$Additionaladdresses,
        [Parameter()][int]$Stripealignmentbytes,
        [Parameter()][switch]$Allowsrandomwrites,
        [Parameter()][switch]$Excludefromclustercapacityfreespace,
        [Parameter()][int]$Version,
        [Parameter()][object[]]$Effectiveaddresses,
        [Parameter()][hashtable]$Resources,
        [Parameter()][hashtable]$Assimilationspec,
        [Parameter()][string]$Uri
    )

        $qp = @{
            "force" = $Force
            "stripeAlignToDefault" = $Stripealigntodefault
            "skipPerfTest" = $Skipperftest
            "skipConfigTest" = $Skipconfigtest
            "createPlacementObjectives" = $Createplacementobjectives
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Modificationcount")) { $body["modificationCount"] = $Modificationcount }
        if ($PSBoundParameters.ContainsKey("Operstatereason")) { $body["operStateReason"] = $Operstatereason }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Storagevolumestate")) { $body["storageVolumeState"] = $Storagevolumestate }
        $body["realignOnProtectionDrop"] = $Realignonprotectiondrop.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastregradeinitiated")) { $body["lastRegradeInitiated"] = $Lastregradeinitiated }
        if ($PSBoundParameters.ContainsKey("Lastvolumerealigned")) { $body["lastVolumeRealigned"] = $Lastvolumerealigned }
        if ($PSBoundParameters.ContainsKey("Regradeinfo")) { $body["regradeInfo"] = $Regradeinfo }
        if ($PSBoundParameters.ContainsKey("Workflowstage")) { $body["workflowStage"] = $Workflowstage }
        if ($PSBoundParameters.ContainsKey("Storagecapabilities")) { $body["storageCapabilities"] = $Storagecapabilities }
        if ($PSBoundParameters.ContainsKey("Suspectedsince")) { $body["suspectedSince"] = $Suspectedsince }
        if ($PSBoundParameters.ContainsKey("Maxsuspectedseconds")) { $body["maxSuspectedSeconds"] = $Maxsuspectedseconds }
        if ($PSBoundParameters.ContainsKey("Rootfilehandle")) { $body["rootFileHandle"] = $Rootfilehandle }
        if ($PSBoundParameters.ContainsKey("Associatedlocations")) { $body["associatedLocations"] = $Associatedlocations }
        if ($PSBoundParameters.ContainsKey("Effectivetotalcapacity")) { $body["effectiveTotalCapacity"] = $Effectivetotalcapacity }
        if ($PSBoundParameters.ContainsKey("Cost")) { $body["cost"] = $Cost }
        if ($PSBoundParameters.ContainsKey("Numoffiles")) { $body["numOfFiles"] = $Numoffiles }
        if ($PSBoundParameters.ContainsKey("Spaceused")) { $body["spaceUsed"] = $Spaceused }
        if ($PSBoundParameters.ContainsKey("Logicalvolume")) { $body["logicalVolume"] = $Logicalvolume }
        if ($PSBoundParameters.ContainsKey("Accesstype")) { $body["accessType"] = $Accesstype }
        if ($PSBoundParameters.ContainsKey("Excludedipaddresses")) { $body["excludedIpAddresses"] = $Excludedipaddresses }
        if ($PSBoundParameters.ContainsKey("Additionaladdresses")) { $body["additionalAddresses"] = $Additionaladdresses }
        if ($PSBoundParameters.ContainsKey("Stripealignmentbytes")) { $body["stripeAlignmentBytes"] = $Stripealignmentbytes }
        $body["allowsRandomWrites"] = $Allowsrandomwrites.IsPresent
        $body["excludeFromClusterCapacityFreeSpace"] = $Excludefromclustercapacityfreespace.IsPresent
        if ($PSBoundParameters.ContainsKey("Version")) { $body["version"] = $Version }
        if ($PSBoundParameters.ContainsKey("Effectiveaddresses")) { $body["effectiveAddresses"] = $Effectiveaddresses }
        if ($PSBoundParameters.ContainsKey("Resources")) { $body["resources"] = $Resources }
        if ($PSBoundParameters.ContainsKey("Assimilationspec")) { $body["assimilationSpec"] = $Assimilationspec }
        if ($PSBoundParameters.ContainsKey("Uri")) { $body["uri"] = $Uri }

        Invoke-HsRequest -Method POST -Endpoint "/storage-volumes" -QueryParams $qp -Body $body
}

function Get-HsStorageVolume2 {
    <#
    .SYNOPSIS
        Get all storage volumes filtered by relation to other entity
    .DESCRIPTION
        GET /storage-volumes/related-list
    .PARAMETER Filteruuid
        (Query) filterUuid
    .PARAMETER Filterobjecttype
        (Query) filterObjectType
    .PARAMETER Sort
        (Query) sort
    .PARAMETER Terse
        (Query) terse
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Filteruuid,
        [Parameter()][string]$Filterobjecttype,
        [Parameter()][string]$Sort,
        [Parameter()][string]$Terse,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "filterUuid" = $Filteruuid
            "filterObjectType" = $Filterobjecttype
            "sort" = $Sort
            "terse" = $Terse
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/storage-volumes/related-list" -QueryParams $qp
}

function Get-HsStorageVolume3 {
    <#
    .SYNOPSIS
        Get storage volume by ID
    .DESCRIPTION
        GET /storage-volumes/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/storage-volumes/${Identifier}"
}

function Set-HsStorageVolume {
    <#
    .SYNOPSIS
        Additional Documentation Resources
    .DESCRIPTION
        Additional Documentation Resources. Mark an unavailable storage volume as available. Mark a storage volume as unavailable. Set a storage volume to the FAILED state. Typically used to allow the removal of a storage volume
    .NOTES
    CLI equivalent: volume-update, volume-set-available, volume-set-unavailable, volume-fail
    WARNING: WARNING: Be aware that failed volumes cannot be recovered!
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Stripealigntodefault,
        [Parameter()][string]$Comment,
        [Parameter()][int]$Modificationcount,
        [Parameter()][string]$Operstatereason,
        [ValidateSet('DOWN', 'UP', 'DISABLED')]
        [Parameter()][string]$Adminstate,
        [Parameter()][string]$Name,
        [ValidateSet('ADDED', 'OK', 'DECOMMISSIONING', 'DECOMMISSIONED', 'FAILED', 'UNAVAILABLE')]
        [Parameter()][string]$Storagevolumestate,
        [Parameter()][switch]$Realignonprotectiondrop,
        [Parameter()][int]$Lastregradeinitiated,
        [Parameter()][int]$Lastvolumerealigned,
        [Parameter()][hashtable]$Regradeinfo,
        [ValidateSet('NONE', 'DECOM_QUIESCE_DME', 'DECOM_QUIESCE_ENVOY', 'DECOM_QUIESCE_PDFS', 'DECOM_REGRADE', 'DECOM_INSTANCE_REMOVAL', 'DECOM_CLEANING')]
        [Parameter()][string]$Workflowstage,
        [Parameter()][hashtable]$Storagecapabilities,
        [Parameter()][int]$Suspectedsince,
        [Parameter()][int]$Maxsuspectedseconds,
        [Parameter()][string]$Rootfilehandle,
        [Parameter()][object[]]$Associatedlocations,
        [Parameter()][int]$Effectivetotalcapacity,
        [Parameter()][double]$Cost,
        [Parameter()][int]$Numoffiles,
        [Parameter()][int]$Spaceused,
        [Parameter()][hashtable]$Logicalvolume,
        [ValidateSet('READ_ONLY', 'READ_WRITE')]
        [Parameter()][string]$Accesstype,
        [Parameter()][object[]]$Excludedipaddresses,
        [Parameter()][object[]]$Additionaladdresses,
        [Parameter()][int]$Stripealignmentbytes,
        [Parameter()][switch]$Allowsrandomwrites,
        [Parameter()][switch]$Excludefromclustercapacityfreespace,
        [Parameter()][int]$Version,
        [Parameter()][object[]]$Effectiveaddresses,
        [Parameter()][hashtable]$Resources,
        [Parameter()][hashtable]$Assimilationspec,
        [Parameter()][string]$Uri
    )

        $qp = @{
            "stripeAlignToDefault" = $Stripealigntodefault
        }

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Modificationcount")) { $body["modificationCount"] = $Modificationcount }
        if ($PSBoundParameters.ContainsKey("Operstatereason")) { $body["operStateReason"] = $Operstatereason }
        if ($PSBoundParameters.ContainsKey("Adminstate")) { $body["adminState"] = $Adminstate }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Storagevolumestate")) { $body["storageVolumeState"] = $Storagevolumestate }
        $body["realignOnProtectionDrop"] = $Realignonprotectiondrop.IsPresent
        if ($PSBoundParameters.ContainsKey("Lastregradeinitiated")) { $body["lastRegradeInitiated"] = $Lastregradeinitiated }
        if ($PSBoundParameters.ContainsKey("Lastvolumerealigned")) { $body["lastVolumeRealigned"] = $Lastvolumerealigned }
        if ($PSBoundParameters.ContainsKey("Regradeinfo")) { $body["regradeInfo"] = $Regradeinfo }
        if ($PSBoundParameters.ContainsKey("Workflowstage")) { $body["workflowStage"] = $Workflowstage }
        if ($PSBoundParameters.ContainsKey("Storagecapabilities")) { $body["storageCapabilities"] = $Storagecapabilities }
        if ($PSBoundParameters.ContainsKey("Suspectedsince")) { $body["suspectedSince"] = $Suspectedsince }
        if ($PSBoundParameters.ContainsKey("Maxsuspectedseconds")) { $body["maxSuspectedSeconds"] = $Maxsuspectedseconds }
        if ($PSBoundParameters.ContainsKey("Rootfilehandle")) { $body["rootFileHandle"] = $Rootfilehandle }
        if ($PSBoundParameters.ContainsKey("Associatedlocations")) { $body["associatedLocations"] = $Associatedlocations }
        if ($PSBoundParameters.ContainsKey("Effectivetotalcapacity")) { $body["effectiveTotalCapacity"] = $Effectivetotalcapacity }
        if ($PSBoundParameters.ContainsKey("Cost")) { $body["cost"] = $Cost }
        if ($PSBoundParameters.ContainsKey("Numoffiles")) { $body["numOfFiles"] = $Numoffiles }
        if ($PSBoundParameters.ContainsKey("Spaceused")) { $body["spaceUsed"] = $Spaceused }
        if ($PSBoundParameters.ContainsKey("Logicalvolume")) { $body["logicalVolume"] = $Logicalvolume }
        if ($PSBoundParameters.ContainsKey("Accesstype")) { $body["accessType"] = $Accesstype }
        if ($PSBoundParameters.ContainsKey("Excludedipaddresses")) { $body["excludedIpAddresses"] = $Excludedipaddresses }
        if ($PSBoundParameters.ContainsKey("Additionaladdresses")) { $body["additionalAddresses"] = $Additionaladdresses }
        if ($PSBoundParameters.ContainsKey("Stripealignmentbytes")) { $body["stripeAlignmentBytes"] = $Stripealignmentbytes }
        $body["allowsRandomWrites"] = $Allowsrandomwrites.IsPresent
        $body["excludeFromClusterCapacityFreeSpace"] = $Excludefromclustercapacityfreespace.IsPresent
        if ($PSBoundParameters.ContainsKey("Version")) { $body["version"] = $Version }
        if ($PSBoundParameters.ContainsKey("Effectiveaddresses")) { $body["effectiveAddresses"] = $Effectiveaddresses }
        if ($PSBoundParameters.ContainsKey("Resources")) { $body["resources"] = $Resources }
        if ($PSBoundParameters.ContainsKey("Assimilationspec")) { $body["assimilationSpec"] = $Assimilationspec }
        if ($PSBoundParameters.ContainsKey("Uri")) { $body["uri"] = $Uri }

        Invoke-HsRequest -Method PUT -Endpoint "/storage-volumes/${Identifier}" -QueryParams $qp -Body $body
}

function Remove-HsStorageVolume {
    <#
    .SYNOPSIS
        Remove a storage volume from the system
    .DESCRIPTION
        Remove a storage volume from the system. Cancel the removal of a storage volume. The volume must be in the DECOMMISSIONING state
    .NOTES
    CLI equivalent: volume-remove, volume-remove-cancel
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Bypassdecommission
    )

        $qp = @{
            "bypassDecommission" = $Bypassdecommission
        }

        Invoke-HsRequest -Method DELETE -Endpoint "/storage-volumes/${Identifier}" -QueryParams $qp
}

function Invoke-HsStorageVolumeAssimilation {
    <#
    .SYNOPSIS
        Assimilate an existing storage volume
    .DESCRIPTION
        Assimilate an existing storage volume. Cancel a running assimilation
    .NOTES
    CLI equivalent: volume-assimilation, volume-assimilation-cancel
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Sourcepath,
        [Parameter()][string]$Share,
        [Parameter()][string]$Destpath,
        [Parameter()][hashtable]$Smbassimilationspec,
        [Parameter()][switch]$Log,
        [Parameter()][switch]$Update,
        [Parameter()][switch]$Skipfileaccesstest,
        [Parameter()][int]$Resolvedshareinternalid
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Sourcepath")) { $body["sourcePath"] = $Sourcepath }
        if ($PSBoundParameters.ContainsKey("Share")) { $body["share"] = $Share }
        if ($PSBoundParameters.ContainsKey("Destpath")) { $body["destPath"] = $Destpath }
        if ($PSBoundParameters.ContainsKey("Smbassimilationspec")) { $body["smbAssimilationSpec"] = $Smbassimilationspec }
        $body["log"] = $Log.IsPresent
        $body["update"] = $Update.IsPresent
        $body["skipFileAccessTest"] = $Skipfileaccesstest.IsPresent
        if ($PSBoundParameters.ContainsKey("Resolvedshareinternalid")) { $body["resolvedShareInternalId"] = $Resolvedshareinternalid }

        Invoke-HsRequest -Method POST -Endpoint "/storage-volumes/${Identifier}/assimilation" -Body $body
}

function Invoke-HsStorageVolumeDecommission {
    <#
    .SYNOPSIS
        Start the storage volume decommission process (DEPRECATED)
    .DESCRIPTION
        Start the storage volume decommission process (DEPRECATED). Cancel the storage volume decommission process (DEPRECATED)
    .NOTES
    CLI equivalent: volume-decommission, volume-decommission-cancel
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method POST -Endpoint "/storage-volumes/${Identifier}/decommission"
}

function Set-HsStorageVolumeReplace {
    <#
    .SYNOPSIS
        Replace storage volume
    .DESCRIPTION
        POST /storage-volumes/{identifier}/replace
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method POST -Endpoint "/storage-volumes/${Identifier}/replace"
}

# ---------------------------------------------------------------------------
# SECTION: subnet-gateways
# ---------------------------------------------------------------------------

function Get-HsSubnetGateway {
    <#
    .SYNOPSIS
        List subnet gateways
    .DESCRIPTION
        List subnet gateways
    .NOTES
    CLI equivalent: subnet-gateway-list
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/subnet-gateways"
}

function New-HsSubnetGateway {
    <#
    .SYNOPSIS
        Add a new subnet gateway
    .DESCRIPTION
        Add a new subnet gateway
    .NOTES
    CLI equivalent: subnet-gateway-add
    #>
    [CmdletBinding()]
    param(
        [Parameter()][hashtable]$Subnet,
        [Parameter()][hashtable]$Subnetgateway
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Subnet")) { $body["subnet"] = $Subnet }
        if ($PSBoundParameters.ContainsKey("Subnetgateway")) { $body["subnetgateway"] = $Subnetgateway }

        Invoke-HsRequest -Method POST -Endpoint "/subnet-gateways" -Body $body
}

function Remove-HsSubnetGateway {
    <#
    .SYNOPSIS
        Delete a subnet gateway
    .DESCRIPTION
        Delete a subnet gateway
    .NOTES
    CLI equivalent: subnet-gateway-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/subnet-gateways/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: sw-update
# ---------------------------------------------------------------------------

function Get-HsSwUpdate {
    <#
    .SYNOPSIS
        Monitor update status
    .DESCRIPTION
        Monitor update status
    .NOTES
    CLI equivalent: software-update-status
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/sw-update" -QueryParams $qp
}

function Install-HsSwUpdateApply {
    <#
    .SYNOPSIS
        Apply update
    .DESCRIPTION
        POST /sw-update/apply/{version}
    .PARAMETER Version
        (Path) version
    .PARAMETER NodeIdentifier
        (Query) node-identifier
    .PARAMETER Skipordervalidation
        (Query) skipOrderValidation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter()][string]$NodeIdentifier,
        [Parameter()][string]$Skipordervalidation
    )

        $qp = @{
            "node-identifier" = $NodeIdentifier
            "skipOrderValidation" = $Skipordervalidation
        }

        Invoke-HsRequest -Method POST -Endpoint "/sw-update/apply/${Version}" -QueryParams $qp
}

function Install-HsSwUpdateSystem {
    <#
    .SYNOPSIS
        Apply update
    .DESCRIPTION
        POST /sw-update/apply/{version}/system
    .PARAMETER Version
        (Path) version
    .PARAMETER Skipordervalidation
        (Query) skipOrderValidation
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Version,
        [Parameter()][string]$Skipordervalidation
    )

        $qp = @{
            "skipOrderValidation" = $Skipordervalidation
        }

        Invoke-HsRequest -Method POST -Endpoint "/sw-update/apply/${Version}/system" -QueryParams $qp
}

function Get-HsSwUpdate2 {
    <#
    .SYNOPSIS
        Get sw update task
    .DESCRIPTION
        GET /sw-update/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/sw-update/${Identifier}"
}

function Stop-HsSwUpdate {
    <#
    .SYNOPSIS
        Cancel software update task
    .DESCRIPTION
        POST /sw-update/{identifier}/cancel
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method POST -Endpoint "/sw-update/${Identifier}/cancel"
}

# ---------------------------------------------------------------------------
# SECTION: syslog
# ---------------------------------------------------------------------------

function Get-HsSyslog {
    <#
    .SYNOPSIS
        Get Syslog configuration
    .DESCRIPTION
        GET /syslog
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/syslog" -QueryParams $qp
}

function Get-HsSyslog2 {
    <#
    .SYNOPSIS
        Get Syslog configuration by ID
    .DESCRIPTION
        GET /syslog/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/syslog/${Identifier}"
}

function Set-HsSyslog {
    <#
    .SYNOPSIS
        Configure syslog servers
    .DESCRIPTION
        Configure syslog servers
    .NOTES
    CLI equivalent: syslog-config
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/syslog/${Identifier}" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: system-info
# ---------------------------------------------------------------------------

function Get-HsSystemInfo {
    <#
    .SYNOPSIS
        Get system information
    .DESCRIPTION
        GET /system-info
    .PARAMETER Timeoutsec
        (Query) timeoutSec
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Timeoutsec
    )

        $qp = @{
            "timeoutSec" = $Timeoutsec
        }

        Invoke-HsRequest -Method GET -Endpoint "/system-info" -QueryParams $qp
}

# ---------------------------------------------------------------------------
# SECTION: system
# ---------------------------------------------------------------------------

function Get-HsSystem {
    <#
    .SYNOPSIS
        Get storage-related counts (systems, volumes, shares, files)
    .DESCRIPTION
        GET /system/counts
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/system/counts"
}

function Get-HsSystem2 {
    <#
    .SYNOPSIS
        Get a summary of system health
    .DESCRIPTION
        GET /system/health
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/system/health"
}

function Get-HsSystem3 {
    <#
    .SYNOPSIS
        responds with empty body
    .DESCRIPTION
        GET /system/ping
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/system/ping"
}

# ---------------------------------------------------------------------------
# SECTION: tasks
# ---------------------------------------------------------------------------

function Get-HsTask {
    <#
    .SYNOPSIS
        List all running tasks in the system. The command can also be used to list completed tasks using
    .DESCRIPTION
        List all running tasks in the system. The command can also be used to list completed tasks using
    .NOTES
    CLI equivalent: task-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/tasks" -QueryParams $qp
}

function Stop-HsTaskCancelActive {
    <#
    .SYNOPSIS
        Attempt to cancel a task. If the task is HALTED, it will be restarted and the new task will be
    .DESCRIPTION
        Attempt to cancel a task. If the task is HALTED, it will be restarted and the new task will be
    .NOTES
    CLI equivalent: task-cancel
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Taskname,
        [Parameter()][string]$Objecttype,
        [Parameter()][string]$Identifier
    )

        $qp = @{
            "taskName" = $Taskname
            "objectType" = $Objecttype
            "identifier" = $Identifier
        }

        Invoke-HsRequest -Method POST -Endpoint "/tasks/cancel-active" -QueryParams $qp
}

function Get-HsTask2 {
    <#
    .SYNOPSIS
        Get a task
    .DESCRIPTION
        GET /tasks/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/tasks/${Identifier}"
}

function Set-HsTask {
    <#
    .SYNOPSIS
        Modify a task's status in order to manipulate its lifecycle
    .DESCRIPTION
        PUT /tasks/{taskId}
    .PARAMETER Taskid
        (Path) taskId
    .PARAMETER Uuid
        (Body) uuid
    .PARAMETER Name
        (Body) name
    .PARAMETER Status
        (Body) status
    .PARAMETER Statusmessage
        (Body) statusMessage
    .PARAMETER Started
        (Body) started
    .PARAMETER Ended
        (Body) ended
    .PARAMETER Duration
        (Body) duration
    .PARAMETER Progress
        (Body) progress
    .PARAMETER Paramsmap
        (Body) paramsMap
    .PARAMETER Ctxmap
        (Body) ctxMap
    .PARAMETER Hidden
        (Body) hidden
    .PARAMETER Resumedfromid
        (Body) resumedFromId
    .PARAMETER Subtasks
        (Body) subTasks
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Taskid,
        [Parameter()][string]$Uuid,
        [Parameter()][string]$Name,
        [ValidateSet('NONE', 'QUEUED', 'VALIDATING', 'VALIDATED', 'VALIDATION_FAILED', 'EXECUTING', 'CANCELLING', 'HALTED', 'RECOVERING', 'RESUMED', 'FAILED', 'CANCELLED', 'COMPLETED')]
        [Parameter()][string]$Status,
        [Parameter()][string]$Statusmessage,
        [Parameter()][int]$Started,
        [Parameter()][int]$Ended,
        [Parameter()][int]$Duration,
        [Parameter()][double]$Progress,
        [Parameter()][hashtable]$Paramsmap,
        [Parameter()][hashtable]$Ctxmap,
        [Parameter()][switch]$Hidden,
        [Parameter()][string]$Resumedfromid,
        [Parameter()][object[]]$Subtasks
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Uuid")) { $body["uuid"] = $Uuid }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Status")) { $body["status"] = $Status }
        if ($PSBoundParameters.ContainsKey("Statusmessage")) { $body["statusMessage"] = $Statusmessage }
        if ($PSBoundParameters.ContainsKey("Started")) { $body["started"] = $Started }
        if ($PSBoundParameters.ContainsKey("Ended")) { $body["ended"] = $Ended }
        if ($PSBoundParameters.ContainsKey("Duration")) { $body["duration"] = $Duration }
        if ($PSBoundParameters.ContainsKey("Progress")) { $body["progress"] = $Progress }
        if ($PSBoundParameters.ContainsKey("Paramsmap")) { $body["paramsMap"] = $Paramsmap }
        if ($PSBoundParameters.ContainsKey("Ctxmap")) { $body["ctxMap"] = $Ctxmap }
        $body["hidden"] = $Hidden.IsPresent
        if ($PSBoundParameters.ContainsKey("Resumedfromid")) { $body["resumedFromId"] = $Resumedfromid }
        if ($PSBoundParameters.ContainsKey("Subtasks")) { $body["subTasks"] = $Subtasks }

        Invoke-HsRequest -Method PUT -Endpoint "/tasks/${Taskid}" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: user-groups
# ---------------------------------------------------------------------------

function Get-HsUserGroup {
    <#
    .SYNOPSIS
        Get all user groups
    .DESCRIPTION
        GET /user-groups
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/user-groups" -QueryParams $qp
}

function New-HsUserGroup {
    <#
    .SYNOPSIS
        Create user group
    .DESCRIPTION
        POST /user-groups
    .PARAMETER Comment
        (Body) comment
    .PARAMETER Name
        (Body) name
    .PARAMETER Managementrole
        (Body) managementRole
    .PARAMETER Users
        (Body) users
    .PARAMETER Gid
        (Body) gid
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Name,
        [Parameter()][hashtable]$Managementrole,
        [Parameter()][object[]]$Users,
        [Parameter()][int]$Gid
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Managementrole")) { $body["managementRole"] = $Managementrole }
        if ($PSBoundParameters.ContainsKey("Users")) { $body["users"] = $Users }
        if ($PSBoundParameters.ContainsKey("Gid")) { $body["gid"] = $Gid }

        Invoke-HsRequest -Method POST -Endpoint "/user-groups" -Body $body
}

function Get-HsUserGroup2 {
    <#
    .SYNOPSIS
        Get user group
    .DESCRIPTION
        GET /user-groups/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/user-groups/${Identifier}"
}

function Set-HsUserGroup {
    <#
    .SYNOPSIS
        Update user group
    .DESCRIPTION
        PUT /user-groups/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Comment
        (Body) comment
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/user-groups/${Identifier}" -Body $body
}

function Remove-HsUserGroup {
    <#
    .SYNOPSIS
        Delete user group
    .DESCRIPTION
        DELETE /user-groups/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/user-groups/${Identifier}"
}

# ---------------------------------------------------------------------------
# SECTION: users
# ---------------------------------------------------------------------------

function Get-HsUser {
    <#
    .SYNOPSIS
        List all existing users
    .DESCRIPTION
        List all existing users
    .NOTES
    CLI equivalent: user-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/users" -QueryParams $qp
}

function New-HsUser {
    <#
    .SYNOPSIS
        Create a system user
    .DESCRIPTION
        Create a system user
    .NOTES
    CLI equivalent: user-create
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method POST -Endpoint "/users" -Body $body
}

function Get-HsUserCurrent {
    <#
    .SYNOPSIS
        Get currently authenticated user
    .DESCRIPTION
        GET /users/_current
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/users/_current"
}

function Get-HsUserPermittedOperation {
    <#
    .SYNOPSIS
        Get permitted operations
    .DESCRIPTION
        GET /users/_current/permitted-operations
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/users/_current/permitted-operations"
}

function Add-HsUserAdd {
    <#
    .SYNOPSIS
        Add user to a builtin group
    .DESCRIPTION
        POST /users/builtin/user-add/{groupname}/{username}
    .PARAMETER Groupname
        (Path) groupname
    .PARAMETER Username
        (Path) username
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Groupname,
        [Parameter(Mandatory)][string]$Username
    )

        Invoke-HsRequest -Method POST -Endpoint "/users/builtin/user-add/${Groupname}/${Username}"
}

function Get-HsUserList {
    <#
    .SYNOPSIS
        Get list of users of builtin group
    .DESCRIPTION
        GET /users/builtin/user-list/{groupname}
    .PARAMETER Groupname
        (Path) groupname
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Groupname
    )

        Invoke-HsRequest -Method GET -Endpoint "/users/builtin/user-list/${Groupname}"
}

function Remove-HsUserRemove {
    <#
    .SYNOPSIS
        Remove user from a builtin group
    .DESCRIPTION
        POST /users/builtin/user-remove/{groupname}/{username}
    .PARAMETER Groupname
        (Path) groupname
    .PARAMETER Username
        (Path) username
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Groupname,
        [Parameter(Mandatory)][string]$Username
    )

        Invoke-HsRequest -Method POST -Endpoint "/users/builtin/user-remove/${Groupname}/${Username}"
}

function Import-HsUserImport {
    <#
    .SYNOPSIS
        Imports users from CSV file
    .DESCRIPTION
        Imports users from CSV file
    .NOTES
    CLI equivalent: user-import
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method POST -Endpoint "/users/import"
}

function Import-HsUserImport2 {
    <#
    .SYNOPSIS
        Import users
    .DESCRIPTION
        POST /users/import/{path}
    .PARAMETER Path
        (Path) path
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path
    )

        Invoke-HsRequest -Method POST -Endpoint "/users/import/${Path}"
}

function Get-HsUser2 {
    <#
    .SYNOPSIS
        Get user by identifier
    .DESCRIPTION
        GET /users/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/users/${Identifier}"
}

function Set-HsUser {
    <#
    .SYNOPSIS
        Update the user’s properties, including the applied user role. If a new role is provided it overwrites
    .DESCRIPTION
        Update the user’s properties, including the applied user role. If a new role is provided it overwrites
    .NOTES
    CLI equivalent: user-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }

        Invoke-HsRequest -Method PUT -Endpoint "/users/${Identifier}" -Body $body
}

function Remove-HsUser {
    <#
    .SYNOPSIS
        Delete a system user
    .DESCRIPTION
        Delete a system user
    .NOTES
    CLI equivalent: user-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/users/${Identifier}"
}

function Set-HsUserPassword {
    <#
    .SYNOPSIS
        Update a user password
    .DESCRIPTION
        Update a user password
    .NOTES
    CLI equivalent: user-password-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Oldpassword,
        [Parameter()][string]$Newpassword
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Oldpassword")) { $body["oldPassword"] = $Oldpassword }
        if ($PSBoundParameters.ContainsKey("Newpassword")) { $body["newPassword"] = $Newpassword }

        Invoke-HsRequest -Method PUT -Endpoint "/users/${Identifier}/password" -Body $body
}

function Get-HsUserPreferences {
    <#
    .SYNOPSIS
        Get user preferences by identifier
    .DESCRIPTION
        GET /users/{identifier}/preferences
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/users/${Identifier}/preferences"
}

function Get-HsUserPreferences2 {
    <#
    .SYNOPSIS
        Get user preferences by identifier and preference key
    .DESCRIPTION
        GET /users/{identifier}/preferences/{preference-key}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER PreferenceKey
        (Path) preference-key
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter(Mandatory)][string]$PreferenceKey
    )

        Invoke-HsRequest -Method GET -Endpoint "/users/${Identifier}/preferences/${PreferenceKey}"
}

function Set-HsUserPreferences {
    <#
    .SYNOPSIS
        Update user preferences
    .DESCRIPTION
        PUT /users/{identifier}/preferences/{preference-key}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER PreferenceKey
        (Path) preference-key
    .PARAMETER Preferences
        (Body) preferences
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter(Mandatory)][string]$PreferenceKey,
        [Parameter()][string]$Preferences
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Preferences")) { $body["preferences"] = $Preferences }

        Invoke-HsRequest -Method PUT -Endpoint "/users/${Identifier}/preferences/${PreferenceKey}" -Body $body
}

function Remove-HsUserPreferences {
    <#
    .SYNOPSIS
        Delete user preferences
    .DESCRIPTION
        DELETE /users/{identifier}/preferences/{preference-key}
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER PreferenceKey
        (Path) preference-key
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter(Mandatory)][string]$PreferenceKey
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/users/${Identifier}/preferences/${PreferenceKey}"
}

function Reset-HsUserResetPassword {
    <#
    .SYNOPSIS
        Reset password
    .DESCRIPTION
        POST /users/{identifier}/reset-password
    .PARAMETER Identifier
        (Path) identifier
    .PARAMETER Oldpassword
        (Body) oldPassword
    .PARAMETER Newpassword
        (Body) newPassword
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Oldpassword,
        [Parameter()][string]$Newpassword
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Oldpassword")) { $body["oldPassword"] = $Oldpassword }
        if ($PSBoundParameters.ContainsKey("Newpassword")) { $body["newPassword"] = $Newpassword }

        Invoke-HsRequest -Method POST -Endpoint "/users/${Identifier}/reset-password" -Body $body
}

# ---------------------------------------------------------------------------
# SECTION: versions
# ---------------------------------------------------------------------------

function Get-HsVersionAvailable {
    <#
    .SYNOPSIS
        List software versions
    .DESCRIPTION
        List software versions
    .NOTES
    CLI equivalent: software-list
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method GET -Endpoint "/versions/available"
}

function Remove-HsVersionDelete {
    <#
    .SYNOPSIS
        Delete software update packages
    .DESCRIPTION
        Delete software update packages
    .NOTES
    CLI equivalent: software-package-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$PackageName
    )

        $qp = @{
            "package-name" = $PackageName
        }

        Invoke-HsRequest -Method POST -Endpoint "/versions/delete" -QueryParams $qp
}

function Publish-HsVersionUpload {
    <#
    .SYNOPSIS
        Upload a software package with UPD format
    .DESCRIPTION
        Upload a software package with UPD format
    .NOTES
    CLI equivalent: software-upload
    #>
    [CmdletBinding()]
    param()

        Invoke-HsRequest -Method POST -Endpoint "/versions/upload"
}

function Publish-HsVersionUpload2 {
    <#
    .SYNOPSIS
        Upload package
    .DESCRIPTION
        POST /versions/upload/{package-location}
    .PARAMETER PackageLocation
        (Path) package-location
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PackageLocation
    )

        Invoke-HsRequest -Method POST -Endpoint "/versions/upload/${PackageLocation}"
}

# ---------------------------------------------------------------------------
# SECTION: volume-groups
# ---------------------------------------------------------------------------

function Get-HsVolumeGroup {
    <#
    .SYNOPSIS
        Display a detailed list of all volume groups available in the system
    .DESCRIPTION
        Display a detailed list of all volume groups available in the system
    .NOTES
    CLI equivalent: volume-group-list
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/volume-groups" -QueryParams $qp
}

function New-HsVolumeGroup {
    <#
    .SYNOPSIS
        Create a new volume group
    .DESCRIPTION
        Create a new volume group
    .NOTES
    CLI equivalent: volume-group-create
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Comment,
        [Parameter()][string]$Placeonobjectiveuuid,
        [Parameter()][string]$Excludefromobjectiveuuid,
        [Parameter()][string]$Confinetoobjectiveuuid,
        [Parameter()][hashtable]$Storagevolume,
        [Parameter()][string]$Name,
        [Parameter()][object[]]$Expressions
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Placeonobjectiveuuid")) { $body["placeOnObjectiveUuid"] = $Placeonobjectiveuuid }
        if ($PSBoundParameters.ContainsKey("Excludefromobjectiveuuid")) { $body["excludeFromObjectiveUuid"] = $Excludefromobjectiveuuid }
        if ($PSBoundParameters.ContainsKey("Confinetoobjectiveuuid")) { $body["confineToObjectiveUuid"] = $Confinetoobjectiveuuid }
        if ($PSBoundParameters.ContainsKey("Storagevolume")) { $body["storageVolume"] = $Storagevolume }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Expressions")) { $body["expressions"] = $Expressions }

        Invoke-HsRequest -Method POST -Endpoint "/volume-groups" -Body $body
}

function Get-HsVolumeGroupFindbylocation {
    <#
    .SYNOPSIS
        Get volume groups using given location
    .DESCRIPTION
        GET /volume-groups/findByLocation
    .PARAMETER Uuid
        (Query) uuid
    .PARAMETER Objecttype
        (Query) objectType
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Uuid,
        [Parameter()][string]$Objecttype
    )

        $qp = @{
            "uuid" = $Uuid
            "objectType" = $Objecttype
        }

        Invoke-HsRequest -Method GET -Endpoint "/volume-groups/findByLocation" -QueryParams $qp
}

function Get-HsVolumeGroup2 {
    <#
    .SYNOPSIS
        Get all volume groups filtered by relation to other entity
    .DESCRIPTION
        GET /volume-groups/related-list
    .PARAMETER Filteruuid
        (Query) filterUuid
    .PARAMETER Filterobjecttype
        (Query) filterObjectType
    .PARAMETER Sort
        (Query) sort
    .PARAMETER Terse
        (Query) terse
    .PARAMETER Spec
        (Query) spec
    .PARAMETER Page
        (Query) page
    .PARAMETER PageSize
        (Query) page.size
    .PARAMETER PageSort
        (Query) page.sort
    .PARAMETER PageSortDir
        (Query) page.sort.dir
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$Filteruuid,
        [Parameter()][string]$Filterobjecttype,
        [Parameter()][string]$Sort,
        [Parameter()][string]$Terse,
        [Parameter()][string]$Spec,
        [Parameter()][string]$Page,
        [Parameter()][string]$PageSize,
        [Parameter()][string]$PageSort,
        [Parameter()][string]$PageSortDir
    )

        $qp = @{
            "filterUuid" = $Filteruuid
            "filterObjectType" = $Filterobjecttype
            "sort" = $Sort
            "terse" = $Terse
            "spec" = $Spec
            "page" = $Page
            "page.size" = $PageSize
            "page.sort" = $PageSort
            "page.sort.dir" = $PageSortDir
        }

        Invoke-HsRequest -Method GET -Endpoint "/volume-groups/related-list" -QueryParams $qp
}

function Get-HsVolumeGroup3 {
    <#
    .SYNOPSIS
        Get volume group by ID
    .DESCRIPTION
        GET /volume-groups/{identifier}
    .PARAMETER Identifier
        (Path) identifier
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method GET -Endpoint "/volume-groups/${Identifier}"
}

function Set-HsVolumeGroup {
    <#
    .SYNOPSIS
        Update a volume group
    .DESCRIPTION
        Update a volume group
    .NOTES
    CLI equivalent: volume-group-update
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier,
        [Parameter()][string]$Comment,
        [Parameter()][string]$Placeonobjectiveuuid,
        [Parameter()][string]$Excludefromobjectiveuuid,
        [Parameter()][string]$Confinetoobjectiveuuid,
        [Parameter()][hashtable]$Storagevolume,
        [Parameter()][string]$Name,
        [Parameter()][object[]]$Expressions
    )

        $body = @{}
        if ($PSBoundParameters.ContainsKey("Comment")) { $body["comment"] = $Comment }
        if ($PSBoundParameters.ContainsKey("Placeonobjectiveuuid")) { $body["placeOnObjectiveUuid"] = $Placeonobjectiveuuid }
        if ($PSBoundParameters.ContainsKey("Excludefromobjectiveuuid")) { $body["excludeFromObjectiveUuid"] = $Excludefromobjectiveuuid }
        if ($PSBoundParameters.ContainsKey("Confinetoobjectiveuuid")) { $body["confineToObjectiveUuid"] = $Confinetoobjectiveuuid }
        if ($PSBoundParameters.ContainsKey("Storagevolume")) { $body["storageVolume"] = $Storagevolume }
        if ($PSBoundParameters.ContainsKey("Name")) { $body["name"] = $Name }
        if ($PSBoundParameters.ContainsKey("Expressions")) { $body["expressions"] = $Expressions }

        Invoke-HsRequest -Method PUT -Endpoint "/volume-groups/${Identifier}" -Body $body
}

function Remove-HsVolumeGroup {
    <#
    .SYNOPSIS
        Delete a volume group
    .DESCRIPTION
        Delete a volume group
    .NOTES
    CLI equivalent: volume-group-delete
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Identifier
    )

        Invoke-HsRequest -Method DELETE -Endpoint "/volume-groups/${Identifier}"
}

# ---------------------------------------------------------------------------
# Export public functions
# ---------------------------------------------------------------------------
Export-ModuleMember -Function @(
    'Connect-HammerspaceSession',
    'Disconnect-HammerspaceSession',
    'Get-HammerspaceSession',
    'Get-HsAd',
    'Get-HsAd2',
    'Invoke-HsAd',
    'Get-HsAd3',
    'Set-HsAd',
    'Get-HsAntivirus',
    'New-HsAntivirus',
    'Get-HsAntivirus2',
    'Set-HsAntivirus',
    'Remove-HsAntivirus',
    'Get-HsBackup',
    'New-HsBackup',
    'Invoke-HsBackupCreate',
    'Get-HsBackupList',
    'Invoke-HsBackupRestore',
    'Invoke-HsBackupRestore2',
    'Set-HsBackup',
    'Remove-HsBackup',
    'Get-HsStorageVolume',
    'Get-HsStorageVolume2',
    'Get-HsCntl',
    'Invoke-HsCntlAcceptEula',
    'Invoke-HsCntlShutdown',
    'Get-HsCntl2',
    'Get-HsCntl3',
    'Set-HsCntl',
    'Get-HsDataAnalytic',
    'Start-HsDataCopyToObject',
    'Get-HsDataCopyToObjectListBucket',
    'Get-HsDataPortal',
    'Get-HsDataPortal2',
    'Set-HsDataPortal',
    'Get-HsDiskDrive',
    'Get-HsDiskDrive2',
    'Get-HsDns',
    'Get-HsDns2',
    'Set-HsDns',
    'Get-HsDomainIdmap',
    'New-HsDomainIdmap',
    'Invoke-HsDomainIdmapReload',
    'Get-HsDomainIdmap2',
    'Set-HsDomainIdmap',
    'Remove-HsDomainIdmap',
    'Get-HsEvent',
    'Clear-HsEventClear',
    'Get-HsEvent2',
    'Get-HsEvent3',
    'Set-HsEvent',
    'Get-HsFileSnapshot',
    'New-HsFileSnapshot',
    'New-HsFileSnapshotCreate',
    'Remove-HsFileSnapshotDelete',
    'Get-HsFileSnapshot2',
    'Invoke-HsFileSnapshotRestore',
    'New-HsFileSnapshot2',
    'Get-HsFileSnapshot3',
    'Set-HsFileSnapshot',
    'Remove-HsFileSnapshot',
    'Get-HsFile',
    'Get-HsFileExistDp',
    'Get-HsFileUsedCapacity',
    'Remove-HsFileWorm',
    'Get-HsFile2',
    'Get-HsGateway',
    'Set-HsGateway',
    'Get-HsGateway2',
    'Get-HsHeartbeat',
    'Send-HsHeartbeatSend',
    'Set-HsHeartbeat',
    'Get-HsI18n',
    'Get-HsI18n2',
    'Get-HsIdentityGroupMapping',
    'New-HsIdentityGroupMapping',
    'Get-HsIdentityGroupMapping2',
    'Set-HsIdentityGroupMapping',
    'Remove-HsIdentityGroupMapping',
    'Get-HsIdentity',
    'Get-HsIdp',
    'New-HsIdp',
    'Get-HsIdp2',
    'Set-HsIdp',
    'Remove-HsIdp',
    'Get-HsKms',
    'New-HsKms',
    'Get-HsKms2',
    'Set-HsKms',
    'Remove-HsKms',
    'Get-HsLabel',
    'New-HsLabel',
    'Get-HsLabel2',
    'Set-HsLabel',
    'Remove-HsLabel',
    'Get-HsLdap',
    'New-HsLdap',
    'Get-HsLdap2',
    'Set-HsLdap',
    'Remove-HsLdap',
    'Get-HsLicenseServer',
    'Submit-HsLicenseServerReportUsage',
    'Get-HsLicense',
    'New-HsLicense',
    'Get-HsLicenseOfflineAddRequestDownload',
    'Export-HsLicenseOfflineAddRequestExport',
    'Import-HsLicenseOfflineAddResponseImport',
    'Import-HsLicenseOfflineAddResponseUpload',
    'Stop-HsLicenseOfflineCancelPending',
    'Get-HsLicenseOfflineRemoveRequestDownload',
    'Export-HsLicenseOfflineRemoveRequestExport',
    'Import-HsLicenseOfflineRemoveResponseImport',
    'Import-HsLicenseOfflineRemoveResponseUpload',
    'Get-HsLicenseOfflineUpdateRequestDownload',
    'Export-HsLicenseOfflineUpdateRequestExport',
    'Import-HsLicenseOfflineUpdateResponseImport',
    'Import-HsLicenseOfflineUpdateResponseUpload',
    'Get-HsLicense2',
    'Set-HsLicense',
    'Remove-HsLicense',
    'Get-HsLogicalVolume',
    'New-HsLogicalVolume',
    'Get-HsLogicalVolume2',
    'Remove-HsLogicalVolume',
    'Get-HsLogicalVolume3',
    'Connect-HsLogin',
    'Get-HsLoginPolicy',
    'New-HsLoginPolicy',
    'Get-HsLoginPolicy2',
    'Set-HsLoginPolicy',
    'Remove-HsLoginPolicy',
    'Get-HsMailsmtp',
    'New-HsMailsmtp',
    'Send-HsMailsmtpTest',
    'Get-HsMailsmtp2',
    'Set-HsMailsmtp',
    'Remove-HsMailsmtp',
    'Get-HsMdsi',
    'New-HsMdsi',
    'Get-HsMdsi2',
    'Remove-HsMdsi',
    'Get-HsMetric',
    'Get-HsMetricCapacity',
    'Get-HsMetric2',
    'Invoke-HsModelerTriggerSweep',
    'Get-HsModelerTreeStat',
    'Get-HsNameService',
    'New-HsNameService',
    'Test-HsNameServiceConnectiontest',
    'Set-HsNameServiceReorder',
    'Get-HsNameServiceResolvegroup',
    'Get-HsNameServiceResolveuser',
    'Get-HsNameServiceResolveusergroup',
    'Get-HsNameService2',
    'Set-HsNameService',
    'Remove-HsNameService',
    'Get-HsNetworkInterface',
    'Get-HsNetworkInterface2',
    'Get-HsNetworkInterface3',
    'New-HsNetworkInterface',
    'Set-HsNetworkInterface',
    'Remove-HsNetworkInterface',
    'Get-HsNfsClient',
    'Get-HsNis',
    'Get-HsNis2',
    'Set-HsNis',
    'Get-HsNode',
    'New-HsNode',
    'Get-HsNode2',
    'Get-HsNodeUnauthenticated',
    'Get-HsNode3',
    'Set-HsNode',
    'Remove-HsNode',
    'Invoke-HsNode',
    'Set-HsNodeSetMode',
    'Get-HsNotificationRule',
    'New-HsNotificationRule',
    'Get-HsNotificationRule2',
    'Set-HsNotificationRule',
    'Remove-HsNotificationRule',
    'Get-HsNtp',
    'Get-HsNtp2',
    'Set-HsNtp',
    'Get-HsNvmeofEnclosure',
    'New-HsNvmeofEnclosure',
    'Set-HsNvmeofEnclosure',
    'Get-HsNvmeofEnclosure2',
    'Set-HsNvmeofEnclosure2',
    'Remove-HsNvmeofEnclosure',
    'Get-HsObjectStorageVolume',
    'New-HsObjectStorageVolume',
    'Get-HsObjectStorageVolume2',
    'Get-HsObjectStorageVolume3',
    'Set-HsObjectStorageVolume',
    'Remove-HsObjectStorageVolume',
    'Invoke-HsObjectStorageVolumeDecommission',
    'Start-HsObjectStorageVolumeGarbageCollect',
    'Stop-HsObjectStorageVolumeGarbageCollect',
    'Remove-HsObjectStorageVolumeRemoteReservation',
    'Set-HsObjectStorageVolumeReplace',
    'Get-HsObjectStoreLogicalVolume',
    'Get-HsObjectStoreLogicalVolume2',
    'Get-HsObjective',
    'New-HsObjective',
    'Export-HsObjectiveExport',
    'Find-HsObjectiveFindmatchingvolume',
    'Import-HsObjectiveImport',
    'Get-HsObjectiveValidate',
    'Get-HsObjective2',
    'Set-HsObjective',
    'Remove-HsObjective',
    'Add-HsPdNodeCntl',
    'Repair-HsPdNodeCntl',
    'Invoke-HsPdSupport',
    'Get-HsPkiCertificateAuthority',
    'Get-HsPkiCertificateAuthoritiesSystem',
    'Get-HsPkiCertificateAuthority2',
    'Get-HsPkiCertificate',
    'New-HsPkiCertificate',
    'New-HsPkiCertificateSignCsr',
    'Remove-HsPkiCertificate',
    'Get-HsPkiCertificate2',
    'Get-HsPkiManagedCertificate',
    'Get-HsPkiManagedCertificate2',
    'Get-HsReportActiveFiles',
    'Get-HsReportActivityAnalytic',
    'Get-HsReportStat',
    'Get-HsReportLicensedUsage',
    'Get-HsReportMobility',
    'Get-HsReportReplication',
    'Get-HsReportReplication2',
    'Get-HsReportShare',
    'Get-HsReport',
    'Get-HsReportMobilityBandwidth',
    'Get-HsReportProxyUsage',
    'Get-HsReportShareLatencies',
    'Get-HsReportAlignment',
    'Get-HsReportCloud',
    'Get-HsReportMetadata',
    'Get-HsReportPerformance',
    'Get-HsReportSpace',
    'Get-HsReportVolumesExceededThreshold',
    'Get-HsRole',
    'New-HsRole',
    'Get-HsRole2',
    'Set-HsRole',
    'Remove-HsRole',
    'Get-HsS3server',
    'New-HsS3server',
    'Get-HsS3server2',
    'Set-HsS3server',
    'Remove-HsS3server',
    'Add-HsS3serverBucket',
    'Remove-HsS3serverBucket',
    'Get-HsS3serverListbuckets',
    'Add-HsS3serverUser',
    'Remove-HsS3serverUser',
    'Get-HsSchedule',
    'New-HsSchedule',
    'Get-HsSchedule2',
    'Set-HsSchedule',
    'Remove-HsSchedule',
    'Get-HsShareParticipant',
    'New-HsShareParticipant',
    'Set-HsShareParticipantChangeAdminState',
    'Get-HsShareParticipant2',
    'Set-HsShareParticipant',
    'Remove-HsShareParticipant',
    'Remove-HsShareParticipant2',
    'Remove-HsShareReplication',
    'Get-HsShareSnapshotSchedule',
    'New-HsShareSnapshotSchedule',
    'Copy-HsShareSnapshotCloneCreate',
    'New-HsShareSnapshotCreate',
    'Remove-HsShareSnapshotDelete',
    'Get-HsShareSnapshotList',
    'Restore-HsShareSnapshotRestoreFiles',
    'Restore-HsShareSnapshotRestore',
    'Set-HsShareSnapshotSchedule',
    'Remove-HsShareSnapshotSchedule',
    'Get-HsShare',
    'New-HsShare',
    'Get-HsShare2',
    'Get-HsShare3',
    'Get-HsShare4',
    'Get-HsShare5',
    'Set-HsShare',
    'Remove-HsShare',
    'Get-HsShareAttribute',
    'Set-HsShareAttribute',
    'Remove-HsShareAttribute',
    'Get-HsShareCollectionSum',
    'Get-HsShare6',
    'Move-HsShareMove',
    'Get-HsShareObjectiveList',
    'Reset-HsShareObjectiveReset',
    'Set-HsShareObjectiveSet',
    'Clear-HsShareObjectiveUnset',
    'Update-HsShareObjective',
    'Restore-HsShareUndelete',
    'Get-HsSite',
    'New-HsSite',
    'Get-HsSite2',
    'Get-HsSite3',
    'Get-HsSite4',
    'Set-HsSite',
    'Remove-HsSite',
    'Get-HsSmbautohome',
    'New-HsSmbautohome',
    'Remove-HsSmbautohome',
    'Get-HsSmbautohomeUsername',
    'Remove-HsSmbautohomeUsername',
    'Get-HsSmbautohome2',
    'Set-HsSmbautohome',
    'Remove-HsSmbautohome2',
    'Get-HsSnapshotRetention',
    'New-HsSnapshotRetention',
    'Get-HsSnapshotRetention2',
    'Set-HsSnapshotRetention',
    'Remove-HsSnapshotRetention',
    'Get-HsSnmp',
    'Send-HsSnmpTrapTest',
    'Get-HsSnmp2',
    'Set-HsSnmp',
    'Get-HsStaticRoute',
    'New-HsStaticRoute',
    'Remove-HsStaticRoute',
    'Get-HsStorageVolume',
    'New-HsStorageVolume',
    'Get-HsStorageVolume2',
    'Get-HsStorageVolume3',
    'Set-HsStorageVolume',
    'Remove-HsStorageVolume',
    'Invoke-HsStorageVolumeAssimilation',
    'Invoke-HsStorageVolumeDecommission',
    'Set-HsStorageVolumeReplace',
    'Get-HsSubnetGateway',
    'New-HsSubnetGateway',
    'Remove-HsSubnetGateway',
    'Get-HsSwUpdate',
    'Install-HsSwUpdateApply',
    'Install-HsSwUpdateSystem',
    'Get-HsSwUpdate2',
    'Stop-HsSwUpdate',
    'Get-HsSyslog',
    'Get-HsSyslog2',
    'Set-HsSyslog',
    'Get-HsSystemInfo',
    'Get-HsSystem',
    'Get-HsSystem2',
    'Get-HsSystem3',
    'Get-HsTask',
    'Stop-HsTaskCancelActive',
    'Get-HsTask2',
    'Set-HsTask',
    'Get-HsUserGroup',
    'New-HsUserGroup',
    'Get-HsUserGroup2',
    'Set-HsUserGroup',
    'Remove-HsUserGroup',
    'Get-HsUser',
    'New-HsUser',
    'Get-HsUserCurrent',
    'Get-HsUserPermittedOperation',
    'Add-HsUserAdd',
    'Get-HsUserList',
    'Remove-HsUserRemove',
    'Import-HsUserImport',
    'Import-HsUserImport2',
    'Get-HsUser2',
    'Set-HsUser',
    'Remove-HsUser',
    'Set-HsUserPassword',
    'Get-HsUserPreferences',
    'Get-HsUserPreferences2',
    'Set-HsUserPreferences',
    'Remove-HsUserPreferences',
    'Reset-HsUserResetPassword',
    'Get-HsVersionAvailable',
    'Remove-HsVersionDelete',
    'Publish-HsVersionUpload',
    'Publish-HsVersionUpload2',
    'Get-HsVolumeGroup',
    'New-HsVolumeGroup',
    'Get-HsVolumeGroupFindbylocation',
    'Get-HsVolumeGroup2',
    'Get-HsVolumeGroup3',
    'Set-HsVolumeGroup',
    'Remove-HsVolumeGroup'
)
