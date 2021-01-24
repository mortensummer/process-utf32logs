#requires -version 6.0

If(-not (Get-Module -ListAvailable -Name AWS.Tools.S3)){
    Install-Module -Name AWS.Tools.Installer -Scope CurrentUser -AllowClobber -Force
    Install-AWSToolsModule AWS.Tools.EC2, AWS.Tools.S3 -Scope CurrentUser -Force
}

#for testing so i dont need to keep downloading files.
$WhatIF = $false

function Get-FileEncoding
{
    [CmdletBinding()] 
    Param (
        [Parameter(Mandatory = $True, ValueFromPipelineByPropertyName = $True)] 
        [string]$Path
    )
    $legacyEncoding = $false
    try {
        try {
            [byte[]]$byte = get-content -AsByteStream -ReadCount 4 -TotalCount 4 -LiteralPath $Path
            
        } catch {
            [byte[]]$byte = get-content -Encoding Byte -ReadCount 4 -TotalCount 4 -LiteralPath $Path
            $legacyEncoding = $true
        }
        
        if(-not $byte) {
            if($legacyEncoding) { "unknown" } else {  [System.Text.Encoding]::Default }
        }
    } catch {
        throw
    }
    
    #Write-Host Bytes: $byte[0] $byte[1] $byte[2] $byte[3]
 
    # EF BB BF (UTF8)
    if ( $byte[0] -eq 0xef -and $byte[1] -eq 0xbb -and $byte[2] -eq 0xbf )
    { if($legacyEncoding) { "UTF8" } else { [System.Text.Encoding]::UTF8 } }
 
    # FE FF (UTF-16 Big-Endian)
    elseif ($byte[0] -eq 0xfe -and $byte[1] -eq 0xff)
    { if($legacyEncoding) { "bigendianunicode" } else { [System.Text.Encoding]::BigEndianUnicode } }
 
    # FF FE (UTF-16 Little-Endian)
    elseif ($byte[0] -eq 0xff -and $byte[1] -eq 0xfe -and $byte[2] -ne 0 -and $byte[3] -ne 0)
    { if($legacyEncoding) { "unicode" } else { [System.Text.Encoding]::Unicode }}
 
    # 00 00 FE FF (UTF32 Big-Endian)
    elseif ($byte[0] -eq 0 -and $byte[1] -eq 0 -and $byte[2] -eq 0xfe -and $byte[3] -eq 0xff)
    { if($legacyEncoding) { "utf32" } else { [System.Text.Encoding]::UTF32 }}
 
    # FE FF 00 00 (UTF32 Little-Endian)
    elseif ($byte[0] -eq 0xff -and $byte[1] -eq 0xfe -and $byte[2] -eq 0 -and $byte[3] -eq 0)
    { if($legacyEncoding) { "utf32" } else { [System.Text.Encoding]::UTF32 }}
 
    # 2B 2F 76 (38 | 38 | 2B | 2F)
    elseif ($byte[0] -eq 0x2b -and $byte[1] -eq 0x2f -and $byte[2] -eq 0x76 -and ($byte[3] -eq 0x38 -or $byte[3] -eq 0x39 -or $byte[3] -eq 0x2b -or $byte[3] -eq 0x2f) )
    {if($legacyEncoding) { "utf7" } else { [System.Text.Encoding]::UTF7}}
 
    # F7 64 4C (UTF-1)
    elseif ( $byte[0] -eq 0xf7 -and $byte[1] -eq 0x64 -and $byte[2] -eq 0x4c )
    { throw "UTF-1 not a supported encoding" }
 
    # DD 73 66 73 (UTF-EBCDIC)
    elseif ($byte[0] -eq 0xdd -and $byte[1] -eq 0x73 -and $byte[2] -eq 0x66 -and $byte[3] -eq 0x73)
    { throw "UTF-EBCDIC not a supported encoding" }
 
    # 0E FE FF (SCSU)
    elseif ( $byte[0] -eq 0x0e -and $byte[1] -eq 0xfe -and $byte[2] -eq 0xff )
    { throw "SCSU not a supported encoding" }
 
    # FB EE 28 (BOCU-1)
    elseif ( $byte[0] -eq 0xfb -and $byte[1] -eq 0xee -and $byte[2] -eq 0x28 )
    { throw "BOCU-1 not a supported encoding" }
 
    # 84 31 95 33 (GB-18030)
    elseif ($byte[0] -eq 0x84 -and $byte[1] -eq 0x31 -and $byte[2] -eq 0x95 -and $byte[3] -eq 0x33)
    { throw "GB-18030 not a supported encoding" }
 
    else
    { if($legacyEncoding) { "ascii" } else { [System.Text.Encoding]::ASCII }}
}

Function Get-Files([psobject]$S3Object, [string]$region){
    foreach($object in $S3Object) {
        $folder= $Object.Key.Substring($prefix.Length).Split('/')[0]
        $filename = $Object.Key.Substring($prefix.Length).Split('/')[1]
        $format = "yyyyMMdd"
        $FileDate = [datetime]::parseexact($filename.Split('-')[0], $format, $null)

        $OutPath = Join-Path $CustomerPath $folder
        If(-not (Test-Path $OutPath)){
            $Null = New-Item -ItemType Directory $OutPath
        }

        if ((Get-Date $FileDate) -ge (Get-Date $ProcessDate)) {
            $localFilePath = Join-Path $OutPath $FileName
            IF($WhatIF){
                Write-Output "WhatIF: Downloading '$($object.Key)' to '$localFilePath' from '$region'"
            }else{
                $null = Copy-S3Object -BucketName $bucket -Key $object.Key -LocalFile $localFilePath -Region $region -Force 
            }
        }
    }
}

Function Convert-Files([string]$Path){
    Get-ChildItem -path $path -Recurse | ForEach-Object {
        $SubFolder = $_.Directory.Name
        $CustomerOutputPath = Join-Path $Config.WorkingDir $folder $bucket $SubFolder
        
        If(-not (Test-Path $CustomerOutputPath)){
            $null = New-Item -ItemType Directory $CustomerOutputPath
        }
        
        If(!($_.PSIsContainer)){
            $FileEncode = (Get-FileEncoding $_).HeaderName

            If($FileEncode -eq 'UTF-32'){
                Write-OUtput "Converting $($_.Name) to UTF-32 in $CustomerOutputPath"
                Get-Content -Encoding utf32 -Path $_ | Out-File -Encoding utf8 $(Join-Path $CustomerOutputPath $_.Name) -Force
                
            }
        }
    }
}

$BaseDir = Get-Location
$BaseConfig = "$BaseDir\config.json"

# Load and parse the JSON configuration file
try{
    $Config = Get-Content "$BaseConfig" -Raw | ConvertFrom-Json
    Write-Host "$BaseConfig parsed..."
}
catch{
    Write-Error "Cannot load configuration $BaseConfig. Exiting"
    Exit
}

#Set the TimeStamp up for the backups
$TimeStamp = (Get-Date).ToString('yyyy-MM-dd_HHmmss')
$folder = "UTF_Output_$Timestamp"

#Get the process from date into something comparable
$ProcessDate  = [datetime]::parseexact($($Config.ProcessDate), "yyyyMMdd", $null)
$prefix = $Config.Prefix

# Authenticate with AWS S3
try{
    Get-S3Bucket | Out-Null
}catch{
    If(!(Get-AWSCredentials -ProfileName Storage-User)){
        $Cred = Get-Credential -Message "Please enter in Access Key (User) and Secret (Password) for accessing bucket:"
        Set-AWSCredential -AccessKey $Cred.UserName -SecretKey $Cred.GetNetworkCredential().Password -StoreAs Storage-User
    }
    Set-AWSCredentials -ProfileName Storage-User
}

# Get some buckets. 
$Buckets = $config.Buckets | Get-Member -MemberType 'NoteProperty' | Select-Object -ExpandProperty Name
foreach ($bucket in $buckets) {

    $Region = $($config.Buckets.$bucket.Region)
    Write-Output "Downloading '$($Bucket)' in '$($Region)'... "

    $Objs = Get-S3Object -BucketName $bucket -Region $Region -Prefix $($Config.Prefix)
        
    $CustomerPath = Join-Path $($Config.WorkingDir) $bucket
    If(-not (Test-Path $CustomerPath)){
        $null = New-Item -ItemType Directory $CustomerPath
    }

    # Download the files
    Get-Files -S3Object $Objs -Region $Region

    # Convert the files
    Convert-Files $CustomerPath $bucket

    Write-Output "Writing back to S3..."
    $OutputFolder = JOin-Path $($Config.WorkingDir) $folder $bucket

    IF($WhatIF){
        Write-Output "WhatIF: Uploading '$($OutputFolder)' to '$bucket' in '$region'"
    }else{
        $null = Write-S3Object -Region $Region -BucketName $bucket -Folder $OutputFolder -KeyPrefix $prefix -Recurse -Force
    }
}